import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/online_playlists.dart';
import 'online_playlist_importer.dart';
import 'screenshot_matcher.dart';

/// Lives with the controller, so leaving a route does not cancel its work.
class OnlinePlaylistTasks extends ChangeNotifier {
  OnlinePlaylistTasks({required this.matcher, required this.concurrency});
  final ScreenshotMatcher matcher;
  final int Function() concurrency;
  final Map<String, OnlinePlaylistTask> _tasks = {};
  List<OnlinePlaylistTask> get tasks => _tasks.values.toList(growable: false);

  bool canRemoveSavedMatch(OnlinePlaylistTask task, int row, String trackId) {
    final destinationId = task.destination?.id;
    if (destinationId == null) return false;
    final sharing = _tasks.values.where(
      (t) => t.destination?.id == destinationId,
    );
    // Ownership belongs to this destination across all imports, not one task.
    return sharing.any((t) => t.ownedTrackIds.contains(trackId)) &&
        !sharing.any(
          (t) => t.savedRows.entries.any(
            (entry) =>
                !(identical(t, task) && entry.key == row) &&
                entry.value == trackId,
          ),
        );
  }

  void forgetOwnedMatch(String destinationId, String trackId) {
    for (final task in _tasks.values) {
      if (task.destination?.id == destinationId) {
        task.ownedTrackIds.remove(trackId);
      }
    }
  }

  OnlinePlaylistTask obtain(
    OnlinePlaylist playlist,
    OnlinePlaylistRepository repository,
  ) {
    final existing = _tasks[playlist.key];
    if (existing != null) return existing;
    final task = OnlinePlaylistTask(
      playlist: playlist,
      repository: repository,
      matcher: matcher,
      concurrency: concurrency,
    );
    _tasks[playlist.key] = task;
    task.addListener(notifyListeners);
    // Defer notifications until the route has finished building.
    scheduleMicrotask(task.load);
    return task;
  }

  @override
  void dispose() {
    for (final task in _tasks.values) {
      task.removeListener(notifyListeners);
      task.dispose();
    }
    super.dispose();
  }
}

class OnlinePlaylistTask extends ChangeNotifier {
  OnlinePlaylistTask({
    required this.playlist,
    required this.repository,
    required this.matcher,
    required this.concurrency,
  });
  final OnlinePlaylist playlist;
  final OnlinePlaylistRepository repository;
  final ScreenshotMatcher matcher;
  final int Function() concurrency;
  OnlinePlaylistDetail? detail;
  final selected = <int>{};
  final matches = <int, OnlinePlaylistMatch>{};
  final choices = <int, MusicSearchCandidate>{};
  final reviewed = <int>{};
  final expanded = <int>{};
  final savedRows = <int, String>{};
  final ownedTrackIds = <String>{};
  MusicPlaylist? destination;
  bool loading = true;
  bool matching = false;
  bool saving = false;
  bool loadFailed = false;
  bool unavailableNotified = false;
  int loaded = 0;
  int loadTotal = 0;
  int completed = 0;
  int matchTotal = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _reading = false;
  bool get busy => loading || matching || saving;
  int get ready => choices.keys.where((i) => !savedRows.containsKey(i)).length;

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (_disposed || _reading || detail != null) return;
    _reading = true;
    final generation = ++_generation;
    loading = true;
    loadFailed = false;
    changed();
    try {
      final result = await repository.load(
        playlist,
        isCanceled: () => _disposed || generation != _generation,
        onProgress: (count, total) {
          if (_disposed || generation != _generation) return;
          loaded = count;
          loadTotal = total;
          changed();
        },
      );
      if (_disposed || generation != _generation) return;
      detail = result;
      selected.addAll(Iterable.generate(result.songs.length));
      loading = false;
      changed();
      unawaited(matchPending());
    } catch (_) {
      if (_disposed || generation != _generation) return;
      loading = false;
      loadFailed = true;
      changed();
    } finally {
      _reading = false;
    }
  }

  Future<void> matchPending() async {
    if (_disposed || matching || saving || detail == null) return;
    final generation = ++_generation;
    final pending = detail!.songs
        .asMap()
        .keys
        .where((i) => !choices.containsKey(i))
        .toList();
    matching = true;
    completed = 0;
    matchTotal = pending.length;
    changed();
    await OnlinePlaylistImporter(matcher).match(
      [for (final index in pending) detail!.songs[index]],
      concurrency: concurrency(),
      isCanceled: () => _disposed || generation != _generation,
      onResult: (position, result) {
        if (_disposed || generation != _generation) return;
        final index = pending[position];
        matches[index] = result;
        final choice = result.result?.recommended;
        if (choice != null) choices[index] = choice;
        completed++;
        changed();
      },
    );
    if (_disposed || generation != _generation) return;
    matching = false;
    changed();
  }

  void pause() {
    _generation++;
    matching = false;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
