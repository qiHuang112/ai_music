import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/track.dart';

typedef DownloadProgress = void Function(int received, int total);

class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  Future<List<Track>> loadTracks() async {
    final file = await _libraryFile();
    if (!await file.exists()) {
      return const [];
    }

    final tracks = tracksFromLibraryJson(await file.readAsString());
    return Future.wait(tracks.map(_refreshCacheState));
  }

  Future<List<Track>> mergeSourceTracks(List<Track> sourceTracks) async {
    final existing = await loadTracks();
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

    await saveTracks(merged);
    return merged;
  }

  Future<Track> cacheTrack(Track track, {DownloadProgress? onProgress}) async {
    if (track.isCached && track.localPath != null) {
      final file = File(track.localPath!);
      if (await file.exists()) {
        return track;
      }
    }

    final target = await _cacheFileFor(track);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.download');
    if (await temp.exists()) {
      await temp.delete();
    }

    try {
      await _dio.download(
        track.sourceUrl,
        temp.path,
        onReceiveProgress: onProgress,
        options: Options(responseType: ResponseType.bytes),
      );
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);

      final cached = track.copyWith(
        localPath: target.path,
        cacheState: TrackCacheState.cached,
      );
      await upsertTrack(cached);
      return cached;
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      final failed = track.copyWith(
        clearLocalPath: true,
        cacheState: TrackCacheState.failed,
      );
      await upsertTrack(failed);
      rethrow;
    }
  }

  Future<void> upsertTrack(Track updated) async {
    final tracks = await loadTracks();
    final next = [
      for (final track in tracks)
        if (track.id == updated.id) updated else track,
      if (!tracks.any((track) => track.id == updated.id)) updated,
    ];
    await saveTracks(next);
  }

  Future<void> saveTracks(List<Track> tracks) async {
    final file = await _libraryFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(tracksToLibraryJson(tracks));
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
}
