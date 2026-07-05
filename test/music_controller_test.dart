import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/music_mappers.dart';
import 'package:ai_music/src/application/music_ui_message.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/playback_state_store.dart';
import 'package:ai_music/src/data/progressive_audio_cache.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playTrack uses the explicit queue and applies shuffle mode', () async {
    final handler = _SpyAudioHandler();
    final tracks = [
      _cachedTrack(id: 'song-1', name: '第一首'),
      _cachedTrack(id: 'song-2', name: '第二首'),
    ];
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: tracks),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      await controller.setPlaybackMode(PlaybackMode.shuffle);
      final favoriteQueue = [trackFromCached(tracks.last)];

      await controller.playTrack(
        favoriteQueue.single,
        index: 0,
        queueTracks: favoriteQueue,
      );

      expect(handler.loadedIds, [tracks.last.cacheId]);
      expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('initialize restores favorite queue without auto-playing', () async {
    final handler = _SpyAudioHandler();
    final first = _cachedTrack(id: 'song-1', name: '第一首');
    final second = _cachedTrack(id: 'song-2', name: '第二首');
    final playbackStore = _MemoryPlaybackStateStore(
      SavedPlaybackState(
        playbackMode: PlaybackMode.shuffle,
        queueSource: const PlaybackQueueSource.favorite(),
        queueTrackIds: [second.cacheId, first.cacheId],
        currentTrackId: first.cacheId,
      ),
    );
    final playlistStore = _MemoryPlaylistStore()
      ..library = PlaylistLibrary(
        favoriteEntries: [
          PlaylistTrackEntry(trackId: second.cacheId, addedAt: DateTime(2026)),
          PlaylistTrackEntry(trackId: first.cacheId, addedAt: DateTime(2026)),
        ],
        playlists: const [],
      );
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [first, second]),
      playlistStore: playlistStore,
      settingsStore: _FakeSettingsStore(),
      playbackStateStore: playbackStore,
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();

      expect(handler.loadedIds, [second.cacheId, first.cacheId]);
      expect(handler.mediaItem.value?.id, first.cacheId);
      expect(handler.loadedInitialPosition, Duration.zero);
      expect(handler.playCalls, 0);
      expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
      expect(controller.playbackMode, PlaybackMode.shuffle);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'initialize does not restore removed favorite tracks from local cache',
    () async {
      final handler = _SpyAudioHandler();
      final removed = _cachedTrack(id: 'song-1', name: '已取消收藏');
      final kept = _cachedTrack(id: 'song-2', name: '仍在收藏');
      final playbackStore = _MemoryPlaybackStateStore(
        SavedPlaybackState(
          playbackMode: PlaybackMode.loopAll,
          queueSource: const PlaybackQueueSource.favorite(),
          queueTrackIds: [removed.cacheId, kept.cacheId],
          currentTrackId: removed.cacheId,
        ),
      );
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(
          favoriteEntries: [
            PlaylistTrackEntry(trackId: kept.cacheId, addedAt: DateTime(2026)),
          ],
          playlists: const [],
        );
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [removed, kept]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        playbackStateStore: playbackStore,
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();

        expect(handler.loadedIds, [kept.cacheId]);
        expect(handler.loadedInitialIndex, 0);
        expect(playbackStore.state?.queueTrackIds, [kept.cacheId]);
        expect(playbackStore.state?.currentTrackId, kept.cacheId);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('initialize restores custom playlist queue', () async {
    final handler = _SpyAudioHandler();
    final first = _cachedTrack(id: 'song-1', name: '第一首');
    final second = _cachedTrack(id: 'song-2', name: '第二首');
    final playbackStore = _MemoryPlaybackStateStore(
      SavedPlaybackState(
        playbackMode: PlaybackMode.loopAll,
        queueSource: const PlaybackQueueSource.customPlaylist('road'),
        queueTrackIds: [first.cacheId, second.cacheId],
        currentTrackId: second.cacheId,
      ),
    );
    final playlistStore = _MemoryPlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            trackIds: [first.cacheId, second.cacheId],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [first, second]),
      playlistStore: playlistStore,
      settingsStore: _FakeSettingsStore(),
      playbackStateStore: playbackStore,
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();

      expect(handler.loadedIds, [first.cacheId, second.cacheId]);
      expect(handler.mediaItem.value?.id, second.cacheId);
      expect(handler.playCalls, 0);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'initialize clears custom playlist state when playlist no longer exists',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '本地仍存在');
      final playbackStore = _MemoryPlaybackStateStore(
        SavedPlaybackState(
          playbackMode: PlaybackMode.loopAll,
          queueSource: const PlaybackQueueSource.customPlaylist('deleted'),
          queueTrackIds: [cached.cacheId],
          currentTrackId: cached.cacheId,
        ),
      );
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        playbackStateStore: playbackStore,
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();

        expect(handler.loadedIds, isEmpty);
        expect(playbackStore.state, isNull);
        expect(playbackStore.clearCount, 1);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('initialize skips a deleted current track in saved queue', () async {
    final handler = _SpyAudioHandler();
    final first = _cachedTrack(id: 'song-1', name: '第一首');
    final third = _cachedTrack(id: 'song-3', name: '第三首');
    final missing = _cachedTrack(id: 'song-2', name: '已删除');
    final playbackStore = _MemoryPlaybackStateStore(
      SavedPlaybackState(
        playbackMode: PlaybackMode.sequential,
        queueSource: const PlaybackQueueSource.searchCache(),
        queueTrackIds: [first.cacheId, missing.cacheId, third.cacheId],
        currentTrackId: missing.cacheId,
      ),
    );
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [first, third]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      playbackStateStore: playbackStore,
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();

      expect(handler.loadedIds, [first.cacheId, third.cacheId]);
      expect(handler.loadedInitialIndex, 1);
      expect(playbackStore.state?.currentTrackId, third.cacheId);
      expect(playbackStore.state?.queueTrackIds, [
        first.cacheId,
        third.cacheId,
      ]);
      expect(handler.playCalls, 0);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'initialize clears saved playback when queue has no cached tracks',
    () async {
      final handler = _SpyAudioHandler();
      final missing = _cachedTrack(id: 'song-2', name: '已删除');
      final playbackStore = _MemoryPlaybackStateStore(
        SavedPlaybackState(
          playbackMode: PlaybackMode.repeatOne,
          queueSource: const PlaybackQueueSource.localCache(),
          queueTrackIds: [missing.cacheId],
          currentTrackId: missing.cacheId,
        ),
      );
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        playbackStateStore: playbackStore,
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();

        expect(handler.loadedIds, isEmpty);
        expect(playbackStore.state, isNull);
        expect(playbackStore.clearCount, 1);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('media item changes trigger metadata reload', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final metadata = _StaticMetadataRepository(
      metadata: const TrackMetadata(
        lyrics: [LyricLine(time: Duration(seconds: 1), text: '第一句')],
      ),
    );
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      handler.emit(mediaItemFromTrack(trackFromCached(cached)));
      for (var i = 0; i < 10 && controller.currentLyrics.isEmpty; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(metadata.loadIds, contains(cached.cacheId));
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('metadata load keeps existing artwork media item unchanged', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(
      id: 'song-1',
      name: '第一首',
      coverUrl: 'https://cdn.example.test/song-1.jpg',
    );
    final metadata = _StaticMetadataRepository(
      metadata: TrackMetadata(
        artworkUri: Uri.parse('https://cdn.example.test/song-1.jpg'),
      ),
    );
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      handler.emit(mediaItemFromTrack(trackFromCached(cached)));
      for (var i = 0; i < 10 && metadata.loadIds.isEmpty; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(metadata.loadIds, contains(cached.cacheId));
      expect(handler.mediaItemUpdateCount, 0);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'downloaded candidate is cached before metadata priming completes',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final metadata = _CompletingMetadataRepository();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final candidate = _candidate(id: 'song-1', name: '第一首');

      try {
        await controller.initialize();

        await controller.downloadCandidate(candidate);

        expect(metadata.loadIds, [cacheStore.cached.single.cacheId]);
        expect(controller.isCandidateCached(candidate), isTrue);
        expect(controller.cachedTracks.single.title, '第一首');

        metadata.complete(const TrackMetadata());
        for (var i = 0; i < 10 && controller.isLoadingCache; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'system favorite action toggles the active track favorite state',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final playlistStore = _MemoryPlaylistStore();
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        handler.emit(mediaItemFromTrack(track));
        handler
          ..currentPositionOverride = const Duration(seconds: 37)
          ..currentBufferedPositionOverride = const Duration(seconds: 60)
          ..currentQueueIndexOverride = 0
          ..loadedIds = const [];
        handler.playbackState.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: true,
            updatePosition: const Duration(seconds: 5),
            bufferedPosition: const Duration(seconds: 10),
            queueIndex: 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.isFavorite(track), isFalse);

        await handler.customAction(MusicAudioHandler.toggleFavoriteAction);

        expect(controller.isFavorite(track), isTrue);
        expect(playlistStore.library.favoriteTrackIds, [track.id]);
        expect(handler.loadedIds, isEmpty);
        expect(handler.restoredMediaId, isNull);
        expect(handler.restoredPosition, isNull);
        expect(
          handler.playbackState.value.updatePosition,
          const Duration(seconds: 37),
        );
        expect(
          handler.playbackState.value.bufferedPosition,
          const Duration(seconds: 60),
        );
        expect(handler.playbackState.value.queueIndex, 0);

        await handler.customAction(MusicAudioHandler.toggleFavoriteAction, {
          'mediaId': 'other-song',
        });

        expect(controller.isFavorite(track), isTrue);
        expect(playlistStore.library.favoriteTrackIds, [track.id]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('changing playback mode keeps current song and position', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final item = mediaItemFromTrack(trackFromCached(cached));
      handler
        ..emit(item)
        ..currentPositionOverride = const Duration(seconds: 42);

      await controller.setPlaybackMode(PlaybackMode.shuffle);

      expect(handler.restoredMediaId, isNull);
      expect(handler.restoredPosition, isNull);
      expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'repeating current track does not reload queue and resumes if paused',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        await controller.playTrack(track);

        handler
          ..loadedIds = const []
          ..playCalls = 0;
        handler.playbackState.add(PlaybackState(playing: true));

        await controller.playTrack(track);

        expect(handler.loadedIds, isEmpty);
        expect(handler.playCalls, 0);

        handler.playbackState.add(PlaybackState(playing: false));
        await controller.playTrack(track);

        expect(handler.loadedIds, isEmpty);
        expect(handler.playCalls, 1);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'same track in a different visible queue rebuilds queue at current position',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final firstTrack = trackFromCached(first);
        final secondTrack = trackFromCached(second);
        await controller.playTrack(
          firstTrack,
          index: 0,
          queueTracks: [firstTrack, secondTrack],
        );

        handler
          ..loadedIds = const []
          ..loadedInitialPosition = null
          ..currentPositionOverride = const Duration(seconds: 38);
        handler.playbackState.add(PlaybackState(playing: true));

        await controller.playTrack(
          firstTrack,
          index: 0,
          queueTracks: [firstTrack],
        );

        expect(handler.loadedIds, [first.cacheId]);
        expect(handler.loadedInitialPosition, const Duration(seconds: 38));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('clearSearch ignores delayed stale search results', () async {
    final handler = _SpyAudioHandler();
    final resolver = _CompletingSearchResolver();
    final controller = MusicController(
      audioHandler: handler,
      resolver: resolver,
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final search = controller.search('周杰伦');
      await Future<void>.delayed(Duration.zero);

      expect(controller.isSearching, isTrue);

      controller.clearSearch();
      resolver.complete([_candidate(id: 'song-1', name: '稻香')]);
      await search;

      expect(controller.isSearching, isFalse);
      expect(controller.candidates, isEmpty);
      expect(controller.errorDetail, isNull);
      expect(controller.statusMessage, isNull);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('new search supersedes an in-flight search', () async {
    final handler = _SpyAudioHandler();
    final resolver = _SequencedSearchResolver();
    final controller = MusicController(
      audioHandler: handler,
      resolver: resolver,
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final firstSearch = controller.search('A');
      await Future<void>.delayed(Duration.zero);
      final secondSearch = controller.search('B');
      await Future<void>.delayed(Duration.zero);

      resolver.complete(0, [_candidate(id: 'song-a', name: '旧结果')]);
      await firstSearch;
      expect(controller.candidates, isEmpty);
      expect(controller.isSearching, isTrue);

      resolver.complete(1, [_candidate(id: 'song-b', name: '新结果')]);
      await secondSearch;

      expect(controller.candidates.single.name, '新结果');
      expect(controller.isSearching, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('favorite and playlist entries keep added time metadata', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final track = trackFromCached(cached);

      await controller.toggleFavorite(track);
      final playlist = await controller.createPlaylist('Road');
      await controller.addTrackToPlaylist(playlist!, track);

      expect(controller.favoriteAddedAt(track), isNotNull);
      expect(
        controller.playlistTrackAddedAt(
          controller.customPlaylists.single,
          track,
        ),
        isNotNull,
      );
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'batch adding tracks appends in selection order and skips duplicates',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('Road');
        await controller.addTrackToPlaylist(playlist!, trackFromCached(first));
        await controller.addTracksToPlaylist(
          controller.customPlaylists.single,
          [trackFromCached(second), trackFromCached(first)],
        );

        expect(controller.customPlaylists.single.trackIds, [
          first.cacheId,
          second.cacheId,
        ]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'batch deleting cached tracks removes metadata and playlist references',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final cacheStore = _FakeCacheStore(cached: [first, second]);
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(
          favoriteEntries: [
            PlaylistTrackEntry(trackId: first.cacheId, addedAt: DateTime(2026)),
            PlaylistTrackEntry(
              trackId: second.cacheId,
              addedAt: DateTime(2026),
            ),
          ],
          playlists: [
            MusicPlaylist(
              id: 'road',
              name: 'Road',
              entries: [
                PlaylistTrackEntry(
                  trackId: first.cacheId,
                  addedAt: DateTime(2026),
                ),
                PlaylistTrackEntry(
                  trackId: second.cacheId,
                  addedAt: DateTime(2026),
                ),
              ],
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: cacheStore,
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );

      try {
        await controller.initialize();
        await controller.deleteCachedTracks([
          trackFromCached(first),
          trackFromCached(second),
        ]);

        expect(cacheStore.cached, isEmpty);
        expect(
          metadata.deletedIds,
          unorderedEquals([first.cacheId, second.cacheId]),
        );
        expect(controller.favoriteTracks, isEmpty);
        expect(controller.customPlaylists.single.trackIds, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'removing active favorite clears persisted queue and does not resurrect it',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final playbackStore = _MemoryPlaybackStateStore();
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(
          favoriteEntries: [
            PlaylistTrackEntry(
              trackId: cached.cacheId,
              addedAt: DateTime(2026),
            ),
          ],
          playlists: const [],
        );
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        playbackStateStore: playbackStore,
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        await controller.playTrack(
          track,
          index: 0,
          queueTracks: [track],
          queueSource: const PlaybackQueueSource.favorite(),
        );

        expect(playbackStore.state?.queueTrackIds, [cached.cacheId]);

        await controller.toggleFavorite(track);
        await controller.setPlaybackMode(PlaybackMode.shuffle);

        expect(playbackStore.state, isNull);
        expect(playbackStore.clearCount, 1);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'removing active playlist track clears persisted custom playlist queue',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final playbackStore = _MemoryPlaybackStateStore();
      final playlist = MusicPlaylist(
        id: 'road',
        name: 'Road',
        trackIds: [cached.cacheId],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(playlists: [playlist]);
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        playbackStateStore: playbackStore,
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        await controller.playTrack(
          track,
          index: 0,
          queueTracks: [track],
          queueSource: const PlaybackQueueSource.customPlaylist('road'),
        );

        await controller.removeTrackFromPlaylist(
          controller.customPlaylists.single,
          track,
        );
        await controller.setPlaybackMode(PlaybackMode.repeatOne);

        expect(playbackStore.state, isNull);
        expect(playbackStore.clearCount, 1);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'deleting a queued non-current cached track rebuilds queue around current track',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final firstTrack = trackFromCached(first);
        final secondTrack = trackFromCached(second);
        await controller.playTrack(
          firstTrack,
          index: 0,
          queueTracks: [firstTrack, secondTrack],
        );
        handler
          ..loadedIds = const []
          ..loadedInitialPosition = null
          ..currentPositionOverride = const Duration(seconds: 21);
        handler.playbackState.add(PlaybackState(playing: true));

        await controller.deleteCachedTrack(secondTrack);

        expect(handler.loadedIds, [first.cacheId]);
        expect(handler.loadedInitialPosition, const Duration(seconds: 21));
        expect(handler.mediaItem.value?.id, first.cacheId);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'reordering favorites and playlists preserves added time metadata',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final firstAddedAt = DateTime(2026, 1, 1);
      final secondAddedAt = DateTime(2026, 1, 2);
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(
          favoriteEntries: [
            PlaylistTrackEntry(trackId: first.cacheId, addedAt: firstAddedAt),
            PlaylistTrackEntry(trackId: second.cacheId, addedAt: secondAddedAt),
          ],
          playlists: [
            MusicPlaylist(
              id: 'road',
              name: 'Road',
              entries: [
                PlaylistTrackEntry(
                  trackId: first.cacheId,
                  addedAt: firstAddedAt,
                ),
                PlaylistTrackEntry(
                  trackId: second.cacheId,
                  addedAt: secondAddedAt,
                ),
              ],
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );
      final controller = MusicController(
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final reversedTracks = [
          trackFromCached(second),
          trackFromCached(first),
        ];
        await controller.reorderFavoriteTracks(reversedTracks);
        await controller.reorderPlaylistTracks(
          controller.customPlaylists.single,
          reversedTracks,
        );

        expect(playlistStore.library.favoriteTrackIds, [
          second.cacheId,
          first.cacheId,
        ]);
        expect(
          playlistStore.library.favoriteEntries.first.addedAt,
          secondAddedAt,
        );
        expect(playlistStore.library.playlists.single.trackIds, [
          second.cacheId,
          first.cacheId,
        ]);
        expect(
          playlistStore.library.playlists.single.entries.first.addedAt,
          secondAddedAt,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('clearing media item invalidates pending metadata load', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final metadata = _CompletingMetadataRepository();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      handler.emit(mediaItemFromTrack(trackFromCached(cached)));
      for (var i = 0; i < 10 && metadata.loadIds.isEmpty; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      handler.emit(null);
      metadata.complete(
        const TrackMetadata(
          lyrics: [LyricLine(time: Duration(seconds: 1), text: '旧歌词')],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.currentLyrics, isEmpty);
      expect(controller.currentArtworkUri, isNull);
      expect(controller.isLoadingMetadata, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('playlist mutations are serialized', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();

      final first = controller.createPlaylist('A');
      final second = controller.createPlaylist('B');
      await Future.wait([first, second]);

      expect(controller.customPlaylists.map((playlist) => playlist.name), [
        'A',
        'B',
      ]);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'downloadCandidate caches without auto-playing and allows concurrency',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final firstCandidate = _candidate(id: 'song-1', name: '第一首');
      final secondCandidate = _candidate(id: 'song-2', name: '第二首');

      try {
        await controller.initialize();

        final first = controller.downloadCandidate(firstCandidate);
        await Future<void>.delayed(Duration.zero);
        final second = controller.downloadCandidate(secondCandidate);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(resolver.resolveIds, ['song-1', 'song-2']);
        expect(controller.isCandidateDownloading(firstCandidate), isTrue);
        expect(controller.isCandidateDownloading(secondCandidate), isTrue);

        await Future.wait([first, second]);

        expect(cacheStore.downloadIds, unorderedEquals(['song-1', 'song-2']));
        expect(handler.loadedIds, isEmpty);
        expect(controller.isCandidateDownloading(firstCandidate), isFalse);
        expect(controller.isCandidateDownloading(secondCandidate), isFalse);
        expect(controller.activeDownloadTasks, isEmpty);
        expect(
          controller.cachedTracks.map((track) => track.title),
          unorderedEquals(['第一首', '第二首']),
        );
        expect(metadata.loadIds, hasLength(2));
        expect(metadata.loadIds.toSet(), {
          cacheStore.cached[0].cacheId,
          cacheStore.cached[1].cacheId,
        });
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'repeated download tap keeps task status and does not resolve twice',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      final candidate = _candidate(id: 'song-1', name: '第一首');

      try {
        await controller.initialize();

        final first = controller.downloadCandidate(candidate);
        await Future<void>.delayed(Duration.zero);
        await controller.downloadCandidate(candidate);

        expect(resolver.resolveIds, ['song-1']);
        expect(
          controller.statusMessage?.code,
          MusicUiMessageCode.downloadAlreadyRunning,
        );

        await first;

        expect(controller.activeDownloadTasks, isEmpty);
        expect(
          controller.recentDownloadTasks.single.status,
          DownloadTaskStatus.completed,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('failed downloads remain visible as recent tasks', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FailingMusicResolver(),
      cacheStore: _DownloadCacheStore(),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      await controller.downloadCandidate(_candidate(id: 'song-1', name: '第一首'));

      expect(controller.activeDownloadTasks, isEmpty);
      expect(
        controller.recentDownloadTasks.single.status,
        DownloadTaskStatus.failed,
      );
      expect(
        controller.recentDownloadTasks.single.error,
        contains('resolve failed'),
      );

      controller.clearDownloadTask(controller.recentDownloadTasks.single.id);
      expect(controller.recentDownloadTasks, isEmpty);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('playCandidate downloads when needed and starts cached track', () async {
    final handler = _SpyAudioHandler();
    final resolver = _DelayedMusicResolver();
    final cacheStore = _DownloadCacheStore();
    final controller = MusicController(
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cacheStore,
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    final candidate = _candidate(id: 'song-1', name: '第一首');

    try {
      await controller.initialize();

      expect(controller.isCandidateCached(candidate), isFalse);

      await controller.playCandidate(candidate);

      expect(resolver.resolveIds, ['song-1']);
      expect(cacheStore.downloadIds, ['song-1']);
      expect(controller.isCandidateCached(candidate), isTrue);
      expect(handler.loadedIds, [
        cacheIdForResolved(cacheStore.cached.single.music),
      ]);
      expect(handler.playCalls, 1);
      expect(
        controller.statusMessage?.code,
        MusicUiMessageCode.playingCachedFile,
      );
      expect(controller.hasSearchState, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'playCandidate plays itunes preview without downloading cache',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _PreviewMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      final candidate = _candidate(
        id: 'preview-1',
        name: '稻香',
        source: MusicDataSource.itunesPreview,
        platform: 'itunes',
      );

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(resolver.resolveIds, ['preview-1']);
        expect(cacheStore.downloadIds, isEmpty);
        expect(controller.cachedTracks, isEmpty);
        expect(handler.loadedIds, ['preview:itunes_preview:preview-1']);
        expect(handler.playCalls, 1);
        expect(
          controller.statusMessage?.code,
          MusicUiMessageCode.playingPreviewAudio,
        );
        expect(controller.currentLyrics.single.text, '试听歌词');
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'playCandidate streams Kuwo full audio without download task and promotes cache',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_controller_kuwo_',
      );
      final transientRoot = await Directory.systemTemp.createTemp(
        'ai_music_controller_kuwo_transient_',
      );
      final audioBytes = _controllerValidMp3Bytes(48 * 1024);
      final handler = _SpyAudioHandler();
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final logs = <String>[];
      final streaming = StreamingPlaybackCache(
        cacheStore: cacheStore,
        progressiveCache: ProgressiveAudioCache(
          cacheStore: cacheStore,
          rootProvider: () async => root,
          client: _FakeProgressiveHttpClient(audioBytes, chunkSize: 4096),
          logger: logs.add,
        ),
        transientStore: TransientStreamingCacheStore(
          rootProvider: () async => transientRoot,
        ),
      );
      final controller = MusicController(
        audioHandler: handler,
        resolver: _KuwoFullAudioMusicResolver(
          'https://audio.example.test/song.mp3',
        ),
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        streamingPlaybackCache: streaming,
      );
      final candidate = _candidate(
        id: 'MUSIC_351583919',
        name: '稻香',
        artist: '周杰伦',
        source: MusicDataSource.kuwoFullAudio,
        platform: 'kuwo',
      );

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(handler.loadedIds, [
          'stream:source_kuwo_full_audio:MUSIC_351583919',
        ]);
        expect(handler.loadedUris.single.scheme, 'http');
        expect(handler.playCalls, 1);
        expect(controller.activeDownloadTasks, isEmpty);
        expect(controller.recentDownloadTasks, isEmpty);
        expect(
          controller.statusMessage?.code,
          MusicUiMessageCode.playingFullAudioStream,
        );
        expect(
          controller.hotlistPlaybackLogs.any(
            (log) =>
                log.contains('full-audio play-started') &&
                log.contains('not-in-download-list=true'),
          ),
          isTrue,
        );

        List<CachedTrack> cached = const [];
        for (var i = 0; i < 80; i += 1) {
          cached = await cacheStore.listCached();
          if (cached.isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(cached, hasLength(1));
        expect(cached.single.music.source, MusicDataSource.kuwoFullAudio);
        expect(await File(cached.single.filePath).exists(), isTrue);
        expect(cached.single.filePath.endsWith('.part'), isFalse);
        expect(
          controller.hotlistPlaybackLogs.any(
            (log) => log.contains('full-audio first_byte_ms='),
          ),
          isTrue,
        );
        expect(
          controller.hotlistPlaybackLogs.any(
            (log) => log.contains('full-audio part-growth'),
          ),
          isTrue,
        );
        expect(
          controller.hotlistPlaybackLogs.any(
            (log) =>
                log.contains('full-audio download-complete') &&
                log.contains('download_complete_ms='),
          ),
          isTrue,
        );
        expect(
          logs.any((log) => log.startsWith('progressive promoted')),
          isTrue,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
        await transientRoot.delete(recursive: true);
      }
    },
  );

  test(
    'playCandidate keeps Kuwo full audio stream failures out of cache and downloads',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_controller_kuwo_fail_',
      );
      final handler = _SpyAudioHandler();
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final controller = MusicController(
        audioHandler: handler,
        resolver: _KuwoFullAudioMusicResolver('https://cdn.example.test/a.mp3'),
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        streamingPlaybackCache: _FailingStreamingPlayback(),
      );
      final candidate = _candidate(
        id: 'MUSIC_475511188',
        name: '一丝不挂',
        artist: '陈奕迅',
        source: MusicDataSource.kuwoFullAudio,
        platform: 'kuwo',
      );

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(handler.loadedIds, isEmpty);
        expect(controller.activeDownloadTasks, isEmpty);
        expect(controller.recentDownloadTasks, isEmpty);
        expect(await cacheStore.listCached(), isEmpty);
        expect(controller.errorDetail, contains('stream open failed'));
        expect(
          controller.hotlistPlaybackLogs.any(
            (log) => log.contains('full-audio play-failed'),
          ),
          isTrue,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('next resumes playback when player is paused', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      handler.playbackState.add(PlaybackState(playing: false));

      await controller.next();

      expect(handler.skipNextCalls, 1);
      expect(handler.playCalls, 1);
      expect(handler.playbackState.value.playing, isTrue);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'playCandidate refreshes cached candidate cover without redownloading',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _CoverResolvingMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      cacheStore.cached.add(cached);
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final candidate = _candidate(
        id: 'song-1',
        name: '第一首',
        coverUrl: 'https://img.example.test/song-1.jpg',
      );

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(resolver.resolveIds, ['song-1']);
        expect(cacheStore.downloadIds, isEmpty);
        expect(
          cacheStore.cached.single.music.coverUrl,
          'https://img.example.test/song-1.jpg',
        );
        expect(metadata.loadIds, contains(cached.cacheId));
        expect(handler.loadedIds, [cached.cacheId]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'playCandidate refreshes cached candidate lyrics even when cover exists',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LyricsResolvingMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final cached = _cachedTrack(
        id: 'song-1',
        name: '第一首',
        coverUrl: 'https://img.example.test/existing.jpg',
      );
      cacheStore.cached.add(cached);
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final candidate = _candidate(id: 'song-1', name: '第一首');

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(resolver.resolveIds, ['song-1']);
        expect(cacheStore.downloadIds, isEmpty);
        expect(cacheStore.cached.single.music.coverUrl, cached.music.coverUrl);
        expect(cacheStore.cached.single.music.lyrics?.text, contains('补齐歌词'));
        expect(metadata.loadIds, contains(cached.cacheId));
        expect(handler.loadedIds, [cached.cacheId]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );
}

class _SpyAudioHandler extends MusicAudioHandler {
  List<String> loadedIds = const [];
  List<Uri> loadedUris = const [];
  AudioServiceShuffleMode? shuffleMode;
  AudioServiceRepeatMode? repeatMode;
  Duration currentPositionOverride = Duration.zero;
  Duration currentBufferedPositionOverride = Duration.zero;
  int? currentQueueIndexOverride;
  int? loadedInitialIndex;
  Duration? loadedInitialPosition;
  String? restoredMediaId;
  Duration? restoredPosition;
  int playCalls = 0;
  int skipNextCalls = 0;
  int mediaItemUpdateCount = 0;

  @override
  Duration get currentPosition => currentPositionOverride;

  @override
  Duration get currentBufferedPosition => currentBufferedPositionOverride;

  @override
  int? get currentQueueIndex => currentQueueIndexOverride;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    loadedIds = [for (final item in items) item.mediaItem.id];
    loadedUris = [for (final item in items) item.uri];
    loadedInitialIndex = initialIndex;
    loadedInitialPosition = initialPosition;
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex].mediaItem);
    }
    if (playWhenReady) {
      await play();
    }
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> skipToNext() async {
    skipNextCalls += 1;
    await play();
  }

  @override
  Future<void> updateCurrentMediaItem(MediaItem updated) async {
    mediaItemUpdateCount += 1;
    mediaItem.add(updated);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    this.shuffleMode = shuffleMode;
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    this.repeatMode = repeatMode;
  }

  @override
  Future<void> restoreCurrentItemPosition(
    String mediaId,
    Duration position,
  ) async {
    restoredMediaId = mediaId;
    restoredPosition = position;
  }

  void emit(MediaItem? item) {
    mediaItem.add(item);
  }
}

class _StaticMetadataRepository extends TrackMetadataRepository {
  _StaticMetadataRepository({this.metadata = const TrackMetadata()});

  final TrackMetadata metadata;
  final loadIds = <String>[];
  final deletedIds = <String>[];

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return metadata;
  }

  @override
  Future<TrackMetadata> loadBypassingMetadataMiss(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return metadata;
  }

  @override
  Future<void> delete(String cacheId) async {
    deletedIds.add(cacheId);
  }
}

class _CompletingMetadataRepository extends TrackMetadataRepository {
  final loadIds = <String>[];
  final _completer = Completer<TrackMetadata>();

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return _completer.future;
  }

  void complete(TrackMetadata metadata) {
    _completer.complete(metadata);
  }
}

class _FakeCacheStore extends CachedTrackStore {
  _FakeCacheStore({required this.cached});

  final List<CachedTrack> cached;

  @override
  Future<List<CachedTrack>> listCached() async {
    return cached;
  }

  @override
  Future<void> cleanupTemporaryFiles() async {}

  @override
  Future<void> deleteCached(String cacheId) async {
    cached.removeWhere((track) => track.cacheId == cacheId);
  }
}

class _FakePlaylistStore extends PlaylistStore {
  _FakePlaylistStore() : super(rootProvider: _unusedRootProvider);

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async {
    return const PlaylistLibrary.empty();
  }

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {}
}

class _MemoryPlaylistStore extends PlaylistStore {
  _MemoryPlaylistStore() : super(rootProvider: _unusedRootProvider);

  PlaylistLibrary library = const PlaylistLibrary.empty();

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    library = _sanitize(library, validTrackIds);
    return library;
  }

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    this.library = _sanitize(library, validTrackIds);
  }

  PlaylistLibrary _sanitize(PlaylistLibrary library, Set<String>? validIds) {
    List<PlaylistTrackEntry> filter(List<PlaylistTrackEntry> entries) {
      final unique = <PlaylistTrackEntry>[];
      final seen = <String>{};
      for (final entry in entries) {
        if (seen.add(entry.trackId) &&
            (validIds == null || validIds.contains(entry.trackId))) {
          unique.add(entry);
        }
      }
      return unique;
    }

    return PlaylistLibrary(
      favoriteEntries: filter(library.favoriteEntries),
      playlists: [
        for (final playlist in library.playlists)
          playlist.copyWith(entries: filter(playlist.entries)),
      ],
    );
  }
}

class _FakeSettingsStore implements MusicSettingsStore {
  @override
  Future<MusicAppSettings> loadSettings() async {
    return const MusicAppSettings();
  }

  @override
  Future<void> saveSettings(MusicAppSettings settings) async {}

  @override
  Future<MusicDataSource> loadSource() async {
    return MusicDataSource.buguyy;
  }

  @override
  Future<void> saveSource(MusicDataSource source) async {}
}

class _MemoryPlaybackStateStore extends PlaybackStateStore {
  _MemoryPlaybackStateStore([this.state])
    : super(rootProvider: _unusedRootProvider);

  SavedPlaybackState? state;
  int clearCount = 0;
  int saveCount = 0;

  @override
  Future<SavedPlaybackState?> load() async {
    return state;
  }

  @override
  Future<void> save(SavedPlaybackState state) async {
    saveCount += 1;
    this.state = state;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    state = null;
  }
}

class _FakeMusicResolver implements MusicResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    return const [];
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    throw UnimplementedError();
  }
}

class _DelayedMusicResolver implements MusicResolver {
  final resolveIds = <String>[];

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    return const [];
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
    );
  }
}

class _FailingMusicResolver extends _FakeMusicResolver {
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    throw StateError('resolve failed');
  }
}

class _CoverResolvingMusicResolver extends _FakeMusicResolver {
  final resolveIds = <String>[];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
      coverUrl: candidate.coverUrl,
    );
  }
}

class _LyricsResolvingMusicResolver extends _FakeMusicResolver {
  final resolveIds = <String>[];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
      lyrics: const ResolvedLyrics(
        source: 'test',
        text: '[00:01.00]补齐歌词',
        lines: 1,
        timed: true,
      ),
    );
  }
}

class _PreviewMusicResolver extends _FakeMusicResolver {
  final resolveIds = <String>[];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    return ResolvedMusic(
      query: candidate.query,
      source: MusicDataSource.itunesPreview,
      platform: 'itunes',
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://audio-ssl.itunes.apple.com/preview.m4a',
      quality: const MusicQuality(format: 'preview'),
      urlType: MediaUrlType.previewAudio,
      canCacheAudio: false,
      lyrics: const ResolvedLyrics(
        source: 'lrclib:syncedLyrics',
        text: '[00:01.00]试听歌词',
        lines: 1,
        timed: true,
      ),
    );
  }
}

class _KuwoFullAudioMusicResolver extends _FakeMusicResolver {
  _KuwoFullAudioMusicResolver(this.url);

  final String url;
  final resolveIds = <String>[];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    return ResolvedMusic(
      query: candidate.query,
      source: MusicDataSource.kuwoFullAudio,
      platform: 'kuwo',
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: url,
      quality: const MusicQuality(format: 'mp3', bitrate: '128'),
      duration: 187,
      urlType: MediaUrlType.directAudio,
      canCacheAudio: true,
      sourceAttempts: [
        SourceAttempt(
          query: candidate.query,
          source: MusicDataSource.kuwoFullAudio,
          stage: 'media_validation',
          status: SourceAttemptStatus.ok,
          reasonCode: 'direct_audio_ready',
          candidateId: candidate.id,
          candidateTitle: candidate.name,
          candidateArtist: candidate.artist,
          mediaUrl: url,
          mediaUrlType: MediaUrlType.directAudio,
          mediaContentType: 'audio/mpeg',
          mediaContentLength: 49152,
          clientReady: true,
          mediaValidation: 'HEAD 200 audio/mpeg; Range 206 bytes 0-0/49152',
        ),
      ],
    );
  }
}

class _FailingStreamingPlayback implements HotlistStreamingPlayback {
  @override
  Future<StreamingPlaybackHandle> openHotlistTrack(
    ResolvedMusic resolved,
    StreamingPlaybackPolicy policy,
  ) {
    throw const SourceDownloadException(
      'stream open failed',
      failureCode: 'audio_validation_failed',
    );
  }

  @override
  Future<void> close() async {}
}

class _FakeProgressiveHttpClient implements HttpClient {
  _FakeProgressiveHttpClient(this.bytes, {required this.chunkSize});

  final List<int> bytes;
  final int chunkSize;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeProgressiveHttpClientRequest(bytes, chunkSize: chunkSize);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProgressiveHttpClientRequest implements HttpClientRequest {
  _FakeProgressiveHttpClientRequest(this.bytes, {required this.chunkSize});

  final List<int> bytes;
  final int chunkSize;
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    final chunks = <List<int>>[];
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = offset + chunkSize > bytes.length
          ? bytes.length
          : offset + chunkSize;
      chunks.add(bytes.sublist(offset, end));
    }
    return _FakeProgressiveHttpClientResponse(bytes, chunks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProgressiveHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeProgressiveHttpClientResponse(this.bytes, this.chunks);

  final List<int> bytes;
  final List<List<int>> chunks;

  @override
  int get statusCode => HttpStatus.partialContent;

  @override
  int get contentLength => bytes.length;

  @override
  HttpHeaders get headers => _FakeHttpHeaders(
    contentType: ContentType('audio', 'mpeg'),
    values: {
      HttpHeaders.contentRangeHeader:
          'bytes 0-${bytes.length - 1}/${bytes.length}',
      HttpHeaders.acceptRangesHeader: 'bytes',
    },
  );

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(chunks).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  _FakeHttpHeaders({this.contentType, Map<String, String> values = const {}})
    : _values = {
        for (final entry in values.entries)
          entry.key.toLowerCase(): entry.value,
      };

  @override
  ContentType? contentType;
  final Map<String, String> _values;
  final Map<String, String> _setValues = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _setValues[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) {
    return _setValues[name.toLowerCase()] ?? _values[name.toLowerCase()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CompletingSearchResolver extends _FakeMusicResolver {
  final _searchCompleter = Completer<List<MusicSearchCandidate>>();

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    return _searchCompleter.future;
  }

  void complete(List<MusicSearchCandidate> candidates) {
    _searchCompleter.complete(candidates);
  }
}

class _SequencedSearchResolver extends _FakeMusicResolver {
  final _searchCompleters = <Completer<List<MusicSearchCandidate>>>[];

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    final completer = Completer<List<MusicSearchCandidate>>();
    _searchCompleters.add(completer);
    return completer.future;
  }

  void complete(int index, List<MusicSearchCandidate> candidates) {
    _searchCompleters[index].complete(candidates);
  }
}

class _DownloadCacheStore extends CachedTrackStore {
  final cached = <CachedTrack>[];
  final downloadIds = <String>[];

  @override
  Future<CachedTrack> downloadOrReuse(
    ResolvedMusic result, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCanceled();
    downloadIds.add(result.id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final track = CachedTrack(
      cacheId: cacheIdForResolved(result),
      music: result,
      filePath: '/tmp/${result.id}.mp3',
      sizeBytes: 4,
      fromCache: false,
    );
    cached.add(track);
    return track;
  }

  @override
  Future<List<CachedTrack>> listCached() async {
    return List<CachedTrack>.unmodifiable(cached);
  }

  @override
  Future<CachedTrack> updateCachedMusic(
    CachedTrack cachedTrack,
    ResolvedMusic music,
  ) async {
    final index = cached.indexWhere(
      (track) => track.cacheId == cachedTrack.cacheId,
    );
    final updated = cachedTrack.copyWith(music: music, fromCache: true);
    if (index == -1) {
      cached.add(updated);
    } else {
      cached[index] = updated;
    }
    return updated;
  }

  @override
  Future<void> cleanupTemporaryFiles() async {}
}

MusicSearchCandidate _candidate({
  required String id,
  required String name,
  String artist = 'artist',
  String coverUrl = '',
  MusicDataSource source = MusicDataSource.buguyy,
  String platform = 'buguyy',
}) {
  return MusicSearchCandidate(
    query: name,
    source: source,
    platform: platform,
    keyword: name,
    page: 1,
    id: id,
    name: name,
    artist: artist,
    album: '',
    duration: 200,
    link: '',
    coverUrl: coverUrl,
    qualities: const [MusicQuality(format: 'mp3')],
    score: 100,
    raw: const {},
  );
}

CachedTrack _cachedTrack({
  required String id,
  required String name,
  String coverUrl = '',
}) {
  final music = ResolvedMusic(
    query: name,
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: id,
    name: name,
    artist: 'artist',
    album: '',
    url: 'https://cdn.example.test/$id.mp3',
    quality: const MusicQuality(format: 'mp3'),
    coverUrl: coverUrl,
  );
  return CachedTrack(
    cacheId: cacheIdForResolved(music),
    music: music,
    filePath: '/tmp/$id.mp3',
    sizeBytes: 4,
    fromCache: true,
  );
}

Future<Directory> _unusedRootProvider() async {
  return Directory.systemTemp.createTemp('ai_music_unused_');
}

List<int> _controllerValidMp3Bytes(int size) {
  final payload = size < 16 * 1024 ? 16 * 1024 : size;
  return [
    0x49,
    0x44,
    0x33,
    0x04,
    0x00,
    0x00,
    ...List<int>.filled(payload - 6, 0),
  ];
}
