import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/music_mappers.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/song_search_cache.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/playback_queue.dart';
import 'package:ai_music/src/presentation/player_page.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_download_history.dart';

void main() {
  const scenarios = [
    (
      name: '320dp Chinese with long metadata and 2x text',
      size: Size(320, 700),
      scale: 2.0,
      language: AppLanguage.zh,
      brightness: Brightness.light,
      firstScreen: false,
    ),
    (
      name: '320dp English with long metadata and 2x text',
      size: Size(320, 700),
      scale: 2.0,
      language: AppLanguage.en,
      brightness: Brightness.light,
      firstScreen: false,
    ),
    (
      name: 'short landscape English',
      size: Size(740, 320),
      scale: 1.0,
      language: AppLanguage.en,
      brightness: Brightness.light,
      firstScreen: false,
    ),
    (
      name: 'narrow English dark theme',
      size: Size(320, 640),
      scale: 1.3,
      language: AppLanguage.en,
      brightness: Brightness.dark,
      firstScreen: false,
    ),
    (
      name: 'normal phone keeps controls and both actions on the first screen',
      size: Size(393, 851),
      scale: 1.0,
      language: AppLanguage.zh,
      brightness: Brightness.light,
      firstScreen: true,
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('player layout: ${scenario.name}', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cached = _cachedTrack(scenario.language);
      final handler = _LayoutAudioHandler();
      final controller = MusicController(
        audioHandler: handler,
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        resolver: _LayoutResolver(),
        cacheStore: _LayoutCacheStore(cached),
        playlistStore: _LayoutPlaylistStore(cached.cacheId),
        settingsStore: _LayoutSettingsStore(scenario.language),
        metadataRepository: _LayoutMetadataRepository(),
      );
      final strings = AppStrings(scenario.language);
      try {
        await controller.initialize();
        final item = mediaItemFromTrack(
          trackFromCached(cached),
        ).copyWith(duration: const Duration(minutes: 4, seconds: 15));
        handler.queue.add([item]);
        handler.mediaItem.add(item);
        await controller.loadMetadataForCurrentTrack();
        await tester.pumpWidget(
          AppStringsScope(
            language: scenario.language,
            child: MaterialApp(
              theme: MusicAppTheme.create(scenario.brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scenario.scale),
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                ),
                child: child!,
              ),
              home: PlayerPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(item.title), findsOneWidget);
        expect(find.text(item.artist!), findsOneWidget);
        expect(
          find.byKey(const ValueKey('player-switch-source')).hitTestable(),
          findsOneWidget,
        );

        final player = find.byKey(const ValueKey('player-swipe-area'));
        final scrollable = find
            .descendant(of: player, matching: find.byType(Scrollable))
            .first;
        final lyrics = find.byKey(const ValueKey('lyrics-preview'));
        final position = find.byKey(ValueKey('player-position-${item.id}'));
        final comments = find.byKey(const ValueKey('player-comments'));
        final queue = find.byKey(const ValueKey('playback-queue'));
        final controls = [
          find.byTooltip(strings.previous),
          find.byTooltip(strings.play),
          find.byTooltip(strings.next),
          find.byKey(const ValueKey('playback-queue')),
        ];

        if (scenario.firstScreen) {
          // Do not scroll before these checks: finding a widget alone does not
          // establish that its control is reachable in the initial viewport.
          for (final target in [
            lyrics,
            position,
            ...controls,
            comments,
            queue,
          ]) {
            expect(target.hitTestable(), findsOneWidget);
            final rect = tester.getRect(target);
            expect(rect.top, greaterThanOrEqualTo(24));
            expect(rect.bottom, lessThanOrEqualTo(scenario.size.height - 24));
          }
        }

        Future<void> reach(Finder target) async {
          if (target.hitTestable().evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              target,
              120,
              scrollable: scrollable,
            );
          }
          await tester.pumpAndSettle();
          expect(target.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        // Only song content scrolls. Transport stays at the safe-area bottom
        // even on short screens, with large text and after scrolling lyrics.
        final controlsBefore = tester.getRect(queue);
        for (final control in [position, ...controls]) {
          expect(control.hitTestable(), findsOneWidget);
        }
        expect(
          controlsBefore.bottom,
          greaterThan(scenario.size.height - 24 - 80),
        );
        final favorite = find.byKey(const Key('player-favorite'));
        if (scenario.size.width < 680) {
          expect(favorite.hitTestable(), findsOneWidget);
          expect(comments.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(favorite).bottom,
            lessThan(tester.getRect(position).top),
          );
          expect(
            tester.getRect(comments).center.dy,
            tester.getRect(favorite).center.dy,
          );
          expect(
            tester.getRect(comments).left,
            greaterThan(tester.getRect(favorite).right),
          );
        }
        expect(
          find.descendant(of: find.byType(AppBar), matching: comments),
          findsNothing,
        );
        expect(
          find.descendant(of: find.byType(AppBar), matching: favorite),
          findsNothing,
        );
        await reach(lyrics);
        await reach(position);
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
        await reach(find.byTooltip(strings.play));
        for (final control in controls) {
          expect(control.hitTestable(), findsOneWidget);
        }
        await tester.tap(find.byTooltip(strings.play));
        await tester.pumpAndSettle();
        expect(handler.playCalls, 1);
        expect(find.byTooltip(strings.pause).hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip(strings.pause));
        await tester.pumpAndSettle();
        expect(handler.pauseCalls, 1);

        await reach(comments);
        expect(tester.widget<IconButton>(comments).onPressed, isNotNull);
        expect(tester.getRect(queue), controlsBefore);
        await reach(queue);
        await tester.tap(queue);
        await tester.pumpAndSettle();
        expect(find.byType(PlaybackQueue), findsOneWidget);
        expect(find.byKey(ValueKey('queue-item-${item.id}')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(PlaybackQueue), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(handler.dispose);
      }
    });
  }
}

class _LayoutAudioHandler extends MusicAudioHandler {
  final positions = StreamController<Duration>.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Future<void> play() async {
    playCalls++;
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  @override
  Future<void> dispose() async {
    await positions.close();
    unawaited(super.dispose());
  }
}

class _LayoutMetadataRepository extends TrackMetadataRepository {
  static const metadata = TrackMetadata(
    lyrics: [
      LyricLine(time: Duration.zero, text: '那些一起听歌的日子，还留在熟悉的旋律里'),
      LyricLine(
        time: Duration(seconds: 20),
        text: 'The familiar melody brings back all those evenings together',
      ),
      LyricLine(time: Duration(seconds: 40), text: '下一段旅途，我们继续听歌'),
    ],
  );

  @override
  Future<TrackMetadata> load(CachedTrack track) async => metadata;

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) async => metadata;
}

class _LayoutCacheStore extends CachedTrackStore {
  _LayoutCacheStore(this.cached);
  final CachedTrack cached;

  @override
  Future<Map<String, ({int bytes, int? total})>> partialProgress() async => {};

  @override
  Future<List<CachedTrack>> listCached() async => [cached];

  @override
  Future<void> cleanupTemporaryFiles() async {}
}

class _LayoutPlaylistStore extends PlaylistStore {
  _LayoutPlaylistStore(this.trackId) : super(rootProvider: _unusedRootProvider);
  final String trackId;

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async =>
      PlaylistLibrary(
        favoriteEntries: [
          PlaylistTrackEntry(trackId: trackId, addedAt: DateTime(2026)),
        ],
        playlists: const [],
      );

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {}
}

class _LayoutSettingsStore implements MusicSettingsStore {
  _LayoutSettingsStore(this.language);
  final AppLanguage language;

  @override
  Future<MusicAppSettings> loadSettings() async =>
      MusicAppSettings(language: language);

  @override
  Future<void> saveSettings(MusicAppSettings settings) async {}

  @override
  Future<MusicDataSource> loadSource() async => MusicDataSource.flac;

  @override
  Future<void> saveSource(MusicDataSource source) async {}
}

class _LayoutResolver implements MusicResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async => const [];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async =>
      throw UnsupportedError('Layout tests must not resolve network audio');
}

CachedTrack _cachedTrack(AppLanguage language) {
  final title = language == AppLanguage.zh
      ? '回忆观影券（伴奏）与那些一起听歌的日子，还有未说完的故事'
      : 'A Very Long Song Title (Instrumental Version) About All Those '
            'Unforgettable Evenings Together';
  final artist = language == AppLanguage.zh
      ? '张天一 / 王忻辰 / 那些来自不同城市的老朋友'
      : 'An Artist with a Very Long Name / Another Featured Artist';
  final music = ResolvedMusic(
    query: '$title $artist',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'layout-song',
    name: title,
    artist: artist,
    album: 'A long album title for player layout checks',
    url: 'https://cdn.example.test/layout-song.mp3',
    quality: const MusicQuality(format: 'mp3'),
  );
  return CachedTrack(
    cacheId: cacheIdForResolved(music),
    music: music,
    filePath: '/tmp/player-layout-song.mp3',
    sizeBytes: 1024,
    fromCache: true,
  );
}

Future<Directory> _unusedRootProvider() async =>
    throw UnsupportedError('Layout test playlists stay in memory');
