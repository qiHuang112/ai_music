import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'json_file_store.dart';
import 'music_resolver.dart';
import 'resolver_utils.dart';
import '../platform/app_storage.dart';

class CachedTrack {
  const CachedTrack({
    required this.cacheId,
    required this.music,
    required this.filePath,
    required this.sizeBytes,
    required this.fromCache,
    this.lyricsPath = '',
    this.cachedAt,
  });

  final String cacheId;
  final ResolvedMusic music;
  final String filePath;
  final int sizeBytes;
  final bool fromCache;
  final String lyricsPath;
  final DateTime? cachedAt;

  CachedTrack copyWith({
    String? cacheId,
    ResolvedMusic? music,
    String? filePath,
    int? sizeBytes,
    bool? fromCache,
    String? lyricsPath,
    DateTime? cachedAt,
  }) {
    return CachedTrack(
      cacheId: cacheId ?? this.cacheId,
      music: music ?? this.music,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      fromCache: fromCache ?? this.fromCache,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cacheId': cacheId,
      'music': music.toJson(),
      'filePath': filePath,
      'sizeBytes': sizeBytes,
      'lyricsPath': lyricsPath,
      'cachedAt': cachedAt?.toIso8601String(),
    };
  }

  static CachedTrack? fromJson(Map<String, dynamic> json) {
    final musicJson = json['music'];
    if (musicJson is! Map<String, dynamic>) {
      return null;
    }
    final filePath = json['filePath']?.toString() ?? '';
    if (filePath.isEmpty) {
      return null;
    }
    final music = ResolvedMusic.fromJson(musicJson);
    return CachedTrack(
      cacheId: json['cacheId']?.toString().trim().isNotEmpty == true
          ? json['cacheId'].toString()
          : cacheIdForResolved(music),
      music: music,
      filePath: filePath,
      sizeBytes: json['sizeBytes'] is num
          ? (json['sizeBytes'] as num).toInt()
          : int.tryParse(json['sizeBytes']?.toString() ?? '') ?? 0,
      fromCache: true,
      lyricsPath: json['lyricsPath']?.toString() ?? '',
      cachedAt: _parseDateTime(json['cachedAt']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

class CacheIndexException implements Exception {
  const CacheIndexException(this.message, {this.backupPath});

  final String message;
  final String? backupPath;

  @override
  String toString() {
    final backup = backupPath == null ? '' : ' Backup: $backupPath';
    return '$message.$backup';
  }
}

class AudioValidationException implements Exception {
  const AudioValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CachedDownloadProgress {
  const CachedDownloadProgress({required this.bytes, required this.totalBytes});

  final int bytes;
  final int? totalBytes;

  double? get percent {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return bytes / total;
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download canceled';
}

class DownloadCancelToken {
  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  void cancel() {
    _isCanceled = true;
  }

  void throwIfCanceled() {
    if (_isCanceled) {
      throw const DownloadCancelledException();
    }
  }
}

abstract class AudioDownloader {
  Future<int> download(
    Uri url,
    File target, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  });
}

class HttpAudioDownloader implements AudioDownloader {
  HttpAudioDownloader({this.client, bool? requireHttps})
    : requireHttps =
          requireHttps ?? const bool.fromEnvironment('dart.vm.product');

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final HttpClient? client;
  final bool requireHttps;

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    if (requireHttps && url.scheme.toLowerCase() != 'https') {
      throw const AudioValidationException(
        'Release builds require HTTPS audio URLs',
      );
    }
    final ownsClient = client == null;
    final httpClient = client ?? HttpClient();
    try {
      cancelToken?.throwIfCanceled();
      await _validateRemoteAudio(url, httpClient, cancelToken);
      cancelToken?.throwIfCanceled();
      final request = await httpClient
          .getUrl(url)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      cancelToken?.throwIfCanceled();
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('download HTTP ${response.statusCode}', uri: url);
      }
      final mimeType = response.headers.contentType?.mimeType.toLowerCase();
      if (_isRejectedAudioContentType(mimeType)) {
        throw SourceDownloadException(
          '下载链接返回的不是音频内容。',
          failureCode: 'non_audio_content',
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : null;
      if (totalBytes != null && totalBytes < _minimumAudioBytes) {
        throw const SourceDownloadException(
          '下载链接返回的不是音频内容。',
          failureCode: 'non_audio_content',
        );
      }
      final sink = target.openWrite();
      var bytes = 0;
      var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await for (final chunk in response) {
          cancelToken?.throwIfCanceled();
          bytes += chunk.length;
          sink.add(chunk);
          final now = DateTime.now();
          if (now.difference(lastProgressAt).inMilliseconds >= 500 ||
              (totalBytes != null && bytes >= totalBytes)) {
            lastProgressAt = now;
            onProgress?.call(
              CachedDownloadProgress(bytes: bytes, totalBytes: totalBytes),
            );
          }
        }
      } finally {
        await sink.close();
      }
      return bytes;
    } on TimeoutException {
      throw const SourceDownloadException(
        '源站响应超时，请稍后再试。',
        failureCode: 'network_timeout',
      );
    } on AudioValidationException {
      throw const SourceDownloadException(
        '下载链接返回的不是音频内容。',
        failureCode: 'non_audio_content',
      );
    } finally {
      if (ownsClient) {
        httpClient.close(force: true);
      }
    }
  }

  Future<void> _validateRemoteAudio(
    Uri url,
    HttpClient httpClient,
    DownloadCancelToken? cancelToken,
  ) async {
    try {
      final request = await httpClient
          .openUrl('HEAD', url)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      cancelToken?.throwIfCanceled();
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final statusCode = response.statusCode;
      if (statusCode == HttpStatus.methodNotAllowed ||
          statusCode == HttpStatus.notImplemented ||
          statusCode == HttpStatus.forbidden) {
        await response.drain<void>();
        return;
      }
      if (statusCode < 200 || statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('download HEAD HTTP $statusCode', uri: url);
      }
      final mimeType = response.headers.contentType?.mimeType.toLowerCase();
      if (_isRejectedAudioContentType(mimeType)) {
        await response.drain<void>();
        throw SourceDownloadException(
          '下载链接返回的不是音频内容。',
          failureCode: 'non_audio_content',
        );
      }
      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : null;
      if (totalBytes != null && totalBytes < _minimumAudioBytes) {
        await response.drain<void>();
        throw const SourceDownloadException(
          '下载链接返回的不是音频内容。',
          failureCode: 'non_audio_content',
        );
      }
      await response.drain<void>();
    } on TimeoutException {
      throw const SourceDownloadException(
        '源站响应超时，请稍后再试。',
        failureCode: 'network_timeout',
      );
    }
  }
}

class CachedTrackStore {
  CachedTrackStore({
    Future<Directory> Function()? rootProvider,
    AudioDownloader? downloader,
  }) : _rootProvider = rootProvider ?? _defaultRoot,
       _downloader = downloader ?? HttpAudioDownloader();

  final Future<Directory> Function() _rootProvider;
  final AudioDownloader _downloader;
  Future<void> _indexTail = Future.value();

  Future<CachedTrack> downloadOrReuse(
    ResolvedMusic result, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCanceled();
    if (result.urlType == MediaUrlType.directAudioCandidate) {
      throw SourceDownloadException(
        '音频地址未通过客户端校验。',
        failureCode: 'audio_validation_failed',
        sourceAttempts: result.sourceAttempts,
      );
    }
    if (result.urlType == MediaUrlType.previewAudio || !result.canCacheAudio) {
      throw SourceDownloadException(
        '当前仅支持试听，无法缓存为完整歌曲。',
        failureCode: 'preview_audio_available',
        sourceAttempts: result.sourceAttempts,
      );
    }
    if (result.urlType == MediaUrlType.externalPan ||
        result.urlType == MediaUrlType.htmlPage) {
      final failureCode = failureCodeForUrlType(result.urlType);
      throw SourceDownloadException(
        _messageForFailureCode(failureCode),
        failureCode: failureCode,
        sourceAttempts: result.sourceAttempts,
      );
    }
    if (result.panLink) {
      throw SourceDownloadException(
        '源站只提供网盘链接，已跳过音频下载。',
        failureCode: 'external_pan_link',
        sourceAttempts: result.sourceAttempts,
      );
    }
    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    // cacheId 绑定来源、平台、id 和质量，避免同名歌曲/不同版本互相复用。
    final cacheId = cacheIdForResolved(result);
    final target = File(_targetPath(root, result));
    final existing = await _lookup(cacheId);
    if (existing != null && await File(existing.filePath).exists()) {
      final file = File(existing.filePath);
      try {
        await _validateAudioFile(file, result);
      } on AudioValidationException {
        await _deleteIfExists(file);
      }
    }
    if (existing != null && await File(existing.filePath).exists()) {
      final file = File(existing.filePath);
      final stat = await file.stat();
      final lyricsPath = await _writeLyricsIfNeeded(result, file);
      final cached = CachedTrack(
        cacheId: existing.cacheId,
        music: result,
        filePath: existing.filePath,
        sizeBytes: stat.size,
        fromCache: true,
        lyricsPath: lyricsPath.isNotEmpty ? lyricsPath : existing.lyricsPath,
        cachedAt: existing.cachedAt ?? stat.modified,
      );
      await _upsert(cached);
      return cached;
    }

    if (await target.exists()) {
      try {
        await _validateAudioFile(target, result);
      } on AudioValidationException {
        await _deleteIfExists(target);
      }
    }

    if (await target.exists()) {
      final stat = await target.stat();
      final lyricsPath = await _writeLyricsIfNeeded(result, target);
      final cached = CachedTrack(
        cacheId: cacheId,
        music: result,
        filePath: target.path,
        sizeBytes: stat.size,
        fromCache: true,
        lyricsPath: lyricsPath,
        cachedAt: stat.modified,
      );
      await _upsert(cached);
      return cached;
    }

    final temp = File(
      '${target.path}.download-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      // 先写临时文件并完成音频校验，通过后才 rename 和写索引，避免半文件进入缓存。
      final bytes = await _downloader.download(
        Uri.parse(result.url),
        temp,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      cancelToken?.throwIfCanceled();
      try {
        await _validateAudioFile(temp, result);
      } on AudioValidationException {
        throw SourceDownloadException(
          '下载链接返回的不是音频内容。',
          failureCode: 'non_audio_content',
          sourceAttempts: result.sourceAttempts,
        );
      }
      if (await target.exists()) {
        await temp.delete();
        await _validateAudioFile(target, result);
        final stat = await target.stat();
        final lyricsPath = await _writeLyricsIfNeeded(result, target);
        final cached = CachedTrack(
          cacheId: cacheId,
          music: result,
          filePath: target.path,
          sizeBytes: stat.size,
          fromCache: true,
          lyricsPath: lyricsPath,
          cachedAt: stat.modified,
        );
        await _upsert(cached);
        return cached;
      }
      await temp.rename(target.path);
      await _validateAudioFile(target, result);
      final lyricsPath = await _writeLyricsIfNeeded(result, target);
      final cached = CachedTrack(
        cacheId: cacheId,
        music: result,
        filePath: target.path,
        sizeBytes: bytes,
        fromCache: false,
        lyricsPath: lyricsPath,
        cachedAt: DateTime.now(),
      );
      await _upsert(cached);
      return cached;
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  Future<CachedTrack> adoptCompleteDownload(
    ResolvedMusic result,
    File completeFile,
  ) async {
    if (result.panLink) {
      throw UnsupportedError('Cloud-drive links cannot be cached as audio.');
    }
    if (!await completeFile.exists()) {
      throw FileSystemException('Progressive audio missing', completeFile.path);
    }
    await _validateAudioFile(completeFile, result);

    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final cacheId = cacheIdForResolved(result);
    final target = File(_targetPath(root, result));
    if (completeFile.path != target.path) {
      if (await target.exists()) {
        await _validateAudioFile(target, result);
        await completeFile.delete();
      } else {
        await completeFile.rename(target.path);
      }
    }
    final audioFile = File(target.path);
    await _validateAudioFile(audioFile, result);
    final stat = await audioFile.stat();
    final lyricsPath = await _writeLyricsIfNeeded(result, audioFile);
    final cached = CachedTrack(
      cacheId: cacheId,
      music: result,
      filePath: audioFile.path,
      sizeBytes: stat.size,
      fromCache: false,
      lyricsPath: lyricsPath,
      cachedAt: DateTime.now(),
    );
    await _upsert(cached);
    return cached;
  }

  Future<void> cleanupTemporaryFiles() async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      return;
    }
    await for (final entity in root.list()) {
      if (entity is File && entity.path.contains('.download-')) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort startup cleanup.
        }
      }
    }
  }

  Future<void> deleteCached(String cacheId) async {
    await _withIndexLock(() async {
      final root = await _rootProvider();
      if (!await root.exists()) {
        return;
      }
      final rows = await _readIndex(root);
      Map<String, dynamic>? removed;
      rows.removeWhere((row) {
        final match = row['cacheId'] == cacheId;
        if (match) {
          removed = row;
        }
        return match;
      });
      final cached = removed == null ? null : CachedTrack.fromJson(removed!);
      if (cached != null) {
        await _deleteIfExists(File(cached.filePath));
        if (cached.lyricsPath.isNotEmpty) {
          await _deleteIfExists(File(cached.lyricsPath));
        }
        await _deleteIfExists(File(lyricsPathForAudioPath(cached.filePath)));
      }
      await _writeIndex(root, rows);
    });
  }

  Future<CachedTrack> updateCachedMusic(
    CachedTrack cached,
    ResolvedMusic music,
  ) async {
    final file = File(cached.filePath);
    if (!await file.exists()) {
      throw FileSystemException('Cached audio missing', cached.filePath);
    }
    final stat = await file.stat();
    final lyricsPath = await _writeLyricsIfNeeded(music, file);
    final updated = cached.copyWith(
      music: music,
      sizeBytes: stat.size,
      fromCache: true,
      lyricsPath: lyricsPath.isNotEmpty ? lyricsPath : cached.lyricsPath,
      cachedAt: cached.cachedAt ?? stat.modified,
    );
    await _upsert(updated);
    return updated;
  }

  Future<List<CachedTrack>> listCached() async {
    return _withIndexLock(() async {
      final root = await _rootProvider();
      final index = await _readIndex(root);
      final tracks = <CachedTrack>[];
      for (final row in index) {
        final cached = CachedTrack.fromJson(row);
        if (cached == null) {
          continue;
        }
        final file = File(cached.filePath);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        tracks.add(
          CachedTrack(
            cacheId: cached.cacheId,
            music: cached.music,
            filePath: cached.filePath,
            sizeBytes: stat.size,
            fromCache: true,
            lyricsPath: cached.lyricsPath,
            cachedAt: cached.cachedAt ?? stat.modified,
          ),
        );
      }
      final deduped = _dedupeCachedTracks(tracks);
      if (deduped.length != index.length) {
        await _writeIndex(root, [for (final track in deduped) track.toJson()]);
      }
      deduped.sort((a, b) => a.music.name.compareTo(b.music.name));
      return deduped;
    });
  }

  String _targetPath(Directory root, ResolvedMusic result) {
    final artist = sanitizeFilePart(result.artist, 'unknown-artist');
    final name = sanitizeFilePart(
      result.name.isNotEmpty ? result.name : result.query,
      'unknown-title',
    );
    final shortId = cacheIdForResolved(result).substring(0, 10);
    return '${root.path}${Platform.pathSeparator}$artist-$name-$shortId${extensionFromResolved(result)}';
  }

  Future<String> _writeLyricsIfNeeded(
    ResolvedMusic result,
    File audioFile,
  ) async {
    final lyrics = result.lyrics;
    if (lyrics == null || lyrics.text.trim().isEmpty) {
      return '';
    }
    final target = File(lyricsPathForAudioPath(audioFile.path));
    if (await target.exists()) {
      return target.path;
    }
    final temp = File(
      '${target.path}.download-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      final text = '${lyrics.text.trimRight()}\n';
      await temp.writeAsString(text);
      if (await target.exists()) {
        await temp.delete();
      } else {
        await temp.rename(target.path);
      }
      return target.path;
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  static Future<Directory> _defaultRoot() async {
    return getAiMusicSupportSubdirectory('ai_music_cache');
  }

  Future<void> _upsert(CachedTrack cached) async {
    await _withIndexLock(() async {
      final root = await _rootProvider();
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      final rows = await _readIndex(root);
      rows.removeWhere((row) => row['cacheId'] == cached.cacheId);
      rows.add(cached.toJson());
      rows.sort((a, b) {
        final left = _sortTitle(a);
        final right = _sortTitle(b);
        return left.compareTo(right);
      });
      await _writeIndex(root, rows);
    });
  }

  Future<CachedTrack?> _lookup(String cacheId) async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      return null;
    }
    final rows = await _readIndex(root);
    for (final row in rows) {
      final cached = CachedTrack.fromJson(row);
      if (cached != null && cached.cacheId == cacheId) {
        return cached;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _readIndex(Directory root) async {
    final file = _indexFile(root);
    if (!await file.exists()) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        final backup = await _backupCorruptIndex(file);
        throw CacheIndexException(
          'Cache index is not a JSON list',
          backupPath: backup.path,
        );
      }
      return decoded
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(growable: true);
    } on CacheIndexException {
      rethrow;
    } catch (error) {
      final backup = await _backupCorruptIndex(file);
      throw CacheIndexException(
        'Cache index is damaged: $error',
        backupPath: backup.path,
      );
    }
  }

  Future<void> _writeIndex(
    Directory root,
    List<Map<String, dynamic>> rows,
  ) async {
    final file = _indexFile(root);
    await const JsonFileStore().write(file, rows);
  }

  Future<File> _backupCorruptIndex(File file) async {
    return const JsonFileStore().backupCorruptFile(file);
  }

  Future<T> _withIndexLock<T>(Future<T> Function() action) {
    // 缓存索引是 read-modify-write；串行化避免并发下载完成时互相覆盖索引。
    final previous = _indexTail;
    final completer = Completer<void>();
    _indexTail = previous.then((_) => completer.future);
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }

  File _indexFile(Directory root) {
    return File('${root.path}${Platform.pathSeparator}_cache_index.json');
  }
}

List<CachedTrack> _dedupeCachedTracks(List<CachedTrack> tracks) {
  final byCacheId = <String, CachedTrack>{};
  for (final track in tracks) {
    byCacheId.update(
      track.cacheId,
      (current) => _preferCachedTrack(current, track),
      ifAbsent: () => track,
    );
  }

  final byFilePath = <String, CachedTrack>{};
  for (final track in byCacheId.values) {
    byFilePath.update(
      track.filePath,
      (current) => _preferCachedTrack(current, track),
      ifAbsent: () => track,
    );
  }
  return byFilePath.values.toList(growable: false);
}

CachedTrack _preferCachedTrack(CachedTrack left, CachedTrack right) {
  final byTime = _cachedTrackTime(right).compareTo(_cachedTrackTime(left));
  if (byTime > 0) {
    return right;
  }
  if (byTime < 0) {
    return left;
  }
  if (right.sizeBytes > left.sizeBytes) {
    return right;
  }
  return left;
}

DateTime _cachedTrackTime(CachedTrack track) {
  return track.cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

const _minimumAudioBytes = 16 * 1024;

Future<void> _validateAudioFile(File file, ResolvedMusic result) async {
  // 第三方源可能 200 返回 HTML/JSON/反爬页；写入索引前必须做内容级校验。
  final length = await file.length();
  if (length < _minimumAudioBytes) {
    throw const AudioValidationException('downloaded audio is too small');
  }
  final header = await _readHeader(file, min<int>(512, length));
  if (_looksLikeTextResponse(header)) {
    throw const AudioValidationException(
      'downloaded file looks like text, not audio',
    );
  }
  if (_hasAudioMagic(header)) {
    return;
  }
  final extension = extensionFromResolved(result).toLowerCase();
  if (_knownAudioExtensions.contains(extension)) {
    return;
  }
  throw AudioValidationException('downloaded file is not recognized as audio');
}

Future<List<int>> _readHeader(File file, int byteCount) async {
  final opened = await file.open();
  try {
    return await opened.read(byteCount);
  } finally {
    await opened.close();
  }
}

bool _isRejectedAudioContentType(String? mimeType) {
  if (mimeType == null || mimeType.trim().isEmpty) {
    return false;
  }
  final mime = mimeType.toLowerCase();
  if (mime.startsWith('audio/')) {
    return false;
  }
  if (mime == 'application/octet-stream' ||
      mime == 'binary/octet-stream' ||
      mime == 'video/mp4') {
    return false;
  }
  return mime.startsWith('text/') ||
      mime.contains('html') ||
      mime.contains('json') ||
      mime.contains('xml') ||
      mime.contains('javascript');
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
    return true; // MP3 ID3
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
    return true; // MP3/AAC frame sync
  }
  return at(0, const [0x66, 0x4c, 0x61, 0x43]) || // fLaC
      (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
          at(8, const [0x57, 0x41, 0x56, 0x45])) || // RIFF/WAVE
      at(0, const [0x4f, 0x67, 0x67, 0x53]) || // OggS
      at(0, const [0x4d, 0x41, 0x43, 0x20]) || // APE MAC
      at(4, const [0x66, 0x74, 0x79, 0x70]); // MP4/M4A ftyp
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
      ascii.contains('waf');
}

const _knownAudioExtensions = {
  '.mp3',
  '.flac',
  '.wav',
  '.m4a',
  '.mp4',
  '.aac',
  '.ogg',
  '.ape',
};

String _messageForFailureCode(String failureCode) {
  return switch (failureCode) {
    'external_pan_link' => '源站只提供网盘链接，已跳过音频下载。',
    'non_audio_content' => '下载链接返回的不是音频内容。',
    'network_timeout' => '源站响应超时，请稍后再试。',
    _ => '暂时没有可下载的音频直链。',
  };
}

Future<void> _deleteIfExists(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Deleting cache is best-effort; stale index rows are removed regardless.
  }
}

String cacheIdForResolved(ResolvedMusic result) {
  final identity = result.id.trim().isNotEmpty
      ? result.id.trim()
      : result.url.trim().isNotEmpty
      ? result.url.trim()
      : '${result.artist}|${result.name}|${result.query}';
  final qualityKey = [
    result.quality.format,
    result.quality.bitrate,
    result.quality.size,
  ].map((value) => value.trim().toLowerCase()).join('|');
  final raw = [
    result.source.storageValue,
    result.platform.trim().toLowerCase(),
    identity,
    qualityKey,
  ].join('|');
  return sha1.convert(utf8.encode(raw)).toString();
}

String lyricsPathForAudioPath(String audioPath) {
  if (audioPath.trim().isEmpty) {
    return '';
  }
  final separator = Platform.pathSeparator;
  final slashIndex = audioPath.lastIndexOf(separator);
  final fileNameStart = slashIndex == -1 ? 0 : slashIndex + 1;
  final dotIndex = audioPath.lastIndexOf('.');
  final cut = dotIndex > fileNameStart ? dotIndex : audioPath.length;
  return '${audioPath.substring(0, cut)}.lrc';
}

String _sortTitle(Map<String, dynamic> row) {
  final music = row['music'];
  if (music is Map) {
    return (music['name'] ?? music['query'] ?? '').toString();
  }
  return '';
}

String sanitizeFilePart(String? value, String fallback) {
  final cleaned = (value?.trim().isNotEmpty == true ? value!.trim() : fallback)
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safe = cleaned.isEmpty ? fallback : cleaned;
  return safe.substring(0, min(100, safe.length));
}

String extensionFromResolved(ResolvedMusic result) {
  try {
    final extension = _extension(Uri.parse(result.url).path);
    if (RegExp(r'^\.[a-z0-9]{2,6}$').hasMatch(extension)) {
      return extension;
    }
  } catch (_) {
    // Fall through to quality-based detection.
  }

  final format = result.quality.format.toLowerCase();
  if (format.contains('flac')) {
    return '.flac';
  }
  if (format.contains('mp3')) {
    return '.mp3';
  }
  if (format.contains('wav')) {
    return '.wav';
  }
  if (format.contains('ape')) {
    return '.ape';
  }
  if (format.isNotEmpty) {
    return '.${sanitizeFilePart(format, 'audio').toLowerCase()}';
  }
  return '.mp3';
}

String _extension(String path) {
  final index = path.lastIndexOf('.');
  return index == -1 ? '' : path.substring(index).toLowerCase();
}
