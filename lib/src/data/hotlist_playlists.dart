import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../platform/app_storage.dart';
import 'hotlist.dart';
import 'json_file_store.dart';

class HotlistPlaylistEntry {
  const HotlistPlaylistEntry({
    required this.id,
    required this.rank,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.sourceTrackId,
    required this.searchQuery,
    required this.addedAt,
  });

  final String id;
  final int rank;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String sourceTrackId;
  final String searchQuery;
  final DateTime addedAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'rank': rank,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'sourceTrackId': sourceTrackId,
      'searchQuery': searchQuery,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  static HotlistPlaylistEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final json = value.cast<String, dynamic>();
    final id = json['id']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty) {
      return null;
    }
    return HotlistPlaylistEntry(
      id: id,
      rank: _int(json['rank']),
      title: title,
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      sourceTrackId: json['sourceTrackId']?.toString() ?? '',
      searchQuery: json['searchQuery']?.toString().trim().isNotEmpty == true
          ? json['searchQuery'].toString().trim()
          : '$title ${json['artist'] ?? ''}'.trim(),
      addedAt:
          DateTime.tryParse(json['addedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class HotlistPlaylist {
  const HotlistPlaylist({
    required this.id,
    required this.source,
    required this.chartId,
    required this.name,
    required this.coverUrl,
    required this.period,
    required this.updatedAt,
    required this.entries,
    required this.createdAt,
    required this.savedAt,
  });

  final String id;
  final HotlistSource source;
  final String chartId;
  final String name;
  final String coverUrl;
  final String period;
  final DateTime? updatedAt;
  final List<HotlistPlaylistEntry> entries;
  final DateTime createdAt;
  final DateTime savedAt;

  HotlistPlaylist copyWith({
    String? name,
    String? coverUrl,
    String? period,
    DateTime? updatedAt,
    List<HotlistPlaylistEntry>? entries,
    DateTime? savedAt,
  }) {
    return HotlistPlaylist(
      id: id,
      source: source,
      chartId: chartId,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      period: period ?? this.period,
      updatedAt: updatedAt ?? this.updatedAt,
      entries: entries ?? this.entries,
      createdAt: createdAt,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'source': source.name,
      'chartId': chartId,
      'name': name,
      'coverUrl': coverUrl,
      'period': period,
      'updatedAt': updatedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'savedAt': savedAt.toIso8601String(),
      'entries': [for (final entry in entries) entry.toJson()],
    };
  }

  static HotlistPlaylist? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final json = value.cast<String, dynamic>();
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) {
      return null;
    }
    return HotlistPlaylist(
      id: id,
      source: HotlistSource.values.byName(json['source']?.toString() ?? 'qq'),
      chartId: json['chartId']?.toString() ?? '',
      name: name,
      coverUrl: json['coverUrl']?.toString() ?? '',
      period: json['period']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      savedAt:
          DateTime.tryParse(json['savedAt']?.toString() ?? '') ??
          DateTime.now(),
      entries: [
        for (final row
            in json['entries'] is List ? json['entries'] as List : const [])
          ?HotlistPlaylistEntry.fromJson(row),
      ],
    );
  }
}

class HotlistPlaylistSaveResult {
  const HotlistPlaylistSaveResult({
    required this.playlist,
    required this.addedCount,
    required this.skippedCount,
  });

  final HotlistPlaylist playlist;
  final int addedCount;
  final int skippedCount;
}

class HotlistPlaylistStore {
  HotlistPlaylistStore({
    Future<Directory> Function()? rootProvider,
    JsonFileStore store = const JsonFileStore(),
    DateTime Function()? now,
  }) : _rootProvider =
           rootProvider ??
           (() => getAiMusicSupportSubdirectory('hotlist_playlists')),
       _store = store,
       _now = now ?? DateTime.now;

  static const _fileName = 'hotlist_playlists.json';

  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _store;
  final DateTime Function() _now;
  Future<void> _writeTail = Future.value();

  Future<List<HotlistPlaylist>> load() async {
    final value = await _store.read(await _file());
    if (value is! Map) {
      return const [];
    }
    final rows = value['playlists'] is List ? value['playlists'] as List : [];
    return [
      for (final row in rows) ?HotlistPlaylist.fromJson(row),
    ].where((playlist) => playlist.entries.isNotEmpty).toList(growable: false);
  }

  Future<HotlistPlaylistSaveResult> saveChart(HotlistChart chart) async {
    return _withWriteLock(() async {
      final playlists = List<HotlistPlaylist>.of(await load());
      final now = _now();
      final playlistId = _playlistId(chart.source, chart.chartId);
      final existingIndex = playlists.indexWhere(
        (playlist) => playlist.id == playlistId,
      );
      final existing = existingIndex == -1 ? null : playlists[existingIndex];
      final currentEntries = existing?.entries ?? const [];
      final currentById = {for (final entry in currentEntries) entry.id: entry};
      final nextEntries = <HotlistPlaylistEntry>[];
      var addedCount = 0;
      for (final item in chart.items) {
        final draft = _entryFromItem(chart, item, now);
        final current = currentById[draft.id];
        if (current == null) {
          addedCount += 1;
          nextEntries.add(draft);
        } else {
          nextEntries.add(_entryFromItem(chart, item, current.addedAt));
        }
      }
      final next = existing == null
          ? HotlistPlaylist(
              id: playlistId,
              source: chart.source,
              chartId: chart.chartId,
              name: chart.title,
              coverUrl: chart.coverUrl,
              period: chart.period,
              updatedAt: chart.updatedAt,
              entries: nextEntries,
              createdAt: now,
              savedAt: now,
            )
          : existing.copyWith(
              name: chart.title,
              coverUrl: chart.coverUrl,
              period: chart.period,
              updatedAt: chart.updatedAt,
              entries: nextEntries,
              savedAt: now,
            );
      if (existingIndex == -1) {
        playlists.add(next);
      } else {
        playlists[existingIndex] = next;
      }
      await _write(playlists);
      return HotlistPlaylistSaveResult(
        playlist: next,
        addedCount: addedCount,
        skippedCount: chart.items.length - addedCount,
      );
    });
  }

  Future<File> _file() async {
    final root = await _rootProvider();
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> _write(List<HotlistPlaylist> playlists) async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    await _store.write(
      File('${root.path}${Platform.pathSeparator}$_fileName'),
      {
        'playlists': [for (final playlist in playlists) playlist.toJson()],
      },
    );
  }

  Future<T> _withWriteLock<T>(Future<T> Function() action) {
    final run = _writeTail.then((_) => action());
    _writeTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

String _playlistId(HotlistSource source, String chartId) {
  return 'hotlist-${source.name}-$chartId';
}

HotlistPlaylistEntry _entryFromItem(
  HotlistChart chart,
  HotlistItem item,
  DateTime addedAt,
) {
  final idParts = [
    chart.source.name,
    chart.chartId,
    item.sourceTrackId.trim().isNotEmpty ? item.sourceTrackId : item.title,
    item.artist,
  ].join('\u001f');
  return HotlistPlaylistEntry(
    id: 'hotlist-${sha1.convert(utf8.encode(idParts)).toString().substring(0, 16)}',
    rank: item.rank,
    title: item.title,
    artist: item.artist,
    album: item.album,
    coverUrl: item.coverUrl,
    sourceTrackId: item.sourceTrackId,
    searchQuery: item.searchQuery,
    addedAt: addedAt,
  );
}

int _int(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
