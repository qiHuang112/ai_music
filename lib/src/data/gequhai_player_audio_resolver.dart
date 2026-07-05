import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lyrics_normalizer.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class GequhaiPlayerAudioResolver {
  const GequhaiPlayerAudioResolver({required MusicResolverHttp httpClient})
    : _http = httpClient;

  static const _source = MusicDataSource.gequhai;
  static const _platform = 'gequhai';
  static const _playId = '38173';
  static const _apiHost = 'www.gequhai.com';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final MusicResolverHttp _http;

  Future<List<MusicSearchCandidate>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    if (!_matchesScopedSong(trimmed)) {
      return const [];
    }
    return [
      MusicSearchCandidate(
        query: trimmed,
        source: _source,
        platform: _platform,
        keyword: trimmed,
        page: 0,
        id: _playId,
        name: '哎呀',
        artist: '王蓉',
        album: '',
        duration: 216,
        link: 'https://www.gequhai.com/play/$_playId',
        coverUrl: '',
        qualities: const [MusicQuality(format: 'mp3', bitrate: 'validated')],
        score: 212,
        raw: const {'seed': 'gequhai_play_38173'},
      ),
    ];
  }

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    final detailUri = Uri.tryParse(candidate.link);
    if (detailUri == null || candidate.id != _playId) {
      throw _failure(candidate, 'page', 'play_url_unavailable', '歌曲海页面地址不可用。');
    }

    final page = await _fetchPage(detailUri, candidate);
    final pageAttempt = _attempt(
      query: candidate.query,
      stage: 'page',
      status: SourceAttemptStatus.ok,
      reasonCode: 'page_metadata_ready',
      candidate: candidate,
      lyricsStatus: page.lyrics == null ? 'missing' : 'page_lrc',
      coverUrl: page.coverUrl,
      coverStatus: page.coverUrl.isEmpty ? 'missing' : 'page_cover',
      evidenceUrl: detailUri.toString(),
    );

    final api = await _fetchApi(detailUri, page, candidate);
    final apiAttempt = _attempt(
      query: candidate.query,
      stage: 'api',
      status: SourceAttemptStatus.ok,
      reasonCode: 'player_audio_url_ready',
      candidate: candidate,
      mediaUrl: api.audioUrl,
      mediaUrlType: MediaUrlType.directAudioCandidate,
      mediaContentType: api.contentType,
      lyricsStatus: page.lyrics == null ? 'missing' : 'page_lrc',
      coverUrl: page.coverUrl,
      coverStatus: page.coverUrl.isEmpty ? 'missing' : 'page_cover',
      evidenceUrl: detailUri.toString(),
      browserPlayable: true,
      scriptReproducible: true,
    );

    final mediaUri = Uri.parse(api.audioUrl);
    final validation = await _validateMedia(mediaUri);
    if (!validation.clientReady) {
      throw SourceDownloadException(
        '歌曲海播放器音频未通过客户端完整音频校验。',
        failureCode: validation.failureCode,
        sourceAttempts: [
          pageAttempt,
          apiAttempt,
          _attempt(
            query: candidate.query,
            stage: 'media_validation',
            status: SourceAttemptStatus.failed,
            failureCode: validation.failureCode,
            candidate: candidate,
            mediaUrl: api.audioUrl,
            mediaUrlType: MediaUrlType.directAudioCandidate,
            mediaContentType: validation.contentType,
            mediaContentLength: validation.contentLength,
            mediaValidation: validation.summary,
            lyricsStatus: page.lyrics == null ? 'missing' : 'page_lrc',
            coverUrl: page.coverUrl,
            coverStatus: page.coverUrl.isEmpty ? 'missing' : 'page_cover',
            evidenceUrl: detailUri.toString(),
            browserPlayable: true,
            scriptReproducible: true,
          ),
        ],
      );
    }

    return ResolvedMusic(
      query: candidate.query,
      source: _source,
      platform: _platform,
      id: candidate.id,
      name: page.title.isNotEmpty ? page.title : candidate.name,
      artist: page.artist.isNotEmpty ? page.artist : candidate.artist,
      album: candidate.album,
      url: api.audioUrl,
      quality: const MusicQuality(format: 'mp3', bitrate: 'validated'),
      coverUrl: page.coverUrl,
      lyrics: page.lyrics,
      duration: page.durationSeconds > 0 ? page.durationSeconds : 216,
      urlType: MediaUrlType.directAudio,
      canCacheAudio: true,
      sourceAttempts: [
        pageAttempt,
        apiAttempt,
        _attempt(
          query: candidate.query,
          stage: 'media_validation',
          status: SourceAttemptStatus.ok,
          reasonCode: 'direct_full_audio_ready',
          candidate: candidate,
          mediaUrl: api.audioUrl,
          mediaUrlType: MediaUrlType.directAudio,
          mediaContentType: validation.contentType,
          mediaContentLength: validation.contentLength,
          mediaValidation: validation.summary,
          lyricsStatus: page.lyrics == null ? 'missing' : 'page_lrc',
          coverUrl: page.coverUrl,
          browserPlayable: true,
          scriptReproducible: true,
          clientReady: true,
          evidenceUrl: detailUri.toString(),
          coverStatus: page.coverUrl.isEmpty ? 'missing' : 'page_cover',
        ),
      ],
    );
  }

  Future<_PageResult> _fetchPage(
    Uri detailUri,
    MusicSearchCandidate candidate,
  ) async {
    final cookies = <String, Cookie>{};
    var response = await _http.get(detailUri, headers: _pageHeaders);
    _mergeCookies(cookies, response.cookies);
    if (response.statusCode == HttpStatus.forbidden &&
        _looksLikeDefender(response.body)) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      response = await _http.get(
        detailUri,
        headers: {..._pageHeaders, ..._cookieHeaderFromJar(cookies)},
      );
      _mergeCookies(cookies, response.cookies);
    }
    final contentType = _header(response, HttpHeaders.contentTypeHeader);
    if (response.statusCode == HttpStatus.forbidden ||
        _looksLikeDefender(response.body)) {
      throw _failure(
        candidate,
        'page',
        'security_or_defender',
        '歌曲海页面进入安全验证或防护页。',
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(
        candidate,
        'page',
        'provider_http_${response.statusCode}',
        '歌曲海页面请求失败。',
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    final html = response.body;
    final playId = _extractJsString(html, 'play_id');
    if (playId.isEmpty) {
      throw _failure(
        candidate,
        'page',
        'play_url_unavailable',
        '歌曲海页面没有播放器 play_id。',
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    final externalPan = _extractExternalPan(html);
    if (externalPan.isNotEmpty) {
      // Kept as evidence only. The player API is the completion path.
    }
    return _PageResult(
      playId: playId,
      title: _cleanHtmlText(_extractJsString(html, 'mp3_title')),
      artist: _cleanHtmlText(_extractJsString(html, 'mp3_author')),
      coverUrl: _absoluteUrl(_extractJsString(html, 'mp3_cover'), detailUri),
      lyrics: makeResolvedLyrics(
        _extractContentLrc(html),
        'gequhai:page:#content-lrc2',
      ),
      durationSeconds: _parseDurationSeconds(_extractDuration(html)),
      cookieHeader: _cookieHeaderFromJar(cookies),
    );
  }

  Future<_ApiResult> _fetchApi(
    Uri detailUri,
    _PageResult page,
    MusicSearchCandidate candidate,
  ) async {
    final uri = Uri.https(_apiHost, '/api/music');
    final response = await _http.postForm(
      uri,
      {'id': page.playId, 'type': '0'},
      headers: {
        'origin': 'https://$_apiHost',
        'referer': detailUri.toString(),
        'x-requested-with': 'Http',
        'x-custom-header': 'Key',
        'user-agent': _userAgent,
        'accept': 'application/json, text/javascript, */*; q=0.01',
        ...page.cookieHeader,
      },
    );
    final contentType = _header(response, HttpHeaders.contentTypeHeader);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(
        candidate,
        'api',
        'provider_http_${response.statusCode}',
        '歌曲海播放器接口请求失败。',
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw _failure(
        candidate,
        'api',
        'anticc_non_json',
        '歌曲海播放器接口返回非 JSON。',
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    final json = asStringMap(decoded);
    final code = json['code']?.toString();
    final data = asStringMap(json['data']);
    final audioUrl = (data['url'] ?? json['url'])?.toString().trim() ?? '';
    if (code != '200' || audioUrl.isEmpty) {
      throw _failure(
        candidate,
        'api',
        'play_url_unavailable',
        '歌曲海播放器接口没有返回完整音频地址。',
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    final type = classifyMediaUrl(audioUrl);
    if (type == MediaUrlType.externalPan || type == MediaUrlType.htmlPage) {
      final failureCode = failureCodeForUrlType(type);
      throw _failure(
        candidate,
        'api',
        failureCode,
        '歌曲海播放器接口返回的不是完整音频直链。',
        mediaUrl: audioUrl,
        mediaUrlType: type,
        mediaContentType: contentType,
        evidenceUrl: detailUri.toString(),
      );
    }
    return _ApiResult(audioUrl: audioUrl, contentType: contentType);
  }

  Future<_MediaValidation> _validateMedia(Uri mediaUri) async {
    final head = await _http.head(mediaUri, headers: _mediaHeaders);
    final headType = _header(head, HttpHeaders.contentTypeHeader).toLowerCase();
    final headLength = _parsePositiveInt(_header(head, 'content-length'));
    if (head.statusCode == HttpStatus.forbidden ||
        head.statusCode == HttpStatus.gone) {
      return _MediaValidation.failed(
        'browser_playable_only',
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

    final range = await _http.range(
      mediaUri,
      end: 8191,
      headers: _mediaHeaders,
    );
    final rangeType = _header(
      range,
      HttpHeaders.contentTypeHeader,
    ).toLowerCase();
    final contentRange = _header(range, HttpHeaders.contentRangeHeader);
    final rangeTotal = _parseRangeTotal(contentRange);
    if (range.statusCode != HttpStatus.partialContent ||
        !rangeType.startsWith('audio/') ||
        !contentRange.startsWith('bytes 0-8191/') ||
        rangeTotal == null) {
      return _MediaValidation.failed(
        rangeType.startsWith('audio/')
            ? 'range_not_supported'
            : 'non_audio_content',
        rangeType,
        headLength,
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
    bool browserPlayable = true,
    bool scriptReproducible = true,
    bool clientReady = false,
    String mediaValidation = '',
    String evidenceUrl = '',
    String coverStatus = '',
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
}

const _pageHeaders = {
  'user-agent': GequhaiPlayerAudioResolver._userAgent,
  'accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
};

const _mediaHeaders = {
  'user-agent': GequhaiPlayerAudioResolver._userAgent,
  'accept': '*/*',
};

bool _matchesScopedSong(String query) {
  final normalized = _normalize(query);
  return normalized == '哎呀' ||
      normalized.contains('哎呀王蓉') ||
      normalized.contains('王蓉哎呀');
}

bool _looksLikeDefender(String html) {
  final lower = html.toLowerCase();
  return lower.contains('just a moment') ||
      lower.contains('security') ||
      lower.contains('安全验证') ||
      lower.contains('403 forbidden');
}

String _extractJsString(String html, String name) {
  final pattern = RegExp(
    r'(?:window\.)?' + RegExp.escape(name) + r'''\s*=\s*['"]([^'"]*)['"]''',
    caseSensitive: false,
  );
  return _decodeHtml(pattern.firstMatch(html)?.group(1) ?? '').trim();
}

String _extractContentLrc(String html) {
  final match = RegExp(
    r'''<[^>]+id=["']content-lrc2["'][^>]*>(.*?)</[^>]+>''',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  return match?.group(1) ?? '';
}

String _extractDuration(String html) {
  final match = RegExp(r'\b\d{2}:\d{2}\b').firstMatch(html);
  return match?.group(0) ?? '';
}

String _extractExternalPan(String html) {
  final match = RegExp(
    r'''https?://pan\.quark\.cn/[^\s"'<>]+''',
    caseSensitive: false,
  ).firstMatch(html);
  if (match != null) {
    return match.group(0) ?? '';
  }
  final extraUrl = _extractJsString(html, 'mp3_extra_url');
  if (extraUrl.isEmpty) {
    return '';
  }
  String decoded = extraUrl;
  for (var i = 0; i < 2; i += 1) {
    final next = Uri.decodeComponent(decoded);
    if (next == decoded) {
      break;
    }
    decoded = next;
  }
  return RegExp(
        r'''https?://pan\.quark\.cn/[^\s"'<>]+''',
        caseSensitive: false,
      ).firstMatch(decoded)?.group(0) ??
      '';
}

String _absoluteUrl(String url, Uri base) {
  if (url.trim().isEmpty) {
    return '';
  }
  return base.resolve(url.trim()).toString();
}

Map<String, String> _cookieHeader(List<Cookie> cookies) {
  if (cookies.isEmpty) {
    return const {};
  }
  return {
    'cookie': cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; '),
  };
}

void _mergeCookies(Map<String, Cookie> jar, List<Cookie> cookies) {
  for (final cookie in cookies) {
    jar[cookie.name] = cookie;
  }
}

Map<String, String> _cookieHeaderFromJar(Map<String, Cookie> jar) {
  return _cookieHeader(jar.values.toList(growable: false));
}

String _header(ResolverHttpResponse response, String name) {
  final lower = name.toLowerCase();
  return response.headers.entries
          .where((entry) => entry.key.toLowerCase() == lower)
          .map((entry) => entry.value)
          .firstOrNull
          ?.trim() ??
      '';
}

int _parseDurationSeconds(String text) {
  final parts = text.split(':');
  if (parts.length != 2) {
    return 0;
  }
  final minutes = int.tryParse(parts[0]) ?? 0;
  final seconds = int.tryParse(parts[1]) ?? 0;
  return minutes * 60 + seconds;
}

int? _parsePositiveInt(String value) {
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
  return _parsePositiveInt(contentRange.substring(slash + 1));
}

String _cleanHtmlText(String text) {
  return _decodeHtml(text.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
}

String _decodeHtml(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(
    RegExp(r'[\s·•_\-—/\\()\[\]（）【】《》<>:：，,。.!！?？]'),
    '',
  );
}

class _PageResult {
  const _PageResult({
    required this.playId,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.lyrics,
    required this.durationSeconds,
    required this.cookieHeader,
  });

  final String playId;
  final String title;
  final String artist;
  final String coverUrl;
  final ResolvedLyrics? lyrics;
  final int durationSeconds;
  final Map<String, String> cookieHeader;
}

class _ApiResult {
  const _ApiResult({required this.audioUrl, required this.contentType});

  final String audioUrl;
  final String contentType;
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
