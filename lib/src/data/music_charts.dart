import 'dart:convert';

import 'resolver_http_client.dart';
import 'resolver_models.dart';

enum MusicChartPlatform { qq, netease }

class MusicChart {
  const MusicChart({
    required this.platform,
    required this.id,
    required this.title,
    this.isVideo = false,
  });

  final MusicChartPlatform platform;
  final int id;
  final String title;
  final bool isVideo;
}

const qqMusicCharts = [
  MusicChart(platform: MusicChartPlatform.qq, id: 62, title: '飙升榜'),
  MusicChart(platform: MusicChartPlatform.qq, id: 26, title: '热歌榜'),
  MusicChart(platform: MusicChartPlatform.qq, id: 27, title: '新歌榜'),
  MusicChart(platform: MusicChartPlatform.qq, id: 4, title: '流行指数榜'),
  MusicChart(platform: MusicChartPlatform.qq, id: 67, title: '听歌识曲榜'),
  MusicChart(
    platform: MusicChartPlatform.qq,
    id: 201,
    title: 'MV榜',
    isVideo: true,
  ),
];

const neteaseMusicCharts = [
  MusicChart(platform: MusicChartPlatform.netease, id: 19723756, title: '飙升榜'),
  MusicChart(platform: MusicChartPlatform.netease, id: 3779629, title: '新歌榜'),
  MusicChart(platform: MusicChartPlatform.netease, id: 2884035, title: '原创榜'),
  MusicChart(platform: MusicChartPlatform.netease, id: 3778678, title: '热歌榜'),
];

class MusicChartEntry {
  const MusicChartEntry({
    required this.rank,
    required this.title,
    required this.artist,
    this.artworkUri,
  });

  final int rank;
  final String title;
  final String artist;
  final Uri? artworkUri;
}

class MusicChartResult {
  const MusicChartResult({required this.entries, this.updatedAt});

  final List<MusicChartEntry> entries;
  final String? updatedAt;
}

class MusicChartRepository {
  MusicChartRepository({MusicResolverHttp? httpClient})
    : _http = httpClient ?? HttpMusicResolverClient();

  final MusicResolverHttp _http;

  Future<MusicChartResult> load(MusicChart chart) async {
    return switch (chart.platform) {
      MusicChartPlatform.qq => _loadQq(chart),
      MusicChartPlatform.netease => _loadNetease(chart),
    };
  }

  Future<MusicChartResult> _loadQq(MusicChart chart) async {
    final request = {
      'detail': {
        'module': 'musicToplist.ToplistInfoServer',
        'method': 'GetDetail',
        'param': {'topId': chart.id, 'offset': 0, 'num': 300},
      },
    };
    final uri = Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
      'format': 'json',
      'data': jsonEncode(request),
    });
    final response = await _http.get(uri, headers: _qqHeaders);
    _checkHttp(response.statusCode);
    return parseQqChart(response.body);
  }

  Future<MusicChartResult> _loadNetease(MusicChart chart) async {
    final uri = Uri.https('music.163.com', '/api/playlist/detail', {
      'id': '${chart.id}',
    });
    final response = await _http.get(uri, headers: _neteaseHeaders);
    _checkHttp(response.statusCode);
    return parseNeteaseChart(response.body);
  }

  static void _checkHttp(int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw StateError('榜单请求失败（HTTP $statusCode）');
    }
  }

  static const _qqHeaders = {
    'user-agent': 'Mozilla/5.0',
    'referer': 'https://y.qq.com/',
  };
  static const _neteaseHeaders = {
    'user-agent': 'Mozilla/5.0',
    'referer': 'https://music.163.com/',
  };
}

MusicChartResult parseQqChart(String body) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  final detail = _object(root['detail']);
  if (detail['code'] != 0) throw const FormatException('QQ 音乐榜单不可用');
  final data = _object(_object(detail['data'])['data']);
  final songs = data['song'];
  if (songs is! List) throw const FormatException('QQ 音乐榜单缺少歌曲');
  final entries = <MusicChartEntry>[];
  for (final raw in songs) {
    final song = _object(raw);
    final title = (song['title'] as String? ?? '').trim();
    if (title.isEmpty) continue;
    entries.add(
      MusicChartEntry(
        rank: (song['rank'] as num?)?.toInt() ?? entries.length + 1,
        title: title,
        artist: (song['singerName'] as String? ?? '').trim(),
        artworkUri: _httpsUri(song['cover']),
      ),
    );
  }
  return MusicChartResult(
    entries: List.unmodifiable(entries),
    updatedAt: data['updateTime'] as String?,
  );
}

MusicChartResult parseNeteaseChart(String body) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  if (root['code'] != 200) {
    throw const FormatException('网易云音乐榜单不可用');
  }
  final result = _object(root['result']);
  final tracks = result['tracks'];
  if (tracks is! List) throw const FormatException('网易云音乐榜单缺少歌曲');
  final entries = <MusicChartEntry>[];
  for (final raw in tracks) {
    final song = _object(raw);
    final title = (song['name'] as String? ?? '').trim();
    if (title.isEmpty) continue;
    final artists = song['artists'];
    final artistNames = artists is List
        ? artists
              .map(
                (artist) => (_object(artist)['name'] as String? ?? '').trim(),
              )
              .where((name) => name.isNotEmpty)
              .join(' / ')
        : '';
    entries.add(
      MusicChartEntry(
        rank: entries.length + 1,
        title: title,
        artist: artistNames,
        artworkUri: _httpsUri(_object(song['album'])['picUrl']),
      ),
    );
  }
  final updated = result['updateTime'];
  final updatedAt = updated is num
      ? DateTime.fromMillisecondsSinceEpoch(updated.toInt()).toLocal()
      : null;
  return MusicChartResult(
    entries: List.unmodifiable(entries),
    updatedAt: updatedAt == null
        ? null
        : '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}'
              '-${updatedAt.day.toString().padLeft(2, '0')}',
  );
}

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

Uri? _httpsUri(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.replace(scheme: 'https');
}
