import 'dart:async';
import 'dart:io';

import 'json_file_store.dart';
import '../platform/app_storage.dart';

class PlaylistAutoDownloadAttempt {
  const PlaylistAutoDownloadAttempt({
    required this.revision,
    required this.startedAt,
    this.completed = true,
  });

  final String revision;
  final DateTime startedAt;
  final bool completed;
}

/// Records automatic attempts separately from playlists so download progress
/// never rewrites a user's playlist or its modification time.
class PlaylistAutoDownloadStore {
  PlaylistAutoDownloadStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;

  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _jsonStore = const JsonFileStore();
  Future<void> _writeTail = Future<void>.value();
  Future<void>? _loadFuture;
  final Map<String, PlaylistAutoDownloadAttempt> _attempts = {};

  Future<PlaylistAutoDownloadAttempt?> get(String playlistId) async {
    await _load();
    return _attempts[playlistId];
  }

  Future<void> record(String playlistId, PlaylistAutoDownloadAttempt attempt) {
    return _write(() async {
      await _load();
      _attempts[playlistId] = attempt;
      await _save();
    });
  }

  Future<void> clearIfCurrent(
    String playlistId,
    PlaylistAutoDownloadAttempt attempt,
  ) {
    return _write(() async {
      await _load();
      if (!identical(_attempts[playlistId], attempt)) return;
      _attempts.remove(playlistId);
      await _save();
    });
  }

  Future<void> _load() => _loadFuture ??= _loadNow();

  Future<void> _loadNow() async {
    final root = await _rootProvider();
    final file = File(
      '${root.path}${Platform.pathSeparator}playlist_auto_download.json',
    );
    Object? decoded;
    try {
      decoded = await _jsonStore.read(file);
    } on JsonFileStoreException {
      return;
    }
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final value = entry.value as Map;
      final revision = value['revision'];
      final startedAt = DateTime.tryParse(value['startedAt']?.toString() ?? '');
      if (revision is String && revision.isNotEmpty && startedAt != null) {
        _attempts[entry.key as String] = PlaylistAutoDownloadAttempt(
          revision: revision,
          startedAt: startedAt,
          // Older files did not distinguish pending from completed. Preserve
          // their existing 24-hour limit when upgrading the file format.
          completed: value['completed'] is bool
              ? value['completed'] as bool
              : true,
        );
      }
    }
  }

  Future<void> _save() async {
    final root = await _rootProvider();
    final file = File(
      '${root.path}${Platform.pathSeparator}playlist_auto_download.json',
    );
    await _jsonStore.write(file, {
      for (final entry in _attempts.entries)
        entry.key: {
          'revision': entry.value.revision,
          'startedAt': entry.value.startedAt.toUtc().toIso8601String(),
          'completed': entry.value.completed,
        },
    });
  }

  Future<void> _write(Future<void> Function() action) {
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
