import 'package:ai_music/src/presentation/playlist_sync_button.dart';
import 'package:ai_music/src/application/online_playlist_search.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ai_music/src/presentation/playback_queue.dart';
import 'package:ai_music/src/presentation/player_page.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/data/song_search_cache.dart';
import 'dart:async';
import 'dart:collection';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/presentation/download_manager_page.dart';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/online_playlist_importer.dart';
import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/online_playlists.dart';
import 'package:ai_music/src/presentation/music_home_page.dart';
import 'package:ai_music/src/presentation/online_playlist_page.dart';
import 'package:ai_music/src/presentation/direct_playlist_page.dart';
import 'package:ai_music/src/presentation/song_source_page.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'source picker re-searches and lets user select at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _SourceController(_Store());
      const track = Track(id: 'song', title: '稻香', artist: '周杰伦', album: '');
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showSongSourcePicker(context, controller, track),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(controller.searches, [MusicDataSource.flac]);
      expect(find.text('稻香'), findsOneWidget);
      expect(find.textContaining('kuwo'), findsOneWidget);
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(controller.searches.last, MusicDataSource.auto);
      await tester.tap(find.text('FLAC'));
      await tester.pumpAndSettle();
      expect(controller.searches.last, MusicDataSource.flac);
      await tester.tap(find.byKey(const ValueKey('song-source-0')));
      await tester.pumpAndSettle();
      expect(controller.chosen?.source, MusicDataSource.flac);
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'playlist more menu shows actual audio source and opens its picker',
    (tester) async {
      final store = _Store();
      final controller = _SourceController(store);
      final playlist = (await controller.importPlaylistCandidates('来源入口', [
        _candidate('First'),
      ]))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: MusicHomePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(ValueKey('home-playlist-${playlist.id}')),
      );
      await tester.tap(find.byKey(ValueKey('home-playlist-${playlist.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多').last);
      await tester.pumpAndSettle();
      expect(find.text('歌曲来源（布谷YY）'), findsOneWidget);
      await tester.tap(find.text('歌曲来源（布谷YY）'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSourcePage), findsOneWidget);
      expect(controller.searches, [MusicDataSource.flac]);
      await tester.tap(find.byTooltip('刷新来源'));
      await tester.pumpAndSettle();
      expect(controller.refreshes, [false, true]);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'direct playlist page saves metadata before starting background matching',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = _Store();
      var matchCalls = 0;
      final controller = _Controller(
        store,
        matcher: _Matcher((draft) async {
          expect(store.library.playlists.single.entries.length, 2);
          matchCalls++;
          return _match(draft.title);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: DirectPlaylistPage(
            playlist: OnlinePlaylist(
              source: _playlist.source,
              id: _playlist.id,
              name: '夜晚独处时慢慢聆听的华语经典珍藏歌单',
              creator: _playlist.creator,
              trackCount: _playlist.trackCount,
            ),
            repository: _Repository(),
            controller: controller,
            onOpenPlaylist: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('playlist-detail-title')),
      );
      expect(title.data, '夜晚独处时慢慢聆听的华语经典珍藏歌单');
      expect(title.maxLines, isNull);
      expect(title.softWrap, isTrue);
      expect(matchCalls, 0);
      await tester.tap(find.byKey(const ValueKey('direct-play-song-1')));
      await tester.pumpAndSettle();
      expect(controller.previewSongs.map((s) => s.title), ['Second']);
      expect(find.byKey(const ValueKey('mini-player-card')), findsOneWidget);
      expect(find.byType(MiniPlaybackProgress), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('mini-player-card')),
          matching: find.text('Second'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(PlayerPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.library.playlists, isEmpty);
      expect(matchCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('direct-new-playlist')));
      await tester.pumpAndSettle();
      expect(store.library.playlists.single.entries.length, 2);
      expect(
        store.library.playlists.single.entries.every(
          (e) => e.song != null && e.onlineTrack == null,
        ),
        isTrue,
      );
      expect(matchCalls, 2);
      expect(find.byKey(const Key('direct-open-playlist')), findsOneWidget);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'source playlist collapses its heading while keeping import controls visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _Controller(_Store());
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: DirectPlaylistPage(
            playlist: _playlist,
            repository: _LongRepository(),
            controller: controller,
            onOpenPlaylist: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playlist-detail-title')),
        findsOneWidget,
      );
      final scroll = find.byType(CustomScrollView);
      await tester.drag(scroll, const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playlist-compact-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('direct-new-playlist')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('direct-playlist-select-all')).hitTestable(),
        findsOneWidget,
      );
      await tester.drag(scroll, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playlist-detail-title')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _unmount(tester, controller);
    },
  );

  test(
    'sync retains original artwork when the source has no new cover',
    () async {
      final store = _Store();
      final repository = _SyncRepository();
      final controller = _Controller(store, repository: repository);
      const origin = OnlinePlaylist(
        source: OnlinePlaylistSource.netease,
        id: '1',
        name: '睡前歌单',
        creator: '',
        trackCount: 2,
        coverUrl: 'https://example.test/cover.jpg',
      );
      try {
        final saved = (await controller.addPlaylistDirectly(origin, _songs))!;
        repository.songs = const [
          OnlinePlaylistSong(id: '1', title: 'Updated', artist: 'Artist'),
        ];
        await controller.syncOnlinePlaylist(saved);
        final synced = store.library.playlists.single;
        expect(synced.entries.first.song!.title, 'Updated');
        expect(
          synced.entries.map((e) => e.song!.coverUrl),
          everyElement(origin.coverUrl),
        );
        // A later known cover should still replace the retained one.
        await controller.addPlaylistDirectly(
          const OnlinePlaylist(
            source: OnlinePlaylistSource.netease,
            id: '1',
            name: '睡前歌单',
            creator: '',
            trackCount: 2,
            coverUrl: 'https://example.test/new.jpg',
          ),
          _songs,
          target: synced,
          updateMetadata: true,
        );
        expect(
          store.library.playlists.single.entries.map((e) => e.song!.coverUrl),
          everyElement('https://example.test/new.jpg'),
        );
      } finally {
        controller.dispose();
        await controller.audioHandler.dispose();
      }
    },
  );

  testWidgets(
    'saved search playlist is marked and sync preserves removed local songs',
    (tester) async {
      final store = _Store();
      final repository = _SyncRepository();
      final controller = _Controller(store, repository: repository);
      MusicPlaylist? opened;
      final search = OnlinePlaylistSearch(repository);
      await search.search('睡前');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnlinePlaylistSearchPanel(
              search: search,
              controller: controller,
              onOpenPlaylist: (playlist) => opened = playlist,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('online-playlist-owned-${_playlist.key}')),
        findsNothing,
      );
      final saved = (await controller.addPlaylistDirectly(_playlist, _songs))!;
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('online-playlist-owned-${_playlist.key}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey(_playlist.key)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-new-playlist')), findsNothing);
      expect(find.byKey(const Key('direct-open-playlist')), findsOneWidget);
      expect(find.byKey(const Key('direct-sync-playlist')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('online-open-playlist-${_playlist.key}')),
      );
      expect(opened?.id, saved.id);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                PlaylistSyncButton(controller: controller, playlist: saved),
              ],
            ),
            body: const Text('My playlist'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final firstId = saved.entries.first.trackId;
      repository.songs = const [
        OnlinePlaylistSong(
          id: '1',
          title: 'First updated',
          artist: 'Artist updated',
        ),
        OnlinePlaylistSong(id: '3', title: 'Third', artist: 'Artist'),
      ];
      await tester.tap(find.byKey(const ValueKey('my-playlist-sync')));
      await tester.pumpAndSettle();
      expect(store.library.playlists, hasLength(1));
      final synced = store.library.playlists.single;
      expect(synced.id, saved.id);
      expect(synced.entries.map((e) => e.song!.title), [
        'First updated',
        'Second',
        'Third',
      ]);
      expect(synced.entries.first.trackId, firstId);
      expect(repository.loads, 2);
      repository.fail = true;
      await tester.tap(find.byKey(const ValueKey('my-playlist-sync')));
      await tester.pumpAndSettle();
      expect(find.text('同步失败，请重试'), findsOneWidget);
      expect(store.library.playlists.single.entries, hasLength(3));
      expect(tester.takeException(), isNull);
      await _unmount(tester, controller);
      search.dispose();
    },
  );

  test(
    'import uses default low confidence recommendation, not strict title equality',
    () async {
      final importer = OnlinePlaylistImporter(
        ScreenshotMatcher(
          resolver: _Resolver(),
          requestStartSpacing: Duration.zero,
        ),
      );
      OnlinePlaylistMatch? match;
      await importer.match(
        const [OnlinePlaylistSong(id: '1', title: '稻向', artist: '周杰伦')],
        isCanceled: () => false,
        onResult: (_, result) => match = result,
      );
      expect(match!.result!.recommended!.name, '稻香');
      expect(match!.result!.needsReview, true);
    },
  );

  test(
    'concurrent matching retains row indexes and cancellation stops callbacks',
    () async {
      final gates = <String, Completer<ScreenshotMatchResult>>{};
      final matcher = _Matcher(
        (draft) => (gates[draft.title] = Completer()).future,
      );
      final completed = <int>[];
      var canceled = false;
      final future = OnlinePlaylistImporter(matcher).match(
        _songs,
        isCanceled: () => canceled,
        onResult: (index, _) => completed.add(index),
      );
      gates['Second']!.complete(_match('Second'));
      await Future<void>.delayed(Duration.zero);
      expect(completed, [1]);
      canceled = true;
      gates['First']!.complete(_match('First'));
      await future;
      expect(completed, [1]);
    },
  );

  test('three consecutive service failures bound new matching work', () async {
    var calls = 0;
    final matcher = _Matcher((_) async {
      calls++;
      throw StateError('offline');
    });
    final results = <OnlinePlaylistMatch>[];
    await OnlinePlaylistImporter(matcher).match(
      List.filled(10, _songs.first),
      concurrency: 1,
      isCanceled: () => false,
      onResult: (_, result) => results.add(result),
    );
    expect(calls, 3);
    expect(results.every((result) => result.serviceFailed), true);
  });

  test('out-of-order failures do not pause across a successful row', () async {
    final gates = <int, Completer<ScreenshotMatchResult>>{};
    final matcher = _Matcher(
      (draft) =>
          (gates[int.parse(draft.title)] = Completer<ScreenshotMatchResult>())
              .future,
    );
    var canceled = false;
    final work = OnlinePlaylistImporter(matcher).match(
      [
        for (var i = 0; i < 10; i++)
          OnlinePlaylistSong(id: '$i', title: '$i', artist: ''),
      ],
      concurrency: 3,
      isCanceled: () => canceled,
      onResult: (_, _) {},
    );
    gates[1]!.complete(_match('1'));
    await Future<void>.delayed(Duration.zero);
    for (final index in [0, 2, 3]) {
      gates[index]!.completeError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
    }
    final started = gates.keys.toList();
    canceled = true;
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete(_match('remaining'));
    }
    await work;
    expect(started, contains(6)); // Rows 0,2,3 are not three adjacent failures.
  });

  test(
    'three adjacent failures pause even when earlier results arrive late',
    () async {
      final gates = <int, Completer<ScreenshotMatchResult>>{};
      final matcher = _Matcher(
        (draft) =>
            (gates[int.parse(draft.title)] = Completer<ScreenshotMatchResult>())
                .future,
      );
      var canceled = false;
      final work = OnlinePlaylistImporter(matcher).match(
        [
          for (var i = 0; i < 10; i++)
            OnlinePlaylistSong(id: '$i', title: '$i', artist: ''),
        ],
        concurrency: 3,
        isCanceled: () => canceled,
        onResult: (_, _) {},
      );
      for (final index in [1, 2, 0]) {
        gates[index]!.completeError(StateError('offline'));
        await Future<void>.delayed(Duration.zero);
      }
      for (final index in [3, 4]) {
        gates[index]!.complete(_match('$index'));
        await Future<void>.delayed(Duration.zero);
      }
      final started = gates.keys.toList();
      canceled = true;
      for (final gate in gates.values) {
        if (!gate.isCompleted) gate.complete(_match('remaining'));
      }
      await work;
      expect(started, [0, 1, 2, 3, 4]);
    },
  );

  testWidgets(
    'cross-task shared import survives changes until its last reference',
    (tester) async {
      final store = _Store();
      final controller = _Controller(
        store,
        matcher: _Matcher((_) async => _match('Shared')),
      );
      Future<void> show(OnlinePlaylist playlist) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicAppTheme.create(Brightness.light),
            home: OnlinePlaylistPage(
              playlist: playlist,
              repository: _Repository(),
              controller: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        final task = controller.onlinePlaylistTasks.tasks.firstWhere(
          (t) => t.playlist.key == playlist.key,
        );
        // Import just one row from each source; a later shared row must be protected.
        if (task.savedRows.isEmpty) {
          await tester.tap(
            find.byKey(const ValueKey('playlist-song-checkbox-1')),
          );
          await tester.pumpAndSettle();
        }
      }

      await show(_playlist);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      const second = OnlinePlaylist(
        source: OnlinePlaylistSource.qq,
        id: 'other',
        name: 'Other source',
        creator: '',
        trackCount: 2,
      );
      await show(second);
      await tester.tap(find.text('加入歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('睡前歌单'));
      await tester.pumpAndSettle();
      expect(store.library.playlists.single.entries.length, 1);
      for (final source in [_playlist, second]) {
        await show(source);
        await tester.tap(find.text('1. First'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Shared alternate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shared alternate'));
        await tester.pumpAndSettle();
        expect(
          store.library.playlists.single.entries.map(
            (e) => e.onlineTrack!.candidate.id,
          ),
          source == _playlist
              ? ['Shared', 'Shared alternate']
              : ['Shared alternate'],
        );
      }
      await _unmount(tester, controller);
    },
  );

  test(
    'create and append are single writes, deduplicate and preserve other playlists',
    () async {
      final store = _Store();
      final controller = _Controller(store);
      addTearDown(() {
        controller.dispose();
        unawaited(controller.audioHandler.dispose());
      });
      final first = await controller.importPlaylistCandidates('First list', [
        _candidate('1'),
        _candidate('1'),
      ]);
      expect(first!.trackIds.length, 1);
      expect(store.writes, 1);
      final second = await controller.importPlaylistCandidates('Second list', [
        _candidate('2'),
      ]);
      final updated = await controller.importPlaylistCandidates(
        'Ignored name',
        [_candidate('1'), _candidate('3')],
        target: first,
      );
      expect(updated!.id, first.id);
      expect(updated.name, 'First list');
      expect(updated.entries.map((item) => item.onlineTrack!.candidate.id), [
        '1',
        '3',
      ]);
      expect(controller.customPlaylists.map((item) => item.id), [
        first.id,
        second!.id,
      ]);
      expect(store.writes, 3);
      final deleted = MusicPlaylist(
        id: 'deleted',
        name: 'Gone',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await expectLater(
        controller.importPlaylistCandidates('x', [
          _candidate('4'),
        ], target: deleted),
        throwsStateError,
      );
      expect(store.writes, 3);
    },
  );

  test(
    'failed and empty imports leave no empty playlist; queue recovers',
    () async {
      final store = _Store()..fail = true;
      final controller = _Controller(store);
      addTearDown(() {
        controller.dispose();
        unawaited(controller.audioHandler.dispose());
      });
      expect(await controller.importPlaylistCandidates('Empty', []), isNull);
      expect(store.writes, 0);
      await expectLater(
        controller.importPlaylistCandidates('Retry', [_candidate('1')]),
        throwsStateError,
      );
      expect(controller.customPlaylists, isEmpty);
      expect(store.library.playlists, isEmpty);
      store.fail = false;
      await controller.importPlaylistCandidates('Retry', [_candidate('1')]);
      expect(controller.customPlaylists.single.name, 'Retry');
      expect(controller.customPlaylists.single.entries.length, 1);
    },
  );

  test(
    'large playlist snapshot avoids scanning the cache for every song',
    () async {
      final store = _Store();
      final controller = _Controller(store);
      try {
        await controller.importPlaylistCandidates('Large', [
          for (var i = 0; i < 1000; i++) _candidate('$i'),
        ]);
        final cached = _CountedCache([
          for (var i = 0; i < 1000; i++)
            CachedTrack(
              cacheId: 'cache-$i',
              filePath: '/tmp/$i.mp3',
              sizeBytes: 4,
              fromCache: true,
              music: ResolvedMusic(
                query: '$i',
                source: MusicDataSource.buguyy,
                platform: 'kuwo',
                id: '$i',
                name: '$i',
                artist: 'Artist',
                album: '',
                url: 'https://example.test/$i.mp3',
                quality: const MusicQuality(format: 'mp3'),
              ),
            ),
        ]);
        final snapshot = controller.libraryUseCase.applyCachedRecords(
          cached,
          store.library,
        );
        expect(snapshot.onlineTracks.length, 1000);
        expect(
          snapshot.onlineTracks.every((track) => track.filePath.isNotEmpty),
          true,
        );
        expect(snapshot.onlineTracks.last.filePath, '/tmp/999.mp3');
        expect(
          cached.reads,
          lessThan(10000),
        ); // Old nested scan reads ~500,000 items.
      } finally {
        controller.dispose();
        await controller.audioHandler.dispose();
      }
    },
  );

  testWidgets('download progress refreshes the task but not playlist counts', (
    tester,
  ) async {
    final controller = _Controller(_Store());
    await controller.importPlaylistCandidates('List', [_candidate('First')]);
    final id = controller.downloadQueue.taskIdForCandidate(_candidate('First'));
    controller.downloadQueue.start(id, _candidate('First'));
    controller.downloadQueue.update(
      id,
      (task) =>
          task.copyWith(status: DownloadTaskStatus.downloading, progress: .1),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        home: DownloadManagerPage(
          controller: controller,
          onOpenPlaylist: (_) {},
        ),
      ),
    );
    await tester.pump();
    final countsBefore = controller.countQueries;
    controller.downloadQueue.update(id, (task) => task.copyWith(progress: .7));
    controller.downloadProgressChanges.notifyListeners();
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .7,
    );
    expect(controller.countQueries, countsBefore);
    await _unmount(tester, controller);
  });

  testWidgets(
    'detail defaults to all songs and auto creates once with review markers',
    (tester) async {
      final store = _Store();
      final controller = _Controller(store);
      await _mount(tester, controller);
      expect(find.text('已选 2 首'), findsOneWidget);
      expect(find.textContaining('另 1 首暂无法读取'), findsNothing);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      expect(store.library.playlists.single.name, '睡前歌单');
      expect(
        store.library.playlists.single.entries.map(
          (entry) => entry.onlineTrack!.candidate.id,
        ),
        ['First', 'Second'],
      );
      expect(find.textContaining('⚠ 需核对'), findsOneWidget);
      expect(find.text('打开歌单'), findsOneWidget);
      expect(store.writes, 1);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'review candidates before saving and navigate to the saved playlist',
    (tester) async {
      final store = _Store();
      final controller = _Controller(store);
      MusicPlaylist? opened;
      await _mount(tester, controller, onOpenPlaylist: (p) => opened = p);
      expect(store.writes, 0); // Automatic matching does not auto-save.
      await tester.tap(find.text('2. Second'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Second alternate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second alternate'));
      await tester.pumpAndSettle();
      expect(find.textContaining('⚠ 需核对'), findsNothing);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      expect(
        store.library.playlists.single.entries.last.onlineTrack!.candidate.id,
        'Second alternate',
      );
      expect(controller.matcher.calls, 2);
      await tester.tap(find.text('打开歌单'));
      expect(opened!.id, store.library.playlists.single.id);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'changing a saved candidate replaces it in order and failed writes preserve it',
    (tester) async {
      final store = _Store();
      final controller = _Controller(store);
      await _mount(tester, controller);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. Second'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Second alternate'));
      await tester.pumpAndSettle();
      store.fail = true;
      await tester.tap(find.text('Second alternate'));
      await tester.pumpAndSettle();
      expect(find.textContaining('更换保存失败'), findsOneWidget);
      expect(
        store.library.playlists.single.entries.last.onlineTrack!.candidate.id,
        'Second',
      );
      store.fail = false;
      await tester.ensureVisible(find.text('Second alternate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second alternate'));
      await tester.pumpAndSettle();
      expect(
        store.library.playlists.single.entries.map(
          (e) => e.onlineTrack!.candidate.id,
        ),
        ['First', 'Second alternate'],
      );
      expect(find.textContaining('⚠ 需核对'), findsNothing);
      expect(controller.matcher.calls, 2);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'reviewing a duplicate in an existing playlist preserves its original song',
    (tester) async {
      final store = _Store();
      final controller = _Controller(store);
      final old = await controller.importPlaylistCandidates('Existing', [
        _candidate('Second'),
      ]);
      MusicPlaylist? opened;
      await _mount(tester, controller, onOpenPlaylist: (p) => opened = p);
      await tester.tap(find.text('加入歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. Second'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Second alternate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second alternate'));
      await tester.pumpAndSettle();
      expect(
        store.library.playlists.single.entries.map(
          (e) => e.onlineTrack!.candidate.id,
        ),
        ['Second', 'Second alternate', 'First'],
      );
      await tester.tap(find.text('打开歌单'));
      expect(opened!.id, old!.id);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'shared imported candidates are retained until the last row changes',
    (tester) async {
      final store = _Store();
      final controller = _Controller(
        store,
        matcher: _Matcher((_) async => _match('Shared')),
      );
      await _mount(tester, controller);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      expect(store.library.playlists.single.entries.length, 1);
      for (final title in ['1. First', '2. Second']) {
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Shared alternate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shared alternate'));
        await tester.pumpAndSettle();
        if (title == '1. First') {
          expect(
            store.library.playlists.single.entries.map(
              (e) => e.onlineTrack!.candidate.id,
            ),
            ['Shared', 'Shared alternate'],
          );
          await tester.ensureVisible(find.text(title));
          await tester.pumpAndSettle();
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
        }
      }
      expect(
        store.library.playlists.single.entries.single.onlineTrack!.candidate.id,
        'Shared alternate',
      );
      await _unmount(tester, controller);
    },
  );

  test(
    'replacement cannot recreate a deleted target or a removed original entry',
    () async {
      final store = _Store();
      final controller = _Controller(store);
      try {
        final saved = await controller.importPlaylistSelection('Target', [
          _candidate('First'),
        ]);
        final target = saved.playlist!;
        final writes = store.writes;
        await expectLater(
          controller.replaceImportedCandidate(
            target,
            'absent',
            _candidate('New'),
            removePrevious: true,
          ),
          throwsStateError,
        );
        expect(store.writes, writes);
        await controller.deletePlaylist(target);
        await expectLater(
          controller.replaceImportedCandidate(
            target,
            target.trackIds.single,
            _candidate('New'),
            removePrevious: true,
          ),
          throwsStateError,
        );
        expect(store.library.playlists, isEmpty);
      } finally {
        controller.dispose();
        await controller.audioHandler.dispose();
      }
    },
  );

  testWidgets('new playlist automatically imports slow later matches', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<ScreenshotMatchResult>();
    final controller = _Controller(
      store,
      matcher: _Matcher(
        (draft) async =>
            draft.title == 'Second' ? await gate.future : _match('First'),
      ),
    );
    await _mount(tester, controller, settle: false);
    await tester.pump();
    await tester.tap(find.text('1. First'));
    await tester.pump();
    expect(find.text('First alternate'), findsOneWidget);
    await tester.tap(find.text('First alternate'));
    await tester.pump();
    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    await tester.pump();
    expect(
      store.library.playlists.single.entries.single.onlineTrack!.candidate.id,
      'First alternate',
    );
    expect(find.textContaining('继续导入'), findsNothing);
    gate.complete(_match('Second'));
    await tester.pumpAndSettle();
    expect(store.library.playlists.length, 1);
    expect(
      store.library.playlists.single.entries.map(
        (e) => e.onlineTrack!.candidate.id,
      ),
      ['First alternate', 'Second'],
    );
    expect(controller.matcher.calls, 2);
    await _unmount(tester, controller);
  });

  testWidgets(
    'replacing a saved match finishes after leaving and resumes later sync',
    (tester) async {
      final store = _Store();
      final laterMatch = Completer<ScreenshotMatchResult>();
      final controller = _Controller(
        store,
        matcher: _Matcher(
          (draft) async => draft.title == 'Second'
              ? await laterMatch.future
              : _match('First'),
        ),
      );
      await _mount(tester, controller, settle: false);
      await tester.pump();
      await tester.tap(find.text('新建歌单'));
      await tester.pump();
      await tester.pump();
      final task = controller.onlinePlaylistTasks.tasks.single;
      expect(task.savedRows.length, 1);

      await tester.tap(find.text('1. First'));
      await tester.pump();
      final delayedWrite = Completer<void>();
      store.writeGate = delayedWrite;
      await tester.tap(find.text('First alternate'));
      await tester.pump();
      expect(task.saving, true);
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: MusicHomePage(controller: controller),
        ),
      );
      laterMatch.complete(_match('Second'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(task.savedRows.length, 1);
      delayedWrite.complete();
      await tester.pumpAndSettle();

      expect(task.saving, false);
      expect(task.choices[0]!.id, 'First alternate');
      expect(task.savedRows.length, 2);
      expect(
        store.library.playlists.single.entries.map(
          (entry) => entry.onlineTrack!.candidate.id,
        ),
        ['First alternate', 'Second'],
      );
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'create before any match and sync out-of-order results off page',
    (tester) async {
      final store = _Store();
      final gates = <String, Completer<ScreenshotMatchResult>>{};
      final controller = _Controller(
        store,
        matcher: _Matcher(
          (draft) =>
              (gates[draft.title] = Completer<ScreenshotMatchResult>()).future,
        ),
      );
      await _mount(tester, controller, settle: false);
      await tester.pump();
      await tester.tap(find.text('新建歌单'));
      await tester.pump();
      await tester.pump();
      final destination = store.library.playlists.single;
      expect(destination.entries, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: MusicHomePage(controller: controller),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(ValueKey('home-playlist-${destination.id}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('home-manage-playlists')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('custom-playlist-${destination.id}')),
        findsOneWidget,
      );
      gates['Second']!.complete(_match('Second'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(
        store.library.playlists.single.entries.single.onlineTrack!.candidate.id,
        'Second',
      );
      expect(find.textContaining('歌单已有 1 首'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('custom-playlist-${destination.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      gates['First']!.complete(_match('First'));
      await tester.pumpAndSettle();
      expect(store.library.playlists.single.id, destination.id);
      expect(
        store.library.playlists.single.entries.map(
          (entry) => entry.onlineTrack!.candidate.id,
        ),
        ['First', 'Second'],
      );
      expect(store.writes, 3); // Create and two match batches.
      await _unmount(tester, controller);
    },
  );

  testWidgets('recognizing playlist stays in the visible home playlist list', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<ScreenshotMatchResult>();
    final controller = _Controller(
      store,
      matcher: _Matcher((_) => gate.future),
    );
    for (var i = 0; i < 5; i++) {
      await controller.createPlaylist('旧歌单 $i');
    }
    await _mount(tester, controller, settle: false);
    await tester.pump();
    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    await tester.pump();
    final destination = store.library.playlists.last;
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        home: MusicHomePage(controller: controller),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(ValueKey('home-playlist-${destination.id}')),
      findsOneWidget,
    );
    expect(find.textContaining('已识别 0/2 首'), findsOneWidget);
    await _unmount(tester, controller);
  });

  testWidgets('failed background sync retries into its original playlist', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<ScreenshotMatchResult>();
    final controller = _Controller(
      store,
      matcher: _Matcher((_) => gate.future),
    );
    await _mount(tester, controller, settle: false);
    await tester.pump();
    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    await tester.pump();
    final destination = store.library.playlists.single;
    store.fail = true;
    gate.complete(_match('First'));
    await tester.pumpAndSettle();
    expect(find.textContaining('自动同步失败'), findsOneWidget);
    expect(store.library.playlists.single.entries, isEmpty);
    expect(find.textContaining('继续导入'), findsNothing);

    store.fail = false;
    await tester.tap(find.byTooltip('重试同步'));
    await tester.pumpAndSettle();
    expect(store.library.playlists.single.id, destination.id);
    expect(store.library.playlists.single.entries.length, 1);
    expect(store.library.playlists.length, 1);
    expect(find.textContaining('自动同步失败'), findsNothing);
    await _unmount(tester, controller);
  });

  testWidgets('retrying an earlier match restores source order', (
    tester,
  ) async {
    final store = _Store();
    final firstGate = Completer<ScreenshotMatchResult>();
    var firstCalls = 0;
    final controller = _Controller(
      store,
      matcher: _Matcher((draft) {
        if (draft.title == 'Second') return Future.value(_match('Second'));
        firstCalls++;
        return firstCalls == 1
            ? firstGate.future
            : Future.value(_match('First'));
      }),
    );
    await _mount(tester, controller, settle: false);
    await tester.pump();
    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    final task = controller.onlinePlaylistTasks.tasks.single;
    task.pause();
    await tester.pumpAndSettle();
    expect(
      store.library.playlists.single.entries.map(
        (entry) => entry.onlineTrack!.candidate.id,
      ),
      ['Second'],
    );
    await task.matchPending();
    await tester.pumpAndSettle();
    expect(
      store.library.playlists.single.entries.map(
        (entry) => entry.onlineTrack!.candidate.id,
      ),
      ['First', 'Second'],
    );
    firstGate.complete(_match('First'));
    await tester.pump();
    await _unmount(tester, controller);
  });

  testWidgets('new local playlist shows matching and sync until completion', (
    tester,
  ) async {
    final store = _Store();
    final gates = <String, Completer<ScreenshotMatchResult>>{};
    final controller = _Controller(
      store,
      matcher: _Matcher(
        (draft) =>
            (gates[draft.title] = Completer<ScreenshotMatchResult>()).future,
      ),
    );
    // Legacy matching tasks remain reachable from the local playlist list.
    final task = controller.onlinePlaylistTasks.obtain(
      _playlist,
      _CompleteRepository(),
    );
    await task.load();
    await task.startAutoSync();
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        home: MusicHomePage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('home-playlist-${task.destination!.id}')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('online-playlist-sync-progress')),
      findsOneWidget,
    );
    expect(find.textContaining('正在识别 0/2 首'), findsOneWidget);
    await tester.tap(find.text('查看识别'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    gates['Second']!.complete(_match('Second'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.textContaining('正在识别 1/2 首'), findsOneWidget);
    expect(store.library.playlists.single.entries.length, 1);
    expect(find.text('Second'), findsOneWidget);
    gates['First']!.complete(_match('First'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('online-playlist-sync-progress')),
      findsNothing,
    );
    expect(store.library.playlists.single.entries.length, 2);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    await _unmount(tester, controller);
  });

  testWidgets('local sync failure remains visible and opens retry', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<ScreenshotMatchResult>();
    final controller = _Controller(
      store,
      matcher: _Matcher((_) => gate.future),
    );
    // Legacy matching tasks remain reachable from the local playlist list.
    final task = controller.onlinePlaylistTasks.obtain(
      _playlist,
      _CompleteRepository(),
    );
    await task.load();
    await task.startAutoSync();
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        home: MusicHomePage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('home-playlist-${task.destination!.id}')),
    );
    await tester.pumpAndSettle();

    store.fail = true;
    gate.complete(_match('First'));
    await tester.pumpAndSettle();
    expect(find.textContaining('同步失败'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('online-playlist-sync-progress')),
      findsOneWidget,
    );
    await tester.tap(find.text('查看识别'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('重试同步'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byTooltip('重试同步'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('online-playlist-sync-progress')),
      findsNothing,
    );
    expect(store.library.playlists.single.entries.length, 1);
    await _unmount(tester, controller);
  });

  testWidgets('save retry reuses matches and does not leave empty playlist', (
    tester,
  ) async {
    final store = _Store()..fail = true;
    final controller = _Controller(store);
    await _mount(tester, controller);
    await tester.tap(find.text('新建歌单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('新建歌单失败'), findsOneWidget);
    expect(store.library.playlists, isEmpty);
    expect(controller.matcher.calls, 2);
    store.fail = false;
    await tester.tap(find.text('新建歌单'));
    await tester.pumpAndSettle();
    expect(store.library.playlists.length, 1);
    expect(controller.matcher.calls, 2);
    await _unmount(tester, controller);
  });

  testWidgets(
    'existing destination imports only checked songs and skips duplicates',
    (tester) async {
      final store = _Store();
      final controller = _Controller(store);
      await controller.importPlaylistCandidates('已有歌单', [_candidate('First')]);
      await _mount(tester, controller);
      await tester.tap(find.text('加入歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已有歌单'));
      await tester.pumpAndSettle();
      expect(store.library.playlists.length, 1);
      expect(store.library.playlists.single.entries.length, 2);
      expect(find.textContaining('添加 1 首'), findsNothing);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'unchecked rows are not imported and saving does not search again',
    (tester) async {
      final store = _Store();
      final controller = _Controller(store);
      await _mount(tester, controller);
      await tester.tap(find.byKey(const ValueKey('playlist-song-checkbox-0')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      expect(controller.matcher.calls, 2);
      expect(
        store.library.playlists.single.entries.single.onlineTrack!.candidate.id,
        'Second',
      );
      await _unmount(tester, controller);
    },
  );

  testWidgets('canceling in-flight matching never creates a playlist', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<ScreenshotMatchResult>();
    final controller = _Controller(
      store,
      matcher: _Matcher((_) => gate.future),
    );
    await _mount(tester, controller, settle: false);
    await tester.pump();
    await tester.tap(find.text('暂停'));
    await tester.pump();
    gate.complete(_match('First'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(store.writes, 0);
    await _unmount(tester, controller);
  });

  testWidgets(
    'leaving during matching retains late results and saves nothing',
    (tester) async {
      final store = _Store();
      final gate = Completer<ScreenshotMatchResult>();
      final controller = _Controller(
        store,
        matcher: _Matcher((_) => gate.future),
      );
      await _mount(tester, controller, settle: false);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete(_match('First'));
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      expect(controller.onlinePlaylistTasks.tasks.single.choices.length, 2);
      await _mount(tester, controller);
      expect(controller.matcher.calls, 2);
      expect(find.text('1. First'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(controller.audioHandler.dispose());
    },
  );

  testWidgets(
    'home defaults to song search and switches to mixed playlist results',
    (tester) async {
      final controller = _Controller(_Store());
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: MusicHomePage(controller: controller, playlistRepository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('歌手或歌曲'), findsOneWidget);
      final libraryBefore = tester.getRect(find.text('我的音乐'));
      final searchBefore = tester.getRect(find.byType(TextField));

      await tester.tap(find.byKey(const ValueKey('search-mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('歌单名称或关键词'), findsOneWidget);
      expect(tester.getRect(find.text('我的音乐')), libraryBefore);
      expect(tester.getRect(find.byType(TextField)), searchBefore);
      expect(repo.searchCalls, 0);

      await tester.enterText(find.byType(TextField), '睡前');
      await tester.tap(find.byTooltip('搜歌单'));
      await tester.pumpAndSettle();
      expect(repo.searchCalls, 2);
      expect(find.text('睡前歌单'), findsNWidgets(2));
      expect(find.textContaining('网易云音乐 ·'), findsOneWidget);
      expect(find.textContaining('QQ 音乐 ·'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('睡前歌单'), findsNothing);
      expect(
        repo.searchCalls,
        2,
      ); // Switching submits a song search without another playlist search.
      await tester.tap(find.byKey(const ValueKey('search-mode-toggle')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byKey(const ValueKey('search-mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('歌手或歌曲'), findsOneWidget);
      expect(find.text('睡前歌单'), findsNothing);
      await _unmount(tester, controller);
    },
  );

  testWidgets(
    'background entry retains results, review, selection and destination',
    (tester) async {
      final store = _Store();
      final gate = Completer<ScreenshotMatchResult>();
      final controller = _Controller(
        store,
        matcher: _Matcher(
          (draft) => draft.title == 'Second'
              ? gate.future
              : Future.value(_match('First')),
        ),
      );
      await _mount(tester, controller, settle: false);
      await tester.pump();
      await tester.tap(find.text('1. First'));
      await tester.pump();
      await tester.tap(find.text('First alternate'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('playlist-song-checkbox-1')));
      await tester.pump();
      await tester.tap(find.text('新建歌单'));
      await tester.pump();
      await tester.pump();
      final destination = store.library.playlists.single;
      // Remove the detail route entirely, as returning to home does.
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(Brightness.light),
          home: MusicHomePage(controller: controller),
        ),
      );
      await tester.pump();
      expect(find.textContaining('后台进行中'), findsOneWidget);
      gate.complete(_match('Second'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playlist-task-entry')), findsNothing);
      expect(store.writes, 2); // Create, then automatically save the match.
      await tester.tap(find.byKey(const ValueKey('home-manage-playlists')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('匹配歌单'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('匹配歌单')).dy,
        greaterThan(tester.getTopLeft(find.text('自建歌单')).dy),
      );
      expect(find.textContaining('已自动同步'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('已自动同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('已自动同步'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);
      expect(find.text('打开歌单'), findsOneWidget);
      final task = controller.onlinePlaylistTasks.tasks.single;
      expect(task.destination!.id, destination.id);
      expect(task.choices[0]!.id, 'First alternate');
      expect(task.reviewed, contains(0));
      expect(controller.matcher.calls, 2);
      expect(task.savedRows.length, 1);
      await _unmount(tester, controller);
    },
  );

  testWidgets('compact controls share rows and missing-song toast expires', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _Controller(_Store());
    await _mount(tester, controller, settle: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('另 1 首暂无法读取'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.textContaining('另 1 首暂无法读取'),
        matching: find.byType(SnackBar),
      ),
      findsOneWidget,
    );
    final create = tester.getRect(find.text('新建歌单'));
    final add = tester.getRect(find.text('加入歌单'));
    expect(create.center.dy, add.center.dy);
    expect(create.right, lessThan(add.left));
    final appBar = tester.getRect(find.byType(AppBar));
    expect(appBar.contains(tester.getCenter(find.text('已选 2 首'))), true);
    expect(
      appBar.contains(
        tester.getCenter(find.byKey(const Key('playlist-select-all'))),
      ),
      true,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('另 1 首暂无法读取'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester, controller);
  });

  testWidgets(
    'tasks isolate sources and resume missing matches without restarting completed rows',
    (tester) async {
      final gate = Completer<ScreenshotMatchResult>();
      final controller = _Controller(
        _Store(),
        matcher: _Matcher(
          (draft) => draft.title == 'Second'
              ? gate.future
              : Future.value(_match('First')),
        ),
      );
      await _mount(tester, controller, settle: false);
      await tester.pump();
      final tasks = controller.onlinePlaylistTasks;
      final task = tasks.tasks.single;
      task.pause();
      gate.complete(_match('Second'));
      await tester.pumpAndSettle();
      expect(task.choices.keys, [0]);
      await task.matchPending();
      await tester.pumpAndSettle();
      expect(task.choices.length, 2);
      expect(controller.matcher.calls, 3);
      expect(identical(task, tasks.obtain(_playlist, _Repository())), true);
      final qq = tasks.obtain(
        const OnlinePlaylist(
          source: OnlinePlaylistSource.qq,
          id: '1',
          name: 'QQ',
          creator: '',
          trackCount: 2,
        ),
        _Repository(),
      );
      await tester.pumpAndSettle();
      expect(identical(task, qq), false);
      expect(tasks.tasks.length, 2);
      expect(qq.choices.length, 2);
      await _unmount(tester, controller);
    },
  );

  testWidgets('disposing the controller cancels pending task callbacks', (
    tester,
  ) async {
    final gate = Completer<ScreenshotMatchResult>();
    final controller = _Controller(
      _Store(),
      matcher: _Matcher((_) => gate.future),
    );
    await _mount(tester, controller, settle: false);
    final task = controller.onlinePlaylistTasks.tasks.single;
    await _unmount(tester, controller);
    gate.complete(_match('First'));
    await tester.pumpAndSettle();
    expect(task.choices, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

const _songs = [
  OnlinePlaylistSong(id: '1', title: 'First', artist: 'Artist'),
  OnlinePlaylistSong(id: '2', title: 'Second', artist: 'Artist'),
];
const _playlist = OnlinePlaylist(
  source: OnlinePlaylistSource.netease,
  id: '1',
  name: '睡前歌单',
  creator: 'Creator',
  trackCount: 3,
);
MusicSearchCandidate _candidate(String id) => MusicSearchCandidate(
  query: id,
  source: MusicDataSource.buguyy,
  platform: 'kuwo',
  keyword: id,
  page: 1,
  id: id,
  name: id,
  artist: 'Artist',
  album: '',
  duration: 0,
  link: '',
  coverUrl: '',
  qualities: const [],
  score: 1,
  raw: const {},
);
ScreenshotMatchResult _match(String id) {
  final candidate = _candidate(id);
  return ScreenshotMatchResult(
    [candidate, _candidate('$id alternate')],
    candidate,
    needsReview: id == 'Second',
  );
}

class _Matcher extends ScreenshotMatcher {
  _Matcher(this.respond) : super(resolver: _Resolver());
  final Future<ScreenshotMatchResult> Function(ScreenshotSongDraft) respond;
  int calls = 0;
  @override
  Future<ScreenshotMatchResult> match(
    ScreenshotSongDraft draft, {
    bool failOnSourceErrorWhenEmpty = false,
    MusicDataSource? source,
  }) {
    calls++;
    return respond(draft);
  }
}

class _Resolver implements MusicResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async => [
    MusicSearchCandidate(
      query: query,
      source: source,
      platform: 'kuwo',
      keyword: query,
      page: 1,
      id: '1',
      name: '稻香',
      artist: '周杰伦',
      album: '',
      duration: 0,
      link: '',
      coverUrl: '',
      qualities: const [],
      score: 1,
      raw: const {},
    ),
  ];
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw UnimplementedError();
}

class _Controller extends MusicController {
  _Controller(
    _Store store, {
    _Matcher? matcher,
    OnlinePlaylistRepository? repository,
  }) : matcher = matcher ?? _Matcher((draft) async => _match(draft.title)),
       super(
         audioHandler: MusicAudioHandler(),
         playlistStore: store,
         playlistMetadataRepository: repository,
         songSearchCache: SongSearchCache.memory(),
       );
  final _Matcher matcher;
  final previewSongs = <OnlinePlaylistSong>[];
  @override
  Future<void> playOnlinePlaylistSong(
    OnlinePlaylist origin,
    OnlinePlaylistSong song,
  ) async {
    previewSongs.add(song);
    audioHandler.mediaItem.add(
      MediaItem(
        id: 'preview-${song.id}',
        title: song.title,
        artist: song.artist,
        duration: Duration(seconds: song.durationSeconds),
      ),
    );
  }

  int countQueries = 0;
  @override
  int cachedCountForPlaylist(MusicPlaylist playlist) {
    countQueries++;
    return super.cachedCountForPlaylist(playlist);
  }

  @override
  Future<void> initialize() async {}
  @override
  ScreenshotMatcher createScreenshotMatcher() => matcher;
  @override
  ScreenshotMatcher createOnlinePlaylistMatcher() => matcher;
}

class _SourceController extends _Controller {
  _SourceController(super.store);
  final searches = <MusicDataSource>[];
  final refreshes = <bool>[];
  MusicSearchCandidate? chosen;
  @override
  Future<List<MusicSearchCandidate>> searchSongSources(
    Track track, {
    String? query,
    MusicDataSource? searchSource,
    bool refresh = false,
  }) {
    final source = searchSource ?? MusicDataSource.auto;
    searches.add(source);
    refreshes.add(refresh);
    return _Resolver().search(query ?? track.title, source);
  }

  @override
  Future<void> chooseSongSource(
    Track track,
    MusicSearchCandidate candidate,
  ) async {
    chosen = candidate;
  }
}

class _Store extends PlaylistStore {
  PlaylistLibrary library = const PlaylistLibrary.empty();
  bool fail = false;
  int writes = 0;
  Completer<void>? writeGate;
  @override
  Future<void> write(
    PlaylistLibrary value, {
    Set<String>? validTrackIds,
  }) async {
    writes++;
    if (fail) throw StateError('disk failure');
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    library = value;
  }

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async => library;
}

class _Repository extends OnlinePlaylistRepository {
  int searchCalls = 0;
  @override
  Future<OnlinePlaylistDetail> load(
    OnlinePlaylist playlist, {
    bool Function()? isCanceled,
    void Function(int, int)? onProgress,
  }) async => const OnlinePlaylistDetail(songs: _songs, total: 3);
  @override
  Future<OnlinePlaylistSearchPage> search(
    OnlinePlaylistSource source,
    String query, {
    int page = 1,
  }) async {
    searchCalls++;
    return OnlinePlaylistSearchPage(
      items: [
        OnlinePlaylist(
          source: source,
          id: '1',
          name: '睡前歌单',
          creator: 'Creator',
          trackCount: 3,
        ),
      ],
      hasMore: false,
    );
  }
}

class _CompleteRepository extends _Repository {
  @override
  Future<OnlinePlaylistDetail> load(
    OnlinePlaylist playlist, {
    bool Function()? isCanceled,
    void Function(int, int)? onProgress,
  }) async => const OnlinePlaylistDetail(songs: _songs, total: 2);
}

Future<void> _mount(
  WidgetTester tester,
  _Controller controller, {
  bool settle = true,
  ValueChanged<MusicPlaylist>? onOpenPlaylist,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: MusicAppTheme.create(Brightness.light),
      home: OnlinePlaylistPage(
        playlist: _playlist,
        repository: _Repository(),
        controller: controller,
        onOpenPlaylist: onOpenPlaylist,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _unmount(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  unawaited(controller.audioHandler.dispose());
}

class _CountedCache extends ListBase<CachedTrack> {
  _CountedCache(this.items);
  final List<CachedTrack> items;
  int reads = 0;
  @override
  int get length => items.length;
  @override
  set length(int value) => throw UnsupportedError('read-only');
  @override
  CachedTrack operator [](int index) {
    reads++;
    return items[index];
  }

  @override
  void operator []=(int index, CachedTrack value) =>
      throw UnsupportedError('read-only');
}

class _SyncRepository extends _Repository {
  List<OnlinePlaylistSong> songs = _songs;
  int loads = 0;
  bool fail = false;
  @override
  Future<OnlinePlaylistDetail> load(
    OnlinePlaylist playlist, {
    bool Function()? isCanceled,
    void Function(int, int)? onProgress,
  }) async {
    loads++;
    if (fail) throw StateError('offline');
    return OnlinePlaylistDetail(songs: songs, total: songs.length);
  }
}

class _LongRepository extends _Repository {
  @override
  Future<OnlinePlaylistDetail> load(
    OnlinePlaylist playlist, {
    bool Function()? isCanceled,
    void Function(int, int)? onProgress,
  }) async => OnlinePlaylistDetail(
    songs: [
      for (var i = 0; i < 40; i++)
        OnlinePlaylistSong(id: '$i', title: '歌曲 $i', artist: '歌手'),
    ],
    total: 40,
  );
}
