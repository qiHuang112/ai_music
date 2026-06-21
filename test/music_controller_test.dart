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

      expect(metadata.loadIds, [cached.cacheId]);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

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
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
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
}

class _SpyAudioHandler extends MusicAudioHandler {
  List<String> loadedIds = const [];
  AudioServiceShuffleMode? shuffleMode;
  AudioServiceRepeatMode? repeatMode;
  Duration currentPositionOverride = Duration.zero;
  Duration? loadedInitialPosition;
  String? restoredMediaId;
  Duration? restoredPosition;
  int playCalls = 0;

  @override
  Duration get currentPosition => currentPositionOverride;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    loadedIds = [for (final item in items) item.mediaItem.id];
    loadedInitialPosition = initialPosition;
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex].mediaItem);
    }
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    playbackState.add(playbackState.value.copyWith(playing: true));
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
  Future<void> cleanupTemporaryFiles() async {}
}

MusicSearchCandidate _candidate({required String id, required String name}) {
  return MusicSearchCandidate(
    query: name,
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    keyword: name,
    page: 1,
    id: id,
    name: name,
    artist: 'artist',
    album: '',
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3')],
    score: 100,
    raw: const {},
  );
}

CachedTrack _cachedTrack({required String id, required String name}) {
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
