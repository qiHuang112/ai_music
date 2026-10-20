import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'resolver_http_client.dart';
import 'resolver_models.dart';

/// Read public metadata only; audio playback keeps using the existing sources.
class QishuiApi {
  QishuiApi({MusicResolverHttp? httpClient}) : _http = httpClient;
  final MusicResolverHttp? _http;

  Future<Map<String, dynamic>> search(
    String kind,
    String query, {
    int offset = 0,
    int count = 20,
  }) => _get('/luna/search/$kind', {
    'q': query,
    'cursor': '$offset',
    'count': '$count',
  });

  Future<Map<String, dynamic>> playlist(String id, String cursor) => _get(
    '/luna/pc/playlist/detail',
    {'playlist_id': id, 'cursor': cursor, 'count': '100'},
  );

  Future<Map<String, dynamic>> comments(String id, String cursor) =>
      _get('/luna/pc/comments', {
        'group_id': id,
        'group_type': '1',
        'image_strategy': '2',
        'cursor': cursor,
        'count': '20',
      });

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final http = _http ?? HttpMusicResolverClient();
    try {
      final uri = Uri.https('api.qishui.com', path, {
        'aid': '386088',
        'device_platform': 'web',
        'channel': 'pc_web',
        ...query,
      });
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://www.qishui.com/',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (!response.ok) {
        throw HttpException('Qishui HTTP ${response.statusCode}', uri: uri);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Missing Qishui metadata');
      }
      final code =
          decoded['status_code'] ??
          qishuiMap(decoded['status_info'])['status_code'] ??
          decoded['code'];
      if (code != null && code.toString() != '0') {
        throw StateError('Qishui metadata unavailable');
      }
      return decoded;
    } finally {
      if (_http == null && http is HttpMusicResolverClient) http.close();
    }
  }
}

Map<String, dynamic> qishuiMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String qishuiText(Object? value) => value?.toString().trim() ?? '';

String qishuiArtists(Object? value) => value is List
    ? value
          .map((a) => qishuiText(qishuiMap(a)['name']))
          .where((a) => a.isNotEmpty)
          .join(' / ')
    : '';

String qishuiCover(Object? value) {
  final map = qishuiMap(value);
  final urls = map['urls'];
  if (urls is! List) return '';
  for (final value in urls) {
    final url = qishuiText(value);
    final uri = Uri.tryParse(url);
    if (uri?.scheme != 'https' || uri!.host.isEmpty) continue;
    if (!url.endsWith('/img/')) return url;
    final image = qishuiText(map['uri']);
    if (image.isEmpty) continue;
    final template = qishuiText(map['template_prefix']);
    final suffix = template.isEmpty
        ? '~c5_300x300.jpg'
        : '~$template-resize:300:300.png';
    return '$url$image$suffix';
  }
  return '';
}

List<Map<String, dynamic>> qishuiSearchRows(
  Map<String, dynamic> data,
  String group,
) {
  final groups = data['result_groups'];
  if (groups is! List) throw const FormatException('Missing Qishui results');
  final rows = <Map<String, dynamic>>[];
  for (final value in groups) {
    final map = qishuiMap(value);
    if (map['id'] != group) continue;
    if (map['data'] is! List) {
      throw const FormatException('Missing Qishui result rows');
    }
    rows.addAll((map['data'] as List).map(qishuiMap));
  }
  return rows;
}
