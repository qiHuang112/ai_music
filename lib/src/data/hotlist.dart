import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/app_storage.dart';
import 'json_file_store.dart';

enum HotlistSource { qq }

class HotlistChart {
  const HotlistChart({
    required this.source,
    required this.chartId,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.period,
    required this.updatedAt,
    required this.items,
    this.fromCache = false,
    this.isStale = false,
  });

  final HotlistSource source;
  final String chartId;
  final String title;
  final String description;
  final String coverUrl;
  final String period;
  final DateTime? updatedAt;
  final List<HotlistItem> items;
  final bool fromCache;
  final bool isStale;

  HotlistChart copyWith({
    List<HotlistItem>? items,
    bool? fromCache,
    bool? isStale,
  }) {
    return HotlistChart(
      source: source,
      chartId: chartId,
      title: title,
      description: description,
      coverUrl: coverUrl,
      period: period,
      updatedAt: updatedAt,
      items: items ?? this.items,
      fromCache: fromCache ?? this.fromCache,
      isStale: isStale ?? this.isStale,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'source': source.name,
      'chartId': chartId,
      'title': title,
      'description': description,
      'coverUrl': coverUrl,
      'period': period,
      'updatedAt': updatedAt?.toIso8601String(),
      'items': [for (final item in items) item.toJson()],
    };
  }

  static HotlistChart fromJson(Object? value) {
    final map = _asMap(value);
    return HotlistChart(
      source: HotlistSource.values.byName(_string(map['source'], 'qq')),
      chartId: _string(map['chartId']),
      title: _string(map['title']),
      description: _string(map['description']),
      coverUrl: _string(map['coverUrl']),
      period: _string(map['period']),
      updatedAt: DateTime.tryParse(_string(map['updatedAt'])),
      items: [
        for (final item in _asList(map['items'])) HotlistItem.fromJson(item),
      ],
    );
  }
}

class HotlistItem {
  const HotlistItem({
    required this.rank,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.sourceTrackId,
    required this.durationMs,
    required this.rankChange,
  });

  final int rank;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String sourceTrackId;
  final int? durationMs;
  final String rankChange;

  String get searchQuery {
    final trimmedArtist = artist.trim();
    if (trimmedArtist.isEmpty) {
      return title.trim();
    }
    return '${title.trim()} $trimmedArtist';
  }

  Map<String, Object?> toJson() {
    return {
      'rank': rank,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'sourceTrackId': sourceTrackId,
      'durationMs': durationMs,
      'rankChange': rankChange,
    };
  }

  static HotlistItem fromJson(Object? value) {
    final map = _asMap(value);
    return HotlistItem(
      rank: _int(map['rank']),
      title: _string(map['title']),
      artist: _string(map['artist']),
      album: _string(map['album']),
      coverUrl: _string(map['coverUrl']),
      sourceTrackId: _string(map['sourceTrackId']),
      durationMs: _nullableInt(map['durationMs']),
      rankChange: _string(map['rankChange']),
    );
  }
}

class HotlistSnapshot {
  const HotlistSnapshot({required this.chart, required this.savedAt});

  final HotlistChart chart;
  final DateTime savedAt;

  Map<String, Object?> toJson() {
    return {'savedAt': savedAt.toIso8601String(), 'chart': chart.toJson()};
  }

  static HotlistSnapshot fromJson(Object? value) {
    final map = _asMap(value);
    return HotlistSnapshot(
      savedAt: DateTime.parse(_string(map['savedAt'])),
      chart: HotlistChart.fromJson(map['chart']),
    );
  }
}

abstract interface class HotlistProvider {
  Future<HotlistChart> fetchQqHotChart();
}

class QqHotlistProvider implements HotlistProvider {
  QqHotlistProvider({
    HttpClient? client,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  @override
  Future<HotlistChart> fetchQqHotChart() async {
    final uri = Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
      'data': jsonEncode({
        'detail': {
          'module': 'musicToplist.ToplistInfoServer',
          'method': 'GetDetail',
          'param': {'topId': 26, 'num': 50, 'offset': 0},
        },
      }),
    });
    final request = await _client.getUrl(uri).timeout(timeout);
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'AI Music/1.0 hotlist metadata')
      ..set(HttpHeaders.refererHeader, 'https://y.qq.com/');
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('QQ hotlist HTTP ${response.statusCode}');
    }
    return parseQqHotlistDetail(body);
  }
}

class HotlistCacheStore {
  HotlistCacheStore({
    Future<Directory> Function()? rootProvider,
    JsonFileStore store = const JsonFileStore(),
  }) : _rootProvider =
           rootProvider ?? (() => getAiMusicSupportSubdirectory('hotlist')),
       _store = store;

  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _store;

  Future<HotlistSnapshot?> read(HotlistSource source, String chartId) async {
    final value = await _store.read(await _file(source, chartId));
    if (value == null) {
      return null;
    }
    return HotlistSnapshot.fromJson(value);
  }

  Future<void> write(HotlistSnapshot snapshot) async {
    await _store.write(
      await _file(snapshot.chart.source, snapshot.chart.chartId),
      snapshot.toJson(),
    );
  }

  Future<File> _file(HotlistSource source, String chartId) async {
    final root = await _rootProvider();
    return File(
      '${root.path}${Platform.pathSeparator}${source.name}-$chartId.json',
    );
  }
}

class HotlistRepository {
  HotlistRepository({
    HotlistProvider? provider,
    HotlistCacheStore? cacheStore,
    DateTime Function()? now,
    this.ttl = const Duration(hours: 12),
    this.maxStale = const Duration(days: 7),
  }) : _provider = provider ?? QqHotlistProvider(),
       _cacheStore = cacheStore ?? HotlistCacheStore(),
       _now = now ?? DateTime.now;

  final HotlistProvider _provider;
  final HotlistCacheStore _cacheStore;
  final DateTime Function() _now;
  final Duration ttl;
  final Duration maxStale;
  final List<String> logs = <String>[];

  Future<List<HotlistChart>> loadCharts({bool forceRefresh = false}) async {
    return [
      await _withCache(HotlistSource.qq, '26', forceRefresh: forceRefresh),
    ];
  }

  Future<HotlistChart> _withCache(
    HotlistSource source,
    String chartId, {
    required bool forceRefresh,
  }) async {
    final cached = await _readSnapshot(source, chartId);
    final now = _now();
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.savedAt) <= ttl) {
      logs.add('${source.name}:cache-hit:$chartId');
      return cached.chart.copyWith(fromCache: true);
    }
    try {
      final chart = await _provider.fetchQqHotChart();
      await _cacheStore.write(HotlistSnapshot(chart: chart, savedAt: now));
      logs.add('${source.name}:provider-hit:$chartId');
      return chart;
    } catch (error) {
      if (cached != null && now.difference(cached.savedAt) <= maxStale) {
        logs.add('${source.name}:stale-fallback:$chartId:$error');
        return cached.chart.copyWith(fromCache: true, isStale: true);
      }
      logs.add('${source.name}:miss:$chartId:$error');
      rethrow;
    }
  }

  Future<HotlistSnapshot?> _readSnapshot(HotlistSource source, String chartId) {
    return _cacheStore.read(source, chartId).catchError((Object error) {
      logs.add('${source.name}:cache-read-error:$chartId:$error');
      return null;
    });
  }
}

HotlistChart parseQqHotlistDetail(String body) {
  final root = jsonDecode(body);
  final detail = _asMap(_asMap(root)['detail']);
  final data = _asMap(detail['data']);
  final nestedData = _asMap(data['data']);
  final dataRoot = nestedData.isNotEmpty
      ? nestedData
      : (data.isEmpty ? _asMap(detail) : data);
  final info = _asMap(dataRoot['info']);
  final song = _asList(dataRoot['song']);
  final period = _string(dataRoot['period']);
  final updateTime = _string(dataRoot['updateTime']);
  final title = _string(dataRoot['title'], _string(info['title'], 'QQ 热歌榜'));
  final cover = _string(
    dataRoot['headPicUrl'],
    _string(
      dataRoot['frontPicUrl'],
      _string(info['headPicUrl'], _string(info['frontPicUrl'])),
    ),
  );
  return HotlistChart(
    source: HotlistSource.qq,
    chartId: '26',
    title: title.isEmpty ? 'QQ 热歌榜' : title.replaceAll('巅峰榜·', ''),
    description: _string(
      dataRoot['intro'],
      _string(info['intro'], 'QQ 音乐热歌榜元数据，仅用于发现音乐。'),
    ),
    coverUrl: cover,
    period: period,
    updatedAt: DateTime.tryParse(updateTime.isEmpty ? period : updateTime),
    items: [
      for (var index = 0; index < song.length; index += 1)
        _qqSongToItem(song[index], fallbackRank: index + 1),
    ],
  );
}

HotlistItem _qqSongToItem(Object? value, {required int fallbackRank}) {
  final map = _asMap(value);
  final rank = _int(map['rank'], fallbackRank);
  final singer = _asList(map['singer'])
      .map((item) => _string(_asMap(item)['name']))
      .where((name) => name.isNotEmpty)
      .join(' / ');
  final album = _asMap(map['album']);
  final mid = _string(album['mid'], _string(map['albumMid']));
  return HotlistItem(
    rank: rank,
    title: _string(map['title'], _string(map['name'])),
    artist: _string(map['singerName'], singer),
    album: _string(album['title'], _string(album['name'])),
    coverUrl: _qqCoverUrl(_string(map['cover']), mid),
    sourceTrackId: _string(
      map['songId'],
      _string(map['id'], _string(map['mid'])),
    ),
    durationMs: _nullableInt(map['interval']) == null
        ? null
        : _nullableInt(map['interval'])! * 1000,
    rankChange: _qqRankChange(map),
  );
}

String _qqCoverUrl(String cover, String albumMid) {
  if (cover.isNotEmpty) {
    return cover.startsWith('//') ? 'https:$cover' : cover;
  }
  if (albumMid.isEmpty) {
    return '';
  }
  return 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg';
}

String _qqRankChange(Map<String, Object?> map) {
  final type = _string(map['rankType']);
  final value = _string(map['rankValue']);
  if (type.isEmpty && value.isEmpty) {
    return '';
  }
  return value.isEmpty ? type : '$type $value';
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String _string(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

int _int(Object? value, [int fallback = 0]) {
  return _nullableInt(value) ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
