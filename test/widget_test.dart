import 'package:ai_music/src/data/listening_stats_store.dart';
import 'package:ai_music/src/presentation/listening_stats_page.dart';
import 'package:ai_music/src/presentation/playback_queue.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/data/song_search_cache.dart';
import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/presentation/date_groups.dart';
import 'memory_download_history.dart';
import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/lan_sync_use_case.dart';
import 'package:ai_music/src/data/lan_library_client.dart';
import 'package:ai_music/src/data/lan_library_models.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:ai_music/src/data/search_history_store.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/music_home_page.dart';
import 'package:ai_music/src/presentation/song_source_page.dart';
import 'package:ai_music/src/presentation/player_page.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'original library navigation preserves search without bottom tabs',
    (tester) async {
      final handler = _WidgetAudioHandler();
      final controller = _NavigationUiController(handler);
      try {
        await tester.pumpWidget(_app(playbackController: controller));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(BottomNavigationBar), findsNothing);
        await tester.enterText(find.byType(TextField), '保留这个关键词');
        tester.binding.focusManager.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('音乐库'));
        await tester.pumpAndSettle();
        expect(find.text('音乐库'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('保留这个关键词'), findsOneWidget);
        expect(controller.initializeCalls, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(controller.positions.close());
        unawaited(handler.dispose());
      }
    },
  );

  for (final largeText in [false, true]) {
    testWidgets(
      'playlist uncertain source is actionable without background search largeText=$largeText',
      (tester) async {
        if (largeText) {
          tester.view.physicalSize = const Size(320, 760);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        final candidate = _candidate(
          id: 'instrumental',
          name: '回忆观影券 (伴奏)',
          artist: 'IN-K',
          source: MusicDataSource.flac,
          platform: 'wyy',
        );
        final saved = SavedOnlineTrack(candidate: candidate);
        final stamp = DateTime(2026, 10, 8);
        PlaylistTrackEntry entry(
          String id, {
          bool manual = false,
          bool pending = false,
          bool exact = false,
        }) => PlaylistTrackEntry(
          trackId: id,
          addedAt: stamp,
          song: PlaylistSong(
            key: 'qq:song:$id',
            title: '回忆观影券 (伴奏)',
            artist: exact ? 'IN-K' : 'IN-K / 王忻辰',
            durationSeconds: 172,
          ),
          onlineTrack: pending ? null : saved,
          manualSource: manual,
        );
        final playlists = _FakePlaylistStore()
          ..library = PlaylistLibrary(
            playlists: [
              MusicPlaylist(
                id: 'review-list',
                name: '待核对测试歌单',
                entries: [
                  entry('uncertain'),
                  entry('manual', manual: true),
                  entry('exact', exact: true),
                  entry('pending', pending: true),
                ],
                createdAt: stamp,
                updatedAt: stamp,
              ),
            ],
          );
        final resolver = _FakeMusicResolver(candidates: [candidate]);
        final handler = _WidgetAudioHandler();
        final controller = MusicController(
          audioHandler: handler,
          resolver: resolver,
          cacheStore: _FakeCacheStore(),
          playlistStore: playlists,
          settingsStore: _FakeSettingsStore(),
          metadataRepository: _FakeMetadataRepository(),
          songSearchCache: SongSearchCache.memory(),
          downloadHistoryStore: MemoryDownloadHistory(),
          listeningStatsStore: ListeningStatsStore.memory(),
          connectivityChanges: const Stream.empty(),
        );
        try {
          await tester.pumpWidget(
            _app(
              playbackController: controller,
              textScaler: largeText ? const TextScaler.linear(2) : null,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('音乐库'));
          await tester.pumpAndSettle();
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('待核对测试歌单').last);
          await tester.pumpAndSettle();
          final review = find.byKey(
            const ValueKey('song-match-review-uncertain'),
          );
          expect(review, findsOneWidget);
          expect(
            find.byKey(const ValueKey('song-match-review-manual')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('song-match-review-exact')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('song-match-review-pending')),
            findsNothing,
          );
          expect(resolver.searchCount, 0);
          expect(tester.takeException(), isNull);
          final tracks = controller.tracksForPlaylist(
            controller.allPlaylists.single,
          );
          expect(
            controller.songSourceNeedsReview(
              tracks.firstWhere((t) => t.id == 'uncertain'),
            ),
            isTrue,
          );
          expect(
            controller.songSourceNeedsReview(
              tracks.firstWhere((t) => t.id == 'manual'),
            ),
            isFalse,
          );
          expect(
            controller.songSourceNeedsReview(
              tracks.firstWhere((t) => t.id == 'exact'),
            ),
            isFalse,
          );
          expect(
            controller.songSourceNeedsReview(
              tracks.firstWhere((t) => t.id == 'pending'),
            ),
            isFalse,
          );
          expect(resolver.searchCount, 0);

          await tester.ensureVisible(review);
          await tester.tap(review);
          await tester.pumpAndSettle();
          expect(find.byType(SongSourcePage), findsOneWidget);
          expect(resolver.searchCount, 1);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('song-source-0')));
          await tester.pumpAndSettle();
          expect(find.byType(SongSourcePage), findsNothing);
          expect(
            find.byKey(const ValueKey('song-match-review-uncertain')),
            findsNothing,
          );
          expect(
            playlists.library.playlists.single.entries.first.manualSource,
            isTrue,
          );
          expect(resolver.searchCount, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          unawaited(handler.dispose());
        }
      },
    );
  }

  testWidgets('listening statistics entry is only in music library', (
    tester,
  ) async {
    final handler = _WidgetAudioHandler();
    final stats = ListeningStatsStore.memory();
    final controller = _QueueUiController(handler, stats: stats);
    try {
      await tester.pumpWidget(_app(playbackController: controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-listening-stats')), findsNothing);
      await tester.tap(find.byTooltip('音乐库'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-listening-stats')));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningStatsPage), findsOneWidget);
      expect(find.byKey(const Key('listening-total-time')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
    }
  });

  testWidgets(
    'statistics adapt to small screens, large text and both themes/languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handler = _WidgetAudioHandler();
      final stats = ListeningStatsStore.memory();
      final controller = _QueueUiController(handler, stats: stats);
      final today = DateTime.now();
      for (var i = 0; i < 8; i++) {
        stats.addInterval(
          'v$i',
          ListeningContext(
            ListeningSong(
              id: 's$i',
              trackId: 's$i',
              title: 'A very long song title $i',
              artist: 'A very long artist name',
            ),
            playlistId: 'p$i',
            playlistName: 'A very long playlist name $i',
          ),
          today,
          today.add(Duration(seconds: 60 + i)),
          qualifiedAt: today.add(const Duration(seconds: 30)),
        );
      }
      try {
        for (final language in AppLanguage.values) {
          for (final brightness in Brightness.values) {
            await tester.pumpWidget(
              MaterialApp(
                theme: MusicAppTheme.create(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: AppStringsScope(language: language, child: child!),
                ),
                home: ListeningStatsPage(
                  controller: controller,
                  onOpenPlaylist: (_) {},
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text(language == AppLanguage.zh ? '每日记录' : 'Daily history'),
              350,
              scrollable: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(handler.dispose());
      }
    },
  );

  testWidgets(
    'old history stays collapsed and ranking/history keep deleted song snapshots',
    (tester) async {
      final handler = _WidgetAudioHandler();
      final stats = ListeningStatsStore.memory();
      final controller = _QueueUiController(handler, stats: stats);
      final today = DateUtils.dateOnly(DateTime.now());
      final old = DateTime(today.year - 1, 1, 1);
      await stats.load();
      stats.startedAt = old;
      for (var i = 0; i < 365; i++) {
        final day = old.add(Duration(days: i));
        stats.addInterval(
          'old$i',
          const ListeningContext(
            ListeningSong(
              id: 'a',
              trackId: 'deleted-a',
              title: 'Archived song',
              artist: 'Artist',
            ),
          ),
          day,
          day.add(const Duration(minutes: 1)),
          qualifiedAt: day.add(const Duration(seconds: 30)),
        );
      }
      stats.addInterval(
        'now',
        const ListeningContext(
          ListeningSong(
            id: 'b',
            trackId: 'deleted-b',
            title: 'Recent song',
            artist: 'Artist',
          ),
        ),
        today,
        today.add(const Duration(minutes: 10)),
        qualifiedAt: today.add(const Duration(seconds: 30)),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicAppTheme.create(Brightness.light),
            home: ListeningStatsPage(
              controller: controller,
              onOpenPlaylist: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('累计'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Archived song'),
          250,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        final tiles = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .where(
              (tile) =>
                  tile.title is Text &&
                  [
                    'Archived song',
                    'Recent song',
                  ].contains((tile.title as Text).data),
            )
            .toList();
        expect((tiles.first.title as Text).data, 'Archived song');
        await tester.ensureVisible(find.text('按次数 ▾'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('按次数 ▾'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is CheckedPopupMenuItem<bool> && w.value == true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('按时长 ▾'), findsOneWidget);
        // 365 short listens also win duration; the selected order remains explicit.

        await tester.ensureVisible(find.text('Archived song'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archived song'));
        await tester.pumpAndSettle();
        expect(find.text('这条记录对应的歌曲或歌单已不在音乐库中'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('history-year-${old.year}')),
          250,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        expect(
          find.byKey(ValueKey('history-month-${old.year}-01')),
          findsNothing,
        );
        await tester.ensureVisible(find.text('${old.year}年'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('${old.year}年'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('history-month-${old.year}-01')),
          250,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.ensureVisible(find.text('1月'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1月'));
        await tester.pumpAndSettle();
        final label = dateGroupLabel(old, zh: true);
        await tester.scrollUntilVisible(
          find.text(label),
          250,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text('Archived song'), findsOneWidget);
        expect(find.textContaining('单曲播放'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(handler.dispose());
      }
    },
  );

  testWidgets('clear history requires confirmation and preserves music state', (
    tester,
  ) async {
    final handler = _WidgetAudioHandler();
    final fixture = _homeLibraryFixture();
    final stats = ListeningStatsStore.memory();
    final controller = _QueueUiController(
      handler,
      fixture: fixture,
      stats: stats,
    );
    await controller.initialize();
    final at = DateTime.now();
    stats.addInterval(
      'v',
      const ListeningContext(
        ListeningSong(id: 'a', trackId: 'a', title: 'Song', artist: 'Artist'),
      ),
      at,
      at.add(const Duration(minutes: 1)),
    );
    final favorites = controller.favoriteTracks.map((t) => t.id).toList();
    final playlists = controller.customPlaylists.map((p) => p.id).toList();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    confirmClearListeningStats(context, controller),
                child: const Text('clear'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(stats.records, isNotEmpty);
      await tester.tap(find.text('clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(stats.records, isEmpty);
      expect(controller.favoriteTracks.map((t) => t.id), favorites);
      expect(controller.customPlaylists.map((p) => p.id), playlists);
      expect(controller.cachedTracks.length, 2);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
    }
  });
  testWidgets('mini progress resets only when the media item changes', (
    tester,
  ) async {
    final handler = _WidgetAudioHandler();
    final controller = _QueueUiController(handler);
    Future<void> show(String id, {int seconds = 100}) => tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        home: Scaffold(
          body: MiniPlaybackProgress(
            controller: controller,
            item: MediaItem(
              id: id,
              title: id,
              duration: Duration(seconds: seconds),
            ),
            state: PlaybackState(),
          ),
        ),
      ),
    );
    try {
      await show('A');
      controller.positions.add(const Duration(seconds: 80));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('mini-played-progress')),
            )
            .widthFactor,
        .8,
      );
      expect(handler.currentPosition, Duration.zero);
      await show('A', seconds: 200);
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('mini-played-progress')),
            )
            .widthFactor,
        .4,
      );
      await show('B');
      await tester.pump();
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('mini-played-progress')),
            )
            .widthFactor,
        0,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(controller.positions.close());
      unawaited(handler.dispose());
    }
  });
  test('reorder helper follows post-removal target index semantics', () {
    final alpha = Track(id: 'alpha', title: 'Alpha', artist: 'A', album: '');
    final beta = Track(id: 'beta', title: 'Beta', artist: 'B', album: '');
    final gamma = Track(id: 'gamma', title: 'Gamma', artist: 'G', album: '');

    final movedToMiddle = reorderTracksForReorderableListView(
      [alpha, beta, gamma],
      0,
      1,
    );
    final movedToEnd = reorderTracksForReorderableListView(
      [alpha, beta, gamma],
      0,
      2,
    );

    expect(movedToMiddle.map((track) => track.id), ['beta', 'alpha', 'gamma']);
    expect(movedToEnd.map((track) => track.id), ['beta', 'gamma', 'alpha']);
    expect(reorderTargetIndexFromRawReorder(0, 1), 0);
    expect(reorderTargetIndexFromRawReorder(0, 2), 1);
    expect(reorderTargetIndexFromRawReorder(0, 3), 2);
    expect(reorderTargetIndexFromRawReorder(2, 0), 0);
  });

  testWidgets(
    'queue reflects live additions, selection, stale failures and closing',
    (tester) async {
      final handler = _WidgetAudioHandler();
      final controller = _QueueUiController(handler);
      const first = MediaItem(id: 'one', title: 'First', artist: 'Artist');
      const second = MediaItem(id: 'two', title: 'Second', artist: 'Artist');
      try {
        await tester.pumpWidget(_app(playbackController: controller));
        await tester.pumpAndSettle();
        handler.queue.add([first]);
        handler.emit(first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mini-player-queue')));
        await tester.pumpAndSettle();
        expect(find.text('当前队列 · 1'), findsOneWidget);
        handler.queue.add([first, second]);
        await tester.pump();
        await tester.pump();
        expect(find.text('当前队列 · 2'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('queue-item-one')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('queue-item-one')));
        expect(controller.requests.length, 1);
        await tester.tap(find.byKey(const ValueKey('queue-item-two')));
        await tester.pump();
        await tester.pump();
        controller.requests[1].complete();
        handler.emit(second);
        await tester.pumpAndSettle();
        controller.requests[0].completeError(StateError('obsolete failure'));
        await tester.pumpAndSettle();
        expect(find.textContaining('obsolete failure'), findsNothing);
        expect(
          tester
              .widget<ListTile>(find.byKey(const ValueKey('queue-item-two')))
              .selected,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('queue-item-one')));
        await tester.pump();
        await tester.pump();
        controller.requests[2].completeError(StateError('source unavailable'));
        await tester.pumpAndSettle();
        expect(find.textContaining('source unavailable'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('queue-item-two')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        controller.requests[3].completeError(StateError('closed failure'));
        await tester.pumpAndSettle();
        expect(find.byType(PlaybackQueue), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(handler.dispose());
      }
    },
  );

  testWidgets(
    'mini progress clamps real time and cached state; unknown duration stays empty',
    (tester) async {
      final handler = _WidgetAudioHandler();
      final controller = _QueueUiController(handler);
      Future<void> show(MediaItem item, PlaybackState state) =>
          tester.pumpWidget(
            MaterialApp(
              theme: MusicAppTheme.create(Brightness.light),
              home: Scaffold(
                body: MiniPlaybackProgress(
                  controller: controller,
                  item: item,
                  state: state,
                ),
              ),
            ),
          );
      double fraction(String key) => tester
          .widget<FractionallySizedBox>(find.byKey(ValueKey(key)))
          .widthFactor!;
      try {
        await show(
          const MediaItem(
            id: 'one',
            title: 'First',
            duration: Duration(seconds: 100),
          ),
          PlaybackState(bufferedPosition: const Duration(seconds: 60)),
        );
        controller.positions.add(const Duration(seconds: 25));
        await tester.pump();
        await tester.pump();
        expect(fraction('mini-played-progress'), .25);
        expect(fraction('mini-buffered-progress'), .6);
        controller.positions.add(const Duration(seconds: 200));
        await tester.pump();
        await tester.pump();
        expect(fraction('mini-played-progress'), 1);
        controller.songCacheProgress.completeKeys({'unresolved|one'});
        await tester.pump();
        await tester.pump();
        expect(fraction('mini-buffered-progress'), 1);
        await show(
          const MediaItem(id: 'one', title: 'First'),
          PlaybackState(bufferedPosition: const Duration(seconds: 60)),
        );
        await tester.pump();
        await tester.pump();
        expect(fraction('mini-played-progress'), 0);
        expect(fraction('mini-buffered-progress'), 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(controller.positions.close());
        unawaited(handler.dispose());
      }
    },
  );

  testWidgets(
    'normal phone player exposes playback controls and queue without scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handler = _WidgetAudioHandler();
      final controller = _QueueUiController(handler);
      try {
        await tester.pumpWidget(_app(playbackController: controller));
        await tester.pumpAndSettle();
        handler.emit(
          const MediaItem(
            id: 'phone',
            title: 'Phone song',
            artist: 'Artist',
            duration: Duration(minutes: 3),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Phone song'));
        await tester.pumpAndSettle();
        final queue = find.byKey(const ValueKey('playback-queue'));
        expect(queue.hitTestable(), findsOneWidget);
        expect(tester.getRect(queue).bottom, lessThanOrEqualTo(851));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(controller.positions.close());
        unawaited(handler.dispose());
      }
    },
  );

  testWidgets(
    'all main routes and long queue stay usable at 320dp with large type',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final language in AppLanguage.values) {
        for (final mode in AppThemePreference.values) {
          final fixture = _homeLibraryFixture();
          final handler = _WidgetAudioHandler();
          final controller = _QueueUiController(handler, fixture: fixture);
          controller.language = language;
          controller.themePreference = mode;
          final strings = AppStrings(language);
          try {
            await tester.pumpWidget(
              _app(
                playbackController: controller,
                textScaler: TextScaler.linear(2),
              ),
            );
            await tester.pumpAndSettle();
            await controller.saveLanguage(language);
            await controller.saveTheme(mode);
            await tester.pumpAndSettle();
            handler.queue.add([
              for (var i = 0; i < 50; i++)
                MediaItem(
                  id: '$i',
                  title: '很长的歌曲名称 Very long title $i',
                  artist: 'Artist name',
                ),
            ]);
            handler.emit(handler.queue.value.first);
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('mini-player-queue')));
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('queue-item-49')),
              200,
              scrollable: find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              ),
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byTooltip('Close'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byTooltip(strings.isZh ? '音乐库' : 'Music library'),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.textContaining(strings.localLibrary));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pageBack();
            await tester.pumpAndSettle();
            await tester.pageBack();
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip(strings.settings));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pageBack();
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip(strings.downloads));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pageBack();
            await tester.pumpAndSettle();
            await tester.tap(find.text('很长的歌曲名称 Very long title 0'));
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('playback-queue')),
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(PlayerPage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(
              find.byKey(const ValueKey('playback-queue')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            unawaited(controller.positions.close());
            unawaited(handler.dispose());
          }
        }
      }
    },
  );

  testWidgets('renders Android-first search and cache shell', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('搜音乐'), findsNothing);
    expect(find.text('歌手或歌曲'), findsOneWidget);
    expect(find.text('我的音乐'), findsOneWidget);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip('音乐库'), findsOneWidget);
    expect(find.text('No cached music yet'), findsNothing);
  });

  testWidgets('mini player and song page swipe between songs', (tester) async {
    final handler = _WidgetAudioHandler();
    final controller = _SwipePlaybackController(handler);
    try {
      await tester.pumpWidget(_app(playbackController: controller));
      await tester.pumpAndSettle();
      handler.emit(
        const MediaItem(
          id: 'swipe-song',
          title: 'Swipe Song',
          artist: 'Singer',
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pumpAndSettle();

      final miniPlayer = find.byKey(const ValueKey('mini-player-swipe-area'));
      expect(miniPlayer, findsOneWidget);
      await tester.drag(miniPlayer, const Offset(-140, 0));
      await tester.pump();
      expect(controller.nextCalls, 1);
      await tester.drag(miniPlayer, const Offset(140, 0));
      await tester.pump();
      expect(controller.previousCalls, 1);
      await tester.drag(miniPlayer, const Offset(30, 0));
      await tester.pump();
      expect(controller.nextCalls, 1);
      expect(controller.previousCalls, 1);
      expect(find.byType(PlayerPage), findsNothing);

      await tester.tap(find.text('Swipe Song'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      final player = find.byKey(const ValueKey('player-swipe-area'));
      // The responsive layout may place a seek slider at the page center.
      // Exercise song changes on artwork, and seeking on the slider below.
      final artwork = find.byKey(const ValueKey('player-artwork'));
      await tester.drag(artwork, const Offset(-140, 0));
      await tester.pump();
      expect(controller.nextCalls, 2);
      await tester.drag(artwork, const Offset(140, 0));
      await tester.pump();
      expect(controller.previousCalls, 2);

      await tester.drag(player, const Offset(0, -500));
      await tester.pump();
      expect(controller.nextCalls, 2);
      expect(controller.previousCalls, 2);
      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pump();
      expect(controller.nextCalls, 2);
      expect(controller.previousCalls, 2);
      expect(controller.seekCalls, 1);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('lyrics-preview')),
        -180,
        scrollable: find.descendant(
          of: player,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('lyrics-preview'))) +
            const Offset(24, 18),
      );
      await tester.pumpAndSettle();
      final lyrics = find.byKey(const ValueKey('lyrics-swipe-area'));
      expect(lyrics, findsOneWidget);
      await tester.drag(lyrics, const Offset(-140, 0));
      await tester.pump();
      expect(controller.nextCalls, 3);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('home stays usable on a narrow screen with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final language in AppLanguage.values) {
      for (final theme in AppThemePreference.values) {
        final fixture = _homeLibraryFixture();
        fixture.playlistStore.library = fixture.playlistStore.library.copyWith(
          playlists: [
            fixture.playlistStore.library.playlists.first.copyWith(
              name: '很长的歌单名称 Long playlist name with many songs',
            ),
          ],
        );
        final settings = _FakeSettingsStore()
          ..settings = MusicAppSettings(language: language, theme: theme);
        final handler = _WidgetAudioHandler();
        await tester.pumpWidget(
          _app(
            cacheStore: fixture.cacheStore,
            playlistStore: fixture.playlistStore,
            settings: settings,
            audioHandler: handler,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();
        handler.emit(
          const MediaItem(
            id: 'narrow',
            title: '很长的歌曲标题 Long song title',
            artist: '很长的歌手名称 Long artist name',
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final favorite = find.byKey(const ValueKey('home-favorites-entry'));
        final before = tester.getTopLeft(favorite).dy;
        await tester.tap(find.byKey(const ValueKey('search-mode-toggle')));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(favorite).dy, before);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(EditableText));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('search-history-panel')),
          findsOneWidget,
        );
        expect(favorite, findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(favorite, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('home defaults to favorite and custom playlist summaries', (
    tester,
  ) async {
    final fixture = _homeLibraryFixture();
    await tester.pumpWidget(
      _app(
        cacheStore: fixture.cacheStore,
        playlistStore: fixture.playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的音乐'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-favorites-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-playlist-road')), findsOneWidget);
    expect(find.text('1 首 · Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('发现')).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('home-playlist-road')))
            .dy,
      ),
    );
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-favorites-entry')));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-playlist-road')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-playlist-road')));
    await tester.pumpAndSettle();

    expect(find.text('Road'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('search results hide home default library summaries', (
    tester,
  ) async {
    final fixture = _homeLibraryFixture();
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(
      _app(
        resolver: resolver,
        cacheStore: fixture.cacheStore,
        playlistStore: fixture.playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-favorites-entry')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-favorites-entry')), findsNothing);
    expect(find.byKey(const ValueKey('home-playlist-road')), findsNothing);
  });

  testWidgets('clearing search restores home default library summaries', (
    tester,
  ) async {
    final fixture = _homeLibraryFixture();
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(
      _app(
        resolver: resolver,
        cacheStore: fixture.cacheStore,
        playlistStore: fixture.playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-favorites-entry')), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-history-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-favorites-entry')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-favorites-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-playlist-road')), findsOneWidget);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);
  });

  testWidgets(
    'focus shows compact history, long press deletes, back restores home',
    (tester) async {
      final fixture = _homeLibraryFixture();
      final history = _MemorySearchHistoryStore();
      await history.record(SearchHistoryKind.song, '稻香');
      await history.record(SearchHistoryKind.song, '晴天');
      await history.record(SearchHistoryKind.playlist, '儿童歌曲');
      await tester.pumpWidget(
        _app(
          cacheStore: fixture.cacheStore,
          playlistStore: fixture.playlistStore,
          searchHistoryStore: history,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search-history-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-favorites-entry')), findsNothing);
      expect(find.byKey(const ValueKey('home-playlist-road')), findsNothing);
      expect(find.byKey(const ValueKey('search-history-稻香')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-history-晴天')), findsOneWidget);
      expect(find.text('儿童歌曲'), findsNothing);

      await tester.longPress(find.byKey(const ValueKey('search-history-稻香')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('search-history-delete-稻香')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('search-history-delete-晴天')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('search-history-delete-稻香')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-history-稻香')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-history-panel')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-favorites-entry')),
        findsOneWidget,
      );
      expect(history.entries(SearchHistoryKind.song), ['晴天']);

      await tester.tap(find.byKey(const ValueKey('search-mode-toggle')));
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-history-儿童歌曲')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-history-晴天')), findsNothing);
    },
  );

  testWidgets('history card submits search and returns to results after back', (
    tester,
  ) async {
    final history = _MemorySearchHistoryStore();
    await history.record(SearchHistoryKind.song, '周杰伦');
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(
      _app(resolver: resolver, searchHistoryStore: history),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-history-周杰伦')));
    await tester.pumpAndSettle();
    expect(find.text('稻香'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-history-panel')), findsNothing);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('稻香'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('稻香'), findsOneWidget);
  });

  testWidgets('empty search does not call resolver', (tester) async {
    final resolver = _FakeMusicResolver();
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pump();

    expect(resolver.searchCount, 0);
  });

  testWidgets('search displays online candidates', (tester) async {
    final resolver = _FakeMusicResolver(
      candidates: [
        for (var i = 0; i < 12; i += 1)
          _candidate(
            id: 'song-$i',
            name: '稻香 $i',
            artist: '周杰伦',
            album: '叶惠美',
            source: MusicDataSource.flac,
            platform: 'kuwo',
            quality: const MusicQuality(format: 'flac', size: '30MB'),
          ),
      ],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(resolver.lastQuery, '周杰伦');
    expect(resolver.lastSource, MusicDataSource.flac);
    expect(find.text('稻香 0'), findsOneWidget);
    expect(find.text('FLAC'), findsWidgets);
    expect(find.textContaining('BuguYY'), findsNothing);
    expect(find.textContaining('kuwo'), findsNothing);
    expect(find.textContaining('03:20'), findsNothing);
    expect(find.textContaining('30MB'), findsWidgets);
    expect(find.textContaining('FLAC · 30MB'), findsNothing);
    expect(
      tester.getSize(find.byType(ListView).first).height,
      greaterThan(300),
    );
    expect(
      find.text(
        'Tap a result to download it into Playlists and start playback.',
      ),
      findsNothing,
    );
  });

  testWidgets('search play shows progress and a visible failure', (
    tester,
  ) async {
    final resolver = _DeferredFailingMusicResolver(
      candidates: [
        _candidate(
          name: '哎呀',
          artist: '王蓉',
          source: MusicDataSource.flac,
          platform: 'kuwo',
        ),
      ],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '王蓉');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-play-spinner')), findsOneWidget);

    resolver.fail(StateError('音源暂不可播放'));
    await tester.pump();
    expect(find.textContaining('音源暂不可播放'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-play-spinner')), findsNothing);
  });

  testWidgets('late audio failure is visible after play starts', (
    tester,
  ) async {
    final handler = MusicAudioHandler();
    await tester.pumpWidget(_app(audioHandler: handler));
    await tester.pumpAndSettle();

    handler.playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.error,
        errorMessage: '音频连接中断',
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('音频连接中断'), findsOneWidget);
  });

  testWidgets(
    'auto search shows first source while another source is loading',
    (tester) async {
      final resolver = _ProgressiveMusicResolver();
      await tester.pumpWidget(
        _app(
          resolver: resolver,
          settings: _FakeSettingsStore()
            ..settings = const MusicAppSettings(source: MusicDataSource.auto),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '晴天');
      await tester.tap(find.byTooltip('在线搜索'));
      await tester.pump();
      expect(resolver.lastSource, MusicDataSource.auto);

      resolver.emit(
        MusicSearchProgress(
          candidates: [_candidate(name: '先回来的歌', artist: '歌手')],
          isComplete: false,
        ),
      );
      await tester.pump();

      expect(find.text('先回来的歌'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      resolver.emit(
        MusicSearchProgress(
          candidates: [
            _candidate(name: '先回来的歌', artist: '歌手'),
            _candidate(id: 'song-2', name: '后回来的歌', artist: '歌手'),
          ],
          isComplete: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('先回来的歌'), findsOneWidget);
      expect(find.text('后回来的歌'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('flac source does not repeat flac in candidate subtitle', (
    tester,
  ) async {
    final resolver = _FakeMusicResolver(
      candidates: [
        _candidate(
          id: 'flac-song',
          name: '黑夜传说',
          artist: '杨世伟',
          source: MusicDataSource.flac,
          platform: 'kuwo',
          quality: const MusicQuality(format: 'flac', size: '16.3Mb'),
        ),
      ],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '黑夜传说');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(find.text('FLAC'), findsOneWidget);
    expect(find.textContaining('16.3Mb'), findsOneWidget);
    expect(find.textContaining('FLAC · 16.3Mb'), findsNothing);
    expect(find.textContaining('flac'), findsNothing);
  });

  testWidgets('clearing search input hides online candidates', (tester) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsNothing);
    expect(find.byKey(const ValueKey('search-history-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-favorites-entry')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的音乐'), findsOneWidget);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);
  });

  testWidgets('downloaded search result exposes play action', (tester) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_for_offline));
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('重新下载'), findsOneWidget);
  });

  testWidgets('playback cache still offers a first manual download', (
    tester,
  ) async {
    final music = _resolvedMusic();
    final cache = _FakeCacheStore(
      cached: [
        CachedTrack(
          cacheId: cacheIdForResolved(music),
          music: music,
          filePath: '/tmp/song-1.mp3',
          sizeBytes: 4,
          fromCache: false,
          playbackCache: true,
        ),
      ],
    );
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(_app(resolver: resolver, cacheStore: cache));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    final downloadButton = find.ancestor(
      of: find.byIcon(Icons.download_for_offline),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(downloadButton).tooltip, '下载');
    expect(find.byTooltip('重新下载'), findsNothing);

    await tester.tap(find.byIcon(Icons.download_for_offline));
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(downloadButton).tooltip, '重新下载');
  });

  testWidgets('download completion exposes play before metadata refresh', (
    tester,
  ) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    final metadata = _BlockingMetadataRepository();
    await tester.pumpWidget(
      _app(resolver: resolver, metadataRepository: metadata),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_for_offline));
    for (var i = 0; i < 6 && find.byTooltip('重新下载').evaluate().isEmpty; i++) {
      await tester.pump();
    }

    expect(metadata.loadCount, 1);
    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('重新下载'), findsOneWidget);

    metadata.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('download status snack does not move search results', (
    tester,
  ) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(find.text('稻香')).dy;

    await tester.tap(find.byIcon(Icons.download_for_offline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已下载到缓存'), findsOneWidget);
    expect(tester.getTopLeft(find.text('稻香')).dy, before);
  });

  testWidgets('completed downloads leave active section and enter cache', (
    tester,
  ) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download_for_offline));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();

    expect(find.text('没有正在下载的任务'), findsOneWidget);
    expect(find.text('稻香'), findsAtLeastNWidgets(2));
    expect(find.textContaining('已完成'), findsOneWidget);
  });

  testWidgets(
    'scrolling local songs does not create playback subscriptions per row',
    (tester) async {
      final cache = _FakeCacheStore(
        cached: [
          for (var i = 0; i < 80; i++)
            CachedTrack(
              cacheId: cacheIdForResolved(
                _resolvedMusic(id: '$i', name: 'Song $i'),
              ),
              music: _resolvedMusic(id: '$i', name: 'Song $i'),
              filePath: '/tmp/$i.mp3',
              sizeBytes: 4,
              fromCache: true,
              cachedAt: DateTime.now(),
            ),
        ],
      );
      final controller = _CountingPlaybackController(cache);
      await tester.pumpWidget(_app(playbackController: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('音乐库'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('本地'));
      await tester.pumpAndSettle();
      final before = controller.subscriptions;
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -1300),
      );
      await tester.pumpAndSettle();
      expect(controller.subscriptions, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('download manager can sort cached tracks', (tester) async {
    final older = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'alpha', name: 'Alpha')),
      music: _resolvedMusic(id: 'alpha', name: 'Alpha'),
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
      cachedAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    final newer = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'beta', name: 'Beta')),
      music: _resolvedMusic(id: 'beta', name: 'Beta'),
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
      cachedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      _app(cacheStore: _FakeCacheStore(cached: [older, newer])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Alpha'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.scrollUntilVisible(
      find.text('下载时间'),
      -100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首字母').last);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
  });

  testWidgets(
    'recent tasks collapse and filter by date while active downloads stay visible',
    (tester) async {
      final now = DateTime.now();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: MusicAudioHandler(),
        downloadHistoryStore: MemoryDownloadHistory(),
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _FakeMetadataRepository(),
      );
      controller.downloadQueue.tasks = [
        DownloadTask(
          id: 'today',
          title: 'Today task',
          subtitle: '',
          status: DownloadTaskStatus.completed,
          finishedAt: now,
        ),
        DownloadTask(
          id: 'yesterday',
          title: 'Yesterday task',
          subtitle: '',
          status: DownloadTaskStatus.failed,
          finishedAt: DateTime(now.year, now.month, now.day - 1),
        ),
        const DownloadTask(
          id: 'active',
          title: 'Active task',
          subtitle: '',
          status: DownloadTaskStatus.resolving,
        ),
      ];
      await tester.pumpWidget(_app(playbackController: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('下载'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('今天 · 下载 1 首'), findsOneWidget);
      await tester.tap(find.text('今天 · 下载 1 首'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Today task'), findsNothing);
      expect(find.text('Yesterday task'), findsOneWidget);
      await tester.tap(find.byTooltip('按日期筛选'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('选择一天'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime(now.year, now.month, now.day - 1));
      await tester.pump();
      await tester.tap(find.text('确定'));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('今天 · 下载 1 首'), findsNothing);
      expect(find.text('Yesterday task'), findsOneWidget);
      expect(find.text('Active task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local dates group songs and search counts only visible songs', (
    tester,
  ) async {
    final now = DateTime.now();
    final cached = [
      for (final entry in [
        ('Alpha', now),
        ('Beta', now),
        ('Gamma', DateTime(now.year, now.month, now.day - 1)),
      ])
        CachedTrack(
          cacheId: cacheIdForResolved(
            _resolvedMusic(id: entry.$1, name: entry.$1),
          ),
          music: _resolvedMusic(id: entry.$1, name: entry.$1),
          filePath: '/tmp/${entry.$1}.mp3',
          sizeBytes: 4,
          fromCache: true,
          cachedAt: entry.$2,
        ),
    ];
    await tester.pumpWidget(_app(cacheStore: _FakeCacheStore(cached: cached)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    expect(find.text('今天 · 2 首'), findsOneWidget);
    expect(find.text('昨天 · 1 首'), findsOneWidget);
    await tester.tap(find.text('今天 · 2 首'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsOneWidget);
    await tester.tap(find.text('今天 · 2 首'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    await tester.tap(find.byTooltip('按日期筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择一天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(DateTime(now.year, now.month, now.day - 1));
    await tester.pump();
    await tester.tap(find.text('确定'));

    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Gamma'), findsOneWidget);
    await tester.tap(find.byTooltip('按日期筛选'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('全部日期').last,
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Alpha');
    await tester.pumpAndSettle();
    expect(find.text('今天 · 1 首'), findsOneWidget);
    expect(find.text('昨天 · 1 首'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首字母').last);
    await tester.pumpAndSettle();
    expect(find.byType(DateGroupHeader), findsNothing);
  });

  testWidgets('download manager filters cached tracks by search text', (
    tester,
  ) async {
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'alpha', name: 'Alpha')),
      music: _resolvedMusic(id: 'alpha', name: 'Alpha'),
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
      cachedAt: DateTime(2026, 1, 1),
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'beta', name: 'Beta')),
      music: _resolvedMusic(id: 'beta', name: 'Beta'),
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
      cachedAt: DateTime(2026, 1, 2),
    );
    await tester.pumpWidget(
      _app(cacheStore: _FakeCacheStore(cached: [alpha, beta])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'alp');
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('returning from language settings does not retain row focus', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('language-setting'));
    await tester.scrollUntilVisible(tile, 180);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    final child = find
        .descendant(of: tile, matching: find.byType(Padding))
        .first;
    final focus = Focus.of(tester.element(child));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(find.text('中文'), findsOneWidget);
  });

  testWidgets('settings pages persist language theme and music source', (
    tester,
  ) async {
    final settings = _FakeSettingsStore();
    await tester.pumpWidget(_app(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('语言'), 180);
    await tester.ensureVisible(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('英文'));
    await tester.pumpAndSettle();

    expect(settings.settings.language, AppLanguage.en);
    expect(find.text('Language'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(settings.settings.theme, AppThemePreference.light);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    settings.savedSource = null;
    await tester.scrollUntilVisible(find.text('Music Source'), -200);
    await tester.ensureVisible(find.text('Music Source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music Source'));
    await tester.pumpAndSettle();

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('BuguYY'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);

    await tester.tap(find.text('BuguYY'));
    await tester.pumpAndSettle();
    expect(settings.savedSource, MusicDataSource.buguyy);
    expect(settings.settings.source, MusicDataSource.buguyy);
    await tester.tap(find.text('FLAC'));
    await tester.pumpAndSettle();

    expect(settings.savedSource, MusicDataSource.flac);
    expect(settings.settings.source, MusicDataSource.flac);
  });

  testWidgets(
    'settings groups related options and keeps concurrency together',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();

      expect(find.text('播放与下载'), findsOneWidget);
      expect(find.text('性能与并发'), findsOneWidget);
      expect(find.text('存储空间'), findsOneWidget);
      expect(
        find.byKey(const Key('screenshotSearchConcurrencySlider')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('playlistDownloadConcurrencySlider')),
        findsNothing,
      );

      final concurrency = find.byKey(const Key('concurrency-settings'));
      await tester.scrollUntilVisible(concurrency, 150);
      await tester.ensureVisible(concurrency);
      await tester.pumpAndSettle();
      expect(find.text('性能与并发'), findsOneWidget);
      await tester.tap(concurrency);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('screenshotSearchConcurrencySlider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('playlistDownloadConcurrencySlider')),
        findsOneWidget,
      );
    },
  );

  testWidgets('LAN library settings save address and test connection', (
    tester,
  ) async {
    final settings = _FakeSettingsStore();
    final gateway = _WidgetLanGateway();
    await tester.pumpWidget(_app(settings: settings, lanGateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('局域网音乐库'), 200);
    await tester.ensureVisible(find.text('局域网音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('局域网音乐库'));
    await tester.pumpAndSettle();

    expect(find.text('局域网音乐库地址'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('lanLibraryUrlField')),
      'http://10.0.0.9:9000/',
    );
    await tester.tap(find.text('保存地址'));
    await tester.pumpAndSettle();

    expect(settings.settings.lanLibraryUrl, 'http://10.0.0.9:9000');

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(gateway.testedUrls, ['http://10.0.0.9:9000']);
    expect(find.text('连接成功，共 4 首'), findsOneWidget);
  });

  testWidgets('screenshot search slider saves the 1–10 range', (tester) async {
    final settings = _FakeSettingsStore();
    await tester.pumpWidget(_app(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final concurrency = find.byKey(const Key('concurrency-settings'));
    await tester.scrollUntilVisible(concurrency, 150);
    await tester.ensureVisible(concurrency);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('screenshotSearchConcurrencySlider')),
      findsNothing,
    );
    await tester.tap(concurrency);
    await tester.pumpAndSettle();
    final slider = find.byKey(const Key('screenshotSearchConcurrencySlider'));
    expect(slider, findsOneWidget);
    expect(find.text('同时搜索 3 首，范围 1～10 首'), findsOneWidget);

    await tester.drag(slider, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(settings.settings.screenshotSearchConcurrency, 10);
    expect(find.text('同时搜索 10 首，范围 1～10 首'), findsOneWidget);

    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(settings.settings.screenshotSearchConcurrency, 1);
    expect(find.text('同时搜索 1 首，范围 1～10 首'), findsOneWidget);
  });

  testWidgets('playlist download slider saves the 1–10 range', (tester) async {
    final settings = _FakeSettingsStore();
    await tester.pumpWidget(_app(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final concurrency = find.byKey(const Key('concurrency-settings'));
    await tester.scrollUntilVisible(concurrency, 150);
    await tester.ensureVisible(concurrency);
    await tester.pumpAndSettle();
    await tester.tap(concurrency);
    await tester.pumpAndSettle();
    final slider = find.byKey(const Key('playlistDownloadConcurrencySlider'));
    await tester.scrollUntilVisible(slider, 150);
    expect(find.text('同时下载 3 首，范围 1～10 首'), findsOneWidget);

    await tester.drag(slider, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(settings.settings.playlistDownloadConcurrency, 10);

    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(settings.settings.playlistDownloadConcurrency, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 首'), findsOneWidget);
    expect(find.text('3 首'), findsOneWidget);
  });

  testWidgets('download quality is saved and playlists do not auto-download', (
    tester,
  ) async {
    final settings = _FakeSettingsStore();
    final controller = _RecordingPlaylistDownloadController(
      _homeLibraryFixture(),
      wifi: true,
    );
    await tester.pumpWidget(_app(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final quality = find.byKey(const Key('default-download-quality'));
    await tester.scrollUntilVisible(quality, 150);
    await tester.tap(quality);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('download-quality-low')));
    await tester.pumpAndSettle();
    expect(settings.settings.defaultDownloadQuality, MusicQualityLevel.low);
    expect(
      find.byKey(const Key('downloadPlaylistsOnWifiSwitch')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-playlist-road')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-playlist-road')));
    await tester.pumpAndSettle();
    expect(controller.requests, isEmpty);
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(controller.requests, isEmpty);
    expect(find.byKey(const ValueKey('download-all-playlist')), findsOneWidget);
  });

  testWidgets('playlist download action hides while searching', (tester) async {
    final controller = _RecordingPlaylistDownloadController(
      _homeLibraryFixture(),
      wifi: false,
    );
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-playlist-road')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-playlist-road')));
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('download-all-playlist'));
    expect(action, findsOneWidget);
    expect(find.text('一键全部下载'), findsNothing);
    expect(find.byTooltip('一键全部下载'), findsOneWidget);
    final search = find.byType(TextField);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(action, findsNothing);

    await tester.enterText(search, 'road');
    await tester.pumpAndSettle();
    expect(action, findsNothing);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(action, findsNothing);

    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
  });

  testWidgets('custom playlist offers manual download without Wi-Fi', (
    tester,
  ) async {
    final controller = _RecordingPlaylistDownloadController(
      _homeLibraryFixture(),
      wifi: false,
    );
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-playlist-road')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-playlist-road')));
    await tester.pumpAndSettle();
    expect(controller.requests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('download-all-playlist')));
    await tester.pumpAndSettle();
    expect(controller.requests, [false]);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('已缓存 1 首'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'playlist and download manager show batch progress then hide it',
    (tester) async {
      final controller =
          _RecordingPlaylistDownloadController(
              _homeLibraryFixture(),
              wifi: false,
            )
            ..progress = const PlaylistDownloadProgress(
              total: 1,
              processed: 0,
              failed: 0,
            );
      await tester.pumpWidget(_app(playbackController: controller));
      await tester.pumpAndSettle();

      expect(find.text('(1/1)'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-playlist-road')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-playlist-road')));
      await tester.pumpAndSettle();
      expect(find.text('(1/1)'), findsNothing);
      expect(
        find.byKey(const ValueKey('playlist-progress-road')),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下载'));
      await tester.pumpAndSettle();
      expect(find.text('歌曲 1 首 · 已下载 1 首'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('playlist-progress-road')),
        findsOneWidget,
      );

      controller.progress = null;
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('歌曲 1 首 · 已下载 1 首'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('playlist-progress-road')),
        findsNothing,
      );
    },
  );

  testWidgets('home download icon spins during work and still opens manager', (
    tester,
  ) async {
    final controller = _RecordingPlaylistDownloadController(
      _homeLibraryFixture(),
      wifi: false,
    );
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-download-spinner')), findsNothing);

    controller.downloadActive = true;
    controller.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('home-download-spinner')), findsOneWidget);
    await tester.tap(find.byTooltip('下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('下载管理'), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    controller.downloadActive = false;
    controller.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('home-download-spinner')), findsNothing);
    expect(find.byIcon(Icons.download), findsOneWidget);
  });

  testWidgets('download manager playlist button starts its whole batch', (
    tester,
  ) async {
    final controller = _RecordingPlaylistDownloadController(
      _homeLibraryFixture(),
      wifi: false,
    );
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 1 首 · 已下载 1 首'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manager-download-road')));
    await tester.pumpAndSettle();
    expect(controller.requests, [false]);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('已缓存 1 首'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('download manager playlist row opens its detail', (tester) async {
    final controller = _RecordingPlaylistDownloadController(
      _homeLibraryFixture(),
      wifi: false,
    );
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('download-all-playlist')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(controller.requests, isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manager-download-road')), findsOneWidget);
  });

  testWidgets('download manager offers LAN scan and shows result', (
    tester,
  ) async {
    final useCase = _WidgetLanSyncUseCase();
    await tester.pumpWidget(_app(lanSyncUseCase: useCase));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();

    expect(find.text('扫描并同步'), findsOneWidget);
    await tester.ensureVisible(find.text('扫描并同步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描并同步'));
    await tester.pumpAndSettle();

    expect(useCase.calls, 1);
    expect(find.textContaining('新增 1 首'), findsOneWidget);
    expect(find.textContaining('跳过 2 首'), findsOneWidget);
    expect(find.textContaining('新建 1 个歌单'), findsOneWidget);
    expect(find.textContaining('更新 1 个歌单'), findsOneWidget);
    expect(find.text('歌曲已保存，但歌单整理失败，可再次同步重试。'), findsOneWidget);
  });

  testWidgets('home back clears search then asks before exiting', (
    tester,
  ) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '稻香', artist: '周杰伦')],
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('在线搜索'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.controller?.text, isEmpty);
    expect(find.text('稻香'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('再按一次返回桌面'), findsOneWidget);
  });

  testWidgets('download entry opens manager and cached tracks can be deleted', (
    tester,
  ) async {
    final cache = _FakeCacheStore(
      cached: [
        CachedTrack(
          cacheId: cacheIdForResolved(_resolvedMusic()),
          music: _resolvedMusic(),
          filePath: '/tmp/song-1.mp3',
          sizeBytes: 4,
          fromCache: true,
        ),
      ],
    );
    await tester.pumpWidget(_app(cacheStore: cache));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();

    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('修复老资源'), findsNothing);
    expect(find.text('稻香'), findsOneWidget);

    await tester.tap(find.byTooltip('删除'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(cache.cached, isEmpty);
  });

  testWidgets('cache library opens local detail for cached tracks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(
          cached: [
            CachedTrack(
              cacheId: cacheIdForResolved(_resolvedMusic()),
              music: _resolvedMusic(),
              filePath: '/tmp/song-1.mp3',
              sizeBytes: 4,
              fromCache: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsNothing);

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();

    expect(find.text('音乐库'), findsOneWidget);
    expect(find.textContaining('收藏'), findsOneWidget);
    expect(find.textContaining('本地'), findsOneWidget);
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);
    expect(find.textContaining('周杰伦'), findsOneWidget);
  });

  testWidgets(
    'uncached playlist play shows preparation and a visible failure',
    (tester) async {
      final candidate = _candidate(
        name: '偏向',
        artist: '孟维来',
        source: MusicDataSource.flac,
        platform: 'kuwo',
      );
      final saved = SavedOnlineTrack(candidate: candidate);
      final playlists = _FakePlaylistStore()
        ..library = PlaylistLibrary(
          playlists: [
            MusicPlaylist(
              id: 'imported',
              name: '截图歌单',
              entries: [
                PlaylistTrackEntry(
                  trackId: saved.trackId,
                  addedAt: DateTime(2026),
                  onlineTrack: saved,
                ),
              ],
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );
      final resolver = _DeferredFailingMusicResolver(candidates: [candidate]);
      await tester.pumpWidget(
        _app(resolver: resolver, playlistStore: playlists),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('音乐库'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('截图歌单').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('播放').first);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      resolver.fail(StateError('请求已过期'));
      await tester.pumpAndSettle();
      expect(find.text('播放失败：请求已过期'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('stale A-B-A play completion does not clear latest preparation', (
    tester,
  ) async {
    final alpha = SavedOnlineTrack(
      candidate: _candidate(id: 'alpha', name: 'Alpha', artist: 'A'),
    );
    final beta = SavedOnlineTrack(
      candidate: _candidate(id: 'beta', name: 'Beta', artist: 'B'),
    );
    final playlists = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'imported',
            name: '截图歌单',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.trackId,
                addedAt: DateTime(2026),
                onlineTrack: alpha,
              ),
              PlaylistTrackEntry(
                trackId: beta.trackId,
                addedAt: DateTime(2026),
                onlineTrack: beta,
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
    final controller = _ControlledPlaybackController(playlists);
    await tester.pumpWidget(_app(playbackController: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('截图歌单').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.tap(find.text('Beta'));
    await tester.pump();
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    expect(controller.pending, hasLength(3));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.pending[0].completeError(StateError('stale A'));
    controller.pending[1].completeError(StateError('stale B'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('stale A'), findsNothing);
    expect(find.textContaining('stale B'), findsNothing);

    controller.pending[2].completeError(StateError('latest A'));
    await tester.pumpAndSettle();
    expect(find.text('播放失败：latest A'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('local library track can be deleted from more actions', (
    tester,
  ) async {
    final cache = _FakeCacheStore(
      cached: [
        CachedTrack(
          cacheId: cacheIdForResolved(_resolvedMusic()),
          music: _resolvedMusic(),
          filePath: '/tmp/song-1.mp3',
          sizeBytes: 4,
          fromCache: true,
        ),
      ],
    );
    await tester.pumpWidget(_app(cacheStore: cache));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除本地音乐'));
    await tester.pumpAndSettle();

    expect(find.text('删除本地音乐？'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(cache.cached, isEmpty);
    expect(find.text('稻香'), findsNothing);
  });

  testWidgets('long press selection can batch add local tracks to playlist', (
    tester,
  ) async {
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'alpha', name: 'Alpha')),
      music: _resolvedMusic(id: 'alpha', name: 'Alpha'),
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'beta', name: 'Beta')),
      music: _resolvedMusic(id: 'beta', name: 'Beta'),
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: const [],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 2 首'), findsOneWidget);

    await tester.tap(find.byTooltip('添加到歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(playlistStore.library.playlists.single.trackIds, [
      beta.cacheId,
      alpha.cacheId,
    ]);
  });

  testWidgets('long press selection can batch delete local tracks', (
    tester,
  ) async {
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'alpha', name: 'Alpha')),
      music: _resolvedMusic(id: 'alpha', name: 'Alpha'),
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'beta', name: 'Beta')),
      music: _resolvedMusic(id: 'beta', name: 'Beta'),
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final cache = _FakeCacheStore(cached: [alpha, beta]);
    await tester.pumpWidget(_app(cacheStore: cache));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选当前列表'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 首'), findsOneWidget);
    await tester.tap(find.byTooltip('删除本地音乐'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(cache.cached, isEmpty);
  });

  testWidgets('cached track can be favorited into favorite detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(
          cached: [
            CachedTrack(
              cacheId: cacheIdForResolved(_resolvedMusic()),
              music: _resolvedMusic(),
              filePath: '/tmp/song-1.mp3',
              sizeBytes: 4,
              fromCache: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加到收藏'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('收藏'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);
  });

  testWidgets('favorite detail selection can batch remove tracks', (
    tester,
  ) async {
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'alpha', name: 'Alpha')),
      music: _resolvedMusic(id: 'alpha', name: 'Alpha'),
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'beta', name: 'Beta')),
      music: _resolvedMusic(id: 'beta', name: 'Beta'),
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        favoriteEntries: [
          PlaylistTrackEntry(trackId: alpha.cacheId, addedAt: DateTime(2026)),
          PlaylistTrackEntry(trackId: beta.cacheId, addedAt: DateTime(2026)),
        ],
        playlists: const [],
      );
    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('收藏'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除所选'));
    await tester.pumpAndSettle();

    expect(playlistStore.library.favoriteTrackIds, isEmpty);
  });

  testWidgets('add sheet scrolls many playlists and selects the last one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _homeLibraryFixture();
    fixture.playlistStore.library = PlaylistLibrary(
      favoriteEntries: const [],
      playlists: [
        for (var i = 0; i < 30; i++)
          MusicPlaylist(
            id: 'target-$i',
            name: 'Target $i',
            entries: const [],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
      ],
    );
    await tester.pumpWidget(
      _app(
        cacheStore: fixture.cacheStore,
        playlistStore: fixture.playlistStore,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加到歌单'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('新建歌单')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.descendant(of: sheet, matching: find.text('Target 29')),
      200,
      scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
    );
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Target 29')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(fixture.playlistStore.library.playlists.last.trackIds, [
      fixture.cacheStore.cached.first.cacheId,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new playlist from add sheet uses live parent context', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(
          cached: [
            CachedTrack(
              cacheId: cacheIdForResolved(_resolvedMusic()),
              music: _resolvedMusic(),
              filePath: '/tmp/song-1.mp3',
              sizeBytes: 4,
              fromCache: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加到歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建歌单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '车上');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('车上'), findsOneWidget);

    await tester.tap(find.text('车上'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);
  });

  testWidgets('library details sort by entry time and initial', (tester) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        favoriteEntries: [
          PlaylistTrackEntry(
            trackId: alpha.cacheId,
            addedAt: DateTime(2026, 1, 1),
          ),
          PlaylistTrackEntry(
            trackId: beta.cacheId,
            addedAt: DateTime(2026, 1, 2),
          ),
        ],
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('收藏'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首字母').last);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('排序'), findsNothing);
    expect(find.byTooltip('调整顺序'), findsOneWidget);
    expect(find.text('调整顺序'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
  });

  testWidgets('custom playlist order shows persisted playlist order', (
    tester,
  ) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    expect(find.byTooltip('排序'), findsNothing);
    expect(find.byTooltip('调整顺序'), findsOneWidget);
    expect(find.text('调整顺序'), findsNothing);
    expect(
      tester.getCenter(find.byKey(const ValueKey('adjust-order-action'))).dx,
      greaterThan(tester.getCenter(find.text('Road')).dx),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
  });

  testWidgets('custom order requires explicit edit mode before dragging', (
    tester,
  ) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('调整顺序'), findsOneWidget);
    expect(find.text('调整顺序'), findsNothing);
    expect(find.byTooltip('排序'), findsNothing);
    expect(find.byTooltip('拖拽排序'), findsNothing);
    expect(find.byTooltip('更多'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('adjust-order-action')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('拖拽排序'), findsNWidgets(2));
    expect(
      tester.getCenter(find.byTooltip('拖拽排序').first).dx,
      greaterThan(tester.getCenter(find.text('Alpha')).dx),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('save-order-action'))).dx,
      greaterThan(tester.getCenter(find.text('调整顺序')).dx),
    );
    expect(find.byTooltip('添加到歌单'), findsNothing);
  });

  testWidgets('order edit mode hides mini player navigation', (tester) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final handler = _WidgetAudioHandler();
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
        audioHandler: handler,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    handler.emit(
      MediaItem(
        id: alpha.cacheId,
        title: 'Mini Alpha',
        artist: 'A',
        duration: const Duration(minutes: 3),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mini Alpha'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('adjust-order-action')));
    await tester.pumpAndSettle();

    expect(find.text('Mini Alpha'), findsNothing);
  });

  testWidgets('custom order draft saves only when edit mode completes', (
    tester,
  ) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-order-action')));
    await tester.pumpAndSettle();

    final writesBeforeDrag = playlistStore.writeCount;
    await tester.drag(find.byTooltip('拖拽排序').first, const Offset(0, 220));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );
    expect(playlistStore.writeCount, writesBeforeDrag);
    expect(playlistStore.library.playlists.single.trackIds, [
      alpha.cacheId,
      beta.cacheId,
    ]);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(playlistStore.library.playlists.single.trackIds, [
      beta.cacheId,
      alpha.cacheId,
    ]);
  });

  testWidgets('custom order edit is blocked while search is active', (
    tester,
  ) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('adjust-order-action')));
    await tester.pumpAndSettle();

    expect(find.text('清除搜索后可调整顺序'), findsOneWidget);
    expect(find.byTooltip('拖拽排序'), findsNothing);
  });

  testWidgets('back from dirty order edit asks before discarding', (
    tester,
  ) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-order-action')));
    await tester.pumpAndSettle();
    await tester.drag(find.byTooltip('拖拽排序').first, const Offset(0, 220));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('放弃本次排序调整？'), findsOneWidget);

    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('拖拽排序'), findsNothing);
    expect(playlistStore.library.playlists.single.trackIds, [
      alpha.cacheId,
      beta.cacheId,
    ]);
  });

  testWidgets('favorite and custom playlist details filter visible tracks', (
    tester,
  ) async {
    final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
    final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
    final alpha = CachedTrack(
      cacheId: cacheIdForResolved(alphaMusic),
      music: alphaMusic,
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final beta = CachedTrack(
      cacheId: cacheIdForResolved(betaMusic),
      music: betaMusic,
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
    );
    final playlistStore = _FakePlaylistStore()
      ..library = PlaylistLibrary(
        favoriteEntries: [
          PlaylistTrackEntry(
            trackId: alpha.cacheId,
            addedAt: DateTime(2026, 1, 1),
          ),
          PlaylistTrackEntry(
            trackId: beta.cacheId,
            addedAt: DateTime(2026, 1, 2),
          ),
        ],
        playlists: [
          MusicPlaylist(
            id: 'road',
            name: 'Road',
            entries: [
              PlaylistTrackEntry(
                trackId: alpha.cacheId,
                addedAt: DateTime(2026, 1, 1),
              ),
              PlaylistTrackEntry(
                trackId: beta.cacheId,
                addedAt: DateTime(2026, 1, 2),
              ),
            ],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

    await tester.pumpWidget(
      _app(
        cacheStore: _FakeCacheStore(cached: [alpha, beta]),
        playlistStore: playlistStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('音乐库'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('收藏'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'alp');
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'beta');
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
  });
}

Widget _app({
  MusicController? playbackController,
  _FakeMusicResolver? resolver,
  _FakeCacheStore? cacheStore,
  _FakePlaylistStore? playlistStore,
  _FakeSettingsStore? settings,
  TrackMetadataRepository? metadataRepository,
  MusicAudioHandler? audioHandler,
  LanLibraryGateway? lanGateway,
  LanSyncUseCase? lanSyncUseCase,
  SearchHistoryStore? searchHistoryStore,
  TextScaler? textScaler,
}) {
  final controller =
      playbackController ??
      MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: audioHandler ?? MusicAudioHandler(),
        resolver: resolver ?? _FakeMusicResolver(),
        cacheStore: cacheStore ?? _FakeCacheStore(),
        playlistStore: playlistStore ?? _FakePlaylistStore(),
        settingsStore: settings ?? _FakeSettingsStore(),
        metadataRepository: metadataRepository ?? _FakeMetadataRepository(),
        lanLibraryGateway: lanGateway,
        lanSyncUseCase: lanSyncUseCase,
      );
  return AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      return MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        darkTheme: MusicAppTheme.create(Brightness.dark),
        themeMode: controller.themePreference == AppThemePreference.light
            ? ThemeMode.light
            : ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: AppStringsScope(
            language: controller.language,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: MusicHomePage(
          controller: controller,
          searchHistoryStore: searchHistoryStore ?? _MemorySearchHistoryStore(),
        ),
      );
    },
  );
}

class _MemorySearchHistoryStore extends SearchHistoryStore {
  final _saved = <SearchHistoryKind, List<String>>{
    SearchHistoryKind.song: [],
    SearchHistoryKind.playlist: [],
  };

  @override
  Future<void> load() async {}

  @override
  List<String> entries(SearchHistoryKind kind) =>
      List.unmodifiable(_saved[kind]!);

  @override
  Future<void> record(SearchHistoryKind kind, String query) async {
    final term = query.trim();
    if (term.isEmpty) return;
    _saved[kind]!.remove(term);
    _saved[kind]!.insert(0, term);
  }

  @override
  Future<void> remove(SearchHistoryKind kind, String query) async {
    _saved[kind]!.remove(query);
  }
}

class _ControlledPlaybackController extends MusicController {
  _ControlledPlaybackController(_FakePlaylistStore playlists)
    : super(
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: MusicAudioHandler(),
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(),
        playlistStore: playlists,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _FakeMetadataRepository(),
      );

  final pending = <Completer<void>>[];

  @override
  Future<void> playTrack(
    Track track, {
    int? index,
    List<Track>? queueTracks,
    String? playlistId,
  }) {
    final completion = Completer<void>();
    pending.add(completion);
    return completion.future;
  }
}

class _SwipePlaybackController extends MusicController {
  _SwipePlaybackController(_WidgetAudioHandler handler)
    : super(
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _FakeMetadataRepository(),
      );

  int nextCalls = 0;
  int previousCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> next() async {
    nextCalls += 1;
  }

  @override
  Future<void> previous() async {
    previousCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls += 1;
  }
}

class _RecordingPlaylistDownloadController extends MusicController {
  _RecordingPlaylistDownloadController(
    _HomeLibraryFixture fixture, {
    required this.wifi,
  }) : super(
         downloadHistoryStore: MemoryDownloadHistory(),
         audioHandler: MusicAudioHandler(),
         resolver: _FakeMusicResolver(),
         cacheStore: fixture.cacheStore,
         playlistStore: fixture.playlistStore,
         settingsStore: _FakeSettingsStore(),
         metadataRepository: _FakeMetadataRepository(),
       );

  bool wifi;
  final requests = <bool>[];
  final Set<String> _autoStartedPlaylists = {};
  final Set<String> _openedPlaylists = {};
  final List<bool> autoProgressChoices = [];
  PlaylistDownloadProgress? progress;
  bool downloadActive = false;
  PlaylistDownloadSummary autoResult = const PlaylistDownloadSummary(
    skipped: 1,
  );

  @override
  bool get isOnWifi => wifi;

  @override
  bool get isConnectivityKnown => true;

  @override
  bool get hasActiveDownloads => downloadActive;

  @override
  Future<bool> claimFirstPlaylistOpening(MusicPlaylist playlist) async =>
      _openedPlaylists.add(playlist.id);

  @override
  Future<PlaylistDownloadSummary>? startWifiPlaylistDownloadOnce(
    MusicPlaylist playlist, {
    bool showProgress = false,
  }) {
    if (!wifi || !_autoStartedPlaylists.add(playlist.id)) return null;
    autoProgressChoices.add(showProgress);
    return downloadPlaylist(playlist, wifiOnly: true);
  }

  @override
  PlaylistDownloadProgress? playlistDownloadProgress(MusicPlaylist playlist) =>
      progress;

  @override
  Future<PlaylistDownloadSummary> downloadPlaylist(
    MusicPlaylist playlist, {
    bool wifiOnly = false,
    MusicPlaylist? playlistSnapshot,
  }) async {
    requests.add(wifiOnly);
    return wifiOnly ? autoResult : const PlaylistDownloadSummary(skipped: 1);
  }
}

class _FakeMetadataRepository extends TrackMetadataRepository {
  final deletedIds = <String>[];

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    return const TrackMetadata();
  }

  @override
  Future<void> delete(String cacheId) async {
    deletedIds.add(cacheId);
  }
}

class _BlockingMetadataRepository extends TrackMetadataRepository {
  final _completer = Completer<TrackMetadata>();
  int loadCount = 0;

  @override
  Future<TrackMetadata> load(CachedTrack track) {
    loadCount += 1;
    return _completer.future;
  }

  void complete([TrackMetadata metadata = const TrackMetadata()]) {
    if (!_completer.isCompleted) {
      _completer.complete(metadata);
    }
  }
}

class _HomeLibraryFixture {
  const _HomeLibraryFixture({
    required this.cacheStore,
    required this.playlistStore,
  });

  final _FakeCacheStore cacheStore;
  final _FakePlaylistStore playlistStore;
}

_HomeLibraryFixture _homeLibraryFixture() {
  final alphaMusic = _resolvedMusic(id: 'alpha', name: 'Alpha', artist: 'A');
  final betaMusic = _resolvedMusic(id: 'beta', name: 'Beta', artist: 'B');
  final alpha = CachedTrack(
    cacheId: cacheIdForResolved(alphaMusic),
    music: alphaMusic,
    filePath: '/tmp/alpha.mp3',
    sizeBytes: 4,
    fromCache: true,
  );
  final beta = CachedTrack(
    cacheId: cacheIdForResolved(betaMusic),
    music: betaMusic,
    filePath: '/tmp/beta.mp3',
    sizeBytes: 4,
    fromCache: true,
  );
  final playlistStore = _FakePlaylistStore()
    ..library = PlaylistLibrary(
      favoriteEntries: [
        PlaylistTrackEntry(trackId: alpha.cacheId, addedAt: DateTime(2026)),
      ],
      playlists: [
        MusicPlaylist(
          id: 'road',
          name: 'Road',
          entries: [
            PlaylistTrackEntry(trackId: beta.cacheId, addedAt: DateTime(2026)),
          ],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
  return _HomeLibraryFixture(
    cacheStore: _FakeCacheStore(cached: [alpha, beta]),
    playlistStore: playlistStore,
  );
}

class _WidgetAudioHandler extends MusicAudioHandler {
  void emit(MediaItem? item) {
    mediaItem.add(item);
  }
}

class _FakePlaylistStore extends PlaylistStore {
  _FakePlaylistStore() : super(rootProvider: _unusedRootProvider);

  PlaylistLibrary library = const PlaylistLibrary.empty();
  int writeCount = 0;

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async {
    return _sanitize(library, validTrackIds);
  }

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {
    writeCount += 1;
    this.library = _sanitize(library, validTrackIds);
  }

  PlaylistLibrary _sanitize(PlaylistLibrary library, Set<String>? validIds) {
    List<PlaylistTrackEntry> filter(List<PlaylistTrackEntry> entries) {
      final unique = <PlaylistTrackEntry>[];
      final seen = <String>{};
      for (final entry in entries) {
        if (seen.add(entry.trackId) &&
            (validIds == null ||
                validIds.contains(entry.trackId) ||
                entry.onlineTrack != null ||
                entry.song != null)) {
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

class _FakeMusicResolver implements MusicResolver {
  _FakeMusicResolver({this.candidates = const []});

  final List<MusicSearchCandidate> candidates;
  int searchCount = 0;
  String? lastQuery;
  MusicDataSource? lastSource;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searchCount += 1;
    lastQuery = query;
    lastSource = source;
    return candidates;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    return _resolvedMusic();
  }
}

class _DeferredFailingMusicResolver extends _FakeMusicResolver {
  _DeferredFailingMusicResolver({super.candidates});

  final _resolution = Completer<ResolvedMusic>();

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) {
    return _resolution.future;
  }

  void fail(Object error) => _resolution.completeError(error);
}

class _ProgressiveMusicResolver extends _FakeMusicResolver
    implements ProgressiveMusicResolver {
  final _controller = StreamController<MusicSearchProgress>();

  @override
  Stream<MusicSearchProgress> searchProgressively(
    String query,
    MusicDataSource source,
  ) {
    searchCount += 1;
    lastQuery = query;
    lastSource = source;
    return _controller.stream;
  }

  void emit(MusicSearchProgress progress) {
    _controller.add(progress);
    if (progress.isComplete) {
      _controller.close();
    }
  }
}

class _FakeSettingsStore implements MusicSettingsStore {
  MusicAppSettings settings = const MusicAppSettings();
  MusicDataSource? savedSource;

  @override
  Future<MusicAppSettings> loadSettings() async {
    return settings;
  }

  @override
  Future<void> saveSettings(MusicAppSettings settings) async {
    savedSource = settings.source;
    this.settings = settings;
  }

  @override
  Future<MusicDataSource> loadSource() async {
    return settings.source;
  }

  @override
  Future<void> saveSource(MusicDataSource source) async {
    savedSource = source;
    settings = settings.copyWith(source: source);
  }
}

class _WidgetLanGateway implements LanLibraryGateway {
  final List<String> testedUrls = [];

  @override
  Future<LanLibraryHealth> testConnection(String baseUrl) async {
    testedUrls.add(baseUrl);
    return const LanLibraryHealth(schemaVersion: 1, trackCount: 4);
  }

  @override
  Future<LanLibraryManifest> fetchLibrary(String baseUrl) async {
    return LanLibraryManifest.fromJson({
      'schemaVersion': 1,
      'libraryId': 'widget',
      'generatedAt': '2026-08-02T00:00:00Z',
      'tracks': const [],
    });
  }

  @override
  Uri resolveAssetUri(String baseUrl, LanAsset asset) {
    return Uri.parse(baseUrl).resolveUri(asset.url);
  }

  @override
  Future<int> downloadAsset(String baseUrl, LanAsset asset, File target) {
    throw UnsupportedError('not used');
  }
}

class _WidgetLanSyncUseCase extends LanSyncUseCase {
  _WidgetLanSyncUseCase()
    : super(gateway: _WidgetLanGateway(), cacheStore: _FakeCacheStore());

  int calls = 0;

  @override
  Future<LanSyncResult> sync(
    String baseUrl, {
    void Function(LanSyncProgress progress)? onProgress,
  }) async {
    calls += 1;
    onProgress?.call(
      const LanSyncProgress(completed: 3, total: 3, currentTitle: '完成'),
    );
    return LanSyncResult(
      total: 3,
      added: 1,
      updated: 0,
      skipped: 2,
      failed: 0,
      failures: [],
      playlistsCreated: 1,
      playlistsUpdated: 1,
      playlistError: StateError('playlist write failed'),
    );
  }
}

class _FakeCacheStore extends CachedTrackStore {
  @override
  Future<Map<String, ({int bytes, int? total})>> partialProgress() async => {};

  _FakeCacheStore({List<CachedTrack> cached = const []}) : cached = [...cached];

  final List<CachedTrack> cached;

  @override
  Future<CachedTrack> downloadOrReuse(
    ResolvedMusic result, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCanceled();
    final track = CachedTrack(
      cacheId: cacheIdForResolved(result),
      music: result,
      filePath: '/tmp/${result.id}.mp3',
      sizeBytes: 4,
      fromCache: false,
    );
    cached
      ..removeWhere((item) => item.cacheId == track.cacheId)
      ..add(track);
    return track;
  }

  @override
  Future<List<CachedTrack>> listCached() async {
    return List<CachedTrack>.unmodifiable(cached);
  }

  @override
  Future<void> cleanupTemporaryFiles() async {}

  @override
  Future<void> deleteCached(String cacheId) async {
    cached.removeWhere((track) => track.cacheId == cacheId);
  }
}

Future<Directory> _unusedRootProvider() async {
  return Directory.systemTemp.createTemp('ai_music_unused_');
}

MusicSearchCandidate _candidate({
  String id = 'song-1',
  required String name,
  required String artist,
  MusicDataSource source = MusicDataSource.buguyy,
  String album = '',
  String platform = 'buguyy',
  MusicQuality quality = const MusicQuality(format: 'mp3'),
}) {
  return MusicSearchCandidate(
    query: artist,
    source: source,
    platform: platform,
    keyword: artist,
    page: 1,
    id: id,
    name: name,
    artist: artist,
    album: album,
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: [quality],
    score: 100,
    raw: const {},
  );
}

ResolvedMusic _resolvedMusic({
  String id = 'song-1',
  String name = '稻香',
  String artist = '周杰伦',
}) {
  return ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: id,
    name: name,
    artist: artist,
    album: '',
    url: 'https://cdn.example.test/$id.mp3',
    quality: const MusicQuality(format: 'mp3'),
  );
}

class _CountingPlaybackController extends MusicController {
  _CountingPlaybackController(_FakeCacheStore cache)
    : super(
        audioHandler: MusicAudioHandler(),
        downloadHistoryStore: MemoryDownloadHistory(),
        resolver: _FakeMusicResolver(),
        cacheStore: cache,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _FakeMetadataRepository(),
      );
  int subscriptions = 0;
  late final _countedStream = Stream<MediaItem?>.multi((sink) {
    subscriptions++;
    final sub = super.mediaItemStream.listen(sink.add);
    sink.onCancel = sub.cancel;
  }, isBroadcast: true);
  @override
  Stream<MediaItem?> get mediaItemStream => _countedStream;
}

class _QueueUiController extends MusicController {
  _QueueUiController(
    MusicAudioHandler handler, {
    _HomeLibraryFixture? fixture,
    ListeningStatsStore? stats,
  }) : super(
         audioHandler: handler,
         listeningStatsStore: stats,
         songSearchCache: SongSearchCache.memory(),
         downloadHistoryStore: MemoryDownloadHistory(),
         connectivityChanges: const Stream.empty(),
         resolver: _FakeMusicResolver(),
         cacheStore: fixture?.cacheStore ?? _FakeCacheStore(),
         playlistStore: fixture?.playlistStore ?? _FakePlaylistStore(),
         settingsStore: _FakeSettingsStore(),
         metadataRepository: _FakeMetadataRepository(),
       );
  final requests = <Completer<void>>[];
  final positions = StreamController<Duration>.broadcast();
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Future<void> playQueueItem(String id) {
    final done = Completer<void>();
    requests.add(done);
    return done.future;
  }
}

class _NavigationUiController extends _QueueUiController {
  _NavigationUiController(super.handler)
    : super(stats: ListeningStatsStore.memory());
  int initializeCalls = 0;
  String? playedTitle, playedPlaylist;
  int playedQueueLength = 0;
  @override
  Future<void> initialize() {
    initializeCalls++;
    return super.initialize();
  }

  @override
  Future<void> playTrack(
    Track track, {
    int? index,
    List<Track>? queueTracks,
    String? playlistId,
  }) async {
    playedTitle = track.title;
    playedPlaylist = playlistId;
    playedQueueLength = queueTracks?.length ?? 0;
  }
}
