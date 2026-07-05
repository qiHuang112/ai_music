import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/data/hotlist.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/playback_state_store.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/music_home_page.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets('renders Android-first search and cache shell', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('搜音乐'), findsOneWidget);
    expect(find.text('歌手或歌曲'), findsOneWidget);
    expect(find.text('我的音乐'), findsOneWidget);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip('播放列表'), findsOneWidget);
    expect(find.text('No cached music yet'), findsNothing);
  });

  testWidgets('mini player swipe skips tracks without opening player', (
    tester,
  ) async {
    final handler = _WidgetAudioHandler();
    await tester.pumpWidget(_app(audioHandler: handler));
    await tester.pumpAndSettle();

    handler.emit(
      const MediaItem(
        id: 'song-1',
        title: 'Swipe Song',
        artist: 'Singer',
        duration: Duration(minutes: 3),
      ),
    );
    await tester.pumpAndSettle();

    final swipeArea = find.byKey(const ValueKey('mini-player-swipe-area'));
    expect(swipeArea, findsOneWidget);

    await tester.drag(swipeArea, const Offset(-160, 0));
    await tester.pump();
    expect(handler.skipNextCalls, 1);
    expect(handler.skipPreviousCalls, 0);
    expect(find.text('正在播放'), findsNothing);

    await tester.drag(swipeArea, const Offset(160, 0));
    await tester.pump();
    expect(handler.skipNextCalls, 1);
    expect(handler.skipPreviousCalls, 1);
  });

  testWidgets('mini player buttons still skip after swipe support', (
    tester,
  ) async {
    final handler = _WidgetAudioHandler();
    await tester.pumpWidget(_app(audioHandler: handler));
    await tester.pumpAndSettle();

    handler.emit(
      const MediaItem(
        id: 'song-1',
        title: 'Button Song',
        artist: 'Singer',
        duration: Duration(minutes: 3),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下一首'));
    await tester.pump();
    await tester.tap(find.byTooltip('上一首'));
    await tester.pump();

    expect(handler.skipNextCalls, 1);
    expect(handler.skipPreviousCalls, 1);
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
    expect(find.text('1 首 · Beta'), findsOneWidget);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-favorites-entry')));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-playlist-road')));
    await tester.pumpAndSettle();

    expect(find.text('Road'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('hotlist entry opens detail and searches existing source', (
    tester,
  ) async {
    final resolver = _FakeMusicResolver(
      candidates: [_candidate(name: '第一首', artist: '歌手 A')],
    );
    await tester.pumpWidget(
      _app(
        resolver: resolver,
        hotlistRepository: _StaticHotlistRepository([_hotlistChart()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的音乐'), findsOneWidget);
    expect(find.text('热榜发现'), findsOneWidget);
    expect(find.text('QQ 热歌榜'), findsOneWidget);

    await tester.tap(find.text('QQ 热歌榜'));
    await tester.pumpAndSettle();

    expect(find.text('榜单仅用于发现，播放需通过 AI Music 搜索匹配。'), findsOneWidget);
    expect(find.text('第一首'), findsOneWidget);

    await tester.tap(find.text('第一首'));
    await tester.pumpAndSettle();

    expect(resolver.lastQuery, '第一首 歌手 A');
    expect(find.text('第一首'), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline), findsOneWidget);
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

    expect(find.byKey(const ValueKey('home-favorites-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-playlist-road')), findsOneWidget);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('输入歌手或歌曲名，下载后会保存在本机缓存里。'), findsNothing);
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
    expect(resolver.lastSource, MusicDataSource.auto);
    expect(find.text('稻香 0'), findsOneWidget);
    expect(find.text('布谷'), findsWidgets);
    expect(find.textContaining('BuguYY'), findsNothing);
    expect(find.textContaining('kuwo'), findsNothing);
    expect(find.textContaining('03:20'), findsNothing);
    expect(find.textContaining('FLAC · 30MB'), findsWidgets);
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

  testWidgets(
    'auto search shows first source while another source is loading',
    (tester) async {
      final resolver = _ProgressiveMusicResolver();
      await tester.pumpWidget(_app(resolver: resolver));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '晴天');
      await tester.tap(find.byTooltip('在线搜索'));
      await tester.pump();

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

    expect(find.byTooltip('播放'), findsNothing);
    expect(find.byIcon(Icons.download_for_offline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_for_offline));
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('重新下载'), findsOneWidget);
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
    for (var i = 0; i < 6 && find.byTooltip('播放').evaluate().isEmpty; i++) {
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

  testWidgets('download manager can sort cached tracks', (tester) async {
    final older = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'alpha', name: 'Alpha')),
      music: _resolvedMusic(id: 'alpha', name: 'Alpha'),
      filePath: '/tmp/alpha.mp3',
      sizeBytes: 4,
      fromCache: true,
      cachedAt: DateTime(2026, 1, 1),
    );
    final newer = CachedTrack(
      cacheId: cacheIdForResolved(_resolvedMusic(id: 'beta', name: 'Beta')),
      music: _resolvedMusic(id: 'beta', name: 'Beta'),
      filePath: '/tmp/beta.mp3',
      sizeBytes: 4,
      fromCache: true,
      cachedAt: DateTime(2026, 1, 2),
    );
    await tester.pumpWidget(
      _app(cacheStore: _FakeCacheStore(cached: [older, newer])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.tap(find.text('下载时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首字母').last);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
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

  testWidgets('settings pages persist language theme and music source', (
    tester,
  ) async {
    final settings = _FakeSettingsStore();
    await tester.pumpWidget(_app(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('英文'));
    await tester.pumpAndSettle();

    expect(settings.settings.language, AppLanguage.en);
    expect(find.text('Language'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(settings.settings.theme, AppThemePreference.light);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    settings.savedSource = null;
    await tester.tap(find.text('Music Source'));
    await tester.pumpAndSettle();

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('BuguYY'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);

    await tester.tap(find.text('FLAC'));
    await tester.pumpAndSettle();

    expect(settings.savedSource, MusicDataSource.flac);
    expect(settings.settings.source, MusicDataSource.flac);
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();

    expect(find.text('我的缓存列表'), findsOneWidget);
    expect(find.textContaining('收藏'), findsOneWidget);
    expect(find.textContaining('本地'), findsOneWidget);
    expect(find.text('还没有自建歌单'), findsOneWidget);
    expect(find.text('全部缓存'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('稻香'), findsNothing);

    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsOneWidget);
    expect(find.textContaining('周杰伦'), findsOneWidget);
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

    await tester.tap(find.byTooltip('播放列表'));
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

    await tester.tap(find.byTooltip('播放列表'));
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

    await tester.tap(find.byTooltip('播放列表'));
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

    await tester.tap(find.byTooltip('播放列表'));
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

    await tester.tap(find.byTooltip('播放列表'));
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本地'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加到歌单'));
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

    await tester.tap(find.byTooltip('播放列表'));
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
    expect(find.text('调整顺序'), findsOneWidget);
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    expect(find.byTooltip('排序'), findsNothing);
    expect(find.text('调整顺序'), findsOneWidget);
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();

    expect(find.text('调整顺序'), findsOneWidget);
    expect(find.byTooltip('排序'), findsNothing);
    expect(find.byTooltip('拖拽排序'), findsNothing);
    expect(find.byTooltip('添加到歌单'), findsWidgets);

    await tester.tap(find.text('调整顺序'));
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

    await tester.tap(find.byTooltip('播放列表'));
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

    await tester.tap(find.text('调整顺序'));
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整顺序'));
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pumpAndSettle();

    await tester.tap(find.text('调整顺序'));
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

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整顺序'));
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

    await tester.tap(find.byTooltip('播放列表'));
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
  _FakeMusicResolver? resolver,
  _FakeCacheStore? cacheStore,
  _FakePlaylistStore? playlistStore,
  _FakeSettingsStore? settings,
  TrackMetadataRepository? metadataRepository,
  MusicAudioHandler? audioHandler,
  PlaybackStateStore? playbackStateStore,
  HotlistRepository? hotlistRepository,
}) {
  final controller = MusicController(
    audioHandler: audioHandler ?? MusicAudioHandler(),
    resolver: resolver ?? _FakeMusicResolver(),
    cacheStore: cacheStore ?? _FakeCacheStore(),
    playlistStore: playlistStore ?? _FakePlaylistStore(),
    settingsStore: settings ?? _FakeSettingsStore(),
    playbackStateStore: playbackStateStore ?? _FakePlaybackStateStore(),
    metadataRepository: metadataRepository ?? _FakeMetadataRepository(),
    hotlistRepository: hotlistRepository ?? _StaticHotlistRepository(const []),
  );
  return AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      return MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: controller.themePreference == AppThemePreference.light
            ? ThemeMode.light
            : ThemeMode.dark,
        builder: (context, child) => AppStringsScope(
          language: controller.language,
          child: child ?? const SizedBox.shrink(),
        ),
        home: MusicHomePage(controller: controller),
      );
    },
  );
}

HotlistChart _hotlistChart() {
  return HotlistChart(
    source: HotlistSource.qq,
    chartId: '26',
    title: 'QQ 热歌榜',
    description: 'QQ 音乐热歌榜元数据',
    coverUrl: '',
    period: '2026-07-05',
    updatedAt: DateTime(2026, 7, 5),
    items: const [
      HotlistItem(
        rank: 1,
        title: '第一首',
        artist: '歌手 A',
        album: '专辑一',
        coverUrl: '',
        sourceTrackId: '1001',
        durationMs: 213000,
        rankChange: '',
      ),
    ],
  );
}

class _StaticHotlistRepository extends HotlistRepository {
  _StaticHotlistRepository(this.charts)
    : super(provider: _NeverHotlistProvider());

  final List<HotlistChart> charts;

  @override
  Future<List<HotlistChart>> loadCharts({bool forceRefresh = false}) async {
    return charts;
  }
}

class _NeverHotlistProvider implements HotlistProvider {
  @override
  Future<HotlistChart> fetchQqHotChart() {
    throw StateError('unused');
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
  int skipNextCalls = 0;
  int skipPreviousCalls = 0;

  void emit(MediaItem? item) {
    mediaItem.add(item);
  }

  @override
  Future<void> skipToNext() async {
    skipNextCalls += 1;
  }

  @override
  Future<void> skipToPrevious() async {
    skipPreviousCalls += 1;
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

class _FakePlaybackStateStore extends PlaybackStateStore {
  _FakePlaybackStateStore() : super(rootProvider: _unusedRootProvider);

  SavedPlaybackState? state;

  @override
  Future<SavedPlaybackState?> load() async {
    return state;
  }

  @override
  Future<void> save(SavedPlaybackState state) async {
    this.state = state;
  }

  @override
  Future<void> clear() async {
    state = null;
  }
}

class _FakeCacheStore extends CachedTrackStore {
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
