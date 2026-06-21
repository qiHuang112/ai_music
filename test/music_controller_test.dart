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

      expect(handler.restoredMediaId, item.id);
      expect(handler.restoredPosition, const Duration(seconds: 42));
      expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
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
  String? restoredMediaId;
  Duration? restoredPosition;

  @override
  Duration get currentPosition => currentPositionOverride;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    bool playWhenReady = true,
  }) async {
    loadedIds = [for (final item in items) item.mediaItem.id];
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex].mediaItem);
    }
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

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return metadata;
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
    return library;
  }

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    this.library = library;
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
