import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/data/hotlist.dart';
import 'package:ai_music/src/data/hotlist_playlists.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/progressive_audio_cache.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saving a hotlist playlist preserves rank order and skips duplicates',
    () async {
      final root = await Directory.systemTemp.createTemp('hotlist_playlist_');
      var now = DateTime(2026, 7, 5);
      final store = HotlistPlaylistStore(
        rootProvider: () async => root,
        now: () => now,
      );

      try {
        final first = await store.saveChart(_chart());
        now = DateTime(2026, 7, 6);
        final second = await store.saveChart(_chart());
        final playlists = await store.load();

        expect(first.addedCount, 3);
        expect(first.skippedCount, 0);
        expect(second.addedCount, 0);
        expect(second.skippedCount, 3);
        expect(playlists.single.entries.map((entry) => entry.title), [
          'A Song',
          'B Song',
          'C Song',
        ]);
        expect(playlists.single.entries.map((entry) => entry.rank), [1, 2, 3]);
        expect(playlists.single.entries.first.addedAt, DateTime(2026, 7, 5));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'saving an existing hotlist refreshes metadata in latest rank order',
    () async {
      final root = await Directory.systemTemp.createTemp('hotlist_playlist_');
      var now = DateTime(2026, 7, 5);
      final store = HotlistPlaylistStore(
        rootProvider: () async => root,
        now: () => now,
      );

      try {
        await store.saveChart(_chart());
        now = DateTime(2026, 7, 6);
        final result = await store.saveChart(_updatedChart());
        final entries = result.playlist.entries;

        expect(result.addedCount, 1);
        expect(result.skippedCount, 2);
        expect(entries.map((entry) => entry.title), [
          'B Song Live',
          'A Song',
          'D Song',
        ]);
        expect(entries.map((entry) => entry.rank), [1, 2, 3]);
        expect(entries[0].sourceTrackId, 'b');
        expect(entries[0].addedAt, DateTime(2026, 7, 5));
        expect(entries[1].addedAt, DateTime(2026, 7, 5));
        expect(entries[2].addedAt, DateTime(2026, 7, 6));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('transient LRU sweep deletes only transient files', () async {
    final root = await Directory.systemTemp.createTemp('transient_cache_');
    final formalRoot = await Directory.systemTemp.createTemp('formal_cache_');
    final store = TransientStreamingCacheStore(
      rootProvider: () async => root,
      now: () => DateTime(2026, 7, 5),
    );
    final formal = File('${formalRoot.path}${Platform.pathSeparator}keep.mp3');
    await formal.writeAsBytes(List<int>.filled(16, 1));

    try {
      final older = await store.createPartFile('older');
      await older.writeAsBytes(List<int>.filled(64, 1));
      await store.upsert(
        TransientStreamingCacheEntry(
          cacheKey: 'older',
          filePath: older.path,
          downloadedBytes: 64,
          state: TransientStreamingState.complete,
          createdAt: DateTime(2026, 7, 5, 1),
          lastAccessed: DateTime(2026, 7, 5, 1),
          playCount: 1,
          source: 'buguyy',
          quality: 'MP3',
        ),
      );

      final newer = await store.createPartFile('newer');
      await newer.writeAsBytes(List<int>.filled(64, 1));
      await store.upsert(
        TransientStreamingCacheEntry(
          cacheKey: 'newer',
          filePath: newer.path,
          downloadedBytes: 64,
          state: TransientStreamingState.complete,
          createdAt: DateTime(2026, 7, 5, 2),
          lastAccessed: DateTime(2026, 7, 5, 2),
          playCount: 1,
          source: 'buguyy',
          quality: 'MP3',
        ),
      );

      final removed = await store.sweep(maxBytes: 80);

      expect(removed, 1);
      expect(await older.exists(), isFalse);
      expect(await newer.exists(), isTrue);
      expect(await formal.exists(), isTrue);
      expect(await store.list(), hasLength(1));
    } finally {
      await root.delete(recursive: true);
      await formalRoot.delete(recursive: true);
    }
  });

  test(
    'transient upsert replaces same cacheKey without leaving orphan',
    () async {
      final root = await Directory.systemTemp.createTemp('transient_cache_');
      var now = DateTime(2026, 7, 5);
      final store = TransientStreamingCacheStore(
        rootProvider: () async => root,
        now: () => now,
      );

      try {
        final first = await store.createPartFile('same');
        await first.writeAsBytes(List<int>.filled(64, 1));
        await store.upsert(
          TransientStreamingCacheEntry(
            cacheKey: 'same',
            filePath: first.path,
            downloadedBytes: 64,
            state: TransientStreamingState.active,
            createdAt: DateTime(2026, 7, 5, 1),
            lastAccessed: DateTime(2026, 7, 5, 1),
            playCount: 1,
            source: 'buguyy',
            quality: 'MP3',
          ),
        );

        now = DateTime(2026, 7, 5, 0, 0, 1);
        final second = await store.createPartFile('same');
        await second.writeAsBytes(List<int>.filled(32, 1));
        await store.upsert(
          TransientStreamingCacheEntry(
            cacheKey: 'same',
            filePath: second.path,
            downloadedBytes: 32,
            state: TransientStreamingState.active,
            createdAt: DateTime(2026, 7, 5, 2),
            lastAccessed: DateTime(2026, 7, 5, 2),
            playCount: 1,
            source: 'buguyy',
            quality: 'MP3',
          ),
        );

        expect(await first.exists(), isFalse);
        expect(await second.exists(), isTrue);
        expect(await store.list(), hasLength(1));
        expect(await root.list().where((entity) => entity is File).length, 2);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'hotlist playback uses ordinary transient stream outside downloads',
    () async {
      final resolver = _HotlistResolver(throwOnDefaultResolve: true);
      final cacheStore = _MemoryCacheStore();
      final streaming = _MemoryStreamingPlayback(cacheStore);
      final audioHandler = _HotlistAudioHandler();
      final controller = MusicController(
        audioHandler: audioHandler,
        resolver: resolver,
        cacheStore: cacheStore,
        streamingPlaybackCache: streaming,
      );
      final playlist = HotlistPlaylist(
        id: 'hotlist-qq-26',
        source: HotlistSource.qq,
        chartId: '26',
        name: '热歌榜',
        coverUrl: '',
        period: '2026-07-05',
        updatedAt: DateTime(2026, 7, 5),
        entries: [
          HotlistPlaylistEntry(
            id: 'entry-1',
            rank: 1,
            title: 'ANGEL',
            artist: '尹美莱',
            album: '',
            coverUrl: '',
            sourceTrackId: 'qq-1',
            searchQuery: 'ANGEL 尹美莱',
            addedAt: DateTime(2026, 7, 5),
          ),
        ],
        createdAt: DateTime(2026, 7, 5),
        savedAt: DateTime(2026, 7, 5),
      );

      await controller.playHotlistPlaylistEntry(
        playlist,
        playlist.entries.single,
      );

      expect(resolver.lastSource, MusicDataSource.buguyy);
      expect(resolver.resolvedCandidateId, 'angel');
      expect(resolver.lastPrefer, 'mp3');
      expect(streaming.openCount, 1);
      expect(streaming.lastResolved?.quality.label, 'MP3 128');
      expect(
        audioHandler.lastMediaItem?.duration,
        const Duration(seconds: 180),
      );
      expect(controller.downloadTasks, isEmpty);
      expect(await cacheStore.listCached(), isEmpty);
      expect(
        controller.hotlistPlaybackLogs.any(
          (log) => log.contains('not-in-download-list=true'),
        ),
        isTrue,
      );

      await streaming.close();
      controller.dispose();
    },
  );

  test('hotlist playback prefers mp3 candidate over flac candidate', () async {
    final resolver = _HotlistResolver(
      candidates: [
        _candidate(
          id: 'angel-flac',
          qualities: const [MusicQuality(format: 'flac')],
        ),
        _candidate(
          id: 'angel-mp3',
          qualities: const [
            MusicQuality(format: 'flac'),
            MusicQuality(format: 'mp3', bitrate: '128'),
          ],
        ),
      ],
      resolvedQuality: const MusicQuality(format: 'mp3', bitrate: '128'),
    );
    final cacheStore = _MemoryCacheStore();
    final streaming = _MemoryStreamingPlayback(cacheStore);
    final controller = MusicController(
      audioHandler: _HotlistAudioHandler(),
      resolver: resolver,
      cacheStore: cacheStore,
      streamingPlaybackCache: streaming,
    );
    final playlist = _playlist();

    await controller.playHotlistPlaylistEntry(
      playlist,
      playlist.entries.single,
    );

    expect(resolver.resolvedCandidateId, 'angel-mp3');
    expect(resolver.lastPrefer, 'mp3');
    expect(streaming.openCount, 1);
    expect(streaming.lastResolved?.quality.label, 'MP3 128');

    await streaming.close();
    controller.dispose();
  });

  test(
    'hotlist playback rejects flac resolved quality before streaming',
    () async {
      final resolver = _HotlistResolver(
        candidates: [
          _candidate(
            id: 'angel-mp3',
            qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
          ),
        ],
        resolvedQuality: const MusicQuality(format: 'flac'),
      );
      final cacheStore = _MemoryCacheStore();
      final streaming = _MemoryStreamingPlayback(cacheStore);
      final controller = MusicController(
        audioHandler: _HotlistAudioHandler(),
        resolver: resolver,
        cacheStore: cacheStore,
        streamingPlaybackCache: streaming,
      );
      final playlist = _playlist();

      await controller.playHotlistPlaylistEntry(
        playlist,
        playlist.entries.single,
      );

      expect(streaming.openCount, 0);
      expect(
        controller.hotlistPlaybackLogs.any(
          (log) => log.contains('play-failed'),
        ),
        isTrue,
      );
      expect(await cacheStore.listCached(), isEmpty);

      await streaming.close();
      controller.dispose();
    },
  );

  test(
    'hotlist playback falls back when preferred candidate resolves flac',
    () async {
      final resolver = _HotlistResolver(
        candidates: [
          _candidate(
            id: 'angel-flac-after-prefer',
            qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
          ),
          _candidate(
            id: 'angel-mp3-fallback',
            qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
          ),
        ],
        resolvedQualities: const {
          'angel-flac-after-prefer': MusicQuality(format: 'flac'),
          'angel-mp3-fallback': MusicQuality(format: 'mp3', bitrate: '128'),
        },
      );
      final cacheStore = _MemoryCacheStore();
      final streaming = _MemoryStreamingPlayback(cacheStore);
      final controller = MusicController(
        audioHandler: _HotlistAudioHandler(),
        resolver: resolver,
        cacheStore: cacheStore,
        streamingPlaybackCache: streaming,
      );
      final playlist = _playlist();

      await controller.playHotlistPlaylistEntry(
        playlist,
        playlist.entries.single,
      );

      expect(resolver.resolvedCandidateIds, [
        'angel-flac-after-prefer',
        'angel-mp3-fallback',
      ]);
      expect(resolver.lastPrefer, 'mp3');
      expect(streaming.openCount, 1);
      expect(streaming.lastResolved?.id, 'angel-mp3-fallback');
      expect(streaming.lastResolved?.quality.label, 'MP3 128');

      await streaming.close();
      controller.dispose();
    },
  );
}

HotlistChart _chart() {
  return HotlistChart(
    source: HotlistSource.qq,
    chartId: '26',
    title: '热歌榜',
    description: '',
    coverUrl: '',
    period: '2026-07-05',
    updatedAt: DateTime(2026, 7, 5),
    items: const [
      HotlistItem(
        rank: 1,
        title: 'A Song',
        artist: 'Singer A',
        album: '',
        coverUrl: '',
        sourceTrackId: 'a',
        durationMs: 1000,
        rankChange: '',
      ),
      HotlistItem(
        rank: 2,
        title: 'B Song',
        artist: 'Singer B',
        album: '',
        coverUrl: '',
        sourceTrackId: 'b',
        durationMs: 1000,
        rankChange: '',
      ),
      HotlistItem(
        rank: 3,
        title: 'C Song',
        artist: 'Singer C',
        album: '',
        coverUrl: '',
        sourceTrackId: 'c',
        durationMs: 1000,
        rankChange: '',
      ),
    ],
  );
}

HotlistChart _updatedChart() {
  return HotlistChart(
    source: HotlistSource.qq,
    chartId: '26',
    title: '热歌榜',
    description: '',
    coverUrl: '',
    period: '2026-07-06',
    updatedAt: DateTime(2026, 7, 6),
    items: const [
      HotlistItem(
        rank: 1,
        title: 'B Song Live',
        artist: 'Singer B',
        album: '',
        coverUrl: 'https://example.com/b.jpg',
        sourceTrackId: 'b',
        durationMs: 1000,
        rankChange: 'up',
      ),
      HotlistItem(
        rank: 2,
        title: 'A Song',
        artist: 'Singer A',
        album: '',
        coverUrl: '',
        sourceTrackId: 'a',
        durationMs: 1000,
        rankChange: 'down',
      ),
      HotlistItem(
        rank: 3,
        title: 'D Song',
        artist: 'Singer D',
        album: '',
        coverUrl: '',
        sourceTrackId: 'd',
        durationMs: 1000,
        rankChange: 'new',
      ),
    ],
  );
}

HotlistPlaylist _playlist() {
  return HotlistPlaylist(
    id: 'hotlist-qq-26',
    source: HotlistSource.qq,
    chartId: '26',
    name: '热歌榜',
    coverUrl: '',
    period: '2026-07-05',
    updatedAt: DateTime(2026, 7, 5),
    entries: [
      HotlistPlaylistEntry(
        id: 'entry-1',
        rank: 1,
        title: 'ANGEL',
        artist: '尹美莱',
        album: '',
        coverUrl: '',
        sourceTrackId: 'qq-1',
        searchQuery: 'ANGEL 尹美莱',
        addedAt: DateTime(2026, 7, 5),
      ),
    ],
    createdAt: DateTime(2026, 7, 5),
    savedAt: DateTime(2026, 7, 5),
  );
}

MusicSearchCandidate _candidate({
  required String id,
  required List<MusicQuality> qualities,
}) {
  return MusicSearchCandidate(
    query: 'ANGEL 尹美莱',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    keyword: 'ANGEL 尹美莱',
    page: 1,
    id: id,
    name: 'ANGEL',
    artist: '尹美莱',
    album: '',
    duration: 180,
    link: '',
    coverUrl: '',
    qualities: qualities,
    score: 100,
    raw: const {},
  );
}

class _HotlistResolver implements MusicResolver, PreferredMusicResolver {
  _HotlistResolver({
    List<MusicSearchCandidate>? candidates,
    this.resolvedQuality = const MusicQuality(format: 'mp3', bitrate: '128'),
    this.resolvedQualities = const {},
    this.throwOnDefaultResolve = false,
  }) : _candidates =
           candidates ??
           [
             _candidate(
               id: 'angel',
               qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
             ),
           ];

  final List<MusicSearchCandidate> _candidates;
  final MusicQuality resolvedQuality;
  final Map<String, MusicQuality> resolvedQualities;
  final bool throwOnDefaultResolve;
  MusicDataSource? lastSource;
  String? resolvedCandidateId;
  final resolvedCandidateIds = <String>[];
  String? lastPrefer;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    lastSource = source;
    return _candidates;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    if (throwOnDefaultResolve) {
      throw StateError('default resolve unavailable');
    }
    return resolveWithPrefer(candidate, prefer: 'default');
  }

  @override
  Future<ResolvedMusic> resolveWithPrefer(
    MusicSearchCandidate candidate, {
    required String prefer,
  }) async {
    resolvedCandidateId = candidate.id;
    resolvedCandidateIds.add(candidate.id);
    lastPrefer = prefer;
    return ResolvedMusic(
      query: candidate.query,
      source: MusicDataSource.buguyy,
      platform: 'buguyy',
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: '',
      url: 'http://127.0.0.1/angel.mp3',
      quality: resolvedQualities[candidate.id] ?? resolvedQuality,
      duration: candidate.duration,
    );
  }
}

class _MemoryStreamingPlayback implements HotlistStreamingPlayback {
  _MemoryStreamingPlayback(this.cacheStore);

  final CachedTrackStore cacheStore;
  final _caches = <ProgressiveAudioCache>[];
  int openCount = 0;
  ResolvedMusic? lastResolved;

  @override
  Future<StreamingPlaybackHandle> openHotlistTrack(
    ResolvedMusic resolved,
    StreamingPlaybackPolicy policy,
  ) async {
    openCount += 1;
    lastResolved = resolved;
    final cache = ProgressiveAudioCache(cacheStore: cacheStore);
    _caches.add(cache);
    final session = await cache.open(resolved);
    return StreamingPlaybackHandle(
      proxyUri: session.proxyUri,
      session: session,
    );
  }

  @override
  Future<void> close() async {
    for (final cache in _caches) {
      await cache.close();
    }
    _caches.clear();
  }
}

class _MemoryCacheStore extends CachedTrackStore {
  @override
  Future<List<CachedTrack>> listCached() async => const [];
}

class _HotlistAudioHandler extends MusicAudioHandler {
  MediaItem? lastMediaItem;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    lastMediaItem = items[initialIndex].mediaItem;
    mediaItem.add(lastMediaItem);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}
}
