import 'dart:io';

import '../platform/app_storage.dart';
import 'json_file_store.dart';
import 'music_playlists.dart';

enum PlaylistSortOrder { recentlyOpened, visitCount }

/// Usage is independent of playlist contents and their manual track order.
class PlaylistUsageStore {
  PlaylistUsageStore({
    Future<Directory> Function()? rootProvider,
    DateTime Function()? now,
  }) : _rootProvider = rootProvider ?? getAiMusicSupportDirectory,
       _now = now ?? DateTime.now;
  final Future<Directory> Function() _rootProvider;
  final DateTime Function() _now;
  final _events = <String, List<_UsageEvent>>{};
  final _lastOpened = <String, DateTime>{};
  PlaylistSortOrder sortOrder = PlaylistSortOrder.recentlyOpened;
  Future<void>? _loading;
  Future<void> _tail = Future.value();

  Future<File> _file() async =>
      File('${(await _rootProvider()).path}/playlist_usage.json');
  Future<File> _preferencesFile() async =>
      File('${(await _rootProvider()).path}/playlist_sort.json');
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final saved = await const JsonFileStore().read(await _preferencesFile());
      if (saved is Map) {
        if (saved['order'] == PlaylistSortOrder.visitCount.name) {
          sortOrder = PlaylistSortOrder.visitCount;
        }
        if (saved['lastOpened'] is Map) {
          for (final row in (saved['lastOpened'] as Map).entries) {
            final at = DateTime.tryParse(row.value.toString());
            if (row.key is String && at != null) _lastOpened[row.key] = at;
          }
        }
      }
    } on JsonFileStoreException {
      // Sorting preferences are optional; retain the default on corruption.
    }
    Object? json;
    try {
      json = await const JsonFileStore().read(await _file());
    } on JsonFileStoreException {
      return;
    }
    if (json is! Map) return;
    for (final entry in json.entries) {
      if (entry.key is! String || entry.value is! List) continue;
      final events = <_UsageEvent>[];
      for (final item in entry.value as List) {
        if (item is! Map) continue;
        final at = DateTime.tryParse(item['at']?.toString() ?? '');
        if (at != null) events.add(_UsageEvent(at, item['played'] == true));
      }
      _events[entry.key as String] = events;
      for (final event in events.where((event) => !event.played)) {
        final id = entry.key as String;
        if (event.at.isAfter(_lastOpened[id] ?? DateTime(1970))) {
          _lastOpened[id] = event.at;
        }
      }
    }
  }

  Future<void> _savePreferences() async =>
      const JsonFileStore().write(await _preferencesFile(), {
        'order': sortOrder.name,
        'lastOpened': {
          for (final row in _lastOpened.entries)
            row.key: row.value.toIso8601String(),
        },
      });

  Future<void> setSortOrder(PlaylistSortOrder value) {
    final work = _tail.then((_) async {
      await load();
      sortOrder = value;
      await _savePreferences();
    });
    _tail = work.then<void>((_) {}, onError: (_) {});
    return work;
  }

  Future<void> record(String id, {required bool played}) {
    final at = _now();
    final work = _tail.then((_) async {
      await load();
      final cutoff = at.subtract(const Duration(days: 30));
      for (final events in _events.values) {
        events.removeWhere((e) => e.at.isBefore(cutoff));
      }
      (_events[id] ??= []).add(_UsageEvent(at, played));
      if (!played) _lastOpened[id] = at;
      await const JsonFileStore().write(await _file(), {
        for (final entry in _events.entries)
          if (entry.value.isNotEmpty)
            entry.key: [
              for (final e in entry.value)
                {'at': e.at.toIso8601String(), 'played': e.played},
            ],
      });
      if (!played) await _savePreferences();
    });
    _tail = work.then<void>((_) {}, onError: (_) {});
    return work;
  }

  List<MusicPlaylist> rank(List<MusicPlaylist> playlists) {
    final cutoff = _now().subtract(const Duration(days: 30));
    final stats = <String, ({int opens, DateTime last})>{};
    for (final p in playlists) {
      final events = (_events[p.id] ?? [])
          .where((e) => !e.at.isBefore(cutoff))
          .toList();
      stats[p.id] = (
        opens: events.where((e) => !e.played).length,
        last: _lastOpened[p.id] ?? p.createdAt,
      );
    }
    final order = {
      for (var i = 0; i < playlists.length; i++) playlists[i].id: i,
    };
    return [...playlists]..sort((a, b) {
      final left = stats[a.id]!;
      final right = stats[b.id]!;
      if (sortOrder == PlaylistSortOrder.visitCount) {
        final result = right.opens.compareTo(left.opens);
        if (result != 0) return result;
      }
      final result = right.last.compareTo(left.last);
      if (result != 0) return result;
      return order[a.id]!.compareTo(order[b.id]!);
    });
  }
}

class _UsageEvent {
  const _UsageEvent(this.at, this.played);
  final DateTime at;
  final bool played;
}
