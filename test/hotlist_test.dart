import 'dart:io';

import 'package:ai_music/src/data/hotlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses QQ hot chart detail fixture', () {
    final chart = parseQqHotlistDetail(_qqFixture);

    expect(chart.source, HotlistSource.qq);
    expect(chart.chartId, '26');
    expect(chart.title, '热歌');
    expect(chart.period, '2026-07-04');
    expect(chart.updatedAt, DateTime(2026, 7, 4));
    expect(chart.items, hasLength(2));
    expect(chart.items.first.rank, 1);
    expect(chart.items.first.title, '第一首');
    expect(chart.items.first.artist, '歌手 A / 歌手 B');
    expect(chart.items.first.album, '专辑一');
    expect(chart.items.first.durationMs, 213000);
    expect(chart.items.first.searchQuery, '第一首 歌手 A / 歌手 B');
  });

  test('uses fresh cache before provider and logs cache hit', () async {
    final root = await Directory.systemTemp.createTemp('hotlist_cache_');
    addTearDown(() => root.delete(recursive: true));
    final cache = HotlistCacheStore(rootProvider: () async => root);
    await cache.write(
      HotlistSnapshot(
        chart: _chart(title: '缓存热歌'),
        savedAt: DateTime(2026, 7, 5, 8),
      ),
    );
    final repository = HotlistRepository(
      provider: _ThrowingHotlistProvider(),
      cacheStore: cache,
      now: () => DateTime(2026, 7, 5, 10),
    );

    final charts = await repository.loadCharts();

    expect(charts.single.title, '缓存热歌');
    expect(charts.single.fromCache, isTrue);
    expect(repository.logs, contains('qq:cache-hit:26'));
  });

  test('falls back to stale cache after provider failure', () async {
    final root = await Directory.systemTemp.createTemp('hotlist_stale_');
    addTearDown(() => root.delete(recursive: true));
    final cache = HotlistCacheStore(rootProvider: () async => root);
    await cache.write(
      HotlistSnapshot(
        chart: _chart(title: '旧热歌'),
        savedAt: DateTime(2026, 7, 1),
      ),
    );
    final repository = HotlistRepository(
      provider: _ThrowingHotlistProvider(),
      cacheStore: cache,
      now: () => DateTime(2026, 7, 5),
    );

    final charts = await repository.loadCharts(forceRefresh: true);

    expect(charts.single.title, '旧热歌');
    expect(charts.single.fromCache, isTrue);
    expect(charts.single.isStale, isTrue);
    expect(repository.logs.single, startsWith('qq:stale-fallback:26:'));
  });

  test('hides expired stale cache when provider fails', () async {
    final root = await Directory.systemTemp.createTemp('hotlist_expired_');
    addTearDown(() => root.delete(recursive: true));
    final cache = HotlistCacheStore(rootProvider: () async => root);
    await cache.write(
      HotlistSnapshot(chart: _chart(), savedAt: DateTime(2026, 6, 20)),
    );
    final repository = HotlistRepository(
      provider: _ThrowingHotlistProvider(),
      cacheStore: cache,
      now: () => DateTime(2026, 7, 5),
    );

    await expectLater(
      repository.loadCharts(forceRefresh: true),
      throwsA(isA<StateError>()),
    );
    expect(repository.logs.single, startsWith('qq:miss:26:'));
  });
}

HotlistChart _chart({String title = 'QQ 热歌榜'}) {
  return HotlistChart(
    source: HotlistSource.qq,
    chartId: '26',
    title: title,
    description: '仅元数据',
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

class _ThrowingHotlistProvider implements HotlistProvider {
  @override
  Future<HotlistChart> fetchQqHotChart() {
    throw StateError('provider down');
  }
}

const _qqFixture = '''
{
  "detail": {
    "data": {
      "data": {
        "period": "2026-07-04",
        "updateTime": "2026-07-04",
        "title": "巅峰榜·热歌",
        "intro": "每日更新",
        "headPicUrl": "https://example.test/cover.jpg",
        "song": [
          {
            "rank": 1,
            "title": "第一首",
            "singer": [{"name": "歌手 A"}, {"name": "歌手 B"}],
            "albumMid": "abc",
            "album": {"title": "专辑一"},
            "songId": 1001,
            "interval": 213
          },
          {
            "rank": 2,
            "title": "第二首",
            "singerName": "歌手 C",
            "album": {"name": "专辑二"},
            "mid": "song-mid",
            "interval": 180
          }
        ]
      }
    }
  }
}
''';
