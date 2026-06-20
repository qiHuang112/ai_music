import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/music_app_exception.dart';
import '../domain/track.dart';

typedef DownloadProgress = void Function(int received, int total);

const _downloadConnectTimeout = Duration(seconds: 10);
const _downloadReceiveTimeout = Duration(minutes: 10);
const _downloadSendTimeout = Duration(seconds: 30);

class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;
  final Map<String, Future<void>> _trackCacheLocks = {};
  Future<void> _libraryWriteLock = Future.value();

  Future<List<Track>> loadTracks() async {
    await _libraryWriteLock.catchError((_) {});
    return _loadTracksUnlocked();
  }

  Future<List<Track>> _loadTracksUnlocked() async {
    final file = await _libraryFile();
    if (!await file.exists()) {
      return const [];
    }

    try {
      final tracks = tracksFromLibraryJson(await file.readAsString());
      return Future.wait(tracks.map(_refreshCacheState));
    } on FormatException {
      await _backupCorruptLibrary(file);
      return const [];
    } on TypeError {
      await _backupCorruptLibrary(file);
      return const [];
    }
  }

  Future<List<Track>> mergeSourceTracks(List<Track> sourceTracks) async {
    return _withLibraryWriteLock(() async {
      final existing = await _loadTracksUnlocked();
      final byId = {for (final track in existing) track.id: track};

      final merged = <Track>[];
      for (final source in sourceTracks) {
        final old = byId[source.id];
        merged.add(
          old == null
              ? source
              : source.copyWith(
                  localPath: old.localPath,
                  cacheState: old.cacheState,
                ),
        );
      }

      await _saveTracksUnlocked(merged);
      return merged;
    });
  }

  Future<Track> cacheTrack(Track track, {DownloadProgress? onProgress}) async {
    return _withTrackCacheLock(track.id, () async {
      final latest = await _findTrack(track.id);
      if (latest == null) {
        throw const MusicAppException(
          MusicAppFailureKind.trackNotInLibrary,
          '这首歌已不在当前曲库中，请重新导入后再试。',
        );
      }
      final effectiveTrack = latest;
      if (effectiveTrack.isCached && effectiveTrack.localPath != null) {
        final file = File(effectiveTrack.localPath!);
        if (await file.exists()) {
          return effectiveTrack;
        }
      }

      final target = await _cacheFileFor(effectiveTrack);
      await target.parent.create(recursive: true);
      final temp = File('${target.path}.download');
      if (await temp.exists()) {
        await temp.delete();
      }

      try {
        await _dio.download(
          effectiveTrack.sourceUrl,
          temp.path,
          onReceiveProgress: onProgress,
          options: Options(
            connectTimeout: _downloadConnectTimeout,
            receiveTimeout: _downloadReceiveTimeout,
            sendTimeout: _downloadSendTimeout,
            responseType: ResponseType.bytes,
          ),
        );
        if (await target.exists()) {
          await target.delete();
        }
        await temp.rename(target.path);

        final cached = effectiveTrack.copyWith(
          localPath: target.path,
          cacheState: TrackCacheState.cached,
        );
        final didUpdate = await upsertTrack(cached, insertIfMissing: false);
        if (!didUpdate) {
          if (await target.exists()) {
            await target.delete();
          }
          throw const MusicAppException(
            MusicAppFailureKind.trackNotInLibrary,
            '这首歌已不在当前曲库中，请重新导入后再试。',
          );
        }
        return cached;
      } catch (error, stackTrace) {
        if (await temp.exists()) {
          await temp.delete();
        }
        final failed = effectiveTrack.copyWith(
          clearLocalPath: true,
          cacheState: TrackCacheState.failed,
        );
        await upsertTrack(failed, insertIfMissing: false);
        Error.throwWithStackTrace(_asMusicAppException(error), stackTrace);
      }
    });
  }

  Future<bool> upsertTrack(Track updated, {bool insertIfMissing = true}) async {
    var didUpdate = false;
    await _withLibraryWriteLock(() async {
      final tracks = await _loadTracksUnlocked();
      var found = false;
      final next = <Track>[];
      for (final track in tracks) {
        if (track.id == updated.id) {
          next.add(updated);
          found = true;
        } else {
          next.add(track);
        }
      }
      if (!found && insertIfMissing) {
        next.add(updated);
      }

      didUpdate = found || insertIfMissing;
      if (didUpdate) {
        await _saveTracksUnlocked(next);
      }
    });
    return didUpdate;
  }

  Future<void> saveTracks(List<Track> tracks) async {
    await _withLibraryWriteLock(() => _saveTracksUnlocked(tracks));
  }

  Future<void> _saveTracksUnlocked(List<Track> tracks) async {
    final file = await _libraryFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) {
      await temp.delete();
    }

    await temp.writeAsString(tracksToLibraryJson(tracks), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<Directory> _musicDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory(_join(base.path, 'music'));
  }

  Future<File> _libraryFile() async {
    final dir = await _musicDirectory();
    return File(_join(dir.path, 'library.json'));
  }

  Future<File> _cacheFileFor(Track track) async {
    final dir = await _musicDirectory();
    final safeName = _safeFileName('${track.id}.${track.extension}');
    return File(_join(dir.path, 'audio_cache', safeName));
  }

  Future<Track> _refreshCacheState(Track track) async {
    final path = track.localPath;
    if (path == null) {
      return track.copyWith(cacheState: TrackCacheState.remoteOnly);
    }
    return await File(path).exists()
        ? track.copyWith(cacheState: TrackCacheState.cached)
        : track.copyWith(
            clearLocalPath: true,
            cacheState: TrackCacheState.remoteOnly,
          );
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _join(String first, String second, [String? third]) {
    final separator = Platform.pathSeparator;
    final path = '$first$separator$second';
    return third == null ? path : '$path$separator$third';
  }

  Future<Track?> _findTrack(String trackId) async {
    final tracks = await loadTracks();
    for (final track in tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  Future<void> _backupCorruptLibrary(File file) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final backup = File('${file.path}.corrupt-$stamp');
    try {
      await file.rename(backup.path);
    } catch (_) {
      try {
        await file.copy(backup.path);
        await file.delete();
      } catch (_) {
        // Keep startup recoverable even if the backup cannot be written.
      }
    }
  }

  MusicAppException _asMusicAppException(Object error) {
    if (error is MusicAppException) {
      return error;
    }
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout => const MusicAppException(
          MusicAppFailureKind.connectionTimeout,
          '连接本地音源超时，请确认手机和电脑在同一局域网。',
        ),
        DioExceptionType.receiveTimeout => const MusicAppException(
          MusicAppFailureKind.receiveTimeout,
          '缓存下载超时，请确认本地音源服务仍在运行后重试。',
        ),
        DioExceptionType.sendTimeout => const MusicAppException(
          MusicAppFailureKind.sendTimeout,
          '请求本地音源超时，请稍后重试。',
        ),
        DioExceptionType.connectionError => const MusicAppException(
          MusicAppFailureKind.connectionFailed,
          '无法连接本地音源服务，请确认 8787 服务正在运行。',
        ),
        DioExceptionType.badResponse => MusicAppException(
          MusicAppFailureKind.badResponse,
          '本地音源服务返回异常：HTTP ${error.response?.statusCode ?? 'unknown'}。',
          statusCode: error.response?.statusCode,
        ),
        DioExceptionType.cancel => const MusicAppException(
          MusicAppFailureKind.cancelled,
          '请求已取消。',
        ),
        DioExceptionType.badCertificate => const MusicAppException(
          MusicAppFailureKind.badCertificate,
          '本地音源证书异常。',
        ),
        DioExceptionType.unknown => const MusicAppException(
          MusicAppFailureKind.unknown,
          '本地音源请求失败，请稍后重试。',
        ),
      };
    }
    return MusicAppException(MusicAppFailureKind.unknown, error.toString());
  }

  Future<T> _withTrackCacheLock<T>(
    String trackId,
    Future<T> Function() action,
  ) {
    final previous = _trackCacheLocks[trackId] ?? Future.value();
    final current = previous.then(
      (_) => action(),
      onError: (error, stackTrace) => action(),
    );
    final guard = current.then<void>((_) {}, onError: (error, stackTrace) {});
    _trackCacheLocks[trackId] = guard;
    guard.whenComplete(() {
      if (identical(_trackCacheLocks[trackId], guard)) {
        _trackCacheLocks.remove(trackId);
      }
    });
    return current;
  }

  Future<T> _withLibraryWriteLock<T>(Future<T> Function() action) {
    final current = _libraryWriteLock.then(
      (_) => action(),
      onError: (error, stackTrace) => action(),
    );
    _libraryWriteLock = current.then<void>(
      (_) {},
      onError: (error, stackTrace) {},
    );
    return current;
  }
}
