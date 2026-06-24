import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/music_mappers.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/player_page.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lyric follow state only follows when index or target changes', () {
    final state = LyricFollowState();

    expect(state.shouldFollow(1, 48), isTrue);
    expect(state.shouldFollow(1, 48), isFalse);
    expect(state.shouldFollow(1, 48.4), isFalse);
    expect(state.shouldFollow(2, 96), isTrue);

    state.reset();
    expect(state.shouldFollow(2, 96), isTrue);
  });

  testWidgets('lyrics scroll does not seek but tapping a line seeks', (
    tester,
  ) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(
        metadata: const TrackMetadata(
          lyrics: [
            LyricLine(time: Duration(seconds: 1), text: '第一句'),
            LyricLine(time: Duration(seconds: 20), text: '第二句'),
            LyricLine(time: Duration(seconds: 40), text: '第三句'),
            LyricLine(time: Duration(seconds: 60), text: '第四句'),
          ],
        ),
      ),
    );

    try {
      await controller.initialize();
      final track = trackFromCached(cached);
      await controller.playTrack(track);
      handler.emit(mediaItemFromTrack(track));
      await controller.loadMetadataForCurrentTrack();
      expect(
        controller.currentLyrics.map((line) => line.text),
        contains('第二句'),
      );

      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: SizedBox(
                height: 360,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => LyricsPanelForTesting(
                    controller: controller,
                    positionStream: Stream<Duration>.value(Duration.zero),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('第三句'), findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, -96));
      await tester.pump(const Duration(milliseconds: 100));

      expect(handler.seekedPositions, isEmpty);

      await tester.tap(find.text('第二句'));
      await tester.pump();

      expect(handler.seekedPositions, [const Duration(seconds: 20)]);
      await tester.pump(const Duration(seconds: 2));
    } finally {
      controller.dispose();
    }
  });

  testWidgets('missing lyrics panel can retry metadata recovery', (
    tester,
  ) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final metadata = _RetryMetadataRepository();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _LyricsResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      final track = trackFromCached(cached);
      await controller.playTrack(track);
      handler.emit(mediaItemFromTrack(track));
      await controller.loadMetadataForCurrentTrack();

      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: SizedBox(
                height: 360,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => LyricsPanelForTesting(
                    controller: controller,
                    positionStream: Stream<Duration>.value(Duration.zero),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('暂无歌词'), findsOneWidget);
      expect(find.text('重新获取歌词'), findsOneWidget);

      await tester.tap(find.text('重新获取歌词'));
      await tester.pumpAndSettle();

      expect(metadata.bypassLoadCount, 1);
      expect(find.text('手动补齐'), findsOneWidget);
    } finally {
      controller.dispose();
    }
  });

  testWidgets('player page swipe skips next and previous', (tester) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(
        metadata: const TrackMetadata(),
      ),
    );

    try {
      await controller.initialize();
      final track = trackFromCached(cached);
      await controller.playTrack(track);
      handler.emit(mediaItemFromTrack(track));

      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: PlayerPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final swipeArea = find.byKey(const ValueKey('player-page-swipe-area'));
      expect(swipeArea, findsOneWidget);

      await tester.drag(swipeArea, const Offset(-180, 0));
      await tester.pump();
      expect(handler.skipNextCalls, 1);
      expect(handler.skipPreviousCalls, 0);

      await tester.drag(swipeArea, const Offset(180, 0));
      await tester.pump();
      expect(handler.skipNextCalls, 1);
      expect(handler.skipPreviousCalls, 1);
    } finally {
      controller.dispose();
    }
  });

  testWidgets('player page slider drag does not skip tracks', (tester) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(
        metadata: const TrackMetadata(),
      ),
    );

    try {
      await controller.initialize();
      final track = trackFromCached(cached);
      await controller.playTrack(track);
      handler.emit(
        mediaItemFromTrack(
          track,
        ).copyWith(duration: const Duration(minutes: 3)),
      );

      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: PlayerPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byType(Slider),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();
      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pump();

      expect(handler.skipNextCalls, 0);
      expect(handler.skipPreviousCalls, 0);
    } finally {
      controller.dispose();
    }
  });
}

class _SpyAudioHandler extends MusicAudioHandler {
  final seekedPositions = <Duration>[];
  int skipNextCalls = 0;
  int skipPreviousCalls = 0;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex].mediaItem);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    seekedPositions.add(position);
  }

  @override
  Future<void> skipToNext() async {
    skipNextCalls += 1;
  }

  @override
  Future<void> skipToPrevious() async {
    skipPreviousCalls += 1;
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  @override
  Future<void> restoreCurrentItemPosition(
    String mediaId,
    Duration position,
  ) async {}

  void emit(MediaItem item) {
    mediaItem.add(item);
  }
}

class _StaticMetadataRepository extends TrackMetadataRepository {
  _StaticMetadataRepository({required this.metadata});

  final TrackMetadata metadata;

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    return metadata;
  }
}

class _RetryMetadataRepository extends TrackMetadataRepository {
  int bypassLoadCount = 0;

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    return const TrackMetadata();
  }

  @override
  Future<TrackMetadata> loadBypassingMetadataMiss(CachedTrack track) async {
    bypassLoadCount += 1;
    return const TrackMetadata(
      lyrics: [LyricLine(time: Duration(seconds: 1), text: '手动补齐')],
    );
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
  Future<CachedTrack> updateCachedMusic(
    CachedTrack cachedTrack,
    ResolvedMusic music,
  ) async {
    final index = cached.indexWhere(
      (track) => track.cacheId == cachedTrack.cacheId,
    );
    final updated = cachedTrack.copyWith(music: music);
    if (index == -1) {
      cached.add(updated);
    } else {
      cached[index] = updated;
    }
    return updated;
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

class _LyricsResolver extends _FakeMusicResolver {
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
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
        text: '[00:01.00]手动补齐',
        lines: 1,
        timed: true,
      ),
    );
  }
}

CachedTrack _cachedTrack() {
  final music = ResolvedMusic(
    query: '测试歌',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'song-1',
    name: '测试歌',
    artist: '测试歌手',
    album: '',
    url: 'https://cdn.example.test/song-1.mp3',
    quality: const MusicQuality(format: 'mp3'),
  );
  return CachedTrack(
    cacheId: cacheIdForResolved(music),
    music: music,
    filePath: '/tmp/song-1.mp3',
    sizeBytes: 1024,
    fromCache: true,
  );
}

Future<Directory> _unusedRootProvider() async {
  return Directory.systemTemp.createTemp('ai_music_unused_');
}
