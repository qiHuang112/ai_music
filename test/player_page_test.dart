import 'package:ai_music/src/presentation/desktop_music_shell.dart';
import 'package:ai_music/src/presentation/desktop_mini_player.dart';
import 'package:ai_music/src/presentation/desktop_scope.dart';
import 'package:ai_music/src/presentation/desktop_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/design/turntable.dart';
import 'package:ai_music/src/data/song_search_cache.dart';
import 'memory_download_history.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui'
    show
        PictureRecorder,
        Canvas,
        ImageByteFormat,
        DisplayFeature,
        DisplayFeatureType,
        DisplayFeatureState;

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
import 'package:ai_music/src/presentation/mini_player.dart';
import 'package:ai_music/src/presentation/playback_queue.dart';
import 'package:ai_music/src/presentation/song_comments_page.dart';
import 'package:ai_music/src/presentation/song_cache_progress.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_music/src/presentation/design/app_icons.dart';

void main() {
  testWidgets(
    'foldable window resizes preserve playback and keep lyrics controls reachable',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      MusicMotion.perpetual = false;
      addTearDown(() => MusicMotion.perpetual = true);
      final textScale = ValueNotifier(1.0);
      final folds = ValueNotifier<List<DisplayFeature>>([]);
      addTearDown(folds.dispose);
      addTearDown(textScale.dispose);
      tester.view.physicalSize = const Size(390, 844);
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(
          metadata: TrackMetadata(
            lyricsStatus: LyricsStatus.available,
            lyrics: List.generate(
              30,
              (i) => LyricLine(
                time: Duration(seconds: i * 5),
                text: '歌词第 $i 句',
              ),
            ),
          ),
        ),
      );
      try {
        await controller.initialize();
        await controller.playTrack(trackFromCached(cached));
        handler.position = const Duration(seconds: 25);
        handler.playbackState.add(PlaybackState(playing: true));
        await tester.pumpWidget(
          AppStringsScope(
            language: AppLanguage.zh,
            child: MaterialApp(
              theme: MusicAppTheme.create(Brightness.light),
              builder: (context, child) => ValueListenableBuilder<double>(
                valueListenable: textScale,
                builder: (context, scale, _) =>
                    ValueListenableBuilder<List<DisplayFeature>>(
                      valueListenable: folds,
                      builder: (context, features, _) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          displayFeatures: features,
                        ),
                        child: child!,
                      ),
                    ),
              ),
              home: PlayerPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final routeState = tester.state(find.byType(PlayerPage));
        final queueLoads = handler.queueLoads;
        final itemId = handler.mediaItem.value!.id;
        final queueIds = handler.queue.value.map((item) => item.id).toList();
        final seeks = List<Duration>.of(handler.seekedPositions);
        final playCalls = handler.playCalls;
        final expanded = find.byKey(const ValueKey('player-expanded-layout'));
        for (final scenario in [
          (size: const Size(930, 650), scale: 1.0, wide: true),
          (size: const Size(700, 900), scale: 1.0, wide: false),
          (size: const Size(1100, 650), scale: 1.6, wide: true),
          (size: const Size(740, 320), scale: 1.0, wide: false),
          (size: const Size(390, 844), scale: 1.0, wide: false),
        ]) {
          tester.view.physicalSize = scenario.size;
          tester.view.padding = const FakeViewPadding(
            left: 12,
            top: 24,
            right: 76,
            bottom: 20,
          );
          textScale.value = scenario.scale;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(expanded, scenario.wide ? findsOneWidget : findsNothing);
          expect(tester.state(find.byType(PlayerPage)), same(routeState));
          expect(handler.queueLoads, queueLoads);
          expect(handler.mediaItem.value!.id, itemId);
          expect(handler.queue.value.map((item) => item.id), queueIds);
          expect(handler.currentPosition, const Duration(seconds: 25));
          expect(handler.seekedPositions, seeks);
          expect(handler.playCalls, playCalls);
          expect(handler.playbackState.value.playing, isTrue);
          if (scenario.wide) {
            final lyrics = tester.getRect(
              find.byKey(const ValueKey('player-expanded-lyrics')),
            );
            expect(
              lyrics.left,
              greaterThan(tester.getRect(find.byType(Turntable)).right),
            );
            expect(lyrics.right, lessThanOrEqualTo(scenario.size.width - 76));
            expect(lyrics.bottom, lessThanOrEqualTo(scenario.size.height - 20));
            expect(find.byKey(const ValueKey('lyrics-preview')), findsNothing);
          }
          final pause = find.byTooltip('暂停');
          final scrollable = find
              .descendant(
                of: find.byKey(
                  PageStorageKey(
                    scenario.wide
                        ? 'player-expanded-scroll'
                        : 'player-compact-scroll',
                  ),
                ),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(pause, 160, scrollable: scrollable);
          await tester.pumpAndSettle();
          expect(pause.hitTestable(), findsOneWidget);
        }
        for (final pose in [
          (
            size: const Size(930, 650),
            fold: const Rect.fromLTWH(450, 0, 28, 650),
            horizontal: false,
          ),
          (
            size: const Size(650, 900),
            fold: const Rect.fromLTWH(0, 430, 650, 28),
            horizontal: true,
          ),
        ]) {
          tester.view.physicalSize = pose.size;
          folds.value = [
            DisplayFeature(
              bounds: pose.fold,
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ];
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('player-fold-layout')),
            findsOneWidget,
          );
          final deck = tester.getRect(
            find.byKey(const PageStorageKey('player-expanded-scroll')),
          );
          final details = tester.getRect(
            find.byKey(const ValueKey('player-expanded-lyrics')),
          );
          if (pose.horizontal) {
            expect(details.bottom, lessThanOrEqualTo(pose.fold.top));
            expect(deck.top, greaterThanOrEqualTo(pose.fold.bottom));
          } else {
            expect(deck.right, lessThanOrEqualTo(pose.fold.left));
            expect(details.left, greaterThanOrEqualTo(pose.fold.right));
          }
          await tester.tap(find.text('待播'));
          await tester.pumpAndSettle();
          expect(find.byType(PlaybackQueue), findsOneWidget);
          expect(
            tester.widget<PlaybackQueue>(find.byType(PlaybackQueue)).embedded,
            isTrue,
          );
          expect(find.byTooltip('Close'), findsNothing);
          await tester.tap(find.text('歌词'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.state(find.byType(PlayerPage)), same(routeState));
          expect(handler.queueLoads, queueLoads);
          expect(handler.currentPosition, const Duration(seconds: 25));
          expect(handler.playCalls, playCalls);
        }
        folds.value = [];
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byTooltip('暂停'),
          160,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('player-compact-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.byTooltip('暂停'));
        await tester.pumpAndSettle();
        expect(handler.playbackState.value.playing, isFalse);
        final preview = find.byKey(const ValueKey('lyrics-preview'));
        await tester.scrollUntilVisible(
          preview,
          -160,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('player-compact-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(preview);
        await tester.pumpAndSettle();
        // A pinned video / split window can reduce height while this route is
        // already open. Large type must not push controls into an overflow.
        tester.view.physicalSize = const Size(390, 260);
        textScale.value = 2.0;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final play = find.byTooltip('播放');
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        expect(play.hitTestable(), findsOneWidget);
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(handler.playbackState.value.playing, isTrue);
        expect(handler.queueLoads, queueLoads);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await handler.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'desktop shell keeps controls, compact panel and input shortcuts independent',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(1100, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      MusicMotion.perpetual = false;
      addTearDown(() => MusicMotion.perpetual = true);
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(
          metadata: const TrackMetadata(lyricsStatus: LyricsStatus.notFound),
        ),
      );
      await controller.initialize();
      await controller.playTrack(
        trackFromCached(cached),
        playlistId: favoritePlaylistId,
      );
      handler.playbackState.add(PlaybackState(playing: false));
      final field = FocusNode();
      final shell = GlobalKey<DesktopMusicShellState>();
      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: MusicAppTheme.create(Brightness.dark),
            home: DesktopMusicShell(
              key: shell,
              controller: controller,
              persistWindowState: false,
              home: Scaffold(
                body: Column(
                  children: [
                    TextField(
                      key: const Key('desktop-input'),
                      focusNode: field,
                    ),
                    MiniPlayer(controller: controller),
                  ],
                ),
              ),
              library: const Scaffold(body: Text('library page')),
              downloads: const Scaffold(body: Text('downloads page')),
              settings: const Scaffold(body: Text('settings page')),
              playlistBuilder: (_) =>
                  const Scaffold(body: Text('origin playlist')),
              focusSearch: field.requestFocus,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mini-player-card')), findsNothing);
      expect(find.byType(DesktopPlaybackBar), findsOneWidget);
      expect(find.bySemanticsLabel('首页'), findsOneWidget);
      final bar = tester.getRect(find.byType(DesktopPlaybackBar));
      await tester.tap(find.byTooltip('队列'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopPlaybackQueue), findsOneWidget);
      expect(tester.getRect(find.byType(DesktopPlaybackBar)), bar);
      await tester.binding.setSurfaceSize(const Size(760, 600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('收起面板'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('desktop-input')));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(handler.playbackState.value.playing, isFalse);
      field.unfocus();
      shell.currentState!.selectSection('library');
      await tester.pumpAndSettle();
      expect(find.text('library page'), findsOneWidget);
      expect(find.byType(DesktopPlaybackBar), findsOneWidget);
      await tester.tap(find.text('来自：我的收藏'));
      await tester.pumpAndSettle();
      expect(find.text('origin playlist'), findsOneWidget);
      final scope = DesktopMusicScope.maybeOf(
        tester.element(find.byType(DesktopPlaybackBar)),
      )!;
      scope.openPlayer();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopNowPlaying), findsOneWidget);
      expect(tester.takeException(), isNull);
      // ⌘[ goes back out of the player, as Esc does.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopNowPlaying), findsNothing);
      scope.openPlayer();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopNowPlaying), findsNothing);
      // The sidebar's search row focuses the home search.
      await tester.tap(find.byKey(const ValueKey('desktop-sidebar-search')));
      await tester.pumpAndSettle();
      expect(field.hasFocus, isTrue);
      field.unfocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(field.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);
      expect(field.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(handler.playbackState.value.playing, isTrue);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      field.dispose();
      controller.dispose();
      await handler.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'mini player strip shows the song, and the controls under the pointer',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(
          metadata: const TrackMetadata(lyricsStatus: LyricsStatus.notFound),
        ),
      );
      await controller.initialize();
      await controller.playTrack(trackFromCached(cached));
      handler.playbackState.add(PlaybackState(playing: false));
      var lyrics = 0, expand = 0, shape = 0;
      Offset? menu;
      Widget mini(Size size) => AppStringsScope(
        language: AppLanguage.zh,
        child: MaterialApp(
          theme: MusicAppTheme.create(Brightness.dark),
          home: Center(
            child: SizedBox.fromSize(
              size: size,
              child: DesktopMiniPlayer(
                controller: controller,
                lyrics: true,
                onLyricsButton: () => lyrics++,
                onToggleShape: () => shape++,
                onExpand: () => expand++,
                onMenu: (at) => menu = at,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(mini(DesktopWindow.miniStrip));
      await tester.pump();
      expect(find.text('测试歌'), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-transport')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(DesktopMiniPlayer)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mini-transport')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mini-play')));
      await tester.pump();
      expect(handler.playbackState.value.playing, isTrue);
      await tester.tap(find.byKey(const ValueKey('mini-lyrics')));
      await tester.tap(find.byKey(const ValueKey('mini-expand')));
      // The cover folds and unfolds the player, as NetEase's does.
      await tester.tap(find.byKey(const ValueKey('mini-cover')));
      expect((lyrics, expand, shape), (1, 1, 1));
      // A right click opens the song's menu where it was clicked.
      final at = tester.getCenter(find.byType(DesktopMiniPlayer));
      await tester.tapAt(at, buttons: kSecondaryButton);
      expect(menu, at);

      // The square keeps its bars hidden until the pointer comes in.
      await mouse.moveTo(Offset.zero);
      await tester.pumpWidget(mini(DesktopWindow.miniSquare));
      await tester.pumpAndSettle();
      expect(find.text('暂无歌词'), findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.byType(DesktopMiniPlayer)));
      await tester.pumpAndSettle();
      menu = null;
      await tester.tap(find.byKey(const ValueKey('mini-more')));
      expect(menu, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await handler.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('desktop song selection does not play and double click does', (
    tester,
  ) async {
    final selection = ValueNotifier<String?>(null);
    final locate = ValueNotifier<({String id, int revision})?>(null);
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopMusicScope(
          selection: selection,
          locate: locate,
          openPlayer: () {},
          openDetail: (_) {},
          child: Scaffold(
            body: DesktopSongInteraction(
              id: 'song',
              onPlay: () => plays++,
              builder: (tap, selected) => ListTile(
                title: const Text('song row'),
                selected: selected,
                onTap: tap,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('song row'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection.value, 'song');
    expect(plays, 0);
    await tester.tap(find.text('song row'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('song row'));
    await tester.pumpAndSettle();
    expect(plays, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    selection.dispose();
    locate.dispose();
  });

  testWidgets('restored playback uses the normal paused UI until play', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(
        metadata: const TrackMetadata(lyricsStatus: LyricsStatus.notFound),
      ),
    );
    try {
      await controller.initialize();
      await controller.playTrack(
        trackFromCached(cached),
        playlistId: favoritePlaylistId,
      );
      handler.awaiting = true;
      handler.playbackState.add(PlaybackState(playing: false));
      Widget app(Widget child) => AppStringsScope(
        language: AppLanguage.zh,
        child: MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 1000),
              textScaler: TextScaler.linear(1.6),
            ),
            child: child,
          ),
        ),
      );
      await tester.pumpWidget(
        app(Scaffold(body: MiniPlayer(controller: controller))),
      );
      await tester.pump();
      expect(find.textContaining('待播放'), findsNothing);
      final miniRect = tester.getRect(
        find.byKey(const ValueKey('mini-player-card')),
      );
      handler.awaiting = false;
      handler.playbackState.add(PlaybackState(playing: false));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('mini-player-card'))),
        miniRect,
      );
      handler.awaiting = true;
      expect(handler.playbackState.value.playing, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(PlayerPage(controller: controller)));
      await tester.pump();
      expect(find.textContaining('待播放'), findsNothing);
      expect(find.text('正在播放'), findsOneWidget);
      await tester.tap(find.byTooltip('当前队列'));
      await tester.pumpAndSettle();
      expect(find.text('当前队列 · 1'), findsOneWidget);
      expect(find.textContaining('待播放'), findsNothing);
      Navigator.of(tester.element(find.byType(PlaybackQueue))).pop();
      await tester.pumpAndSettle();
      expect(handler.playbackState.value.playing, isFalse);
      expect(tester.takeException(), isNull);
      await controller.play();
      await tester.pump();
      expect(find.textContaining('待播放'), findsNothing);
      expect(handler.playbackState.value.playing, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await handler.dispose();
    }
  });

  testWidgets(
    'opening timed lyrics starts at the current line on the first frame',
    (tester) async {
      final cached = _cachedTrack();
      final handler = _SpyAudioHandler()
        ..position = const Duration(seconds: 150);
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(
          metadata: TrackMetadata(
            lyrics: [
              for (var i = 0; i < 30; i++)
                LyricLine(
                  time: Duration(seconds: i * 10),
                  text: '歌词$i',
                ),
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
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 360,
                child: LyricsPanelForTesting(controller: controller),
              ),
            ),
          ),
        );
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        expect(scroll.position.pixels, 15 * 48);
        await tester.pump(const Duration(milliseconds: 300));
        expect(scroll.position.pixels, 15 * 48);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  for (final status in [
    LyricsStatus.available,
    LyricsStatus.notFound,
    LyricsStatus.failed,
    LyricsStatus.unknown,
  ]) {
    testWidgets(
      'lyrics $status keeps player layout stable and same-track work shared',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cached = _cachedTrack();
        final handler = _SpyAudioHandler();
        final metadata = _DeferredMetadataRepository();
        final controller = MusicController(
          songSearchCache: SongSearchCache.memory(),
          downloadHistoryStore: MemoryDownloadHistory(),
          connectivityChanges: const Stream.empty(),
          audioHandler: handler,
          resolver: _FakeMusicResolver(),
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
          final first = controller.loadMetadataForCurrentTrack();
          final second = controller.loadMetadataForCurrentTrack();
          await tester.pumpWidget(
            AppStringsScope(
              language: AppLanguage.zh,
              child: MaterialApp(
                theme: MusicAppTheme.create(Brightness.light),
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(360, 1000),
                    textScaler: TextScaler.linear(1.6),
                  ),
                  child: PlayerPage(controller: controller),
                ),
              ),
            ),
          );
          await tester.pump();
          final preview = find.byKey(const ValueKey('lyrics-preview'));
          final position = find.byKey(ValueKey('player-position-${track.id}'));
          final before = tester.getRect(preview);
          final sliderBefore = tester.getRect(position);
          expect(controller.isLoadingMetadata, true);
          expect(metadata.calls, 1);
          metadata.pending.complete(
            TrackMetadata(
              lyricsStatus: status,
              lyrics: status == LyricsStatus.available
                  ? const [
                      LyricLine(time: Duration(seconds: 1), text: '第一句'),
                      LyricLine(time: Duration(seconds: 2), text: '第二句'),
                      LyricLine(time: Duration(seconds: 3), text: '第三句'),
                    ]
                  : const [],
            ),
          );
          await Future.wait([first, second]);
          await tester.pump();
          expect(tester.getRect(preview), before);
          expect(tester.getRect(position), sliderBefore);
          expect(tester.takeException(), isNull);
          if (status == LyricsStatus.notFound) {
            expect(find.text('暂无歌词'), findsOneWidget);
            expect(find.text('重新获取歌词'), findsNothing);
          } else if (status == LyricsStatus.failed) {
            expect(find.text('歌词加载失败'), findsOneWidget);
            expect(find.text('重新获取歌词'), findsOneWidget);
          }
          if (status == LyricsStatus.unknown) {
            expect(find.text('暂无歌词'), findsNothing);
          }
          if (status == LyricsStatus.available ||
              status == LyricsStatus.notFound) {
            await controller.loadMetadataForCurrentTrack();
            expect(
              metadata.calls,
              status == LyricsStatus.available ? 1 : 2,
              reason: 'confirmed-empty lyrics recheck local data when reopened',
            );
            await tester.ensureVisible(preview);
            await tester.tap(preview);
            await tester.pumpAndSettle();
            if (status == LyricsStatus.notFound) {
              expect(find.text('暂无歌词'), findsOneWidget);
              expect(find.text('重新获取歌词'), findsNothing);
            }
            expect(metadata.calls, status == LyricsStatus.available ? 1 : 2);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }

  testWidgets(
    'changing from artwork to no artwork does not notify during build',
    (tester) async {
      final cached = _cachedTrack();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
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
          ).copyWith(artUri: Uri.file('/tmp/no-artwork.png')),
        );
        await tester.pumpWidget(
          AnimatedBuilder(
            animation: controller,
            builder: (_, _) => MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => PlayerPage(controller: controller),
                    ),
                  ),
                  child: const Text('Open player'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open player'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerPage), findsOneWidget);
        handler.emit(const MediaItem(id: 'without-art', title: 'Without art'));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets('opening the player does not notify the app during build', (
    tester,
  ) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
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
        AnimatedBuilder(
          animation: controller,
          builder: (_, _) => MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PlayerPage(controller: controller),
                  ),
                ),
                child: const Text('Open player'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open player'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerPage), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets(
    'comments entry opens the current song without replacing the player',
    (tester) async {
      // This covers the compact player -> lyrics route. Wide windows show
      // lyrics inline, which is exercised by the foldable resize test above.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cached = _cachedTrack();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
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
          MaterialApp(home: PlayerPage(controller: controller)),
        );
        await tester.pump();
        // Comments wait behind the page's menu with the other rare actions.
        await tester.tap(find.byKey(const ValueKey('player-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('player-comments')));
        await tester.pumpAndSettle();
        final page = tester.widget<SongCommentsPage>(
          find.byType(SongCommentsPage),
        );
        expect(page.query.title, track.title);
        expect(page.query.artist, track.artist);
        expect(
          page.query.platformIds,
          isEmpty,
          reason: 'BuguYY internal IDs are not official song IDs',
        );
        expect(controller.currentTrack?.id, track.id);
        handler.emit(
          const MediaItem(id: 'next', title: '下一首', artist: '另一位歌手'),
        );
        await tester.pump();
        expect(
          page.query.title,
          track.title,
          reason: 'Reading stays on the opened song',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(PlayerPage), findsOneWidget);
        expect(find.byKey(const ValueKey('player-queue')), findsOneWidget);
        handler.emit(mediaItemFromTrack(track));
        await tester.pump();
        expect(find.byIcon(AppIcons.stop), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byKey(const Key('player-switch-source')),
          ),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('player-queue')));
        await tester.pumpAndSettle();
        expect(find.byType(PlaybackQueue), findsOneWidget);
        Navigator.of(tester.element(find.byType(PlaybackQueue))).pop();
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('lyrics-preview')),
        );
        await tester.tap(find.byKey(const ValueKey('lyrics-preview')));
        await tester.pumpAndSettle();
        expect(find.byIcon(AppIcons.stop), findsNothing);
        await tester.tap(find.byKey(const ValueKey('player-queue')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(PlaybackQueue), findsOneWidget);
        expect(controller.currentTrack?.id, track.id);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        await tester.runAsync(handler.dispose);
      }
    },
  );

  testWidgets(
    'song background repaints progress without rebuilding row contents',
    (tester) async {
      final cached = _cachedTrack();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
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
        var rowBuilds = 0;
        await tester.pumpWidget(
          AppStringsScope(
            language: AppLanguage.zh,
            child: MaterialApp(
              theme: MusicAppTheme.create(Brightness.light),
              home: Scaffold(
                body: SongCacheProgressRow(
                  controller: controller,
                  track: track,
                  rowBuilder: (context, cached) {
                    rowBuilds++;
                    return Text(cached ? '已缓存' : '未缓存');
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.text('已缓存'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.textContaining('%'), findsNothing);
        final key = controller.downloadQueue.taskIdForCandidate(
          MusicSearchCandidate(
            query: cached.music.query,
            source: cached.music.source,
            platform: cached.music.platform,
            id: cached.music.id,
            name: cached.music.name,
            artist: cached.music.artist,
            album: cached.music.album,
            coverUrl: '',
            duration: 0,
            keyword: '',
            link: '',
            page: 1,
            qualities: const [],
            raw: const {},
            score: 1,
          ),
        );
        controller.songCacheProgress.completeKeys({});
        controller.songCacheProgress.streaming(
          key,
          bytes: 10,
          total: 100,
          active: true,
        );
        await tester.pump();
        expect(find.text('未缓存'), findsOneWidget);
        final before = rowBuilds;
        for (var bytes = 11; bytes <= 50; bytes++) {
          controller.songCacheProgress.streaming(
            key,
            bytes: bytes,
            total: 100,
            active: true,
          );
          await tester.pump();
        }
        expect(rowBuilds, before);
        final painter = tester
            .widget<CustomPaint>(
              find.byKey(ValueKey('song-cache-background-${track.id}')),
            )
            .painter!;
        // Paint the actual background: half-width tint, no tint after its edge.
        await tester.runAsync(() async {
          final recorder = PictureRecorder();
          painter.paint(Canvas(recorder), const Size(200, 20));
          final picture = recorder.endRecording();
          final image = await picture.toImage(200, 20);
          final data = (await image.toByteData(
            format: ImageByteFormat.rawRgba,
          ))!;
          expect(data.getUint8((10 * 200 + 20) * 4 + 3), greaterThan(0));
          expect(data.getUint8((10 * 200 + 150) * 4 + 3), 0);
          image.dispose();
          picture.dispose();
        });
        controller.songCacheProgress.removePartial(key);
        controller.songCacheProgress.completeKeys({key});
        await tester.pump();
        expect(find.text('已缓存'), findsOneWidget);
        expect(rowBuilds, before + 1);
        await tester.pumpWidget(const SizedBox());
      } finally {
        controller.dispose();
        await tester.runAsync(handler.dispose);
      }
    },
  );

  testWidgets(
    'player secondary progress is independent of position, seek and media changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cached = _cachedTrack();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
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
        const duration = Duration(seconds: 100);
        handler.emit(
          const MediaItem(
            id: 'streaming',
            title: 'Streaming',
            duration: duration,
          ),
        );
        handler.playbackState.add(
          PlaybackState(bufferedPosition: const Duration(seconds: 60)),
        );
        await tester.pumpWidget(
          AppStringsScope(
            language: AppLanguage.zh,
            child: MaterialApp(
              theme: MusicAppTheme.create(Brightness.light),
              home: PlayerPage(controller: controller),
            ),
          ),
        );
        await tester.pump();
        Slider slider() => tester.widget<Slider>(find.byType(Slider));
        handler.emit(
          const MediaItem(
            id: 'streaming',
            title: 'Streaming',
            duration: duration,
          ),
        );
        handler.playbackState.add(
          PlaybackState(bufferedPosition: const Duration(seconds: 60)),
        );
        await tester.pump();
        expect(slider().secondaryTrackValue, 60000);
        handler.positions.add(const Duration(seconds: 10));
        await tester.pump();
        expect(slider().value, 10000);
        expect(slider().secondaryTrackValue, 60000);
        slider().onChangeStart!(70000);
        slider().onChanged!(70000);
        await tester.pump();
        expect(slider().value, 70000);
        expect(slider().secondaryTrackValue, 60000);
        slider().onChangeEnd!(70000);
        await tester.pump();
        expect(handler.seekedPositions, [const Duration(seconds: 70)]);
        // A new song must discard an in-progress drag and clamp its buffer.
        slider().onChangeStart!(90000);
        slider().onChanged!(90000);
        handler.emit(
          const MediaItem(
            id: 'next',
            title: 'Next',
            duration: Duration(seconds: 20),
          ),
        );
        handler.playbackState.add(
          PlaybackState(bufferedPosition: const Duration(seconds: 80)),
        );
        await tester.pump();
        await tester.pump();
        expect(slider().value, 0);
        expect(slider().secondaryTrackValue, 20000);
        handler.emit(const MediaItem(id: 'unknown', title: 'Unknown'));
        await tester.pump();
        await tester.pump();
        expect(slider().secondaryTrackValue, 0);
        expect(slider().onChanged, null);
        // Whole local files remain fully buffered regardless of decoder read-ahead.
        handler.emit(
          mediaItemFromTrack(
            trackFromCached(cached),
          ).copyWith(duration: duration),
        );
        handler.playbackState.add(
          PlaybackState(bufferedPosition: const Duration(seconds: 5)),
        );
        await tester.pump();
        await tester.pump();
        expect(slider().secondaryTrackValue, 100000);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      } finally {
        controller.dispose();
        await tester.runAsync(handler.dispose);
      }
    },
  );

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
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
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
            theme: MusicAppTheme.create(Brightness.dark),
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

  testWidgets('plain lyrics show all lines without seek or timing guide', (
    tester,
  ) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(
        metadata: const TrackMetadata(
          lyrics: [
            LyricLine(time: Duration.zero, text: '纯文本第一句'),
            LyricLine(time: Duration.zero, text: '纯文本第二句'),
            LyricLine(time: Duration.zero, text: '纯文本第三句'),
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
      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: MusicAppTheme.create(Brightness.light),
            home: Scaffold(
              body: SizedBox(
                height: 360,
                child: LyricsPanelForTesting(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('纯文本第一句'), findsOneWidget);
      expect(find.text('纯文本第二句'), findsOneWidget);
      expect(find.text('纯文本第三句'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      await tester.tap(find.text('纯文本第二句'));
      await tester.pump();
      expect(handler.seekedPositions, isEmpty);
    } finally {
      controller.dispose();
    }
  });

  testWidgets('upgraded timed lyrics become tappable without replaying', (
    tester,
  ) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final metadata = _UpgradingMetadataRepository();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
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
      expect(controller.currentLyrics.last.time, Duration.zero);

      metadata.finishUpgrade();
      await tester.pump();
      expect(metadata.upgradeCalls, 1);
      expect(controller.currentLyrics.last.time, const Duration(seconds: 20));

      await tester.pumpWidget(
        AppStringsScope(
          language: AppLanguage.zh,
          child: MaterialApp(
            theme: MusicAppTheme.create(Brightness.light),
            home: Scaffold(
              body: SizedBox(
                height: 360,
                child: LyricsPanelForTesting(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('第二句'));
      await tester.pump();
      expect(handler.seekedPositions, [const Duration(seconds: 20)]);
    } finally {
      controller.dispose();
    }
  });

  testWidgets('failed lyrics panel can retry metadata recovery', (
    tester,
  ) async {
    final cached = _cachedTrack();
    final handler = _SpyAudioHandler();
    final metadata = _RetryMetadataRepository();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
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
            theme: MusicAppTheme.create(Brightness.dark),
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

      expect(find.text('歌词加载失败'), findsOneWidget);
      expect(find.text('重新获取歌词'), findsOneWidget);

      await tester.tap(find.text('重新获取歌词'));
      await tester.pumpAndSettle();

      expect(metadata.bypassLoadCount, 1);
      expect(find.text('手动补齐'), findsOneWidget);
    } finally {
      controller.dispose();
    }
  });

  testWidgets(
    'play lowers the needle first, then starts the record and sound',
    (tester) async {
      final cached = _cachedTrack();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
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
        handler.playbackState.add(
          handler.playbackState.value.copyWith(playing: false),
        );
        await tester.pumpWidget(
          AppStringsScope(
            language: AppLanguage.zh,
            child: MaterialApp(home: PlayerPage(controller: controller)),
          ),
        );
        await tester.pump();
        Turntable deck() => tester.widget<Turntable>(find.byType(Turntable));
        expect(deck().armDown, isFalse);

        await tester.tap(find.byTooltip('播放'));
        await tester.pump();
        // Needle down, record still, no sound yet.
        expect(deck().armDown, isTrue);
        expect(deck().playing, isFalse);
        expect(handler.playbackState.value.playing, isFalse);

        await tester.pump(MusicMotion.toneArm);
        await tester.pump();
        expect(handler.playbackState.value.playing, isTrue);
        expect(deck().playing, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
}

class _SpyAudioHandler extends MusicAudioHandler {
  int queueLoads = 0;
  int playCalls = 0;

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  bool awaiting = false;
  @override
  bool get isAwaitingPlayback => awaiting;
  Duration position = Duration.zero;
  final seekedPositions = <Duration>[];
  final positions = StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Duration get currentPosition => position;

  @override
  Duration get currentBufferedPosition => playbackState.value.bufferedPosition;

  @override
  Future<void> dispose() async {
    await positions.close();
    unawaited(super.dispose());
  }

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
    bool restoreOnFailure = false,
  }) async {
    queueLoads++;
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex].mediaItem);
    }
  }

  @override
  Future<void> play() async {
    playCalls++;
    awaiting = false;
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> seek(Duration position) async {
    seekedPositions.add(position);
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
  @override
  Future<Uri?> cachedArtwork(CachedTrack track) async => null;

  _StaticMetadataRepository({required this.metadata});

  final TrackMetadata metadata;

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    return metadata;
  }

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) async => metadata;
}

class _DeferredMetadataRepository extends TrackMetadataRepository {
  final pending = Completer<TrackMetadata>();
  int calls = 0;
  @override
  Future<Uri?> cachedArtwork(CachedTrack track) async => null;
  @override
  Future<TrackMetadata> load(CachedTrack track) {
    calls++;
    return pending.future;
  }
}

class _UpgradingMetadataRepository extends TrackMetadataRepository {
  @override
  Future<Uri?> cachedArtwork(CachedTrack track) async => null;

  final Completer<TrackMetadata> _upgrade = Completer<TrackMetadata>();
  int upgradeCalls = 0;

  @override
  Future<TrackMetadata> load(CachedTrack track) async => const TrackMetadata(
    lyrics: [
      LyricLine(time: Duration.zero, text: '第一句'),
      LyricLine(time: Duration.zero, text: '第二句'),
    ],
  );

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) {
    upgradeCalls += 1;
    return _upgrade.future;
  }

  void finishUpgrade() {
    _upgrade.complete(
      const TrackMetadata(
        lyrics: [
          LyricLine(time: Duration(seconds: 1), text: '第一句'),
          LyricLine(time: Duration(seconds: 20), text: '第二句'),
        ],
      ),
    );
  }
}

class _RetryMetadataRepository extends TrackMetadataRepository {
  @override
  Future<Uri?> cachedArtwork(CachedTrack track) async => null;

  int bypassLoadCount = 0;

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    return const TrackMetadata(lyricsStatus: LyricsStatus.failed);
  }

  @override
  Future<TrackMetadata> loadBypassingLyricsMiss(CachedTrack track) async {
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
  Future<Map<String, ({int bytes, int? total})>> partialProgress() async => {};

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
