import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/online_playlists.dart';
import '../data/saved_online_track.dart';
import 'library_use_case.dart';
import 'online_playlist_importer.dart';
import 'screenshot_matcher.dart';

typedef ImportPlaylistRows =
    Future<MusicPlaylistResult> Function(
      String name,
      List<MusicSearchCandidate> candidates,
      MusicPlaylist? target,
      List<String> sourceOrderTrackIds,
    );

/// Lives with the controller, so leaving a route does not cancel its work.
class OnlinePlaylistTasks extends ChangeNotifier {
  OnlinePlaylistTasks({
    required this.matcher,
    required this.concurrency,
    required this.createPlaylist,
    required this.importRows,
  });
  final ScreenshotMatcher matcher;
  final int Function() concurrency;
  final Future<MusicPlaylist?> Function(String name) createPlaylist;
  final ImportPlaylistRows importRows;
  final Map<String, OnlinePlaylistTask> _tasks = {};
  List<OnlinePlaylistTask> get tasks => _tasks.values.toList(growable: false);

  OnlinePlaylistTask? autoSyncForDestination(String playlistId) => _tasks.values
      .where(
        (task) => task.autoSyncEnabled && task.destination?.id == playlistId,
      )
      .firstOrNull;

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
      createPlaylist: createPlaylist,
      importRows: importRows,
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
    required this.createPlaylist,
    required this.importRows,
  });
  final OnlinePlaylist playlist;
  final OnlinePlaylistRepository repository;
  final ScreenshotMatcher matcher;
  final int Function() concurrency;
  final Future<MusicPlaylist?> Function(String name) createPlaylist;
  final ImportPlaylistRows importRows;
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
  bool autoSyncEnabled = false;
  bool autoSyncError = false;
  bool unavailableNotified = false;
  int loaded = 0;
  int loadTotal = 0;
  int completed = 0;
  int matchTotal = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _reading = false;
  Timer? _syncTimer;
  bool get busy => loading || matching || saving;
  int get ready => choices.keys.where((i) => !savedRows.containsKey(i)).length;

  /// Once the user creates a destination, the controller-owned task completes
  /// this import even if the detail route is closed. Resolved rows are saved
  /// in small batches while matching continues, then reordered by source row.
  Future<void> startAutoSync() async {
    if (_disposed || autoSyncEnabled || saving || detail == null) return;
    autoSyncEnabled = true;
    autoSyncError = false;
    changed();
    await syncReady(createIfEmpty: true);
  }

  Future<void> retryAutoSync() async {
    if (!autoSyncEnabled || !autoSyncError) return;
    autoSyncError = false;
    changed();
    await syncReady();
  }

  Future<void> syncReady({bool createIfEmpty = false}) async {
    if (_disposed || !autoSyncEnabled || saving || autoSyncError) return;
    _syncTimer?.cancel();
    _syncTimer = null;
    final indexes = detail!.songs
        .asMap()
        .keys
        .where(
          (i) =>
              selected.contains(i) &&
              choices.containsKey(i) &&
              !savedRows.containsKey(i),
        )
        .toList();
    if (destination != null && indexes.isEmpty) return;
    if (destination == null && !createIfEmpty && matching) return;

    saving = true;
    changed();
    try {
      if (destination == null && (matching || indexes.isEmpty)) {
        destination = await createPlaylist(playlist.name);
        if (destination == null) throw StateError('Playlist was not created');
      } else if (indexes.isNotEmpty) {
        final candidates = [for (final i in indexes) choices[i]!];
        final rowTrackIds = {
          for (final i in indexes)
            i: SavedOnlineTrack(candidate: choices[i]!).trackId,
          ...savedRows,
        };
        final sourceOrderTrackIds = <String>[];
        final seen = <String>{};
        for (final i in detail!.songs.asMap().keys) {
          final id = rowTrackIds[i];
          if (id != null && seen.add(id)) sourceOrderTrackIds.add(id);
        }
        final result = await importRows(
          playlist.name,
          candidates,
          destination,
          sourceOrderTrackIds,
        );
        if (result.playlist == null) throw StateError('Playlist was not saved');
        destination = result.playlist;
        ownedTrackIds.addAll(result.addedTrackIds);
        for (final index in indexes) {
          savedRows[index] = SavedOnlineTrack(
            candidate: choices[index]!,
          ).trackId;
        }
      }
    } catch (_) {
      autoSyncError = true;
      if (destination == null) autoSyncEnabled = false;
    } finally {
      saving = false;
      changed();
    }
    if (!_disposed &&
        autoSyncEnabled &&
        !autoSyncError &&
        destination != null &&
        detail!.songs.asMap().keys.any(
          (i) =>
              selected.contains(i) &&
              choices.containsKey(i) &&
              !savedRows.containsKey(i),
        )) {
      // Matching may have completed more rows while a prior batch was saved.
      unawaited(syncReady());
    }
  }

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
        if (choice != null && autoSyncEnabled && destination != null) {
          _syncTimer ??= Timer(
            const Duration(milliseconds: 300),
            () => unawaited(syncReady()),
          );
        }
      },
    );
    if (_disposed || generation != _generation) return;
    matching = false;
    changed();
    if (autoSyncEnabled) unawaited(syncReady());
  }

  void pause() {
    _generation++;
    matching = false;
    changed();
    if (autoSyncEnabled) unawaited(syncReady());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _syncTimer?.cancel();
    super.dispose();
  }
}
