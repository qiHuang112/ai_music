import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'json_file_store.dart';
import 'music_cache.dart';
import 'music_resolver.dart';
import '../platform/app_storage.dart';

enum TransientStreamingState { active, complete, failed, canceled }

class TransientStreamingCacheEntry {
  const TransientStreamingCacheEntry({
    required this.cacheKey,
    required this.filePath,
    required this.downloadedBytes,
    required this.state,
    required this.createdAt,
    required this.lastAccessed,
    required this.playCount,
    required this.source,
    required this.quality,
    this.totalBytes,
  });

  final String cacheKey;
  final String filePath;
  final int downloadedBytes;
  final int? totalBytes;
  final TransientStreamingState state;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final int playCount;
  final String source;
  final String quality;

  TransientStreamingCacheEntry copyWith({
    int? downloadedBytes,
    int? totalBytes,
    TransientStreamingState? state,
    DateTime? lastAccessed,
    int? playCount,
  }) {
    return TransientStreamingCacheEntry(
      cacheKey: cacheKey,
      filePath: filePath,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      state: state ?? this.state,
      createdAt: createdAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      playCount: playCount ?? this.playCount,
      source: source,
      quality: quality,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cacheKey': cacheKey,
      'filePath': filePath,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
      'state': state.name,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessed': lastAccessed.toIso8601String(),
      'playCount': playCount,
      'source': source,
      'quality': quality,
    };
  }

  static TransientStreamingCacheEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final json = value.cast<String, dynamic>();
    final cacheKey = json['cacheKey']?.toString().trim() ?? '';
    final filePath = json['filePath']?.toString().trim() ?? '';
    if (cacheKey.isEmpty || filePath.isEmpty) {
      return null;
    }
    return TransientStreamingCacheEntry(
      cacheKey: cacheKey,
      filePath: filePath,
      downloadedBytes: _int(json['downloadedBytes']),
      totalBytes: _nullableInt(json['totalBytes']),
      state: TransientStreamingState.values.byName(
        json['state']?.toString() ?? TransientStreamingState.active.name,
      ),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastAccessed:
          DateTime.tryParse(json['lastAccessed']?.toString() ?? '') ??
          DateTime.now(),
      playCount: _int(json['playCount']),
      source: json['source']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
    );
  }
}

class TransientStreamingCacheStore {
  TransientStreamingCacheStore({
    Future<Directory> Function()? rootProvider,
    JsonFileStore store = const JsonFileStore(),
    DateTime Function()? now,
  }) : _rootProvider =
           rootProvider ??
           (() => getAiMusicSupportSubdirectory('hotlist_transient_cache')),
       _store = store,
       _now = now ?? DateTime.now;

  static const _indexName = 'transient_streaming_cache.json';

  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _store;
  final DateTime Function() _now;
  Future<void> _writeTail = Future.value();

  Future<File> createPartFile(String cacheKey) async {
    final root = await _root();
    return File(
      '${root.path}${Platform.pathSeparator}$cacheKey'
      '.transient-${_now().microsecondsSinceEpoch}.part',
    );
  }

  Future<TransientStreamingCacheEntry> markStarted({
    required ResolvedMusic music,
    required File file,
  }) async {
    final now = _now();
    final entry = TransientStreamingCacheEntry(
      cacheKey: cacheIdForResolved(music),
      filePath: file.path,
      downloadedBytes: 0,
      state: TransientStreamingState.active,
      createdAt: now,
      lastAccessed: now,
      playCount: 1,
      source: music.source.storageValue,
      quality: music.quality.label,
    );
    await upsert(entry);
    return entry;
  }

  Future<void> updateProgress(
    String cacheKey, {
    required int downloadedBytes,
    int? totalBytes,
    required TransientStreamingState state,
  }) async {
    await _withWriteLock(() async {
      final entries = await _read();
      final index = entries.indexWhere((entry) => entry.cacheKey == cacheKey);
      if (index == -1) {
        return;
      }
      entries[index] = entries[index].copyWith(
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        state: state,
        lastAccessed: _now(),
      );
      await _write(entries);
    });
  }

  Future<void> touch(String cacheKey) async {
    await _withWriteLock(() async {
      final entries = await _read();
      final index = entries.indexWhere((entry) => entry.cacheKey == cacheKey);
      if (index == -1) {
        return;
      }
      final current = entries[index];
      entries[index] = current.copyWith(
        lastAccessed: _now(),
        playCount: current.playCount + 1,
      );
      await _write(entries);
    });
  }

  Future<void> upsert(TransientStreamingCacheEntry entry) async {
    await _withWriteLock(() async {
      final entries = await _read();
      final index = entries.indexWhere(
        (item) => item.cacheKey == entry.cacheKey,
      );
      if (index == -1) {
        entries.add(entry);
      } else {
        await _deleteTransientFileIfUnused(entries[index], replacement: entry);
        entries[index] = entry;
      }
      await _write(entries);
    });
  }

  Future<List<TransientStreamingCacheEntry>> list() async {
    return _read();
  }

  Future<int> sweep({required int maxBytes}) async {
    return _withWriteLock(() async {
      final entries = await _read();
      var total = 0;
      final existing = <TransientStreamingCacheEntry>[];
      for (final entry in entries) {
        final file = File(entry.filePath);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        total += stat.size;
        existing.add(entry.copyWith(downloadedBytes: stat.size));
      }
      existing.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
      var removed = 0;
      while (total > maxBytes && existing.isNotEmpty) {
        final victim = existing.removeAt(0);
        final file = File(victim.filePath);
        if (await file.exists()) {
          final size = await file.length();
          await file.delete();
          total -= size;
          removed += 1;
        }
      }
      await _write(existing);
      return removed;
    });
  }

  Future<Directory> _root() async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<List<TransientStreamingCacheEntry>> _read() async {
    final value = await _store.read(await _indexFile());
    if (value is! Map) {
      return <TransientStreamingCacheEntry>[];
    }
    final rows = value['entries'] is List ? value['entries'] as List : [];
    return [
      for (final row in rows) ?TransientStreamingCacheEntry.fromJson(row),
    ];
  }

  Future<void> _write(List<TransientStreamingCacheEntry> entries) async {
    await _store.write(await _indexFile(), {
      'entries': [for (final entry in entries) entry.toJson()],
    });
  }

  Future<File> _indexFile() async {
    final root = await _root();
    return File('${root.path}${Platform.pathSeparator}$_indexName');
  }

  Future<void> _deleteTransientFileIfUnused(
    TransientStreamingCacheEntry oldEntry, {
    required TransientStreamingCacheEntry replacement,
  }) async {
    if (oldEntry.filePath == replacement.filePath) {
      return;
    }
    final root = await _root();
    final transientPrefix = '${root.path}${Platform.pathSeparator}';
    if (!oldEntry.filePath.startsWith(transientPrefix)) {
      return;
    }
    final file = File(oldEntry.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<T> _withWriteLock<T>(Future<T> Function() action) {
    final run = _writeTail.then((_) => action());
    _writeTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

class StreamingPlaybackPolicy {
  const StreamingPlaybackPolicy({this.maxTransientBytes = 256 * 1024 * 1024});

  final int maxTransientBytes;
}

class StreamingPlaybackHandle {
  const StreamingPlaybackHandle({
    required this.proxyUri,
    required this.session,
  });

  final Uri proxyUri;
  final ProgressiveAudioSession session;
  Stream<void> get progress => session.changes;
}

abstract interface class HotlistStreamingPlayback {
  Future<StreamingPlaybackHandle> openHotlistTrack(
    ResolvedMusic resolved,
    StreamingPlaybackPolicy policy,
  );

  Future<void> close();
}

class StreamingPlaybackCache implements HotlistStreamingPlayback {
  StreamingPlaybackCache({
    required CachedTrackStore cacheStore,
    ProgressiveAudioCache? progressiveCache,
    TransientStreamingCacheStore? transientStore,
    void Function(String message)? logger,
  }) : transientStore = transientStore ?? TransientStreamingCacheStore(),
       _progressiveCache =
           progressiveCache ??
           ProgressiveAudioCache(cacheStore: cacheStore, logger: logger);

  final ProgressiveAudioCache _progressiveCache;
  final TransientStreamingCacheStore transientStore;

  @override
  Future<StreamingPlaybackHandle> openHotlistTrack(
    ResolvedMusic resolved,
    StreamingPlaybackPolicy policy,
  ) async {
    await transientStore.sweep(maxBytes: policy.maxTransientBytes);
    final session = await _progressiveCache.openHotlistTrack(
      resolved,
      transientStore: transientStore,
    );
    return StreamingPlaybackHandle(
      proxyUri: session.proxyUri,
      session: session,
    );
  }

  @override
  Future<void> close() => _progressiveCache.close();
}

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
    return _open(music);
  }

  Future<ProgressiveAudioSession> openHotlistTrack(
    ResolvedMusic music, {
    required TransientStreamingCacheStore transientStore,
  }) async {
    final cacheKey = cacheIdForResolved(music);
    final partFile = await transientStore.createPartFile(cacheKey);
    final session = await _open(
      music,
      partFile: partFile,
      transientStore: transientStore,
      transientCacheKey: cacheKey,
    );
    await transientStore.markStarted(music: music, file: partFile);
    _logger?.call('hotlist streaming transient-start cacheKey=$cacheKey');
    return session;
  }

  Future<ProgressiveAudioSession> _open(
    ResolvedMusic music, {
    File? partFile,
    TransientStreamingCacheStore? transientStore,
    String? transientCacheKey,
  }) async {
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
    final nextPartFile =
        partFile ??
        File(
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
      partFile: nextPartFile,
      cacheStore: cacheStore,
      client: _client,
      firstByteTimeout: _firstByteTimeout,
      logger: _logger,
      transientStore: transientStore,
      transientCacheKey: transientCacheKey,
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
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final token = _sessionTokenFrom(request.uri);
      if (token == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (_retiredTokens.contains(token)) {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
        return;
      }
      final session = _sessions[token];
      if (session == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      unawaited(_handleSessionRequest(session, request));
    } catch (error) {
      _logger?.call('progressive proxy routing failed error=$error');
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        // Headers may already be committed by a partially handled request.
      }
      try {
        await request.response.close();
      } catch (_) {
        // The client may have disconnected before routing completed.
      }
    }
  }

  Future<void> _handleSessionRequest(
    ProgressiveAudioSession session,
    HttpRequest request,
  ) async {
    try {
      await session.handle(request);
    } catch (error) {
      _logger?.call('progressive proxy request failed error=$error');
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        // Headers may already be committed for a stream that disconnected.
      }
      try {
        await request.response.close();
      } catch (_) {
        // The client may have already closed the seek request.
      }
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
    TransientStreamingCacheStore? transientStore,
    String? transientCacheKey,
  }) : _cacheStore = cacheStore,
       _client = client,
       _firstByteTimeout = firstByteTimeout,
       _logger = logger,
       _transientStore = transientStore,
       _transientCacheKey = transientCacheKey;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final ResolvedMusic music;
  final Uri proxyUri;
  final File partFile;
  File? _promotedFile;
  final CachedTrackStore _cacheStore;
  final HttpClient _client;
  final Duration _firstByteTimeout;
  final void Function(String message)? _logger;
  final TransientStreamingCacheStore? _transientStore;
  final String? _transientCacheKey;
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
    if (_fetchError != null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    var rangeProxyFailed = false;
    if (range != null && start > _downloadedBytes) {
      final proxied = await _proxyUpstreamRange(request.response, range);
      if (proxied) {
        return;
      }
      rangeProxyFailed = true;
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
      request.response.statusCode = rangeProxyFailed
          ? HttpStatus.badGateway
          : HttpStatus.gatewayTimeout;
      if (rangeProxyFailed) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${currentTotal ?? '*'}',
        );
      }
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
    _promotedFile = File(cached.filePath);
    _logger?.call(
      'progressive promoted cacheId=${cached.cacheId} file=${cached.filePath}',
    );
    return cached;
  }

  Future<void> cancel({bool deletePartFile = false}) async {
    _cancelToken.cancel();
    await _updateTransient(TransientStreamingState.canceled);
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
      var response = await _openUpstream(useRange: true);
      if (!_isUsableInitialRangeResponse(response)) {
        await response.drain<void>();
        response = await _openUpstream(useRange: false);
      }
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
        unawaited(_updateTransient(TransientStreamingState.active));
        _notifyChanged();
      }
      await sink.flush();
      final expectedBytes = _totalBytes;
      if (expectedBytes != null && _downloadedBytes != expectedBytes) {
        throw SourceDownloadException(
          '流式音频响应不完整，未写入正式缓存。',
          failureCode: 'incomplete_audio_response',
          sourceAttempts: music.sourceAttempts,
        );
      }
      _complete = true;
      _totalBytes ??= _downloadedBytes;
      await _updateTransient(TransientStreamingState.complete);
      _logger?.call(
        'progressive complete bytes=$_downloadedBytes part=${partFile.path}',
      );
      _notifyChanged();
    } catch (error) {
      if (_cancelToken.isCanceled || _closed) {
        return;
      }
      _fetchError = error;
      await _updateTransient(TransientStreamingState.failed);
      _notifyChanged();
    } finally {
      await sink?.close();
    }
  }

  Future<HttpClientResponse> _openUpstream({required bool useRange}) async {
    final request = await _client.getUrl(Uri.parse(music.url));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    if (useRange) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    }
    return request.close();
  }

  Future<bool> _proxyUpstreamRange(
    HttpResponse localResponse,
    _RangeRequest range,
  ) async {
    HttpClientResponse? upstream;
    StreamIterator<List<int>>? chunks;
    try {
      final request = await _client.getUrl(Uri.parse(music.url));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=${range.start}-${range.end ?? ''}',
      );
      upstream = await request.close();
      final contentRange = _parseContentRange(
        upstream.headers.value(HttpHeaders.contentRangeHeader),
      );
      final knownTotal = _totalBytes;
      final expectedEnd = range.end == null
          ? null
          : min(range.end!, (contentRange?.total ?? 1) - 1);
      final aligned =
          upstream.statusCode == HttpStatus.partialContent &&
          contentRange != null &&
          contentRange.start == range.start &&
          (expectedEnd == null || contentRange.end == expectedEnd) &&
          (knownTotal == null || contentRange.total == knownTotal);
      if (!aligned || !_validateResponseContentType(upstream)) {
        await upstream.drain<void>();
        _logger?.call(
          'progressive range rejected status=${upstream.statusCode} '
          'requested=${range.start}-${range.end ?? ''} '
          'knownTotal=$knownTotal receivedTotal=${contentRange?.total} '
          'contentRange=${upstream.headers.value(HttpHeaders.contentRangeHeader)}',
        );
        return false;
      }

      chunks = StreamIterator<List<int>>(upstream);
      if (!await chunks.moveNext()) {
        _logger?.call(
          'progressive range rejected empty body requested=${range.start}-${range.end ?? ''}',
        );
        return false;
      }
      _validateFirstChunk(chunks.current, true);

      _totalBytes ??= contentRange.total;
      localResponse.statusCode = HttpStatus.partialContent;
      localResponse.headers.contentType = ContentType('audio', _audioSubtype());
      localResponse.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      localResponse.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${contentRange.start}-${contentRange.end}/${contentRange.total}',
      );
      localResponse.contentLength = contentRange.end - contentRange.start + 1;
      localResponse.add(chunks.current);
      while (await chunks.moveNext()) {
        _cancelToken.throwIfCanceled();
        localResponse.add(chunks.current);
      }
      await localResponse.close();
      _logger?.call(
        'progressive range proxied bytes=${contentRange.start}-${contentRange.end}/${contentRange.total}',
      );
      return true;
    } catch (error) {
      _logger?.call(
        'progressive range failed requested=${range.start}-${range.end ?? ''} '
        'error=$error',
      );
      return false;
    } finally {
      await chunks?.cancel();
    }
  }

  bool _isUsableInitialRangeResponse(HttpClientResponse response) {
    if (response.statusCode == HttpStatus.ok) {
      return true;
    }
    if (response.statusCode != HttpStatus.partialContent) {
      return false;
    }
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange == null) {
      return false;
    }
    final match = RegExp(
      r'^bytes\s+0-\d+/(\d+)$',
    ).firstMatch(contentRange.trim());
    final total = match == null ? null : int.tryParse(match.group(1)!);
    return total != null && total > 0;
  }

  _ContentRange? _parseContentRange(String? header) {
    if (header == null) {
      return null;
    }
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+)$',
    ).firstMatch(header.trim());
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null ||
        end == null ||
        total == null ||
        start > end ||
        end >= total) {
      return null;
    }
    return _ContentRange(start: start, end: end, total: total);
  }

  Future<void> _pipeAvailableBytes(
    HttpResponse response,
    int start,
    int? end,
  ) async {
    var offset = start;
    final opened = await (_promotedFile ?? partFile).open(mode: FileMode.read);
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
      } on StateError {
        return false;
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

  Future<void> _updateTransient(TransientStreamingState state) async {
    final store = _transientStore;
    final cacheKey = _transientCacheKey;
    if (store == null || cacheKey == null) {
      return;
    }
    await store.updateProgress(
      cacheKey,
      downloadedBytes: _downloadedBytes,
      totalBytes: _totalBytes,
      state: state,
    );
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

class _ContentRange {
  const _ContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
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

int _int(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}
