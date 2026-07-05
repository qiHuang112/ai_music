import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'music_cache.dart';
import 'music_resolver.dart';
import '../platform/app_storage.dart';

class ProgressiveAudioCache {
  ProgressiveAudioCache({
    required this.cacheStore,
    Future<Directory> Function()? rootProvider,
    HttpClient? client,
    Duration firstByteTimeout = const Duration(seconds: 8),
    void Function(String message)? logger,
  }) : _rootProvider = rootProvider ?? _defaultRoot,
       _client = client ?? HttpClient(),
       _ownsClient = client == null,
       _firstByteTimeout = firstByteTimeout,
       _logger = logger;

  final CachedTrackStore cacheStore;
  final Future<Directory> Function() _rootProvider;
  final HttpClient _client;
  final bool _ownsClient;
  final Duration _firstByteTimeout;
  final void Function(String message)? _logger;
  HttpServer? _server;
  final _sessions = <String, ProgressiveAudioSession>{};
  final _retiredTokens = <String>{};
  String? _activeToken;

  Future<ProgressiveAudioSession> open(ResolvedMusic music) async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    var server = _server;
    if (server == null) {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      unawaited(_serve(server));
    }
    final partFile = File(
      '${root.path}${Platform.pathSeparator}${cacheIdForResolved(music)}'
      '.progressive-${DateTime.now().microsecondsSinceEpoch}.part',
    );
    final token = _newSessionToken();
    final oldToken = _activeToken;
    if (oldToken != null) {
      _retiredTokens.add(oldToken);
      final oldSession = _sessions.remove(oldToken);
      unawaited(oldSession?.cancel(deletePartFile: true));
    }
    final session = ProgressiveAudioSession._(
      music: music,
      proxyUri: Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/audio/$token',
      ),
      partFile: partFile,
      cacheStore: cacheStore,
      client: _client,
      firstByteTimeout: _firstByteTimeout,
      logger: _logger,
    );
    _activeToken = token;
    _sessions[token] = session;
    _logger?.call(
      'progressive proxy url=${session.proxyUri} part=${session.partFile.path}',
    );
    return session;
  }

  Future<void> close() async {
    for (final session in _sessions.values) {
      await session.cancel(deletePartFile: true);
    }
    _sessions.clear();
    _retiredTokens.clear();
    _activeToken = null;
    await _server?.close(force: true);
    _server = null;
    if (_ownsClient) {
      _client.close(force: true);
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      final token = _sessionTokenFrom(request.uri);
      if (token == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      if (_retiredTokens.contains(token)) {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
        continue;
      }
      final session = _sessions[token];
      if (session == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      await session.handle(request);
    }
  }

  String? _sessionTokenFrom(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments.first != 'audio') {
      return null;
    }
    return segments[1].trim().isEmpty ? null : segments[1];
  }

  String _newSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Directory> _defaultRoot() async {
    return getAiMusicSupportSubdirectory('ai_music_progressive_cache');
  }
}

class ProgressiveAudioSession {
  ProgressiveAudioSession._({
    required this.music,
    required this.proxyUri,
    required this.partFile,
    required CachedTrackStore cacheStore,
    required HttpClient client,
    required Duration firstByteTimeout,
    void Function(String message)? logger,
  }) : _cacheStore = cacheStore,
       _client = client,
       _firstByteTimeout = firstByteTimeout,
       _logger = logger;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final ResolvedMusic music;
  final Uri proxyUri;
  final File partFile;
  final CachedTrackStore _cacheStore;
  final HttpClient _client;
  final Duration _firstByteTimeout;
  final void Function(String message)? _logger;
  final _changed = StreamController<void>.broadcast();
  final _cancelToken = DownloadCancelToken();
  Future<void>? _fetchFuture;
  int _downloadedBytes = 0;
  int? _totalBytes;
  Object? _fetchError;
  bool _complete = false;
  bool _closed = false;

  int get downloadedBytes => _downloadedBytes;
  int? get totalBytes => _totalBytes;
  bool get isComplete => _complete;
  Object? get fetchError => _fetchError;
  Stream<void> get changes => _changed.stream;

  Future<void> handle(HttpRequest request) async {
    _startFetch();
    final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader));
    final knownTotal = _totalBytes;
    if (range == null &&
        request.headers.value(HttpHeaders.rangeHeader) != null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${knownTotal ?? '*'}',
      );
      await request.response.close();
      return;
    }

    final start = range?.start ?? 0;
    if (knownTotal != null && start >= knownTotal) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$knownTotal',
      );
      await request.response.close();
      return;
    }

    final ready = await _waitForBytes(start + 1, timeout: _firstByteTimeout);
    final currentTotal = _totalBytes;
    if (!ready && _fetchError != null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    if (!ready && currentTotal != null && start >= currentTotal) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$currentTotal',
      );
      await request.response.close();
      return;
    }
    if (!ready) {
      request.response.statusCode = HttpStatus.gatewayTimeout;
      await request.response.close();
      return;
    }

    final end = range?.end;
    final contentEnd = end == null
        ? null
        : currentTotal == null
        ? end
        : min(end, currentTotal - 1);
    request.response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    request.response.headers.contentType = ContentType(
      'audio',
      _audioSubtype(),
    );
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range != null) {
      final rangeEnd = contentEnd ?? max(start, _downloadedBytes - 1);
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$rangeEnd/${currentTotal ?? '*'}',
      );
    }
    await _pipeAvailableBytes(request.response, start, contentEnd);
  }

  Future<CachedTrack> promoteWhenComplete() async {
    _startFetch();
    await _fetchFuture;
    _cancelToken.throwIfCanceled();
    if (!_complete) {
      throw StateError('Progressive fetch did not complete.');
    }
    final cached = await _cacheStore.adoptCompleteDownload(music, partFile);
    _logger?.call(
      'progressive promoted cacheId=${cached.cacheId} file=${cached.filePath}',
    );
    return cached;
  }

  Future<void> cancel({bool deletePartFile = false}) async {
    _cancelToken.cancel();
    _logger?.call(
      'progressive canceled bytes=$_downloadedBytes part=${partFile.path}',
    );
    if (deletePartFile && await partFile.exists()) {
      await partFile.delete();
    }
    if (!_closed) {
      _closed = true;
      await _changed.close();
    }
  }

  void _startFetch() {
    _fetchFuture ??= _fetch();
  }

  Future<void> _fetch() async {
    IOSink? sink;
    try {
      final request = await _client.getUrl(Uri.parse(music.url));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'progressive HTTP ${response.statusCode}',
          uri: Uri.parse(music.url),
        );
      }
      _totalBytes = _totalFrom(response);
      final trustedContentType = _validateResponseContentType(response);
      sink = partFile.openWrite();
      var firstChunk = true;
      await for (final chunk in response) {
        _cancelToken.throwIfCanceled();
        if (firstChunk) {
          _validateFirstChunk(chunk, trustedContentType);
          firstChunk = false;
        }
        sink.add(chunk);
        await sink.flush();
        _downloadedBytes += chunk.length;
        _notifyChanged();
      }
      await sink.flush();
      _complete = true;
      _totalBytes ??= _downloadedBytes;
      _logger?.call(
        'progressive complete bytes=$_downloadedBytes part=${partFile.path}',
      );
      _notifyChanged();
    } catch (error) {
      if (_cancelToken.isCanceled || _closed) {
        return;
      }
      _fetchError = error;
      _notifyChanged();
    } finally {
      await sink?.close();
    }
  }

  Future<void> _pipeAvailableBytes(
    HttpResponse response,
    int start,
    int? end,
  ) async {
    var offset = start;
    final opened = await partFile.open(mode: FileMode.read);
    try {
      while (!_cancelToken.isCanceled) {
        final wanted = end == null
            ? offset + 64 * 1024
            : min(end + 1, offset + 64 * 1024);
        final availableEnd = min(wanted, _downloadedBytes);
        if (availableEnd > offset) {
          await opened.setPosition(offset);
          response.add(await opened.read(availableEnd - offset));
          offset = availableEnd;
          await response.flush();
          if (end != null && offset > end) {
            break;
          }
        }
        if (_complete && offset >= _downloadedBytes) {
          break;
        }
        if (_fetchError != null && offset >= _downloadedBytes) {
          break;
        }
        await _waitForBytes(offset + 1);
      }
    } finally {
      await opened.close();
      await response.close();
    }
  }

  Future<bool> _waitForBytes(int byteCount, {Duration? timeout}) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    while (_downloadedBytes < byteCount && !_complete && _fetchError == null) {
      final remaining = deadline?.difference(DateTime.now());
      if (remaining != null && remaining <= Duration.zero) {
        return false;
      }
      try {
        await _changed.stream.first.timeout(
          remaining ?? const Duration(seconds: 2),
        );
      } on TimeoutException {
        if (deadline != null) {
          return false;
        }
      }
    }
    return _downloadedBytes >= byteCount;
  }

  int? _totalFrom(HttpClientResponse response) {
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return response.contentLength > 0 ? response.contentLength : null;
  }

  _RangeRequest? _parseRange(String? header) {
    if (header == null || header.trim().isEmpty) {
      return null;
    }
    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(header.trim());
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final endText = match.group(2)!;
    final end = endText.isEmpty ? null : int.tryParse(endText);
    if (start == null || (end != null && end < start)) {
      return null;
    }
    return _RangeRequest(start, end);
  }

  String _audioSubtype() {
    final extension = extensionFromResolved(music).toLowerCase();
    return switch (extension) {
      '.flac' => 'flac',
      '.m4a' || '.mp4' => 'mp4',
      '.aac' => 'aac',
      '.ogg' => 'ogg',
      '.wav' => 'wav',
      _ => 'mpeg',
    };
  }

  void _notifyChanged() {
    if (!_closed) {
      _changed.add(null);
    }
  }

  bool _validateResponseContentType(HttpClientResponse response) {
    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    if (mimeType == null || mimeType.trim().isEmpty) {
      return false;
    }
    if (mimeType.startsWith('audio/')) {
      return true;
    }
    if (mimeType == 'application/octet-stream' ||
        mimeType == 'binary/octet-stream' ||
        mimeType == 'video/mp4') {
      return true;
    }
    if (mimeType.contains('html') ||
        mimeType.contains('json') ||
        mimeType.contains('xml') ||
        mimeType.contains('javascript')) {
      throw AudioValidationException(
        'progressive returned $mimeType instead of audio',
      );
    }
    if (mimeType.startsWith('text/')) {
      return false;
    }
    return false;
  }

  void _validateFirstChunk(List<int> chunk, bool trustedContentType) {
    if (_looksLikeTextResponse(chunk)) {
      throw const AudioValidationException(
        'progressive first chunk looks like text, not audio',
      );
    }
    if (!trustedContentType && !_hasAudioMagic(chunk)) {
      throw const AudioValidationException(
        'progressive first chunk is not recognized as audio',
      );
    }
  }
}

class _RangeRequest {
  const _RangeRequest(this.start, this.end);

  final int start;
  final int? end;
}

bool _hasAudioMagic(List<int> bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i += 1) {
      if (bytes[offset + i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  if (at(0, const [0x49, 0x44, 0x33])) {
    return true;
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
    return true;
  }
  return at(0, const [0x66, 0x4c, 0x61, 0x43]) ||
      (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
          at(8, const [0x57, 0x41, 0x56, 0x45])) ||
      at(0, const [0x4f, 0x67, 0x67, 0x53]) ||
      at(0, const [0x4d, 0x41, 0x43, 0x20]) ||
      at(4, const [0x66, 0x74, 0x79, 0x70]);
}

bool _looksLikeTextResponse(List<int> bytes) {
  final ascii = String.fromCharCodes(
    bytes.takeWhile((byte) => byte != 0).where((byte) => byte <= 0x7f),
  ).trimLeft().toLowerCase();
  if (ascii.isEmpty) {
    return false;
  }
  if (ascii.startsWith('<') || ascii.startsWith('{') || ascii.startsWith('[')) {
    return true;
  }
  return ascii.contains('<html') ||
      ascii.contains('<!doctype') ||
      ascii.contains('<script') ||
      ascii.contains('safeline') ||
      ascii.contains('captcha') ||
      ascii.contains('cloudflare') ||
      ascii.contains('challenge') ||
      ascii.contains('waf');
}
