import 'dart:async';
import 'dart:convert';

import 'package:ai_music/src/application/chart_playlist_importer.dart';
import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/data/music_charts.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/discover_charts.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog matches the QQ and NetEase chart groups', () {
    expect(qqMusicCharts.map((chart) => chart.title), [
      '飙升榜',
      '热歌榜',
      '新歌榜',
      '流行指数榜',
      '听歌识曲榜',
      'MV榜',
    ]);
    expect(neteaseMusicCharts.map((chart) => chart.title), [
      '飙升榜',
      '新歌榜',
      '原创榜',
      '热歌榜',
    ]);
    expect(qqMusicCharts.last.isVideo, isTrue);
  });

  test('QQ chart request parses ranked songs and MV entries', () async {
    final http = _ChartHttp((uri) {
      expect(uri.host, 'u.y.qq.com');
      final request = jsonDecode(uri.queryParameters['data']!) as Map;
      final detail = request['detail'] as Map;
      final params = detail['param'] as Map;
      expect(params['offset'], 0);
      expect(params['num'], 300);
      return {
        'detail': {
          'code': 0,
          'data': {
            'data': {
              'updateTime': '2026-09-26',
              'song': [
                {
                  'rank': 1,
                  'title': params['topId'] == 201 ? 'Video A' : 'Song A',
                  'singerName': 'Artist A',
                  'cover': 'http://img.example.test/a.jpg',
                },
              ],
            },
          },
        },
      };
    });
    final repo = MusicChartRepository(httpClient: http);

    final songs = await repo.load(qqMusicCharts[1]);
    final videos = await repo.load(qqMusicCharts.last);

    expect(songs.entries.single.title, 'Song A');
    expect(songs.entries.single.artworkUri?.scheme, 'https');
    expect(videos.entries.single.title, 'Video A');
    expect(videos.entries.single.rank, 1);
  });

  test('NetEase chart keeps all returned tracks in rank order', () async {
    final repo = MusicChartRepository(
      httpClient: _ChartHttp((uri) {
        expect(uri.host, 'music.163.com');
        expect(uri.queryParameters['id'], '3778678');
        return {
          'code': 200,
          'result': {
            'tracks': [
              {
                'name': 'First',
                'artists': [
                  {'name': 'A'},
                  {'name': 'B'},
                ],
                'album': {'picUrl': 'https://img.example.test/first.jpg'},
              },
              {
                'name': 'Second',
                'artists': [
                  {'name': 'C'},
                ],
              },
            ],
          },
        };
      }),
    );

    final result = await repo.load(neteaseMusicCharts.last);

    expect(result.entries.map((entry) => entry.rank), [1, 2]);
    expect(result.entries.first.artist, 'A / B');
    expect(result.entries.last.title, 'Second');
  });

  test(
    'playlist matching preserves selected chart order and skips misses',
    () async {
      final resolver = _ChartSearchResolver();
      final importer = ChartPlaylistImporter(
        ScreenshotMatcher(
          resolver: resolver,
          requestStartSpacing: Duration.zero,
        ),
      );
      final progress = <int>[];
      final result = await importer.match(
        const [
          MusicChartEntry(rank: 1, title: 'Slow', artist: 'A'),
          MusicChartEntry(rank: 2, title: 'Missing', artist: 'B'),
          MusicChartEntry(rank: 3, title: 'Fast', artist: 'C'),
        ],
        concurrency: 3,
        onProgress: (completed, _) => progress.add(completed),
      );

      expect(result.candidates.map((candidate) => candidate.name), [
        'Slow',
        'Fast',
      ]);
      expect(result.failed, 1);
      expect(progress.last, 3);
    },
  );

  test(
    'chart import rejects a different artist or a different title',
    () async {
      final importer = ChartPlaylistImporter(
        ScreenshotMatcher(
          resolver: _MappedChartSearchResolver({
            '遇见': [_chartCandidate('遇见', '其他歌手')],
            '天黑黑': [_chartCandidate('别的歌', '孙燕姿')],
          }),
          requestStartSpacing: Duration.zero,
        ),
      );

      final result = await importer.match(const [
        MusicChartEntry(rank: 1, title: '遇见', artist: '孙燕姿'),
        MusicChartEntry(rank: 2, title: '天黑黑', artist: '孙燕姿'),
      ]);

      expect(result.candidates, isEmpty);
      expect(result.failed, 2);
    },
  );

  test(
    'chart import accepts the exact multi-artist result after a bad first hit',
    () async {
      final importer = ChartPlaylistImporter(
        ScreenshotMatcher(
          resolver: _MappedChartSearchResolver({
            '合唱': [_chartCandidate('合唱', 'A'), _chartCandidate('合唱', 'B，A')],
          }),
          requestStartSpacing: Duration.zero,
        ),
      );

      final result = await importer.match(const [
        MusicChartEntry(rank: 1, title: '合唱', artist: 'A / B'),
      ]);

      expect(result.candidates.single.artist, 'B，A');
      expect(result.failed, 0);
    },
  );

  test('chart import stops scheduling after a source failure', () async {
    final resolver = _MappedChartSearchResolver(
      {},
      onSearch: (_) async => throw StateError('HTTP 429'),
    );
    final importer = ChartPlaylistImporter(
      ScreenshotMatcher(resolver: resolver, requestStartSpacing: Duration.zero),
    );

    final result = await importer.match(const [
      MusicChartEntry(rank: 1, title: 'A', artist: 'Singer'),
      MusicChartEntry(rank: 2, title: 'B', artist: 'Singer'),
      MusicChartEntry(rank: 3, title: 'C', artist: 'Singer'),
    ], concurrency: 1);

    expect(resolver.queries, ['A']);
    expect(result.serviceError, isNotNull);
    expect(result.failed, 0);
    expect(result.unprocessed, 2);
  });

  test('chart import stops scheduling after its page is canceled', () async {
    final first = Completer<List<MusicSearchCandidate>>();
    final resolver = _MappedChartSearchResolver(
      {},
      onSearch: (query) => query == 'A' ? first.future : Future.value([]),
    );
    final importer = ChartPlaylistImporter(
      ScreenshotMatcher(resolver: resolver, requestStartSpacing: Duration.zero),
    );
    var canceled = false;

    final work = importer.match(
      const [
        MusicChartEntry(rank: 1, title: 'A', artist: 'Singer'),
        MusicChartEntry(rank: 2, title: 'B', artist: 'Singer'),
        MusicChartEntry(rank: 3, title: 'C', artist: 'Singer'),
      ],
      concurrency: 1,
      isCanceled: () => canceled,
    );
    await Future<void>.delayed(Duration.zero);
    canceled = true;
    first.complete([_chartCandidate('A', 'Singer')]);
    final result = await work;

    expect(resolver.queries, ['A']);
    expect(result.canceled, isTrue);
    expect(result.unprocessed, 2);
  });

  testWidgets('discover offers every requested chart in two platform groups', (
    tester,
  ) async {
    final opened = <MusicChart>[];
    await tester.pumpWidget(
      _app(DiscoverChartsSection(onOpenChart: opened.add)),
    );

    expect(find.text('发现'), findsOneWidget);
    expect(find.text('QQ音乐'), findsOneWidget);
    expect(find.text('网易云音乐'), findsOneWidget);
    for (final chart in [...qqMusicCharts, ...neteaseMusicCharts]) {
      expect(
        find.byKey(ValueKey('chart-${chart.platform.name}-${chart.id}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('chart-qq-26')));
    expect(opened.single.id, 26);
  });

  testWidgets('chart supports individual and all-song selection', (
    tester,
  ) async {
    final handler = MusicAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      connectivityChanges: const Stream.empty(),
      checkConnectivity: () async => [],
    );
    try {
      await tester.pumpWidget(
        _app(
          MusicChartPage(
            chart: qqMusicCharts[1],
            controller: controller,
            onSearchSong: (_) {},
            repository: _FixedChartRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chart-entry-1')));
      await tester.pump();
      expect(find.text('已选 1 首'), findsOneWidget);

      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(find.text('已选 2 首'), findsOneWidget);

      await tester.tap(find.text('取消全选'));
      await tester.pump();
      expect(find.text('已选 0 首'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
    }
  });

  testWidgets('refresh clears selected rows before the network completes', (
    tester,
  ) async {
    final handler = MusicAudioHandler();
    final controller = MusicController(
      audioHandler: handler,
      connectivityChanges: const Stream.empty(),
      checkConnectivity: () async => [],
    );
    final repository = _RefreshingChartRepository();
    try {
      await tester.pumpWidget(
        _app(
          MusicChartPage(
            chart: qqMusicCharts[1],
            controller: controller,
            onSearchSong: (_) {},
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chart-entry-1')));
      await tester.pump();
      expect(find.text('已选 1 首'), findsOneWidget);

      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(find.text('已选 1 首'), findsNothing);
      expect(find.byKey(const ValueKey('chart-entry-1')), findsNothing);
      repository.refresh.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chart-entry-1')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
    }
  });
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: AppStringsScope(language: AppLanguage.zh, child: child),
  ),
);

class _FixedChartRepository extends MusicChartRepository {
  @override
  Future<MusicChartResult> load(MusicChart chart) async =>
      const MusicChartResult(
        entries: [
          MusicChartEntry(rank: 1, title: 'First', artist: 'A'),
          MusicChartEntry(rank: 2, title: 'Second', artist: 'B'),
        ],
      );
}

class _RefreshingChartRepository extends _FixedChartRepository {
  final refresh = Completer<MusicChartResult>();
  int calls = 0;

  @override
  Future<MusicChartResult> load(MusicChart chart) {
    calls += 1;
    return calls == 1 ? super.load(chart) : refresh.future;
  }
}

class _ChartHttp implements MusicResolverHttp {
  _ChartHttp(this.respond);

  final Map<String, dynamic> Function(Uri uri) respond;

  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async => ResolverHttpResponse(
    statusCode: 200,
    body: jsonEncode(respond(uri)),
    finalUrl: uri,
  );

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) => throw UnimplementedError();

  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) => throw UnimplementedError();
}

class _ChartSearchResolver implements MusicResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    if (query == 'Slow') {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (query == 'Missing') return const [];
    return [
      MusicSearchCandidate(
        query: query,
        source: MusicDataSource.buguyy,
        platform: 'kuwo',
        keyword: query,
        page: 1,
        id: query,
        name: query,
        artist: query == 'Slow' ? 'A' : 'C',
        album: '',
        duration: 0,
        link: '',
        coverUrl: '',
        qualities: const [],
        score: 1,
        raw: const {},
      ),
    ];
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw UnimplementedError();
}

class _MappedChartSearchResolver implements MusicResolver {
  _MappedChartSearchResolver(this.results, {this.onSearch});

  final Map<String, List<MusicSearchCandidate>> results;
  final Future<List<MusicSearchCandidate>> Function(String query)? onSearch;
  final List<String> queries = [];

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    queries.add(query);
    final action = onSearch;
    return action == null ? results[query] ?? const [] : action(query);
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw UnimplementedError();
}

MusicSearchCandidate _chartCandidate(String title, String artist) =>
    MusicSearchCandidate(
      query: title,
      source: MusicDataSource.buguyy,
      platform: 'kuwo',
      keyword: title,
      page: 1,
      id: '$title|$artist',
      name: title,
      artist: artist,
      album: '',
      duration: 0,
      link: '',
      coverUrl: '',
      qualities: const [],
      score: 1,
      raw: const {},
    );
