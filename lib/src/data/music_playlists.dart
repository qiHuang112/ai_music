import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_file_store.dart';
import '../platform/app_storage.dart';

const favoritePlaylistId = 'favorite';

class PlaylistTrackEntry {
  const PlaylistTrackEntry({required this.trackId, required this.addedAt});

  final String trackId;
  final DateTime addedAt;

  Map<String, Object?> toJson() {
    return {'trackId': trackId, 'addedAt': addedAt.toIso8601String()};
  }

  static PlaylistTrackEntry? fromJson(Object? value, DateTime fallbackAddedAt) {
    if (value is String) {
      final id = value.trim();
      if (id.isEmpty) {
        return null;
      }
      return PlaylistTrackEntry(trackId: id, addedAt: fallbackAddedAt);
    }
    if (value is! Map) {
      return null;
    }
    final json = value.cast<String, dynamic>();
    final id = (json['trackId'] ?? json['id'])?.toString().trim() ?? '';
    if (id.isEmpty) {
      return null;
    }
    return PlaylistTrackEntry(
      trackId: id,
      addedAt:
          DateTime.tryParse(json['addedAt']?.toString() ?? '') ??
          fallbackAddedAt,
    );
  }
}

class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    List<String> trackIds = const [],
    List<PlaylistTrackEntry>? entries,
    required this.createdAt,
    required this.updatedAt,
  }) : entries = entries ?? _entriesFromIds(trackIds, updatedAt);

  final String id;
  final String name;
  final List<PlaylistTrackEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<String> get trackIds {
    return [for (final entry in entries) entry.trackId];
  }

  MusicPlaylist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    List<PlaylistTrackEntry>? entries,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextUpdatedAt = updatedAt ?? this.updatedAt;
    return MusicPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      entries:
          entries ??
          (trackIds == null
              ? this.entries
              : _entriesFromIds(trackIds, nextUpdatedAt)),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: nextUpdatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'tracks': [for (final entry in entries) entry.toJson()],
      'trackIds': trackIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static MusicPlaylist? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    final createdAt =
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now;
    final updatedAt =
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now;
    return MusicPlaylist(
      id: id,
      name: name,
      entries: _entriesFromJson(
        json['tracks'] ?? json['trackIds'],
        fallbackAddedAt: updatedAt,
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class PlaylistLibrary {
  PlaylistLibrary({
    List<String> favoriteTrackIds = const [],
    List<PlaylistTrackEntry>? favoriteEntries,
    required this.playlists,
  }) : favoriteEntries =
           favoriteEntries ?? _entriesFromIds(favoriteTrackIds, DateTime.now());

  const PlaylistLibrary.empty()
    : favoriteEntries = const [],
      playlists = const [];

  final List<PlaylistTrackEntry> favoriteEntries;
  final List<MusicPlaylist> playlists;

  List<String> get favoriteTrackIds {
    return [for (final entry in favoriteEntries) entry.trackId];
  }

  PlaylistLibrary copyWith({
    List<String>? favoriteTrackIds,
    List<PlaylistTrackEntry>? favoriteEntries,
    List<MusicPlaylist>? playlists,
  }) {
    return PlaylistLibrary(
      favoriteEntries:
          favoriteEntries ??
          (favoriteTrackIds == null
              ? this.favoriteEntries
              : _entriesFromIds(favoriteTrackIds, DateTime.now())),
      playlists: playlists ?? this.playlists,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'favoriteTracks': [for (final entry in favoriteEntries) entry.toJson()],
      'favoriteTrackIds': favoriteTrackIds,
      'playlists': [for (final playlist in playlists) playlist.toJson()],
    };
  }

  static PlaylistLibrary fromJson(Map<String, dynamic> json) {
    return PlaylistLibrary(
      favoriteEntries: _entriesFromJson(
        json['favoriteTracks'] ?? json['favoriteTrackIds'],
        fallbackAddedAt: DateTime.now(),
      ),
      playlists: (json['playlists'] is List ? json['playlists'] as List : [])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .map(MusicPlaylist.fromJson)
          .nonNulls
          .where((playlist) => playlist.id != favoritePlaylistId)
          .toList(growable: false),
    );
  }
}

class PlaylistStore {
  PlaylistStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? _defaultRoot;

  static const _fileName = 'playlists.json';

  final Future<Directory> Function() _rootProvider;
  Future<void> _writeTail = Future.value();
  final JsonFileStore _jsonStore = const JsonFileStore();

  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async {
    final file = await _playlistFile();
    if (!await file.exists()) {
      return const PlaylistLibrary.empty();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const PlaylistLibrary.empty();
      }
      final library = _sanitize(
        PlaylistLibrary.fromJson(decoded),
        validTrackIds,
      );
      if (validTrackIds != null) {
        await write(library, validTrackIds: validTrackIds);
      }
      return library;
    } catch (_) {
      await _jsonStore.backupCorruptFile(file);
      return const PlaylistLibrary.empty();
    }
  }

  Future<void> write(PlaylistLibrary library, {Set<String>? validTrackIds}) {
    return _withWriteLock(() async {
      final root = await _rootProvider();
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      final file = _playlistFileIn(root);
      final sanitized = _sanitize(library, validTrackIds);
      await _jsonStore.write(file, sanitized.toJson());
    });
  }

  PlaylistLibrary _sanitize(
    PlaylistLibrary library,
    Set<String>? validTrackIds,
  ) {
    return PlaylistLibrary(
      favoriteEntries: _filterValidEntries(
        library.favoriteEntries,
        validTrackIds,
      ),
      playlists: [
        for (final playlist in library.playlists)
          playlist.copyWith(
            entries: _filterValidEntries(playlist.entries, validTrackIds),
          ),
      ],
    );
  }

  List<PlaylistTrackEntry> _filterValidEntries(
    List<PlaylistTrackEntry> entries,
    Set<String>? validTrackIds,
  ) {
    final unique = _uniqueEntries(entries);
    if (validTrackIds == null) {
      return unique;
    }
    return unique
        .where((entry) => validTrackIds.contains(entry.trackId))
        .toList(growable: false);
  }

  Future<File> _playlistFile() async {
    final root = await _rootProvider();
    return _playlistFileIn(root);
  }

  File _playlistFileIn(Directory root) {
    return File('${root.path}${Platform.pathSeparator}$_fileName');
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

  static Future<Directory> _defaultRoot() async {
    return getAiMusicSupportSubdirectory('ai_music_playlists');
  }
}

List<PlaylistTrackEntry> _entriesFromJson(
  Object? value, {
  required DateTime fallbackAddedAt,
}) {
  final rows = value is List ? value : const [];
  return _uniqueEntries([
    for (final row in rows) ?PlaylistTrackEntry.fromJson(row, fallbackAddedAt),
  ]);
}

List<PlaylistTrackEntry> _entriesFromIds(List<String> ids, DateTime addedAt) {
  return _uniqueEntries([
    for (final id in ids)
      if (id.trim().isNotEmpty)
        PlaylistTrackEntry(trackId: id.trim(), addedAt: addedAt),
  ]);
}

List<PlaylistTrackEntry> _uniqueEntries(List<PlaylistTrackEntry> entries) {
  final seen = <String>{};
  final unique = <PlaylistTrackEntry>[];
  for (final entry in entries) {
    final id = entry.trackId.trim();
    if (id.isNotEmpty && seen.add(id)) {
      unique.add(PlaylistTrackEntry(trackId: id, addedAt: entry.addedAt));
    }
  }
  return unique;
}
