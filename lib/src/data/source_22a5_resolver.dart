import 'dart:io';

import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'lyrics_normalizer.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class Source22a5Resolver {
  const Source22a5Resolver({
    required MusicResolverHttp httpClient,
    CandidateScorer scorer = const CandidateScorer(),
  }) : _http = httpClient,
       _scorer = scorer;

  final MusicResolverHttp _http;
  final CandidateScorer _scorer;

  Future<List<MusicSearchCandidate>> search(String query) async {
    final uri = Uri.https('www.22a5.com', '/so/$query.html');
    final response = await _http.get(uri, headers: _headers);
    if (!response.ok) {
      throw HttpException('22a5 search HTTP ${response.statusCode}', uri: uri);
    }
    if (_looksLikeSecurityPage(response.body)) {
      throw SourceDownloadException(
        '22a5 需要网页安全验证，暂不可用。',
        failureCode: 'security_verification',
        sourceAttempts: [
          _attempt(
            query: query,
            stage: 'search',
            status: SourceAttemptStatus.failed,
            failureCode: 'security_verification',
            evidenceUrl: uri.toString(),
          ),
        ],
      );
    }
    final candidates = <MusicSearchCandidate>[];
    final seen = <String>{};
    for (final match in _searchLinkPattern.allMatches(response.body)) {
      final href = _absolute22a5(match.namedGroup('href') ?? '');
      if (href.isEmpty || !seen.add(href)) {
        continue;
      }
      final label = _cleanHtml(match.namedGroup('text') ?? '');
      final parsed = _parseCandidateLabel(label);
      final item = <String, dynamic>{
        'id': _idFromDetailUrl(href),
        'name': parsed.title,
        'artist': parsed.artist,
        'album': '',
        'duration': 0,
        'pic_url': '',
        'link': href,
        'minfo': [
          {'format': 'guarded', 'bitrate': 'HEAD+Range', 'size': ''},
        ],
      };
      final score = _scorer.scoreCandidate(item, query, '22a5', query, 1);
      candidates.add(
        MusicSearchCandidate(
          query: query,
          source: MusicDataSource.source22a5,
          platform: '22a5',
          keyword: query,
          page: 1,
          id: item['id']?.toString() ?? href,
          name: parsed.title,
          artist: parsed.artist,
          album: '',
          duration: 0,
          link: href,
          coverUrl: '',
          qualities: const [
            MusicQuality(format: 'guarded', bitrate: 'HEAD+Range'),
          ],
          score: score,
          raw: item,
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(30).toList(growable: false);
  }

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    final detailUri = Uri.tryParse(candidate.link);
    if (detailUri == null || candidate.link.trim().isEmpty) {
      throw _failure(
        candidate,
        'detail',
        'play_url_unavailable',
        '22a5 详情页不可用。',
      );
    }
    final response = await _http.get(detailUri, headers: _headers);
    if (!response.ok) {
      throw _failure(
        candidate,
        'detail',
        'network_error',
        '22a5 详情页请求失败。',
        evidenceUrl: detailUri.toString(),
      );
    }
    if (_looksLikeSecurityPage(response.body)) {
      throw _failure(
        candidate,
        'detail',
        'security_verification',
        '22a5 需要网页安全验证，暂不可用。',
        evidenceUrl: detailUri.toString(),
      );
    }
    final audioUrl = _extractAudioUrl(response.body);
    final coverUrl = _extractCoverUrl(response.body);
    final lyrics = await _lyrics(candidate, response.body);
    final lyricsStatus = lyrics == null ? 'missing' : 'link_present';
    final coverStatus = coverUrl.isEmpty
        ? 'missing'
        : 'image_present_unverified';
    if (audioUrl.isEmpty) {
      throw _failure(
        candidate,
        'resolve',
        'no_audio_url',
        '22a5 当前候选没有可校验的音频地址。',
        evidenceUrl: detailUri.toString(),
        lyricsStatus: lyricsStatus,
        coverUrl: coverUrl,
        coverStatus: coverStatus,
      );
    }
    final urlType = classifyMediaUrl(audioUrl);
    if (urlType == MediaUrlType.externalPan ||
        urlType == MediaUrlType.htmlPage) {
      final failureCode = failureCodeForUrlType(urlType);
      throw _failure(
        candidate,
        'resolve',
        failureCode,
        _messageForFailureCode(failureCode),
        mediaUrl: audioUrl,
        mediaUrlType: urlType,
        evidenceUrl: detailUri.toString(),
        lyricsStatus: lyricsStatus,
        coverUrl: coverUrl,
        coverStatus: coverStatus,
      );
    }
    final validation = await _validateAudio(audioUrl);
    if (!validation.clientReady) {
      throw _failure(
        candidate,
        'head',
        'audio_validation_failed',
        '22a5 音频地址未通过客户端校验。',
        mediaUrl: audioUrl,
        mediaUrlType: MediaUrlType.directAudioCandidate,
        mediaContentType: validation.contentType,
        mediaContentLength: validation.contentLength,
        mediaValidation: validation.summary,
        evidenceUrl: detailUri.toString(),
        lyricsStatus: lyricsStatus,
        coverUrl: coverUrl,
        coverStatus: coverStatus,
        browserPlayable: true,
        scriptReproducible: true,
      );
    }
    return ResolvedMusic(
      query: candidate.query,
      source: MusicDataSource.source22a5,
      platform: '22a5',
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: audioUrl,
      quality: const MusicQuality(format: 'm4a', bitrate: 'validated'),
      coverUrl: coverUrl,
      lyrics: lyrics,
      duration: candidate.duration,
      urlType: MediaUrlType.directAudio,
      canCacheAudio: true,
      sourceAttempts: [
        _attempt(
          query: candidate.query,
          stage: 'head',
          status: SourceAttemptStatus.ok,
          reasonCode: 'direct_audio_ready',
          candidate: candidate,
          mediaUrl: audioUrl,
          mediaUrlType: MediaUrlType.directAudio,
          mediaContentType: validation.contentType,
          mediaContentLength: validation.contentLength,
          lyricsStatus: lyricsStatus,
          coverUrl: coverUrl,
          browserPlayable: true,
          scriptReproducible: true,
          clientReady: true,
          mediaValidation: validation.summary,
          evidenceUrl: detailUri.toString(),
          coverStatus: coverStatus,
        ),
      ],
    );
  }

  Future<ResolvedLyrics?> _lyrics(
    MusicSearchCandidate candidate,
    String html,
  ) async {
    final lrcUrl = _extractLrcUrl(html);
    if (lrcUrl.isNotEmpty) {
      try {
        final response = await _http.get(Uri.parse(lrcUrl), headers: _headers);
        if (response.ok) {
          final lyrics = makeResolvedLyrics(response.body, '22a5:lrc');
          if (lyrics != null) {
            return lyrics;
          }
        }
      } catch (_) {
        // Inline lyrics below still give the UI something useful.
      }
    }
    return makeResolvedLyrics(
      _extractInlineLyrics(candidate, html),
      '22a5:page',
    );
  }

  Future<_AudioValidation> _validateAudio(String audioUrl) async {
    final uri = Uri.parse(audioUrl);
    try {
      final head = await _http.head(uri, headers: _mediaHeaders);
      final headType = _header(head, HttpHeaders.contentTypeHeader);
      final headLength = int.tryParse(
        _header(head, HttpHeaders.contentLengthHeader),
      );
      if (head.statusCode != HttpStatus.ok || !_isAudioContentType(headType)) {
        return _AudioValidation(
          clientReady: false,
          contentType: headType,
          contentLength: headLength,
          summary: 'head=${head.statusCode};contentType=$headType',
        );
      }
      final range = await _http.range(uri, headers: _mediaHeaders);
      final rangeType = _header(range, HttpHeaders.contentTypeHeader);
      final rangeLength = int.tryParse(
        _header(range, HttpHeaders.contentLengthHeader),
      );
      final ready =
          range.statusCode == HttpStatus.partialContent &&
          _isAudioContentType(rangeType);
      return _AudioValidation(
        clientReady: ready,
        contentType: rangeType.isNotEmpty ? rangeType : headType,
        contentLength: headLength ?? rangeLength,
        summary:
            'head=${head.statusCode};range=${range.statusCode};contentType=${rangeType.isNotEmpty ? rangeType : headType}',
      );
    } catch (error) {
      return _AudioValidation(
        clientReady: false,
        summary: 'validation_error=${error.runtimeType}',
      );
    }
  }
}

SourceDownloadException _failure(
  MusicSearchCandidate candidate,
  String stage,
  String failureCode,
  String message, {
  String mediaUrl = '',
  MediaUrlType mediaUrlType = MediaUrlType.unknown,
  String mediaContentType = '',
  int? mediaContentLength,
  String mediaValidation = '',
  String evidenceUrl = '',
  String lyricsStatus = '',
  String coverUrl = '',
  String coverStatus = '',
  bool browserPlayable = false,
  bool scriptReproducible = false,
}) {
  return SourceDownloadException(
    message,
    failureCode: failureCode,
    sourceAttempts: [
      _attempt(
        query: candidate.query,
        stage: stage,
        status: SourceAttemptStatus.failed,
        failureCode: failureCode,
        candidate: candidate,
        mediaUrl: mediaUrl,
        mediaUrlType: mediaUrlType,
        mediaContentType: mediaContentType,
        mediaContentLength: mediaContentLength,
        mediaValidation: mediaValidation,
        evidenceUrl: evidenceUrl,
        lyricsStatus: lyricsStatus,
        coverUrl: coverUrl,
        coverStatus: coverStatus,
        browserPlayable: browserPlayable,
        scriptReproducible: scriptReproducible,
      ),
    ],
  );
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
  String lyricsStatus = '',
  String coverUrl = '',
  bool browserPlayable = false,
  bool scriptReproducible = false,
  bool clientReady = false,
  String mediaValidation = '',
  String evidenceUrl = '',
  String coverStatus = '',
}) {
  return SourceAttempt(
    query: query,
    source: MusicDataSource.source22a5,
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
    lyricsStatus: lyricsStatus,
    coverUrl: coverUrl,
    browserPlayable: browserPlayable,
    scriptReproducible: scriptReproducible,
    clientReady: clientReady,
    mediaValidation: mediaValidation,
    evidenceUrl: evidenceUrl,
    coverStatus: coverStatus,
  );
}

String _absolute22a5(String href) {
  final trimmed = _decodeHtml(href.trim());
  if (trimmed.isEmpty || trimmed.startsWith('javascript:')) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return '';
  }
  if (uri.hasScheme) {
    return uri.toString();
  }
  return Uri.https('www.22a5.com').resolve(trimmed).toString();
}

String _idFromDetailUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  final file = path.split('/').last;
  return file.replaceFirst(RegExp(r'\.html$'), '');
}

_ParsedLabel _parseCandidateLabel(String label) {
  final match = RegExp(r'^(.+?)《(.+?)》').firstMatch(label);
  if (match == null) {
    return _ParsedLabel(title: label.replaceAll('[MP3_LRC]', ''), artist: '');
  }
  return _ParsedLabel(
    title: match.group(2) ?? '',
    artist: match.group(1) ?? '',
  );
}

String _extractAudioUrl(String html) {
  for (final match in _audioUrlPattern.allMatches(html)) {
    final url = _decodeHtml(match.group(0) ?? '').trim();
    if (url.isEmpty) {
      continue;
    }
    final type = classifyMediaUrl(url);
    if (type == MediaUrlType.directAudio ||
        type == MediaUrlType.unknown ||
        type == MediaUrlType.previewAudio) {
      return url;
    }
  }
  return '';
}

String _extractCoverUrl(String html) {
  for (final match in _imagePattern.allMatches(html)) {
    final url = _absoluteUrl(match.namedGroup('src') ?? '');
    if (url.contains('albumcover') || url.contains('star/albumcover')) {
      return url;
    }
  }
  return '';
}

String _extractLrcUrl(String html) {
  final match = RegExp(
    r'''href=["'](?<href>[^"']*plug/down\.php\?ac=music&lk=lrc[^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  return _absoluteUrl(match?.namedGroup('href') ?? '');
}

String _extractInlineLyrics(MusicSearchCandidate candidate, String html) {
  final text = _cleanHtml(html);
  final title = candidate.name.trim();
  if (title.isEmpty) {
    return '';
  }
  final start = text.indexOf('$title -');
  if (start < 0) {
    return '';
  }
  final endMarkers = ['所属专辑', '温馨提示', 'MP3下载地址'];
  var end = text.length;
  for (final marker in endMarkers) {
    final index = text.indexOf(marker, start);
    if (index > start && index < end) {
      end = index;
    }
  }
  return text.substring(start, end).trim();
}

String _absoluteUrl(String href) {
  final trimmed = _decodeHtml(href.trim());
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return '';
  }
  if (uri.hasScheme) {
    return uri.toString();
  }
  return Uri.https('www.22a5.com').resolve(trimmed).toString();
}

bool _looksLikeSecurityPage(String body) {
  final lower = body.toLowerCase();
  return lower.contains('cloudflare') ||
      lower.contains('safeline') ||
      body.contains('安全验证') ||
      body.contains('人机验证');
}

bool _isAudioContentType(String value) {
  final type = value.toLowerCase().split(';').first.trim();
  return type.startsWith('audio/') ||
      type == 'application/octet-stream' ||
      type == 'video/mp4';
}

String _header(ResolverHttpResponse response, String name) {
  final target = name.toLowerCase();
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return '';
}

String _cleanHtml(String html) {
  final withBreaks = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</p>|</div>|</li>|</tr>|</h\d>', caseSensitive: false),
        '\n',
      );
  return _decodeHtml(withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .replaceAll(RegExp(r'\n\s+'), '\n')
      .trim();
}

String _decodeHtml(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}

String _messageForFailureCode(String failureCode) {
  return switch (failureCode) {
    'audio_validation_failed' => '音频地址未通过客户端校验。',
    'no_audio_url' => '该来源没有可播放音频地址。',
    'external_pan_link' => '该来源只提供网盘链接，不能直接播放。',
    'non_audio_content' => '下载链接返回的不是音频内容。',
    'security_verification' => '该来源需要网页安全验证，暂不可用。',
    _ => '该来源暂不可用。',
  };
}

class _ParsedLabel {
  const _ParsedLabel({required this.title, required this.artist});

  final String title;
  final String artist;
}

class _AudioValidation {
  const _AudioValidation({
    required this.clientReady,
    this.contentType = '',
    this.contentLength,
    this.summary = '',
  });

  final bool clientReady;
  final String contentType;
  final int? contentLength;
  final String summary;
}

final _searchLinkPattern = RegExp(
  r'''<a\b[^>]*href=["'](?<href>[^"']*/mp3/[^"']+\.html)["'][^>]*>(?<text>.*?)</a>''',
  caseSensitive: false,
  dotAll: true,
);

final _audioUrlPattern = RegExp(
  r'''https?://[^"'<>\s]+?\.(?:m4a|mp3|mp4|aac|flac)(?:\?[^"'<>\s]*)?''',
  caseSensitive: false,
);

final _imagePattern = RegExp(
  r'''<img\b[^>]*src=["'](?<src>[^"']+)["'][^>]*>''',
  caseSensitive: false,
);

const _headers = {
  'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'accept-language': 'zh-CN,zh;q=0.9',
  'referer': 'https://www.22a5.com/',
  'user-agent': ChallengeClient.userAgent,
};

const _mediaHeaders = {
  'accept': 'audio/*,*/*;q=0.9',
  'accept-language': 'zh-CN,zh;q=0.9',
  'referer': 'https://www.22a5.com/',
  'user-agent': ChallengeClient.userAgent,
};
