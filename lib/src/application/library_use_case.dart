import '../data/lyrics_artwork.dart';
import '../data/music_charts.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../data/resolver_models.dart';
import '../data/saved_online_track.dart';
import '../data/playlist_song.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/music_models.dart';
import 'library_controller.dart';
import 'music_mappers.dart';

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.cachedRecords,
    required this.cachedTracks,
    required this.onlineTracks,
    required this.playlistLibrary,
    required this.favoriteTracks,
    required this.customPlaylists,
  });

  final List<CachedTrack> cachedRecords;
  final List<Track> cachedTracks;
  final List<Track> onlineTracks;
  List<Track> get allTracks => [...cachedTracks, ...onlineTracks];
  final PlaylistLibrary playlistLibrary;
  final List<Track> favoriteTracks;
  final List<MusicPlaylist> customPlaylists;
}

class LibraryUseCase {
  LibraryUseCase({
    required this.cacheStore,
    required this.playlistStore,
    required this.metadataRepository,
    this.libraryController = const LibraryController(),
  });

  final CachedTrackStore cacheStore;
  final PlaylistStore playlistStore;
  final TrackMetadataRepository metadataRepository;
  final LibraryController libraryController;
  Future<void> _playlistMutationTail = Future.value();
  LibrarySnapshot? _latestSnapshot;

  Future<LibrarySnapshot> loadCache() async {
    final cachedRecords = await cacheStore.listCached();
    final cachedTracks = cachedRecords
        .map(trackFromCached)
        .toList(growable: false);
    final playlistLibrary = await playlistStore.load(
      validTrackIds: libraryController.validTrackIds(cachedTracks),
    );
    final snapshot = _snapshot(cachedRecords, cachedTracks, playlistLibrary);
    _latestSnapshot = snapshot;
    return snapshot;
  }

  LibrarySnapshot applyCachedRecords(
    List<CachedTrack> cachedRecords,
    PlaylistLibrary playlistLibrary,
  ) {
    final cachedTracks = cachedRecords
        .map(trackFromCached)
        .toList(growable: false);
    final snapshot = _snapshot(cachedRecords, cachedTracks, playlistLibrary);
    _latestSnapshot = snapshot;
    return snapshot;
  }

  /// Keep favorites and playlist entries visible when streamed audio is cleared.
  Future<LibrarySnapshot> preservePlaybackReferences({
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final replacements = <String, SavedOnlineTrack>{};
      for (final record in base.cachedRecords.where(
        (item) => item.playbackCache,
      )) {
        final music = record.music;
        if (music.source == MusicDataSource.auto ||
            music.source == MusicDataSource.lan ||
            music.id.isEmpty) {
          continue;
        }
        replacements[record.cacheId] = SavedOnlineTrack(
          candidate: MusicSearchCandidate(
            query: music.query.isEmpty
                ? '${music.artist} ${music.name}'
                : music.query,
            source: music.source,
            platform: music.platform,
            keyword: music.name,
            page: 1,
            id: music.id,
            name: music.name,
            artist: music.artist,
            album: music.album,
            duration: 0,
            link: '',
            coverUrl: music.coverUrl,
            qualities: [music.quality],
            score: 0,
            raw: const {},
          ),
        );
      }
      if (replacements.isEmpty) return base;

      var changed = false;
      List<PlaylistTrackEntry> convert(List<PlaylistTrackEntry> entries) {
        final seen = <String>{};
        final convertedEntries = <PlaylistTrackEntry>[];
        for (final entry in entries) {
          final saved = entry.onlineTrack ?? replacements[entry.trackId];
          final converted = saved == null || entry.onlineTrack != null
              ? entry
              : PlaylistTrackEntry(
                  trackId: saved.trackId,
                  addedAt: entry.addedAt,
                  onlineTrack: saved,
                );
          if (converted.trackId != entry.trackId) changed = true;
          if (seen.add(converted.trackId)) convertedEntries.add(converted);
        }
        return convertedEntries;
      }

      final library = base.playlistLibrary.copyWith(
        favoriteEntries: convert(base.playlistLibrary.favoriteEntries),
        playlists: [
          for (final playlist in base.playlistLibrary.playlists)
            playlist.copyWith(entries: convert(playlist.entries)),
        ],
      );
      return changed ? _savePlaylistLibrary(library, current: base) : base;
    });
  }

  Future<LibrarySnapshot> deleteCachedTrack(
    Track track, {
    required LibrarySnapshot current,
  }) async {
    await cacheStore.deleteCached(track.id);
    await metadataRepository.delete(track.id);
    return loadCache();
  }

  Future<LibrarySnapshot> deleteCachedTracks(
    List<Track> tracks, {
    required LibrarySnapshot current,
  }) async {
    final ids = {for (final track in tracks) track.id};
    for (final id in ids) {
      await cacheStore.deleteCached(id);
    }
    for (final id in ids) {
      await metadataRepository.delete(id);
    }
    return loadCache();
  }

  Future<LibrarySnapshot> toggleFavorite(
    Track track, {
    required LibrarySnapshot current,
    SavedOnlineTrack? onlineTrack,
    PlaylistTrackEntry? fallbackEntry,
    void Function(bool added)? onFavoriteChanged,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final entries = [...base.playlistLibrary.favoriteEntries];
      final existing = entries.indexWhere((entry) => entry.trackId == track.id);
      if (existing != -1) {
        entries.removeAt(existing);
      } else {
        final entry = _entryForTrack(base.playlistLibrary, track.id);
        final sourceEntry = entry?.song != null || entry?.onlineTrack != null
            ? entry
            : fallbackEntry;
        final online =
            onlineTrack ??
            _onlineForTrack(base.playlistLibrary, track.id) ??
            sourceEntry?.onlineTrack;
        entries.add(
          PlaylistTrackEntry(
            trackId: track.id,
            addedAt: DateTime.now(),
            onlineTrack: online,
            song: sourceEntry?.song,
            manualSource: sourceEntry?.manualSource ?? false,
          ),
        );
      }
      final result = await _savePlaylistLibrary(
        base.playlistLibrary.copyWith(favoriteEntries: entries),
        current: base,
      );
      onFavoriteChanged?.call(existing == -1);
      return result;
    });
  }

  /// A chart is a persistent, read-only playlist of metadata. Audio is resolved
  /// on demand, and a refreshed ranking retains each song's selected source.
  Future<MusicPlaylistResult> upsertChart(
    MusicChart chart,
    MusicChartResult result, {
    required LibrarySnapshot current,
  }) => _enqueuePlaylistMutation(() async {
    if (chart.isVideo) throw StateError('MV charts contain videos');
    final base = _currentSnapshot(current);
    final existing = base.playlistLibrary.playlists
        .where((p) => p.id == chart.playlistId)
        .firstOrNull;
    final previous = {
      for (final e in existing?.entries ?? <PlaylistTrackEntry>[]) e.trackId: e,
    };
    final now = DateTime.now();
    final seen = <String>{};
    final entries = <PlaylistTrackEntry>[];
    for (final row in result.entries) {
      final key = row.sourceId.isNotEmpty
          ? '${chart.platform.name}:${row.sourceId}'
          : '${chart.platform.name}:${row.title.trim()}\u001f${row.artist.trim()}';
      final id =
          'song-${sha256.convert(utf8.encode('${chart.playlistId}\u001f$key'))}';
      if (!seen.add(id)) continue;
      final old = previous[id] ?? _entryForTrack(base.playlistLibrary, id);
      entries.add(
        PlaylistTrackEntry(
          trackId: id,
          addedAt: old?.addedAt ?? now,
          onlineTrack: old?.onlineTrack,
          manualSource: old?.manualSource ?? false,
          song: PlaylistSong(
            key: key,
            title: row.title,
            artist: row.artist,
            coverUrl: row.artworkUri?.toString() ?? '',
          ),
        ),
      );
    }
    final playlist = MusicPlaylist(
      id: chart.playlistId,
      name: chart.playlistName,
      entries: entries,
      hasBeenOpened: true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final snapshot = await _savePlaylistLibrary(
      base.playlistLibrary.copyWith(
        playlists: [
          for (final p in base.playlistLibrary.playlists)
            p.id == playlist.id ? playlist : p,
          if (existing == null) playlist,
        ],
      ),
      current: base,
    );
    return MusicPlaylistResult(snapshot: snapshot, playlist: playlist);
  });

  Future<MusicPlaylistResult> createPlaylist(
    String name, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        return MusicPlaylistResult(snapshot: base);
      }
      final now = DateTime.now();
      final playlist = MusicPlaylist(
        id: 'playlist-${now.microsecondsSinceEpoch}',
        name: trimmed,
        entries: const [],
        createdAt: now,
        updatedAt: now,
      );
      final snapshot = await _savePlaylistLibrary(
        base.playlistLibrary.copyWith(
          playlists: [...base.playlistLibrary.playlists, playlist],
        ),
        current: base,
      );
      return MusicPlaylistResult(snapshot: snapshot, playlist: playlist);
    });
  }

  /// Import in one serialized write; no empty playlist or second read/write.
  Future<MusicPlaylistResult> importPlaylistSongs(
    String name,
    List<PlaylistSong> songs, {
    MusicPlaylist? target,
    required LibrarySnapshot current,
  }) => _enqueuePlaylistMutation(() async {
    if (target?.isBuiltIn == true) throw StateError('不能向榜单添加歌曲');
    final base = _currentSnapshot(current);
    if (name.trim().isEmpty || songs.isEmpty) {
      return MusicPlaylistResult(snapshot: base);
    }
    final existing = target == null
        ? null
        : base.customPlaylists.where((p) => p.id == target.id).firstOrNull;
    if (target != null && existing == null) {
      throw StateError('The destination playlist was deleted');
    }
    final now = DateTime.now();
    final playlistId = existing?.id ?? 'playlist-${now.microsecondsSinceEpoch}';
    final keys = {
      for (final e in existing?.entries ?? <PlaylistTrackEntry>[])
        if (e.song != null) e.song!.key,
    };
    final entries = [
      ...?existing?.entries,
      for (final song in songs)
        if (keys.add(song.key))
          PlaylistTrackEntry(
            trackId:
                'song-${sha256.convert(utf8.encode('$playlistId\u001f${song.key}'))}',
            addedAt: now,
            song: song,
          ),
    ];
    final playlist =
        existing?.copyWith(entries: entries, updatedAt: now) ??
        MusicPlaylist(
          id: playlistId,
          name: name.trim(),
          entries: entries,
          createdAt: now,
          updatedAt: now,
        );
    final snapshot = await _savePlaylistLibrary(
      base.playlistLibrary.copyWith(
        playlists: [
          for (final p in base.customPlaylists)
            p.id == playlistId ? playlist : p,
          if (existing == null) playlist,
        ],
      ),
      current: base,
    );
    return MusicPlaylistResult(
      snapshot: snapshot,
      playlist: playlist,
      addedTrackIds: playlist.trackIds.toSet().difference(
        existing?.trackIds.toSet() ?? {},
      ),
    );
  });

  /// A song keeps its logical ID even when the chosen audio resource changes.
  Future<LibrarySnapshot> saveSongSource(
    Track track,
    SavedOnlineTrack source, {
    required LibrarySnapshot current,
    required bool manual,
    SavedOnlineTrack? expectedSource,
  }) => _enqueuePlaylistMutation(() async {
    final base = _currentSnapshot(current);
    List<PlaylistTrackEntry> update(List<PlaylistTrackEntry> entries) => [
      for (final entry in entries)
        if (entry.trackId != track.id ||
            (!manual &&
                (entry.manualSource ||
                    entry.onlineTrack?.trackId != expectedSource?.trackId)))
          entry
        else
          PlaylistTrackEntry(
            trackId: entry.trackId,
            addedAt: entry.addedAt,
            song:
                entry.song ??
                PlaylistSong(
                  key: track.id,
                  title: track.title,
                  artist: track.artist,
                  coverUrl: track.artworkUri?.toString() ?? '',
                ),
            onlineTrack: source,
            manualSource: manual,
          ),
    ];
    return _savePlaylistLibrary(
      base.playlistLibrary.copyWith(
        favoriteEntries: update(base.playlistLibrary.favoriteEntries),
        playlists: [
          for (final p in base.customPlaylists)
            p.copyWith(entries: update(p.entries)),
        ],
      ),
      current: base,
    );
  });

  Future<MusicPlaylistResult> importOnlinePlaylist(
    String name,
    List<SavedOnlineTrack> tracks, {
    MusicPlaylist? target,
    List<String>? sourceOrderTrackIds,
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      if (target?.isBuiltIn == true) throw StateError('不能向榜单添加歌曲');
      final base = _currentSnapshot(current);
      if (name.trim().isEmpty || tracks.isEmpty) {
        return MusicPlaylistResult(snapshot: base);
      }
      final existing = target == null
          ? null
          : base.customPlaylists
                .where((item) => item.id == target.id)
                .firstOrNull;
      if (target != null && existing == null) {
        throw StateError('The destination playlist was deleted');
      }
      final now = DateTime.now();
      final ids = existing?.trackIds.toSet() ?? <String>{};
      final entries = [
        ...?existing?.entries,
        for (final track in tracks)
          if (ids.add(track.trackId))
            PlaylistTrackEntry(
              trackId: track.trackId,
              addedAt: now,
              onlineTrack: track,
            ),
      ];
      var orderedEntries = entries;
      if (sourceOrderTrackIds != null) {
        // A retried earlier source row must not be left at the end. Keep any
        // unrelated local additions after the synced source rows.
        final order = sourceOrderTrackIds.toSet();
        final byId = {for (final entry in entries) entry.trackId: entry};
        orderedEntries = [
          for (final id in order)
            if (byId[id] != null) byId[id]!,
          for (final entry in entries)
            if (!order.contains(entry.trackId)) entry,
        ];
      }
      final playlist =
          existing?.copyWith(entries: orderedEntries, updatedAt: now) ??
          MusicPlaylist(
            id: 'playlist-${now.microsecondsSinceEpoch}',
            name: name.trim(),
            entries: orderedEntries,
            createdAt: now,
            updatedAt: now,
          );
      final library = base.playlistLibrary.copyWith(
        playlists: [
          for (final item in base.customPlaylists)
            item.id == playlist.id ? playlist : item,
          if (existing == null) playlist,
        ],
      );
      await playlistStore.write(
        library,
        validTrackIds: libraryController.validTrackIds(base.cachedTracks),
      );
      final snapshot = _snapshot(
        base.cachedRecords,
        base.cachedTracks,
        library,
      );
      _latestSnapshot = snapshot;
      return MusicPlaylistResult(
        snapshot: snapshot,
        playlist: playlist,
        addedTrackIds: playlist.trackIds.toSet().difference(
          existing?.trackIds.toSet() ?? <String>{},
        ),
      );
    });
  }

  Future<MusicPlaylistResult> replaceImportedCandidate(
    MusicPlaylist target,
    String previousId,
    SavedOnlineTrack replacement, {
    required bool removePrevious,
    required LibrarySnapshot current,
  }) => _enqueuePlaylistMutation(() async {
    final base = _currentSnapshot(current);
    final existing = base.customPlaylists
        .where((p) => p.id == target.id)
        .firstOrNull;
    if (existing == null || !existing.trackIds.contains(previousId)) {
      throw StateError('The playlist or original song was removed');
    }
    final nextId = replacement.trackId;
    if (nextId == previousId) {
      return MusicPlaylistResult(snapshot: base, playlist: existing);
    }
    final alreadyPresent = existing.trackIds.contains(nextId);
    final now = DateTime.now();
    final entries = <PlaylistTrackEntry>[];
    for (final entry in existing.entries) {
      if (entry.trackId != previousId) {
        entries.add(entry);
        continue;
      }
      if (!removePrevious) entries.add(entry);
      if (!alreadyPresent) {
        entries.add(
          PlaylistTrackEntry(
            trackId: nextId,
            addedAt: entry.addedAt,
            onlineTrack: replacement,
          ),
        );
      }
    }
    final playlist = existing.copyWith(entries: entries, updatedAt: now);
    final library = base.playlistLibrary.copyWith(
      playlists: [
        for (final item in base.customPlaylists)
          item.id == target.id ? playlist : item,
      ],
    );
    await playlistStore.write(
      library,
      validTrackIds: libraryController.validTrackIds(base.cachedTracks),
    );
    final snapshot = _snapshot(base.cachedRecords, base.cachedTracks, library);
    _latestSnapshot = snapshot;
    return MusicPlaylistResult(
      snapshot: snapshot,
      playlist: playlist,
      addedTrackIds: alreadyPresent ? const {} : {nextId},
    );
  });

  Future<({LibrarySnapshot snapshot, bool first})> claimFirstPlaylistOpening(
    MusicPlaylist playlist, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final saved = base.playlistLibrary.playlists
          .where((item) => item.id == playlist.id)
          .firstOrNull;
      if (saved == null || saved.hasBeenOpened) {
        return (snapshot: base, first: false);
      }
      final snapshot = await _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) => item.copyWith(hasBeenOpened: true),
      );
      return (snapshot: snapshot, first: true);
    });
  }

  Future<LibrarySnapshot> renamePlaylist(
    MusicPlaylist playlist,
    String name, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      if (playlist.isBuiltIn) throw StateError('榜单由平台维护，不能修改');
      final base = _currentSnapshot(current);
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        return base;
      }
      return _savePlaylistLibrary(
        base.playlistLibrary.copyWith(
          playlists: [
            for (final item in base.playlistLibrary.playlists)
              item.id == playlist.id
                  ? item.copyWith(name: trimmed, updatedAt: DateTime.now())
                  : item,
          ],
        ),
        current: base,
      );
    });
  }

  Future<LibrarySnapshot> deletePlaylist(
    MusicPlaylist playlist, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      if (playlist.isBuiltIn) throw StateError('榜单由平台维护，不能修改');
      final base = _currentSnapshot(current);
      return _savePlaylistLibrary(
        base.playlistLibrary.copyWith(
          playlists: [
            for (final item in base.playlistLibrary.playlists)
              if (item.id != playlist.id) item,
          ],
        ),
        current: base,
      );
    });
  }

  Future<LibrarySnapshot> addTrackToPlaylist(
    MusicPlaylist playlist,
    Track track, {
    required LibrarySnapshot current,
  }) {
    return addTracksToPlaylist(playlist, [track], current: current);
  }

  Future<LibrarySnapshot> addOnlineTracksToPlaylist(
    MusicPlaylist playlist,
    List<SavedOnlineTrack> tracks, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      if (playlist.isBuiltIn) throw StateError('榜单由平台维护，不能修改');
      final base = _currentSnapshot(current);
      return _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) {
          final existing = item.trackIds.toSet();
          final now = DateTime.now();
          final additions = [
            for (final online in tracks)
              if (existing.add(online.trackId))
                PlaylistTrackEntry(
                  trackId: online.trackId,
                  addedAt: now,
                  onlineTrack: online,
                ),
          ];
          return additions.isEmpty
              ? item
              : item.copyWith(
                  entries: [...item.entries, ...additions],
                  updatedAt: now,
                );
        },
      );
    });
  }

  Future<LibrarySnapshot> addTracksToPlaylist(
    MusicPlaylist playlist,
    List<Track> tracks, {
    required LibrarySnapshot current,
    Map<String, SavedOnlineTrack> onlineTracksById = const {},
    Map<String, PlaylistTrackEntry> fallbackEntriesById = const {},
  }) {
    return _enqueuePlaylistMutation(() async {
      if (playlist.isBuiltIn) throw StateError('榜单由平台维护，不能修改');
      final base = _currentSnapshot(current);
      return _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) {
          final existing = item.trackIds.toSet();
          final additions = <PlaylistTrackEntry>[];
          final now = DateTime.now();
          for (final track in tracks) {
            if (existing.add(track.id)) {
              final entry = _entryForTrack(base.playlistLibrary, track.id);
              final sourceEntry =
                  entry?.song != null || entry?.onlineTrack != null
                  ? entry
                  : fallbackEntriesById[track.id];
              additions.add(
                PlaylistTrackEntry(
                  trackId: track.id,
                  addedAt: now,
                  onlineTrack:
                      onlineTracksById[track.id] ??
                      _onlineForTrack(base.playlistLibrary, track.id) ??
                      sourceEntry?.onlineTrack,
                  song: sourceEntry?.song,
                  manualSource: sourceEntry?.manualSource ?? false,
                ),
              );
            }
          }
          if (additions.isEmpty) {
            return item;
          }
          return item.copyWith(
            entries: [...item.entries, ...additions],
            updatedAt: now,
          );
        },
      );
    });
  }

  Future<LibrarySnapshot> removeTrackFromPlaylist(
    MusicPlaylist playlist,
    Track track, {
    required LibrarySnapshot current,
  }) {
    return removeTracksFromPlaylist(playlist, [track], current: current);
  }

  Future<LibrarySnapshot> removeTracksFromPlaylist(
    MusicPlaylist playlist,
    List<Track> tracks, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      if (playlist.isBuiltIn) throw StateError('榜单由平台维护，不能修改');
      final base = _currentSnapshot(current);
      final ids = {for (final track in tracks) track.id};
      return _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) => item.copyWith(
          entries: [
            for (final entry in item.entries)
              if (!ids.contains(entry.trackId)) entry,
          ],
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  Future<LibrarySnapshot> removeTracksFromFavorites(
    List<Track> tracks, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final ids = {for (final track in tracks) track.id};
      return _savePlaylistLibrary(
        base.playlistLibrary.copyWith(
          favoriteEntries: [
            for (final entry in base.playlistLibrary.favoriteEntries)
              if (!ids.contains(entry.trackId)) entry,
          ],
        ),
        current: base,
      );
    });
  }

  Future<LibrarySnapshot> reorderFavoriteTracks(
    List<Track> tracks, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final currentEntries = base.playlistLibrary.favoriteEntries;
      return _savePlaylistLibrary(
        base.playlistLibrary.copyWith(
          favoriteEntries: _reorderedEntries(currentEntries, tracks),
        ),
        current: base,
      );
    });
  }

  Future<LibrarySnapshot> reorderPlaylistTracks(
    MusicPlaylist playlist,
    List<Track> tracks, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      if (playlist.isBuiltIn) throw StateError('榜单由平台维护，不能修改');
      final base = _currentSnapshot(current);
      return _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) => item.copyWith(
          entries: _reorderedEntries(item.entries, tracks),
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  LibrarySnapshot _snapshot(
    List<CachedTrack> cachedRecords,
    List<Track> cachedTracks,
    PlaylistLibrary playlistLibrary,
  ) {
    // Index once per snapshot instead of scanning all cached songs per entry.
    final cachedByIdentity = <(Object, String, String), CachedTrack>{};
    for (final record in cachedRecords) {
      final identity = (
        record.music.source,
        record.music.platform,
        record.music.id,
      );
      cachedByIdentity.update(
        identity,
        (current) =>
            cachedTrackPlaybackPreference(record) >
                cachedTrackPlaybackPreference(current)
            ? record
            : current,
        ifAbsent: () => record,
      );
    }
    final onlineById = <String, Track>{};
    for (final entry in [
      ...playlistLibrary.favoriteEntries,
      for (final playlist in playlistLibrary.playlists) ...playlist.entries,
    ]) {
      final saved = entry.onlineTrack;
      if (saved == null) {
        final song = entry.song;
        if (song != null) {
          onlineById[entry.trackId] = Track(
            id: entry.trackId,
            title: song.title,
            artist: song.artist,
            album: '',
            artworkUri: artworkUriFromText(song.coverUrl),
          );
        }
        continue;
      }
      final candidate = saved.candidate;
      final cached =
          cachedByIdentity[(
            candidate.source,
            candidate.platform,
            candidate.id,
          )];
      onlineById[entry.trackId] = Track(
        id: entry.trackId,
        title: candidate.name,
        artist: candidate.artist,
        album: candidate.album,
        filePath: cached?.filePath ?? '',
        sizeBytes: cached?.sizeBytes ?? 0,
        artworkUri: artworkUriFromText(candidate.coverUrl),
        duration: candidate.duration > 0
            ? Duration(seconds: candidate.duration)
            : null,
        cachedAt: cached?.cachedAt,
      );
    }
    final allTracks = [...cachedTracks, ...onlineById.values];
    return LibrarySnapshot(
      cachedRecords: cachedRecords,
      cachedTracks: cachedTracks,
      onlineTracks: onlineById.values.toList(growable: false),
      playlistLibrary: playlistLibrary,
      favoriteTracks: libraryController.tracksForIds(
        playlistLibrary.favoriteTrackIds,
        allTracks,
      ),
      customPlaylists: playlistLibrary.playlists,
    );
  }

  Future<LibrarySnapshot> _updatePlaylist(
    String playlistId, {
    required LibrarySnapshot current,
    required MusicPlaylist Function(MusicPlaylist playlist) update,
  }) {
    return _savePlaylistLibrary(
      current.playlistLibrary.copyWith(
        playlists: [
          for (final item in current.playlistLibrary.playlists)
            item.id == playlistId ? update(item) : item,
        ],
      ),
      current: current,
    );
  }

  Future<LibrarySnapshot> _savePlaylistLibrary(
    PlaylistLibrary library, {
    required LibrarySnapshot current,
  }) async {
    await playlistStore.write(
      library,
      validTrackIds: libraryController.validTrackIds(current.cachedTracks),
    );
    final playlistLibrary = await playlistStore.load(
      validTrackIds: libraryController.validTrackIds(current.cachedTracks),
    );
    final snapshot = _snapshot(
      current.cachedRecords,
      current.cachedTracks,
      playlistLibrary,
    );
    _latestSnapshot = snapshot;
    return snapshot;
  }

  LibrarySnapshot _currentSnapshot(LibrarySnapshot fallback) {
    return _latestSnapshot ?? fallback;
  }

  Future<T> _enqueuePlaylistMutation<T>(Future<T> Function() action) {
    // 收藏和歌单操作可能被用户快速连点；串行化可以避免 read-modify-write 丢变更。
    final run = _playlistMutationTail.then((_) => action());
    _playlistMutationTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

PlaylistTrackEntry? _entryForTrack(PlaylistLibrary library, String trackId) => [
  ...library.favoriteEntries,
  for (final playlist in library.playlists) ...playlist.entries,
].where((e) => e.trackId == trackId).firstOrNull;

SavedOnlineTrack? _onlineForTrack(PlaylistLibrary library, String trackId) {
  for (final entry in [
    ...library.favoriteEntries,
    for (final playlist in library.playlists) ...playlist.entries,
  ]) {
    if (entry.trackId == trackId && entry.onlineTrack != null) {
      return entry.onlineTrack;
    }
  }
  return null;
}

List<PlaylistTrackEntry> _reorderedEntries(
  List<PlaylistTrackEntry> currentEntries,
  List<Track> orderedTracks,
) {
  final byId = {for (final entry in currentEntries) entry.trackId: entry};
  final orderedIds = <String>{};
  final reordered = <PlaylistTrackEntry>[];
  for (final track in orderedTracks) {
    final entry = byId[track.id];
    if (entry != null && orderedIds.add(track.id)) {
      reordered.add(entry);
    }
  }
  for (final entry in currentEntries) {
    if (orderedIds.add(entry.trackId)) {
      reordered.add(entry);
    }
  }
  return reordered;
}

class MusicPlaylistResult {
  const MusicPlaylistResult({
    required this.snapshot,
    this.playlist,
    this.addedTrackIds = const {},
  });

  final Set<String> addedTrackIds;

  final LibrarySnapshot snapshot;
  final MusicPlaylist? playlist;
}
