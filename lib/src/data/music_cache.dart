import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'json_file_store.dart';
import 'lan_library_client.dart';
import 'lan_library_models.dart';
import 'music_resolver.dart';
import '../platform/app_storage.dart';

class CachedTrack {
  const CachedTrack({
    required this.cacheId,
    required this.music,
    required this.filePath,
    required this.sizeBytes,
    required this.fromCache,
    this.lyricsPath = '',
    this.artworkPath = '',
    this.contentSha256 = '',
    this.lyricsSha256 = '',
    this.artworkSha256 = '',
    this.cachedAt,
  });

  final String cacheId;
  final ResolvedMusic music;
  final String filePath;
  final int sizeBytes;
  final bool fromCache;
  final String lyricsPath;
  final String artworkPath;
  final String contentSha256;
  final String lyricsSha256;
  final String artworkSha256;
  final DateTime? cachedAt;

  CachedTrack copyWith({
    String? cacheId,
    ResolvedMusic? music,
    String? filePath,
    int? sizeBytes,
    bool? fromCache,
    String? lyricsPath,
    String? artworkPath,
    String? contentSha256,
    String? lyricsSha256,
    String? artworkSha256,
    DateTime? cachedAt,
  }) {
    return CachedTrack(
      cacheId: cacheId ?? this.cacheId,
      music: music ?? this.music,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      fromCache: fromCache ?? this.fromCache,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      artworkPath: artworkPath ?? this.artworkPath,
      contentSha256: contentSha256 ?? this.contentSha256,
      lyricsSha256: lyricsSha256 ?? this.lyricsSha256,
      artworkSha256: artworkSha256 ?? this.artworkSha256,
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
      'artworkPath': artworkPath,
      'contentSha256': contentSha256,
      'lyricsSha256': lyricsSha256,
      'artworkSha256': artworkSha256,
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
      artworkPath: json['artworkPath']?.toString() ?? '',
      contentSha256: json['contentSha256']?.toString() ?? '',
      lyricsSha256: json['lyricsSha256']?.toString() ?? '',
      artworkSha256: json['artworkSha256']?.toString() ?? '',
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

class AudioTruncatedException extends AudioValidationException {
  const AudioTruncatedException(super.message);
}

class AudioRetryAfterException implements Exception {
  const AudioRetryAfterException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'Audio source is rate limited';
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
  bool _committing = false;
  final Completer<void> _canceled = Completer<void>();

  bool get isCanceled => _isCanceled;
  Future<void> get whenCanceled => _canceled.future;

  bool cancel() {
    if (_isCanceled || _committing) return false;
    _isCanceled = true;
    _canceled.complete();
    return true;
  }

  void beginCommit() {
    throwIfCanceled();
    _committing = true;
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
  HttpAudioDownloader({
    this.client,
    this.bodyIdleTimeout = const Duration(seconds: 30),
    this.bodyTotalTimeout = const Duration(minutes: 15),
  });

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final HttpClient? client;
  final Duration bodyIdleTimeout;
  final Duration bodyTotalTimeout;

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final ownsClient = client == null;
    final httpClient = client ?? HttpClient();
    try {
      cancelToken?.throwIfCanceled();
      final request = await httpClient
          .getUrl(url)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      cancelToken?.throwIfCanceled();
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == HttpStatus.tooManyRequests) {
        final header = response.headers.value(HttpHeaders.retryAfterHeader);
        Duration retryAfter = Duration.zero;
        final seconds = int.tryParse(header ?? '');
        if (seconds != null && seconds > 0) {
          retryAfter = Duration(seconds: seconds);
        } else if (header != null) {
          try {
            final until = HttpDate.parse(
              header,
            ).difference(DateTime.now().toUtc());
            if (until > Duration.zero) retryAfter = until;
          } catch (_) {}
        }
        throw AudioRetryAfterException(retryAfter);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('download HTTP ${response.statusCode}', uri: url);
      }
      final mimeType = response.headers.contentType?.mimeType.toLowerCase();
      if (_isRejectedAudioContentType(mimeType)) {
        throw AudioValidationException(
          'download returned $mimeType instead of audio',
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : null;
      if (totalBytes != null && totalBytes < _minimumAudioBytes) {
        throw AudioValidationException('download is too small to be audio');
      }
      final sink = target.openWrite();
      var bytes = 0;
      var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
      final bodyDone = Completer<void>();
      StreamSubscription<List<int>>? subscription;
      Timer? idleTimer;
      Timer? totalTimer;
      void fail(Object error, StackTrace stackTrace) {
        if (bodyDone.isCompleted) return;
        bodyDone.completeError(error, stackTrace);
        final active = subscription;
        if (active != null) unawaited(active.cancel());
      }

      void restartIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(
          bodyIdleTimeout,
          () => fail(
            TimeoutException('Audio body stopped sending bytes'),
            StackTrace.current,
          ),
        );
      }

      try {
        subscription = response.listen(
          (chunk) {
            try {
              cancelToken?.throwIfCanceled();
              bytes += chunk.length;
              sink.add(chunk);
              restartIdleTimer();
              final now = DateTime.now();
              if (now.difference(lastProgressAt).inMilliseconds >= 500 ||
                  (totalBytes != null && bytes >= totalBytes)) {
                lastProgressAt = now;
                onProgress?.call(
                  CachedDownloadProgress(bytes: bytes, totalBytes: totalBytes),
                );
              }
            } catch (error, stackTrace) {
              fail(error, stackTrace);
            }
          },
          onError: fail,
          onDone: () {
            if (!bodyDone.isCompleted) bodyDone.complete();
          },
          cancelOnError: true,
        );
        restartIdleTimer();
        totalTimer = Timer(
          bodyTotalTimeout,
          () => fail(
            TimeoutException('Audio body exceeded the download time limit'),
            StackTrace.current,
          ),
        );
        cancelToken?.whenCanceled.then((_) {
          fail(const DownloadCancelledException(), StackTrace.current);
        });
        await bodyDone.future;
      } finally {
        idleTimer?.cancel();
        totalTimer?.cancel();
        await subscription?.cancel();
        await sink.close();
      }
      if (totalBytes != null && bytes != totalBytes) {
        throw AudioTruncatedException(
          'download ended at $bytes bytes, expected $totalBytes',
        );
      }
      return bytes;
    } finally {
      if (ownsClient) {
        httpClient.close(force: true);
      }
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
    if (result.panLink) {
      throw UnsupportedError('Cloud-drive links cannot be cached as audio.');
    }
    final root = await _rootProvider();
    cancelToken?.throwIfCanceled();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    cancelToken?.throwIfCanceled();
    // cacheId 绑定来源、平台、id 和质量，避免同名歌曲/不同版本互相复用。
    final cacheId = cacheIdForResolved(result);
    final target = File(_targetPath(root, result));
    final existing = await _lookup(cacheId);
    cancelToken?.throwIfCanceled();
    if (existing != null && await File(existing.filePath).exists()) {
      final file = File(existing.filePath);
      try {
        await _validateAudioFile(file, result);
        cancelToken?.throwIfCanceled();
      } on AudioValidationException {
        await _deleteIfExists(file);
      }
    }
    cancelToken?.throwIfCanceled();
    if (existing != null && await File(existing.filePath).exists()) {
      final file = File(existing.filePath);
      final stat = await file.stat();
      final lyricsPath = await _writeLyricsIfNeeded(result, file);
      cancelToken?.beginCommit();
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
        cancelToken?.throwIfCanceled();
      } on AudioValidationException {
        await _deleteIfExists(target);
      }
    }

    cancelToken?.throwIfCanceled();
    if (await target.exists()) {
      final stat = await target.stat();
      final lyricsPath = await _writeLyricsIfNeeded(result, target);
      cancelToken?.beginCommit();
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
    var createdTarget = false;
    try {
      // 先写临时文件并完成音频校验，通过后才 rename 和写索引，避免半文件进入缓存。
      final bytes = await _downloader.download(
        Uri.parse(result.url),
        temp,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      cancelToken?.throwIfCanceled();
      await _validateAudioFile(temp, result);
      cancelToken?.throwIfCanceled();
      if (await target.exists()) {
        await temp.delete();
        await _validateAudioFile(target, result);
        cancelToken?.throwIfCanceled();
        final stat = await target.stat();
        final lyricsPath = await _writeLyricsIfNeeded(result, target);
        cancelToken?.beginCommit();
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
      cancelToken?.beginCommit();
      await temp.rename(target.path);
      createdTarget = true;
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
      if (createdTarget) await _deleteIfExists(target);
      rethrow;
    }
  }

  Future<LanCacheImportResult> importLanTrack(
    LanTrackEntry entry, {
    required String baseUrl,
    required String libraryId,
    required LanLibraryGateway gateway,
  }) async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final baseMusic = _resolvedLanMusic(entry, baseUrl, libraryId, gateway);
    final cacheId = cacheIdForResolved(baseMusic);
    final existing = await _lookup(cacheId);
    if (existing != null && await _lanCacheMatches(existing, entry)) {
      final refreshedMusic = _refreshedLanMusic(
        entry,
        baseUrl,
        libraryId,
        gateway,
        existing,
      );
      if (_sameLanMetadata(existing.music, refreshedMusic)) {
        return LanCacheImportResult(
          cached: existing,
          skipped: true,
          updated: false,
        );
      }
      final refreshed = existing.copyWith(
        music: refreshedMusic,
        fromCache: true,
      );
      await _upsert(refreshed);
      return LanCacheImportResult(
        cached: refreshed,
        skipped: false,
        updated: true,
      );
    }

    final shortId = cacheId.substring(0, 10);
    final artist = sanitizeFilePart(entry.artist, 'unknown-artist');
    final title = sanitizeFilePart(entry.title, 'unknown-title');
    final stem =
        '$artist-$title-$shortId-${entry.audio.sha256.substring(0, 12)}';
    final audioTarget = File(
      '${root.path}${Platform.pathSeparator}$stem.${entry.audio.format}',
    );
    final lyricsTarget = entry.lyrics == null
        ? null
        : File(
            '${root.path}${Platform.pathSeparator}$stem-'
            '${entry.lyrics!.sha256.substring(0, 12)}.lrc',
          );
    final artworkExtension = entry.artwork?.mimeType == 'image/png'
        ? 'png'
        : 'jpg';
    final artworkTarget = entry.artwork == null
        ? null
        : File(
            '${root.path}${Platform.pathSeparator}$stem-'
            '${entry.artwork!.sha256.substring(0, 12)}.$artworkExtension',
          );
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final audioTemp = File('${audioTarget.path}.download-$nonce.tmp');
    final lyricsTemp = lyricsTarget == null
        ? null
        : File('${lyricsTarget.path}.download-$nonce.tmp');
    final artworkTemp = artworkTarget == null
        ? null
        : File('${artworkTarget.path}.download-$nonce.tmp');
    final temps = [audioTemp, ?lyricsTemp, ?artworkTemp];
    final promoted = <File>[];
    try {
      await gateway.downloadAsset(baseUrl, entry.audio, audioTemp);
      await _validateLanAsset(audioTemp, entry.audio);
      await _validateLanAudioSignature(audioTemp, entry.audio.format);
      await _validateAudioFile(audioTemp, baseMusic);

      String lyricsText = '';
      if (entry.lyrics != null && lyricsTemp != null) {
        await gateway.downloadAsset(baseUrl, entry.lyrics!, lyricsTemp);
        await _validateLanAsset(lyricsTemp, entry.lyrics!);
        try {
          lyricsText = utf8.decode(await lyricsTemp.readAsBytes());
        } on FormatException {
          throw const AudioValidationException(
            'LAN lyrics are not valid UTF-8',
          );
        }
      }
      if (entry.artwork != null && artworkTemp != null) {
        await gateway.downloadAsset(baseUrl, entry.artwork!, artworkTemp);
        await _validateLanAsset(artworkTemp, entry.artwork!);
      }

      await _promoteLanFile(audioTemp, audioTarget, entry.audio, promoted);
      if (entry.lyrics != null && lyricsTemp != null && lyricsTarget != null) {
        await _promoteLanFile(
          lyricsTemp,
          lyricsTarget,
          entry.lyrics!,
          promoted,
        );
      }
      if (entry.artwork != null &&
          artworkTemp != null &&
          artworkTarget != null) {
        await _promoteLanFile(
          artworkTemp,
          artworkTarget,
          entry.artwork!,
          promoted,
        );
      }

      final music = ResolvedMusic(
        query: entry.title,
        source: MusicDataSource.lan,
        platform: baseMusic.platform,
        id: entry.id,
        name: entry.title,
        artist: entry.artist,
        album: entry.album,
        url: gateway.resolveAssetUri(baseUrl, entry.audio).toString(),
        quality: MusicQuality(format: entry.audio.format),
        coverUrl: artworkTarget?.uri.toString() ?? '',
        lyrics: lyricsText.trim().isEmpty
            ? null
            : ResolvedLyrics(
                source: 'lan:lrc',
                text: lyricsText.trimRight(),
                lines: const LineSplitter().convert(lyricsText).length,
                timed: RegExp(
                  r'^\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]',
                  multiLine: true,
                ).hasMatch(lyricsText),
              ),
      );
      final cached = CachedTrack(
        cacheId: cacheId,
        music: music,
        filePath: audioTarget.path,
        sizeBytes: entry.audio.sizeBytes,
        fromCache: false,
        lyricsPath: lyricsTarget?.path ?? '',
        artworkPath: artworkTarget?.path ?? '',
        contentSha256: entry.audio.sha256,
        lyricsSha256: entry.lyrics?.sha256 ?? '',
        artworkSha256: entry.artwork?.sha256 ?? '',
        cachedAt: DateTime.now(),
      );
      await _upsert(cached);
      if (existing != null) {
        await _deleteReplacedLanFiles(existing, cached);
      }
      return LanCacheImportResult(
        cached: cached,
        skipped: false,
        updated: existing != null,
      );
    } catch (_) {
      for (final file in temps) {
        await _deleteIfExists(file);
      }
      for (final file in promoted) {
        await _deleteIfExists(file);
      }
      rethrow;
    }
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
        if (cached.artworkPath.isNotEmpty) {
          await _deleteIfExists(File(cached.artworkPath));
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
            artworkPath: cached.artworkPath,
            contentSha256: cached.contentSha256,
            lyricsSha256: cached.lyricsSha256,
            artworkSha256: cached.artworkSha256,
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

class LanCacheImportResult {
  const LanCacheImportResult({
    required this.cached,
    required this.skipped,
    required this.updated,
  });

  final CachedTrack cached;
  final bool skipped;
  final bool updated;
}

ResolvedMusic _resolvedLanMusic(
  LanTrackEntry entry,
  String baseUrl,
  String libraryId,
  LanLibraryGateway gateway,
) {
  return ResolvedMusic(
    query: entry.title,
    source: MusicDataSource.lan,
    platform: 'lan:$libraryId',
    id: entry.id,
    name: entry.title,
    artist: entry.artist,
    album: entry.album,
    url: gateway.resolveAssetUri(baseUrl, entry.audio).toString(),
    quality: MusicQuality(format: entry.audio.format),
  );
}

ResolvedMusic _refreshedLanMusic(
  LanTrackEntry entry,
  String baseUrl,
  String libraryId,
  LanLibraryGateway gateway,
  CachedTrack existing,
) {
  final base = _resolvedLanMusic(entry, baseUrl, libraryId, gateway);
  return ResolvedMusic(
    query: base.query,
    source: base.source,
    platform: base.platform,
    id: base.id,
    name: base.name,
    artist: base.artist,
    album: base.album,
    url: base.url,
    quality: base.quality,
    coverUrl: entry.artwork != null && existing.artworkPath.isNotEmpty
        ? File(existing.artworkPath).uri.toString()
        : '',
    lyrics: entry.lyrics == null ? null : existing.music.lyrics,
  );
}

bool _sameLanMetadata(ResolvedMusic left, ResolvedMusic right) {
  return left.query == right.query &&
      left.source == right.source &&
      left.platform == right.platform &&
      left.id == right.id &&
      left.name == right.name &&
      left.artist == right.artist &&
      left.album == right.album &&
      left.url == right.url &&
      left.quality.format == right.quality.format &&
      left.coverUrl == right.coverUrl &&
      left.lyrics?.text == right.lyrics?.text;
}

Future<bool> _lanCacheMatches(CachedTrack cached, LanTrackEntry entry) async {
  if (cached.contentSha256 != entry.audio.sha256 ||
      cached.lyricsSha256 != (entry.lyrics?.sha256 ?? '') ||
      cached.artworkSha256 != (entry.artwork?.sha256 ?? '')) {
    return false;
  }
  try {
    final audio = File(cached.filePath);
    await _validateLanAsset(audio, entry.audio);
    await _validateLanAudioSignature(audio, entry.audio.format);
    await _validateAudioFile(audio, cached.music);
    if (entry.lyrics != null) {
      if (cached.lyricsPath.isEmpty) {
        return false;
      }
      await _validateLanAsset(File(cached.lyricsPath), entry.lyrics!);
    }
    if (entry.artwork != null) {
      if (cached.artworkPath.isEmpty) {
        return false;
      }
      await _validateLanAsset(File(cached.artworkPath), entry.artwork!);
    }
    return true;
  } on Object {
    return false;
  }
}

Future<void> _validateLanAsset(File file, LanAsset asset) async {
  if (!await file.exists()) {
    throw FileSystemException('LAN asset is missing', file.path);
  }
  final length = await file.length();
  if (length != asset.sizeBytes) {
    throw AudioValidationException(
      'LAN asset size mismatch: expected ${asset.sizeBytes}, got $length',
    );
  }
  final digest = await _sha256File(file);
  if (digest != asset.sha256) {
    throw const AudioValidationException('LAN asset SHA-256 mismatch');
  }
}

Future<void> _validateLanAudioSignature(File file, String format) async {
  final length = await file.length();
  final header = await _readHeader(file, min<int>(512, length));
  switch (format.toLowerCase()) {
    case 'mp3':
      final hasId3 =
          header.length >= 3 &&
          header[0] == 0x49 &&
          header[1] == 0x44 &&
          header[2] == 0x33;
      final hasFrameSync =
          header.length >= 2 && header[0] == 0xff && (header[1] & 0xe0) == 0xe0;
      if (hasId3 || hasFrameSync) {
        return;
      }
    case 'flac':
      if (header.length >= 4 &&
          header[0] == 0x66 &&
          header[1] == 0x4c &&
          header[2] == 0x61 &&
          header[3] == 0x43) {
        return;
      }
  }
  throw AudioValidationException('LAN audio signature does not match .$format');
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<void> _promoteLanFile(
  File temp,
  File target,
  LanAsset asset,
  List<File> promoted,
) async {
  if (await target.exists()) {
    await _validateLanAsset(target, asset);
    await _deleteIfExists(temp);
    return;
  }
  await temp.rename(target.path);
  promoted.add(target);
}

Future<void> _deleteReplacedLanFiles(
  CachedTrack previous,
  CachedTrack current,
) async {
  final currentPaths = {
    current.filePath,
    if (current.lyricsPath.isNotEmpty) current.lyricsPath,
    if (current.artworkPath.isNotEmpty) current.artworkPath,
  };
  for (final path in [
    previous.filePath,
    previous.lyricsPath,
    previous.artworkPath,
  ]) {
    if (path.isNotEmpty && !currentPaths.contains(path)) {
      await _deleteIfExists(File(path));
    }
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
