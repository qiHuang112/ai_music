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
import 'package:ai_music/src/presentation/player_page.dart';
import 'package:ai_music/src/presentation/playback_queue.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_download_history.dart';

void main() {
  const scenarios = [
    (
      name: '320dp Chinese with long lyrics and 2x text',
      size: Size(320, 700),
      scale: 2.0,
      language: AppLanguage.zh,
      brightness: Brightness.light,
    ),
    (
      name: '320dp English with long lyrics and 2x text',
      size: Size(320, 700),
      scale: 2.0,
      language: AppLanguage.en,
      brightness: Brightness.light,
    ),
    (
      name: 'short landscape keeps side controls reachable',
      size: Size(740, 320),
      scale: 1.0,
      language: AppLanguage.en,
      brightness: Brightness.light,
    ),
    (
      name: 'narrow English dark theme',
      size: Size(320, 640),
      scale: 1.3,
      language: AppLanguage.en,
      brightness: Brightness.dark,
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('lyrics layout: ${scenario.name}', (tester) async {
      final fixture = _LyricsFixture(scenario.language);
      try {
        await fixture.pumpPlayer(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          brightness: scenario.brightness,
        );
        await fixture.openLyrics(tester);
        final strings = AppStrings(scenario.language);
        final lyrics = find.byKey(const ValueKey('lyrics-list'));
        final position = find.byKey(
          ValueKey('lyrics-position-${fixture.item.id}'),
        );
        expect(lyrics, findsOneWidget);
        expect(find.text(fixture.item.title), findsNothing);
        expect(find.text(fixture.item.artist!), findsNothing);
        expect(tester.getSize(lyrics).height, greaterThan(48));
        expect(tester.takeException(), isNull);

        final controls = [
          position,
          find.byTooltip(strings.previous),
          find.byTooltip(strings.play),
          find.byTooltip(strings.next),
          find.byKey(const ValueKey('playback-queue')),
        ];
        if (scenario.size.width > scenario.size.height) {
          await _reachSideControls(tester, find.byTooltip(strings.play));
        }
        for (final control in controls) {
          _expectInsideSafeViewport(tester, control, scenario.size);
        }
        final slider = find.descendant(
          of: position,
          matching: find.byType(Slider),
        );
        expect(tester.widget<Slider>(slider).onChanged, isNotNull);

        final longLine = find.descendant(
          of: lyrics,
          matching: find.text(fixture.metadata.lyrics.first.text),
        );
        expect(longLine, findsOneWidget);
        _expectWholeWrappedLine(tester, longLine);
        final text = tester.widget<Text>(longLine);
        expect(
          tester.renderObject<RenderParagraph>(longLine).textAlign,
          TextAlign.center,
        );
        expect(text.style!.fontWeight, FontWeight.w600);
        expect(
          text.style!.color,
          Theme.of(tester.element(longLine)).colorScheme.primary,
        );

        // Reading further down must not move the playback controls or seek.
        final originalPosition = tester.getRect(position);
        final scrollable = find.descendant(
          of: lyrics,
          matching: find.byType(Scrollable),
        );
        final scrollState = tester.state<ScrollableState>(scrollable);
        final originalOffset = scrollState.position.pixels;
        await tester.drag(lyrics, const Offset(0, -140));
        await tester.pump(const Duration(milliseconds: 300));
        expect(scrollState.position.pixels, greaterThan(originalOffset));
        expect(fixture.handler.seekedPositions, isEmpty);
        expect(tester.getRect(position), originalPosition);
        for (final control in controls) {
          _expectInsideSafeViewport(tester, control, scenario.size);
        }

        await tester.tap(find.byTooltip(strings.play));
        await tester.pumpAndSettle();
        expect(fixture.handler.playCalls, 1);
        expect(find.byTooltip(strings.pause).hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip(strings.pause));
        await tester.pumpAndSettle();
        expect(fixture.handler.pauseCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('approved lyrics skin keeps actions reachable: $brightness', (
      tester,
    ) async {
      final fixture = _LyricsFixture(AppLanguage.zh);
      try {
        await fixture.pumpPlayer(
          tester,
          size: const Size(393, 851),
          brightness: brightness,
        );
        await fixture.openLyrics(tester);
        expect(find.byKey(const ValueKey('player-artwork')), findsNothing);
        for (final key in [
          'lyrics-add-playlist',
          'lyrics-artwork',
          'lyrics-comments',
        ]) {
          expect(find.byKey(ValueKey(key)), findsNothing);
        }
        final strings = AppStrings(AppLanguage.zh);
        for (final control in [
          find.byTooltip(strings.previous),
          find.byTooltip(strings.play),
          find.byTooltip(strings.next),
          find.byKey(const ValueKey('playback-queue')),
        ]) {
          _expectInsideSafeViewport(tester, control, const Size(393, 851));
        }
        expect(find.byTooltip(strings.stop), findsNothing);
        await tester.tap(find.byKey(const ValueKey('playback-queue')));
        await tester.pumpAndSettle();
        expect(find.byType(PlaybackQueue), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(fixture.handler.stopCalls, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('playback-queue')), findsOneWidget);
        expect(find.byKey(const ValueKey('player-queue')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('playback-queue')));
        await tester.pumpAndSettle();
        expect(find.byType(PlaybackQueue), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('player-swipe-area')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('lyrics browsing and tapping keep distinct playback behavior', (
    tester,
  ) async {
    final fixture = _LyricsFixture(AppLanguage.zh);
    try {
      await fixture.pumpPlayer(tester, size: const Size(393, 851));
      await fixture.openLyrics(tester);
      final lyrics = find.byKey(const ValueKey('lyrics-list'));
      final scrollable = find.descendant(
        of: lyrics,
        matching: find.byType(Scrollable),
      );
      final secondLine = find.descendant(
        of: lyrics,
        matching: find.text(fixture.metadata.lyrics[1].text),
      );
      expect(find.byKey(const ValueKey('lyrics-browse-guide')), findsNothing);

      await tester.drag(lyrics, const Offset(0, -150));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.handler.seekedPositions, isEmpty);
      expect(find.byKey(const ValueKey('lyrics-browse-guide')), findsNothing);
      expect(find.byKey(const ValueKey('lyrics-follow-current')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(fixture.handler.seekedPositions, isEmpty);
      await tester.scrollUntilVisible(secondLine, 100, scrollable: scrollable);
      await tester.pump(const Duration(milliseconds: 100));
      expect(secondLine.hitTestable(), findsOneWidget);
      await tester.tap(secondLine);
      await tester.pump();
      expect(fixture.handler.seekedPositions, [
        fixture.metadata.lyrics[1].time,
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'timed lyrics follow measured centers across progress, resize and browsing',
    (tester) async {
      final fixture = _LyricsFixture(AppLanguage.en);
      try {
        await fixture.pumpPlayer(tester, size: const Size(600, 900));
        await fixture.openLyrics(tester);
        final lyrics = find.byKey(const ValueKey('lyrics-list'));
        final guide = find.byKey(const ValueKey('lyrics-browse-guide'));
        final scrollable = find.descendant(
          of: lyrics,
          matching: find.byType(Scrollable),
        );
        Finder line(int index) => find.descendant(
          of: lyrics,
          matching: find.text(fixture.metadata.lyrics[index].text),
        );
        void expectCurrentLineCentered(int index) {
          final current = line(index);
          expect(current, findsOneWidget);
          final row = find
              .ancestor(of: current, matching: find.byType(InkWell))
              .first;
          expect(
            tester.getRect(row).center.dy,
            closeTo(tester.getRect(lyrics).center.dy, 1),
          );
          expect(
            tester.widget<Text>(current).style!.fontWeight,
            FontWeight.w600,
          );
          expect(guide, findsNothing);
        }

        expectCurrentLineCentered(0);
        final originalLongHeight = tester.getSize(line(0)).height;
        fixture.handler.positions.add(const Duration(seconds: 20));
        await tester.pumpAndSettle();
        expectCurrentLineCentered(1);
        expect(originalLongHeight, greaterThan(tester.getSize(line(1)).height));

        // Frequent audio position events inside one lyric must not start
        // another scroll or accidentally turn automatic following into browsing.
        final position = tester.state<ScrollableState>(scrollable).position;
        final offsets = <double>[];
        void recordScroll() => offsets.add(position.pixels);
        position.addListener(recordScroll);
        try {
          for (final seconds in [22, 30, 39]) {
            fixture.handler.positions.add(Duration(seconds: seconds));
            await tester.pumpAndSettle();
            expectCurrentLineCentered(1);
          }
          expect(offsets, isEmpty);
        } finally {
          position.removeListener(recordScroll);
        }

        // Narrowing the actual viewport wraps the long preceding lyric onto
        // more lines. Its new height must be included in the current offset.
        tester.view.physicalSize = const Size(320, 700);
        await tester.pumpAndSettle();
        expect(tester.getSize(line(0)).height, greaterThan(originalLongHeight));
        expectCurrentLineCentered(1);
        fixture.handler.positions.add(const Duration(seconds: 44));
        await tester.pumpAndSettle();
        expectCurrentLineCentered(2);

        final followedOffset = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;
        await tester.drag(lyrics, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(guide, findsNothing);
        final browsingOffset = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;
        expect(browsingOffset, greaterThan(followedOffset));
        fixture.handler.positions.add(const Duration(seconds: 47));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.state<ScrollableState>(scrollable).position.pixels,
          closeTo(browsingOffset, 0.1),
        );
        expect(fixture.handler.seekedPositions, isEmpty);

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expectCurrentLineCentered(2);
        expect(fixture.handler.seekedPositions, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('missing lyrics can scroll to retry on a short landscape screen', (
    tester,
  ) async {
    final fixture = _LyricsFixture(AppLanguage.en, missingLyrics: true);
    try {
      await fixture.pumpPlayer(
        tester,
        size: const Size(740, 320),
        scale: 1.3,
        brightness: Brightness.dark,
      );
      // A long provider failure is allowed to occupy multiple lines. Entering
      // the real route should keep its retry action accessible by scrolling.
      fixture.controller.metadataError =
          'Lyrics could not be loaded because the music provider is temporarily '
          'unavailable. The song can still be played. Please check your network '
          'connection and try fetching the lyrics again when it is available.';
      await fixture.openLyrics(tester);
      final area = find.byKey(const ValueKey('lyrics-swipe-area'));
      final retry = find.widgetWithText(
        OutlinedButton,
        AppStrings(AppLanguage.en).retryLyrics,
      );
      expect(retry, findsOneWidget);
      expect(tester.takeException(), isNull);
      final scrollable = find
          .ancestor(of: retry, matching: find.byType(Scrollable))
          .first;
      expect(scrollable, findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
      );
      await tester.scrollUntilVisible(retry, 80, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(retry.hitTestable(), findsOneWidget);
      await _reachSideControls(
        tester,
        find.byTooltip(AppStrings(AppLanguage.en).play),
      );
      expect(
        find
            .descendant(of: area, matching: find.byTooltip('Play'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(fixture.repository.bypassLoads, 1);
      expect(
        find.text(_LyricsMetadataRepository.recoveredLine),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('lyrics-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

Future<void> _reachSideControls(WidgetTester tester, Finder play) async {
  // Unified controls stay at the bottom even in landscape; no side scroller.
  expect(play.hitTestable(), findsOneWidget);
}

void _expectInsideSafeViewport(
  WidgetTester tester,
  Finder target,
  Size viewport,
) {
  expect(target.hitTestable(), findsOneWidget);
  final bounds = tester.getRect(target);
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(viewport.width));
  expect(bounds.top, greaterThanOrEqualTo(24));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.height - 24));
}

void _expectWholeWrappedLine(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  try {
    expect(painter.computeLineMetrics().length, greaterThan(1));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height + 0.1, greaterThanOrEqualTo(painter.height));
    // The full paragraph must fit its tappable row, even when only part of
    // that row can fit in the scrolling viewport at a large text scale.
    final row = find.ancestor(of: finder, matching: find.byType(InkWell)).first;
    final rowBounds = tester.getRect(row);
    final textBounds = tester.getRect(finder);
    expect(textBounds.top, greaterThanOrEqualTo(rowBounds.top));
    expect(textBounds.bottom, lessThanOrEqualTo(rowBounds.bottom + 0.1));
    expect(textBounds.left, greaterThanOrEqualTo(rowBounds.left));
    expect(textBounds.right, lessThanOrEqualTo(rowBounds.right + 0.1));
  } finally {
    painter.dispose();
  }
}

class _LyricsFixture {
  _LyricsFixture(this.language, {bool missingLyrics = false}) {
    cached = _cachedTrack(language);
    metadata = TrackMetadata(
      lyrics: [
        LyricLine(
          time: Duration.zero,
          text: language == AppLanguage.zh
              ? '那些一起听歌的日子仍留在熟悉的旋律里，陪我们走过漫长旅途'
              : 'The familiar melody brings back all those unforgettable '
                    'evenings that we spent together',
        ),
        for (var index = 1; index < 12; index++)
          LyricLine(
            time: Duration(seconds: index * 20),
            text: language == AppLanguage.zh
                ? '第${index + 1}句，继续听歌'
                : 'Line ${index + 1}, keep listening',
          ),
      ],
    );
    repository = _LyricsMetadataRepository(
      missingLyrics ? const TrackMetadata() : metadata,
    );
    controller = MusicController(
      audioHandler: handler,
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      resolver: _LyricsResolver(cached.music),
      cacheStore: _LyricsCacheStore(cached),
      playlistStore: _LyricsPlaylistStore(cached.cacheId),
      settingsStore: _LyricsSettingsStore(language),
      metadataRepository: repository,
    );
  }

  final AppLanguage language;
  final handler = _LyricsAudioHandler();
  late final CachedTrack cached;
  late final TrackMetadata metadata;
  late final _LyricsMetadataRepository repository;
  late final MusicController controller;
  late final MediaItem item;

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required Size size,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.initialize();
    item = mediaItemFromTrack(
      trackFromCached(cached),
    ).copyWith(duration: const Duration(minutes: 4, seconds: 15));
    handler.queue.add([item]);
    handler.mediaItem.add(item);
    await controller.loadMetadataForCurrentTrack();
    await tester.pumpWidget(
      AppStringsScope(
        language: language,
        child: MaterialApp(
          theme: MusicAppTheme.create(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
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
  }

  Future<void> openLyrics(WidgetTester tester) async {
    final preview = find.byKey(const ValueKey('lyrics-preview'));
    final player = find.byKey(const ValueKey('player-swipe-area'));
    final scrollable = find
        .descendant(of: player, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(preview, 120, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(preview.hitTestable(), findsOneWidget);
    // The missing-lyrics preview contains its own retry button. Its trailing
    // chevron always opens the detail route instead of triggering that button.
    final bounds = tester.getRect(preview);
    await tester.tapAt(Offset(bounds.right - 22, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyrics-swipe-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Let any delayed return-to-current-line callback observe the disposed
    // route, rather than leaving a pending timer at the end of the test.
    await tester.pump(const Duration(seconds: 3));
    controller.dispose();
    await tester.runAsync(handler.dispose);
  }
}

class _LyricsAudioHandler extends MusicAudioHandler {
  final positions = StreamController<Duration>.broadcast();
  final seekedPositions = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

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
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> seek(Duration position) async => seekedPositions.add(position);

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

class _LyricsMetadataRepository extends TrackMetadataRepository {
  _LyricsMetadataRepository(this.metadata);
  final TrackMetadata metadata;
  int bypassLoads = 0;
  static const recoveredLine = 'Recovered lyrics are ready to read';

  @override
  Future<TrackMetadata> load(CachedTrack track) async => metadata;

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) async => metadata;

  @override
  Future<TrackMetadata> loadBypassingLyricsMiss(CachedTrack track) async {
    bypassLoads++;
    return const TrackMetadata(
      lyrics: [LyricLine(time: Duration(seconds: 1), text: recoveredLine)],
    );
  }
}

class _LyricsCacheStore extends CachedTrackStore {
  _LyricsCacheStore(this.cached);
  CachedTrack cached;

  @override
  Future<Map<String, ({int bytes, int? total})>> partialProgress() async => {};

  @override
  Future<List<CachedTrack>> listCached() async => [cached];

  @override
  Future<void> cleanupTemporaryFiles() async {}

  @override
  Future<CachedTrack> updateCachedMusic(
    CachedTrack track,
    ResolvedMusic music,
  ) async => cached = track.copyWith(music: music);
}

class _LyricsPlaylistStore extends PlaylistStore {
  _LyricsPlaylistStore(this.trackId) : super(rootProvider: _unusedRootProvider);
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

class _LyricsSettingsStore implements MusicSettingsStore {
  _LyricsSettingsStore(this.language);
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

class _LyricsResolver implements MusicResolver {
  _LyricsResolver(this.music);
  final ResolvedMusic music;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async => const [];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async => music;
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
    id: 'lyrics-layout-song',
    name: title,
    artist: artist,
    album: 'An album with long lyrics',
    url: 'https://cdn.example.test/lyrics-layout-song.mp3',
    quality: const MusicQuality(format: 'mp3'),
  );
  return CachedTrack(
    cacheId: cacheIdForResolved(music),
    music: music,
    filePath: '/tmp/lyrics-layout-song.mp3',
    sizeBytes: 1024,
    fromCache: true,
  );
}

Future<Directory> _unusedRootProvider() async =>
    throw UnsupportedError('Lyrics layout playlists stay in memory');
