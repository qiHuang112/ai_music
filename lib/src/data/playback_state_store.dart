import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/music_models.dart';
import '../platform/app_storage.dart';
import 'json_file_store.dart';
import 'music_playlists.dart';

enum PlaybackQueueSourceType {
  localCache('localCache'),
  favorite('favorite'),
  customPlaylist('customPlaylist'),
  searchCache('searchCache');

  const PlaybackQueueSourceType(this.storageValue);

  final String storageValue;

  static PlaybackQueueSourceType fromStorage(String? value) {
    return PlaybackQueueSourceType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => PlaybackQueueSourceType.localCache,
    );
  }
}

class PlaybackQueueSource {
  const PlaybackQueueSource({required this.type, this.id = ''});

  const PlaybackQueueSource.localCache()
    : type = PlaybackQueueSourceType.localCache,
      id = '';

  const PlaybackQueueSource.favorite()
    : type = PlaybackQueueSourceType.favorite,
      id = favoritePlaylistId;

  const PlaybackQueueSource.customPlaylist(String playlistId)
    : type = PlaybackQueueSourceType.customPlaylist,
      id = playlistId;

  const PlaybackQueueSource.searchCache()
    : type = PlaybackQueueSourceType.searchCache,
      id = '';

  final PlaybackQueueSourceType type;
  final String id;

  Map<String, Object?> toJson() {
    return {'type': type.storageValue, 'id': id};
  }

  static PlaybackQueueSource fromJson(Object? value) {
    if (value is! Map) {
      return const PlaybackQueueSource.localCache();
    }
    final json = value.cast<String, dynamic>();
    return PlaybackQueueSource(
      type: PlaybackQueueSourceType.fromStorage(json['type']?.toString()),
      id: json['id']?.toString() ?? '',
    );
  }
}

class SavedPlaybackState {
  const SavedPlaybackState({
    required this.playbackMode,
    required this.queueSource,
    required this.queueTrackIds,
    required this.currentTrackId,
  });

  final PlaybackMode playbackMode;
  final PlaybackQueueSource queueSource;
  final List<String> queueTrackIds;
  final String currentTrackId;

  bool get hasQueue {
    return queueTrackIds.isNotEmpty && currentTrackId.trim().isNotEmpty;
  }

  Map<String, Object?> toJson() {
    return {
      'version': 1,
      'playbackMode': playbackMode.name,
      'queueSource': queueSource.toJson(),
      'queueTrackIds': queueTrackIds,
      'currentTrackId': currentTrackId,
    };
  }

  static SavedPlaybackState? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final json = value.cast<String, dynamic>();
    final queueTrackIds =
        (json['queueTrackIds'] is List
                ? json['queueTrackIds'] as List
                : const [])
            .map((id) => id.toString().trim())
            .where((id) => id.isNotEmpty)
            .toList(growable: false);
    final currentTrackId = json['currentTrackId']?.toString().trim() ?? '';
    return SavedPlaybackState(
      playbackMode: PlaybackMode.values.firstWhere(
        (mode) => mode.name == json['playbackMode']?.toString(),
        orElse: () => PlaybackMode.sequential,
      ),
      queueSource: PlaybackQueueSource.fromJson(json['queueSource']),
      queueTrackIds: queueTrackIds,
      currentTrackId: currentTrackId,
    );
  }
}

class PlaybackStateStore {
  PlaybackStateStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;

  static const _fileName = 'playback_state.json';

  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _jsonStore = const JsonFileStore();
  Future<void> _writeTail = Future.value();

  Future<SavedPlaybackState?> load() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) {
        return null;
      }
      final text = (await file.readAsString()).trim();
      if (text.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(text);
      return SavedPlaybackState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SavedPlaybackState state) {
    return _withWriteLock(() async {
      final file = await _stateFile();
      await _jsonStore.write(file, state.toJson());
    });
  }

  Future<void> clear() {
    return _withWriteLock(() async {
      final file = await _stateFile();
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  Future<File> _stateFile() async {
    final support = await _rootProvider();
    return File('${support.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> _withWriteLock(Future<void> Function() action) {
    final previous = _writeTail;
    final completer = Completer<void>();
    _writeTail = previous.then((_) => completer.future);
    return previous.then((_) async {
      try {
        await action();
      } finally {
        completer.complete();
      }
    });
  }
}
