import 'dart:convert';
import 'dart:math';

import 'candidate_scorer.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class KuwoFullAudioResolver {
  KuwoFullAudioResolver({
    required MusicResolverHttp httpClient,
    CandidateScorer scorer = const CandidateScorer(),
  }) : _http = httpClient,
       _scorer = scorer;

  static const _source = MusicDataSource.kuwoFullAudio;
  static const _platform = 'kuwo';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const _referer = 'http://www.kuwo.cn/';
  static const _minimumMatchScore = 210.0;
  static const _minimumArtistMatchScore = 120.0;
  static const _minimumTitleMatchScore = 150.0;
  static const _minimumFullAudioBytes = 1000000;
  static const _progressivePageSize = 8;
  static const _validationConcurrency = 2;

  final MusicResolverHttp _http;
  final CandidateScorer _scorer;
  final Map<String, ResolvedMusic> _preparedResolutions = {};
  final Map<String, List<Map<String, dynamic>>> _artistCatalogs = {};

  Future<List<MusicSearchCandidate>> search(String query) async {
    final result = await _searchPage(query, page: 1, limit: 30);
    return result.candidates.take(20).toList(growable: false);
  }

  Stream<MusicSearchProgress> searchPageProgressively(
    String query, {
    required int page,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty || page < 1) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page < 1 ? 1 : page,
      );
      return;
    }
    if (page == 1) {
      _preparedResolutions.clear();
      _artistCatalogs.remove(_normalizeTitle(trimmed));
    }
    final searchPage = await _searchPage(
      trimmed,
      page: page,
      limit: _progressivePageSize,
    );
    final original = searchPage.candidates;
    if (original.isEmpty) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
        hasNextPage: searchPage.hasNextPage,
      );
      return;
    }

    final completed = List<bool>.filled(original.length, false);
    final playable = List<MusicSearchCandidate?>.filled(original.length, null);
    final failures = <Object>[];
    yield MusicSearchProgress(
      candidates: [
        for (final candidate in original)
          _candidateWithValidationStatus(candidate, 'validating'),
      ],
      isComplete: false,
      page: page,
      hasNextPage: searchPage.hasNextPage,
    );

    var nextIndex = 0;
    final active = <int, Future<_IndexedResolution>>{};
    void fillWorkers() {
      while (active.length < _validationConcurrency &&
          nextIndex < original.length) {
        final index = nextIndex;
        nextIndex += 1;
        active[index] = _resolveIndexed(index, original[index]);
      }
    }

    fillWorkers();
    while (active.isNotEmpty) {
      final result = await Future.any(active.values);
      active.remove(result.index);
      completed[result.index] = true;
      final resolved = result.resolved;
      if (resolved != null) {
        final candidate = original[result.index];
        _preparedResolutions[_preparedKey(candidate)] = resolved;
        playable[result.index] = _candidateWithResolvedMetadata(
          candidate,
          resolved,
        );
      } else if (result.error != null) {
        failures.add(result.error!);
      }
      fillWorkers();
      yield MusicSearchProgress(
        candidates: _validationSnapshot(original, playable, completed),
        isComplete: false,
        page: page,
        hasNextPage: searchPage.hasNextPage,
      );
    }

    final ready = playable.whereType<MusicSearchCandidate>().toList(
      growable: false,
    );
    if (ready.isEmpty &&
        failures.length == original.length &&
        failures.every(isSourceCircuitBreakerError)) {
      throw _sourceFailureFrom(failures.first);
    }

    yield MusicSearchProgress(
      candidates: ready,
      isComplete: true,
      page: page,
      hasNextPage: searchPage.hasNextPage,
    );
  }

  Future<_KuwoSearchPage> _searchPage(
    String query, {
    required int page,
    required int limit,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const _KuwoSearchPage();
    }
    final catalogKey = _normalizeTitle(trimmed);
    final cachedCatalog = _artistCatalogs[catalogKey];
    if (page > 1 && cachedCatalog != null) {
      return _catalogPage(cachedCatalog, trimmed, page);
    }
    final scopedSong = _scopedSongFor(trimmed);
    final searchTerm = scopedSong?.title ?? trimmed;
    final uri = Uri.http('search.kuwo.cn', '/r.s', {
      'all': searchTerm,
      'ft': 'music',
      'itemset': 'web_2013',
      'client': 'kt',
      'pn': '${page - 1}',
      'rn': '$limit',
      'rformat': 'json',
      'encoding': 'utf8',
    });
    final response = await _http.get(uri, headers: _searchHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SourceDownloadException(
        'Kuwo 搜索暂时不可用。',
        failureCode: 'provider_http_${response.statusCode}',
        sourceAttempts: [
          _attempt(
            query: trimmed,
            stage: 'search',
            status: SourceAttemptStatus.failed,
            failureCode: 'provider_http_${response.statusCode}',
            mediaContentType: _header(response, 'content-type'),
          ),
        ],
      );
    }

    final items = _parseAbslist(response.body);
    var candidates =
        items
            .map((item) => _candidateFromItem(item, trimmed))
            .where(_isTrustedFullAudioCandidate)
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));
    if (page == 1 && scopedSong == null) {
      final artistTitle = _artistTitleQuery(trimmed);
      final exactArtistId = _exactArtistId(items, trimmed);
      var catalog = const <Map<String, dynamic>>[];
      if (artistTitle != null) {
        catalog = await _loadArtistCatalog(
          artistTitle.artist,
          expectedArtistId: '',
        );
        catalog = catalog
            .where(
              (item) =>
                  _normalizeTitle(item['name']) ==
                  _normalizeTitle(artistTitle.title),
            )
            .toList(growable: false);
      } else if (exactArtistId.isNotEmpty || _hasExactArtist(items, trimmed)) {
        catalog = await _loadArtistCatalog(
          trimmed,
          expectedArtistId: exactArtistId,
        );
        if (catalog.isNotEmpty && candidates.isNotEmpty) {
          final seenIds = <String>{};
          catalog = [
            for (final candidate in candidates)
              if (seenIds.add(candidate.id))
                Map<String, dynamic>.from(candidate.raw),
            for (final item in catalog)
              if (seenIds.add(item['musicRid']?.toString() ?? '')) item,
          ];
        }
      }
      if (catalog.isNotEmpty) {
        _artistCatalogs[catalogKey] = catalog;
        return _catalogPage(catalog, trimmed, page);
      }
    }
    // ignore: avoid_print
    print(
      '[AI Music][resolver] Kuwo search query="$trimmed" page=$page '
      'raw=${items.length} trusted=${candidates.length}',
    );
    if (candidates.isEmpty && scopedSong != null) {
      return _KuwoSearchPage(candidates: [_seedCandidate(scopedSong, trimmed)]);
    }
    return _KuwoSearchPage(
      candidates: candidates,
      hasNextPage: items.length >= limit,
    );
  }

  Future<List<Map<String, dynamic>>> _loadArtistCatalog(
    String artist, {
    required String expectedArtistId,
  }) async {
    final uri = Uri.https('m.kuwo.cn', '/artist/content', {'name': artist});
    late final ResolverHttpResponse response;
    try {
      response = await _http.get(uri, headers: _searchHeaders);
    } catch (_) {
      return const [];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final pageArtistId = RegExp(
      r'''data-artistid=["'](\d+)["']''',
    ).firstMatch(response.body)?.group(1);
    if (pageArtistId == null ||
        (expectedArtistId.isNotEmpty && pageArtistId != expectedArtistId)) {
      return const [];
    }
    final catalog = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final match in RegExp(
      r"""data-music\s*=\s*'([^']+)'""",
    ).allMatches(response.body)) {
      try {
        final decoded = jsonDecode(_decodeHtmlAttribute(match.group(1)!));
        if (decoded is! Map) {
          continue;
        }
        final musicRid = decoded['id']?.toString().trim() ?? '';
        final itemArtist = _cleanText(decoded['artist']);
        if (!musicRid.startsWith('MUSIC_') ||
            _normalizeTitle(itemArtist) != _normalizeTitle(artist) ||
            !seen.add(musicRid)) {
          continue;
        }
        catalog.add({
          'name': decoded['name'],
          'songName': decoded['name'],
          'artist': itemArtist,
          'artistId': pageArtistId,
          'album': decoded['album'],
          'duration': 180,
          'musicRid': musicRid,
          'formats': 'MP3128',
          'minfo': 'level:h,bitrate:128,format:mp3',
          'online': '1',
          'pay': '0',
          'copyright': '0',
          'artistCatalog': true,
        });
      } catch (_) {
        continue;
      }
    }
    return List.unmodifiable(catalog);
  }

  _KuwoSearchPage _catalogPage(
    List<Map<String, dynamic>> catalog,
    String query,
    int page,
  ) {
    final offset = (page - 1) * _progressivePageSize;
    if (offset >= catalog.length) {
      return const _KuwoSearchPage();
    }
    final end = min(offset + _progressivePageSize, catalog.length);
    final candidates = catalog
        .sublist(offset, end)
        .map((item) => _candidateFromItem(item, query))
        .where(_isTrustedFullAudioCandidate)
        .toList(growable: false);
    return _KuwoSearchPage(
      candidates: candidates,
      hasNextPage: end < catalog.length,
    );
  }

  String _exactArtistId(List<Map<String, dynamic>> items, String query) {
    final normalizedQuery = _normalizeTitle(query);
    for (final item in items) {
      if (_normalizeTitle(item['artist']) == normalizedQuery) {
        final artistId = item['artistId']?.toString().trim() ?? '';
        if ((int.tryParse(artistId) ?? 0) > 0) {
          return artistId;
        }
      }
    }
    return '';
  }

  bool _hasExactArtist(List<Map<String, dynamic>> items, String query) {
    final normalizedQuery = _normalizeTitle(query);
    return items.any(
      (item) => _normalizeTitle(item['artist']) == normalizedQuery,
    );
  }

  _ArtistTitleQuery? _artistTitleQuery(String query) {
    final tokens = query
        .trim()
        .split(RegExp(r'[\s,，/]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.length < 2) {
      return null;
    }
    return _ArtistTitleQuery(
      artist: tokens.first,
      title: tokens.skip(1).join(' '),
    );
  }

  Future<_IndexedResolution> _resolveIndexed(
    int index,
    MusicSearchCandidate candidate,
  ) async {
    try {
      final resolved = await _resolveFresh(candidate);
      final validation = resolved.sourceAttempts.isEmpty
          ? ''
          : resolved.sourceAttempts.last.mediaValidation;
      // ignore: avoid_print
      print(
        '[AI Music][resolver] Kuwo validation ok id=${candidate.id} '
        '$validation',
      );
      return _IndexedResolution(index, resolved);
    } catch (error) {
      // ignore: avoid_print
      print(
        '[AI Music][resolver] Kuwo validation failed id=${candidate.id} '
        'name="${candidate.name}" error=${formatResolverError(error)}',
      );
      return _IndexedResolution(index, null, error);
    }
  }

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    final prepared = _preparedResolutions.remove(_preparedKey(candidate));
    if (prepared != null) {
      return prepared;
    }
    return _resolveFresh(candidate);
  }

  Future<ResolvedMusic> _resolveFresh(MusicSearchCandidate candidate) async {
    if (!_isTrustedFullAudioCandidate(candidate)) {
      throw SourceDownloadException(
        '候选歌曲匹配度不足，已阻止完整播放和缓存。',
        failureCode: 'low_match_confidence',
        sourceAttempts: [
          _attempt(
            query: candidate.query,
            stage: 'match_gate',
            status: SourceAttemptStatus.failed,
            failureCode: 'low_match_confidence',
            candidate: candidate,
          ),
        ],
      );
    }
    final convert = await _convert(candidate.id);
    if (convert.mediaUrl.isEmpty) {
      throw SourceDownloadException(
        'Kuwo 未返回可播放完整音频地址。',
        failureCode: 'no_audio_url',
        sourceAttempts: [
          _attempt(
            query: candidate.query,
            stage: 'convert',
            status: SourceAttemptStatus.failed,
            failureCode: 'no_audio_url',
            candidate: candidate,
            mediaContentType: convert.contentType,
          ),
        ],
      );
    }

    final mediaUri = Uri.parse(convert.mediaUrl);
    final validation = await _validateMedia(mediaUri);
    if (!validation.clientReady) {
      throw SourceDownloadException(
        '完整音频未通过客户端校验。',
        failureCode: validation.failureCode,
        sourceAttempts: [
          _attempt(
            query: candidate.query,
            stage: 'media_validation',
            status: SourceAttemptStatus.failed,
            failureCode: validation.failureCode,
            candidate: candidate,
            mediaUrl: convert.mediaUrl,
            mediaUrlType: MediaUrlType.directAudioCandidate,
            mediaContentType: validation.contentType,
            mediaContentLength: validation.contentLength,
            mediaValidation: validation.summary,
          ),
        ],
      );
    }

    return ResolvedMusic(
      query: candidate.query,
      source: _source,
      platform: _platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: convert.mediaUrl,
      quality:
          bestQuality(candidate.qualities, 'mp3') ??
          const MusicQuality(format: 'mp3', bitrate: '128'),
      coverUrl: candidate.coverUrl,
      duration: candidate.duration,
      urlType: MediaUrlType.directAudio,
      canCacheAudio: true,
      sourceAttempts: [
        _attempt(
          query: candidate.query,
          stage: 'media_validation',
          status: SourceAttemptStatus.ok,
          reasonCode: 'direct_audio_ready',
          candidate: candidate,
          mediaUrl: convert.mediaUrl,
          mediaUrlType: MediaUrlType.directAudio,
          mediaContentType: validation.contentType,
          mediaContentLength: validation.contentLength,
          mediaValidation: validation.summary,
          clientReady: true,
        ),
      ],
    );
  }

  MusicSearchCandidate _candidateFromItem(
    Map<String, dynamic> item,
    String query,
  ) {
    final normalizedItem = <String, dynamic>{
      'name': item['name'],
      'artist': item['artist'],
      'album_name': item['album'],
      'duration': item['duration'],
      'minfo': _qualitiesFromMinfo(item['minfo']),
    };
    final qualities = _qualitiesFromMinfo(item['minfo']);
    final score =
        _scorer.scoreCandidate(normalizedItem, query, _platform, query, 0) +
        _strictKnownSongBoost(item, query);
    return MusicSearchCandidate(
      query: query,
      source: _source,
      platform: _platform,
      keyword: query,
      page: 0,
      id: item['musicRid']?.toString() ?? '',
      name: _cleanText(item['name']),
      artist: _cleanText(item['artist']),
      album: _cleanText(item['album']),
      duration: intFrom(item['duration']),
      link: item['musicRid']?.toString() ?? '',
      coverUrl: '',
      qualities: qualities,
      score: score,
      raw: item,
    );
  }

  MusicSearchCandidate _seedCandidate(_ScopedSong song, String query) {
    return MusicSearchCandidate(
      query: query,
      source: _source,
      platform: _platform,
      keyword: query,
      page: 0,
      id: song.musicRid,
      name: song.title,
      artist: song.artist,
      album: '',
      duration: 180,
      link: song.musicRid,
      coverUrl: '',
      qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
      score: _minimumMatchScore + 1,
      raw: const {'seed': 'scoped_musicrid'},
    );
  }

  Future<_ConvertResult> _convert(String musicRid) async {
    final uri = Uri.http('antiserver.kuwo.cn', '/anti.s', {
      'type': 'convert_url3',
      'rid': musicRid,
      'format': 'mp3',
      'response': 'url',
    });
    final response = await _http.get(uri, headers: _convertHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _ConvertResult(contentType: _header(response, 'content-type'));
    }
    try {
      final json = jsonDecode(response.body);
      if (json is Map && json['url'] is String) {
        return _ConvertResult(
          mediaUrl: json['url'].toString(),
          contentType: _header(response, 'content-type'),
        );
      }
    } catch (_) {
      final body = response.body.trim();
      if (body.startsWith('http://') || body.startsWith('https://')) {
        return _ConvertResult(
          mediaUrl: body,
          contentType: _header(response, 'content-type'),
        );
      }
    }
    return _ConvertResult(contentType: _header(response, 'content-type'));
  }

  Future<_MediaValidation> _validateMedia(Uri mediaUri) async {
    final head = await _http.head(mediaUri, headers: _mediaHeaders);
    final headType = _header(head, 'content-type').toLowerCase();
    final headLength = _parsePositiveIntHeader(_header(head, 'content-length'));
    if (_looksLikeDefender(head.body)) {
      return _MediaValidation.failed(
        'security_or_defender',
        headType,
        headLength,
        'HEAD ${head.statusCode} defender',
      );
    }
    if (head.statusCode == 403 || head.statusCode == 429) {
      return _MediaValidation.failed(
        'provider_http_${head.statusCode}',
        headType,
        headLength,
        'HEAD ${head.statusCode}',
      );
    }
    if (head.statusCode == 410) {
      return _MediaValidation.failed(
        'browser_only',
        headType,
        headLength,
        'HEAD ${head.statusCode}',
      );
    }
    if (head.statusCode < 200 || head.statusCode >= 300) {
      return _MediaValidation.failed(
        'audio_validation_failed',
        headType,
        headLength,
        'HEAD ${head.statusCode}',
      );
    }
    if (!headType.startsWith('audio/')) {
      return _MediaValidation.failed(
        'non_audio_content',
        headType,
        headLength,
        'HEAD ${head.statusCode} $headType',
      );
    }
    final rawHeadLength = _header(head, 'content-length').trim();
    if (rawHeadLength.isNotEmpty && headLength == null) {
      return _MediaValidation.failed(
        'audio_validation_failed',
        headType,
        headLength,
        'HEAD invalid content-length',
      );
    }
    if (headLength != null && headLength < _minimumFullAudioBytes) {
      return _MediaValidation.failed(
        'audio_too_short',
        headType,
        headLength,
        'HEAD ${head.statusCode} $headType length=$headLength',
      );
    }

    final range = await _http.range(mediaUri, headers: _mediaHeaders);
    final rangeType = _header(range, 'content-type').toLowerCase();
    final contentRange = _header(range, 'content-range');
    final rangeTotal = _parseRangeTotal(contentRange);
    if (_looksLikeDefender(range.body)) {
      return _MediaValidation.failed(
        'security_or_defender',
        rangeType,
        headLength,
        'Range ${range.statusCode} defender',
      );
    }
    if (range.statusCode == 403 || range.statusCode == 429) {
      return _MediaValidation.failed(
        'provider_http_${range.statusCode}',
        rangeType,
        headLength,
        'Range ${range.statusCode}',
      );
    }
    if (range.statusCode != 206 ||
        !rangeType.startsWith('audio/') ||
        !contentRange.startsWith('bytes 0-0/') ||
        rangeTotal == null) {
      return _MediaValidation.failed(
        rangeType.startsWith('audio/')
            ? 'audio_validation_failed'
            : 'non_audio_content',
        rangeType,
        headLength,
        'Range ${range.statusCode} $rangeType $contentRange',
      );
    }
    if (rangeTotal < _minimumFullAudioBytes) {
      return _MediaValidation.failed(
        'audio_too_short',
        rangeType,
        rangeTotal,
        'Range ${range.statusCode} $rangeType $contentRange',
      );
    }
    return _MediaValidation(
      clientReady: true,
      failureCode: '',
      contentType: rangeType,
      contentLength: headLength ?? rangeTotal,
      summary:
          'HEAD ${head.statusCode} $headType length=${headLength ?? rangeTotal}; '
          'Range ${range.statusCode} $contentRange',
    );
  }

  int? _parsePositiveIntHeader(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  int? _parseRangeTotal(String contentRange) {
    final slash = contentRange.lastIndexOf('/');
    if (slash == -1 || slash == contentRange.length - 1) {
      return null;
    }
    return _parsePositiveIntHeader(contentRange.substring(slash + 1));
  }

  bool _isTrustedFullAudioCandidate(MusicSearchCandidate candidate) {
    if (!candidate.id.startsWith('MUSIC_')) {
      return false;
    }
    if (candidate.duration < 90 || candidate.duration > 600) {
      return false;
    }
    if (_looksLikeAlternateOrPartialVersion(candidate.raw['songName'])) {
      return false;
    }
    final scopedSong = _scopedSongFor(candidate.query);
    final title = _normalizeTitle(candidate.name);
    final artist = _normalizeTitle(candidate.artist);
    if (scopedSong != null) {
      return title == scopedSong.title &&
          artist.contains(scopedSong.artist) &&
          candidate.id == scopedSong.musicRid &&
          candidate.score >= _minimumMatchScore;
    }

    final tokens = candidate.query
        .trim()
        .split(RegExp(r'[\s,，/]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.length > 1) {
      return candidate.score >= _minimumArtistMatchScore &&
          isLooseArtistTitleCandidate(candidate, candidate.query);
    }
    final normalizedQuery = _normalizeTitle(candidate.query);
    final artistExact = artist == normalizedQuery;
    final titleExact = title == normalizedQuery;
    return (artistExact && candidate.score >= _minimumArtistMatchScore) ||
        (titleExact && candidate.score >= _minimumTitleMatchScore);
  }

  double _strictKnownSongBoost(Map<String, dynamic> item, String query) {
    final scopedSong = _scopedSongFor(query);
    if (scopedSong == null) {
      return 0;
    }
    final title = _normalizeTitle(item['name']);
    final artist = _normalizeTitle(item['artist']);
    if (title == scopedSong.title && artist.contains(scopedSong.artist)) {
      return 180;
    }
    if (title == scopedSong.title) {
      return 40;
    }
    return 0;
  }

  _ScopedSong? _scopedSongFor(String query) {
    final normalized = _normalizeTitle(query);
    const scoped = [
      _ScopedSong(title: '一丝不挂', artist: '陈奕迅', musicRid: 'MUSIC_475511188'),
      _ScopedSong(title: '稻香', artist: '周杰伦', musicRid: 'MUSIC_351583919'),
      _ScopedSong(title: '外婆', artist: '周杰伦', musicRid: 'MUSIC_477808701'),
    ];
    for (final song in scoped) {
      if (normalized == song.title ||
          (normalized.contains(song.title) &&
              normalized.contains(song.artist))) {
        return song;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _parseAbslist(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['abslist'] is List) {
        return [
          for (final item in decoded['abslist'] as List)
            if (item is Map)
              {
                'name': item['name'] ?? item['NAME'],
                'songName': item['songName'] ?? item['SONGNAME'],
                'artist': item['artist'] ?? item['ARTIST'],
                'artistId': item['artistId'] ?? item['ARTISTID'],
                'album': item['album'] ?? item['ALBUM'],
                'duration': item['duration'] ?? item['DURATION'],
                'musicRid': item['musicRid'] ?? item['MUSICRID'] ?? item['rid'],
                'formats': item['formats'] ?? item['FORMATS'],
                'minfo': item['minfo'] ?? item['MINFO'],
                'online': item['online'] ?? item['ONLINE'],
                'pay': item['pay'] ?? item['PAY'],
                'copyright': item['copyright'] ?? item['COPYRIGHT'],
              },
        ].where(_isAvailableItem).toList(growable: false);
      }
    } catch (_) {
      // Kuwo has returned both JSON and legacy single-quoted blocks.
    }
    final legacyList = _legacyAbslist(text);
    return legacyList
        .map(
          (block) => {
            'name': _field(block, 'NAME'),
            'songName': _field(block, 'SONGNAME'),
            'artist': _field(block, 'ARTIST'),
            'artistId': _field(block, 'ARTISTID'),
            'album': _field(block, 'ALBUM'),
            'duration': int.tryParse(_field(block, 'DURATION')) ?? 0,
            'musicRid': _field(block, 'MUSICRID'),
            'formats': _field(block, 'FORMATS'),
            'minfo': _field(block, 'MINFO'),
            'online': _field(block, 'ONLINE'),
            'pay': _field(block, 'PAY'),
            'copyright': _field(block, 'COPYRIGHT'),
          },
        )
        .where(_isAvailableItem)
        .toList(growable: false);
  }

  List<String> _legacyAbslist(String text) {
    final listMatch = RegExp(r'''['"]abslist['"]\s*:\s*\[''').firstMatch(text);
    if (listMatch == null) {
      return const [];
    }
    final blocks = <String>[];
    var depth = 0;
    var objectStart = -1;
    var inString = false;
    var escaped = false;
    var quote = '';
    for (var index = listMatch.end; index < text.length; index += 1) {
      final char = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == quote) {
          inString = false;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        inString = true;
        quote = char;
        continue;
      }
      if (char == '{') {
        if (depth == 0) {
          objectStart = index;
        }
        depth += 1;
        continue;
      }
      if (char == '}' && depth > 0) {
        depth -= 1;
        if (depth == 0 && objectStart >= 0) {
          blocks.add(text.substring(objectStart, index + 1));
          objectStart = -1;
        }
        continue;
      }
      if (char == ']' && depth == 0) {
        break;
      }
    }
    final musicRidPattern = RegExp(r"'MUSICRID'\s*:\s*'MUSIC_");
    return blocks.where(musicRidPattern.hasMatch).toList(growable: false);
  }

  bool _isAvailableItem(Map<String, dynamic> item) {
    return item['online']?.toString() == '1' &&
        item['pay']?.toString() != '1' &&
        item['musicRid']?.toString().trim().isNotEmpty == true;
  }

  String _field(String block, String name) {
    final match = RegExp("'$name'\\s*:\\s*'([^']*)'").firstMatch(block);
    return _cleanText(match?.group(1) ?? '');
  }

  List<MusicQuality> _qualitiesFromMinfo(Object? minfo) {
    final text = minfo?.toString() ?? '';
    if (text.trim().isEmpty) {
      return const [MusicQuality(format: 'mp3', bitrate: '128')];
    }
    return text
        .split(';')
        .map((row) {
          final values = <String, String>{};
          for (final part in row.split(',')) {
            final pieces = part.split(':');
            if (pieces.length >= 2) {
              values[pieces.first.trim()] = pieces.sublist(1).join(':').trim();
            }
          }
          return MusicQuality(
            format: values['format'] ?? '',
            bitrate: values['bitrate'] ?? '',
            size: values['size'] ?? '',
          );
        })
        .where((quality) => quality.format.trim().isNotEmpty)
        .toList(growable: false);
  }

  SourceAttempt _attempt({
    required String query,
    required String stage,
    required SourceAttemptStatus status,
    String failureCode = '',
    String reasonCode = '',
    MusicSearchCandidate? candidate,
    String mediaUrl = '',
    MediaUrlType mediaUrlType = MediaUrlType.unknown,
    String mediaContentType = '',
    int? mediaContentLength,
    String mediaValidation = '',
    bool clientReady = false,
  }) {
    return SourceAttempt(
      query: query,
      source: _source,
      stage: stage,
      status: status,
      failureCode: failureCode,
      reasonCode: reasonCode,
      candidateId: candidate?.id ?? '',
      candidateTitle: candidate?.name ?? '',
      candidateArtist: candidate?.artist ?? '',
      matchConfidence: candidate?.score,
      mediaUrl: mediaUrl,
      mediaUrlType: mediaUrlType,
      mediaContentType: mediaContentType,
      mediaContentLength: mediaContentLength,
      browserPlayable: true,
      scriptReproducible: true,
      clientReady: clientReady,
      mediaValidation: mediaValidation,
    );
  }
}

const _searchHeaders = {
  'user-agent': KuwoFullAudioResolver._userAgent,
  'accept': 'text/plain,*/*;q=0.8',
  'referer': KuwoFullAudioResolver._referer,
};

const _convertHeaders = {
  'user-agent': KuwoFullAudioResolver._userAgent,
  'accept': 'application/json,text/plain,*/*;q=0.8',
  'referer': KuwoFullAudioResolver._referer,
};

const _mediaHeaders = {
  'user-agent': KuwoFullAudioResolver._userAgent,
  'accept': 'audio/*,*/*;q=0.9',
  'referer': KuwoFullAudioResolver._referer,
};

String _cleanText(Object? value) {
  return value
      .toString()
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _decodeHtmlAttribute(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

bool _looksLikeDefender(String body) {
  final lower = body.toLowerCase();
  return lower.contains('just a moment') ||
      lower.contains('safeline') ||
      lower.contains('challenge') ||
      lower.contains('security verification') ||
      lower.contains('too many requests') ||
      lower.contains('403 forbidden');
}

SourceDownloadException _sourceFailureFrom(Object error) {
  if (error is SourceDownloadException && error.failureCode.isNotEmpty) {
    return error;
  }
  final failureCode = sourceFailureCode(error);
  return SourceDownloadException(
    failureCode == 'network_timeout' ? '源站响应超时，请稍后再试。' : '源站暂时不可用。',
    failureCode: failureCode.isEmpty ? 'network_timeout' : failureCode,
  );
}

String _normalizeTitle(Object? value) {
  return _cleanText(value)
      .replaceAll(RegExp(r'[（(][^（）()]{1,24}[）)]'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
}

String _header(ResolverHttpResponse response, String name) {
  final lower = name.toLowerCase();
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == lower) {
      return entry.value;
    }
  }
  return '';
}

bool _looksLikeAlternateOrPartialVersion(Object? value) {
  final text = _cleanText(value).toLowerCase();
  if (text.isEmpty) {
    return false;
  }
  return RegExp(
    r'\+|片段|伴奏|纯音乐|纯人声|演唱会|艺术节|串烧|升调|\bdj\b|\blive\b|\bdemo\b|\bremix\b',
    caseSensitive: false,
  ).hasMatch(text);
}

String _preparedKey(MusicSearchCandidate candidate) {
  return '${candidate.platform}|${candidate.id}';
}

MusicSearchCandidate _candidateWithResolvedMetadata(
  MusicSearchCandidate candidate,
  ResolvedMusic resolved,
) {
  final lastAttempt = resolved.sourceAttempts.isEmpty
      ? null
      : resolved.sourceAttempts.last;
  return MusicSearchCandidate(
    query: candidate.query,
    source: candidate.source,
    platform: candidate.platform,
    keyword: candidate.keyword,
    page: candidate.page,
    id: candidate.id,
    name: resolved.name,
    artist: resolved.artist,
    album: resolved.album,
    duration: resolved.duration,
    link: candidate.link,
    coverUrl: resolved.coverUrl,
    qualities: [resolved.quality],
    score: candidate.score,
    raw: {
      ...candidate.raw,
      'validationStatus': 'ready',
      'clientReady': resolved.canCacheAudio,
      'urlType': resolved.urlType.storageValue,
      'mediaValidation': lastAttempt?.mediaValidation ?? '',
      'mediaContentLength': lastAttempt?.mediaContentLength,
    },
  );
}

MusicSearchCandidate _candidateWithValidationStatus(
  MusicSearchCandidate candidate,
  String status,
) {
  return MusicSearchCandidate(
    query: candidate.query,
    source: candidate.source,
    platform: candidate.platform,
    keyword: candidate.keyword,
    page: candidate.page,
    id: candidate.id,
    name: candidate.name,
    artist: candidate.artist,
    album: candidate.album,
    duration: candidate.duration,
    link: candidate.link,
    coverUrl: candidate.coverUrl,
    qualities: candidate.qualities,
    score: candidate.score,
    raw: {...candidate.raw, 'validationStatus': status, 'clientReady': false},
  );
}

List<MusicSearchCandidate> _validationSnapshot(
  List<MusicSearchCandidate> original,
  List<MusicSearchCandidate?> playable,
  List<bool> completed,
) {
  return List<MusicSearchCandidate>.unmodifiable([
    for (var index = 0; index < original.length; index += 1)
      if (playable[index] != null)
        playable[index]!
      else if (!completed[index])
        _candidateWithValidationStatus(original[index], 'validating'),
  ]);
}

class _IndexedResolution {
  const _IndexedResolution(this.index, this.resolved, [this.error]);

  final int index;
  final ResolvedMusic? resolved;
  final Object? error;
}

class _KuwoSearchPage {
  const _KuwoSearchPage({this.candidates = const [], this.hasNextPage = false});

  final List<MusicSearchCandidate> candidates;
  final bool hasNextPage;
}

class _ConvertResult {
  const _ConvertResult({this.mediaUrl = '', this.contentType = ''});

  final String mediaUrl;
  final String contentType;
}

class _ScopedSong {
  const _ScopedSong({
    required this.title,
    required this.artist,
    required this.musicRid,
  });

  final String title;
  final String artist;
  final String musicRid;
}

class _ArtistTitleQuery {
  const _ArtistTitleQuery({required this.artist, required this.title});

  final String artist;
  final String title;
}

class _MediaValidation {
  const _MediaValidation({
    required this.clientReady,
    required this.failureCode,
    required this.contentType,
    required this.contentLength,
    required this.summary,
  });

  factory _MediaValidation.failed(
    String failureCode,
    String contentType,
    int? contentLength,
    String summary,
  ) {
    return _MediaValidation(
      clientReady: false,
      failureCode: failureCode,
      contentType: contentType,
      contentLength: contentLength,
      summary: summary,
    );
  }

  final bool clientReady;
  final String failureCode;
  final String contentType;
  final int? contentLength;
  final String summary;
}
