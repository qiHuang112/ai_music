import '../data/lyrics_artwork.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../domain/music_models.dart';
import 'library_controller.dart';
import 'music_mappers.dart';

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.cachedRecords,
    required this.cachedTracks,
    required this.playlistLibrary,
    required this.favoriteTracks,
    required this.customPlaylists,
  });

  final List<CachedTrack> cachedRecords;
  final List<Track> cachedTracks;
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

  Future<LibrarySnapshot> deleteCachedTrack(
    Track track, {
    required LibrarySnapshot current,
  }) async {
    await cacheStore.deleteCached(track.id);
    await metadataRepository.delete(track.id);
    return loadCache();
  }

  Future<LibrarySnapshot> toggleFavorite(
    Track track, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      final entries = [...base.playlistLibrary.favoriteEntries];
      final existing = entries.indexWhere((entry) => entry.trackId == track.id);
      if (existing != -1) {
        entries.removeAt(existing);
      } else {
        entries.add(
          PlaylistTrackEntry(trackId: track.id, addedAt: DateTime.now()),
        );
      }
      return _savePlaylistLibrary(
        base.playlistLibrary.copyWith(favoriteEntries: entries),
        current: base,
      );
    });
  }

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

  Future<LibrarySnapshot> renamePlaylist(
    MusicPlaylist playlist,
    String name, {
    required LibrarySnapshot current,
  }) {
    return _enqueuePlaylistMutation(() async {
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
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      return _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) {
          if (item.trackIds.contains(track.id)) {
            return item;
          }
          final now = DateTime.now();
          return item.copyWith(
            entries: [
              ...item.entries,
              PlaylistTrackEntry(trackId: track.id, addedAt: now),
            ],
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
    return _enqueuePlaylistMutation(() async {
      final base = _currentSnapshot(current);
      return _updatePlaylist(
        playlist.id,
        current: base,
        update: (item) => item.copyWith(
          entries: [
            for (final entry in item.entries)
              if (entry.trackId != track.id) entry,
          ],
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
    return LibrarySnapshot(
      cachedRecords: cachedRecords,
      cachedTracks: cachedTracks,
      playlistLibrary: playlistLibrary,
      favoriteTracks: libraryController.tracksForIds(
        playlistLibrary.favoriteTrackIds,
        cachedTracks,
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
    final run = _playlistMutationTail.then((_) => action());
    _playlistMutationTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

class MusicPlaylistResult {
  const MusicPlaylistResult({required this.snapshot, this.playlist});

  final LibrarySnapshot snapshot;
  final MusicPlaylist? playlist;
}
