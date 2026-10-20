import 'operation_log.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'qishui_api.dart';

enum OnlinePlaylistSource { netease, qq, qishui }

extension OnlinePlaylistSourceLabel on OnlinePlaylistSource {
  String get label => switch (this) {
    OnlinePlaylistSource.netease => '网易云音乐',
    OnlinePlaylistSource.qq => 'QQ 音乐',
    OnlinePlaylistSource.qishui => '汽水音乐',
  };
}

class OnlinePlaylist {
  const OnlinePlaylist({
    required this.source,
    required this.id,
    required this.name,
    required this.creator,
    required this.trackCount,
    this.coverUrl = '',
    this.description = '',
  });

  final OnlinePlaylistSource source;
  final String id;
  final String name;
  final String creator;
  final int trackCount;
  final String coverUrl;
  final String description;
  String get key => '${source.name}:$id';
}

class OnlinePlaylistSearchPage {
  const OnlinePlaylistSearchPage({required this.items, required this.hasMore});
  final List<OnlinePlaylist> items;
  final bool hasMore;
}

class OnlinePlaylistSong {
  const OnlinePlaylistSong({
    required this.id,
    required this.title,
    required this.artist,
    this.durationSeconds = 0,
  });
  final String id;
  final String title;
  final String artist;
  final int durationSeconds;
}

class OnlinePlaylistDetail {
  const OnlinePlaylistDetail({required this.songs, required this.total});
  final List<OnlinePlaylistSong> songs;
  final int total;
  int get unavailable => math.max(0, total - songs.length);
}

/// Public playlist metadata only. Playback continues through the existing resolver.
class OnlinePlaylistRepository {
  OnlinePlaylistRepository({MusicResolverHttp? httpClient})
    : _http = httpClient ?? HttpMusicResolverClient();

  final MusicResolverHttp _http;
  static const pageSize = 20;
  static const _maximumSongs = 10000;
  static const _qqHeaders = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://y.qq.com/',
  };
  static const _neHeaders = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://music.163.com/',
  };

  Future<OnlinePlaylistSearchPage> search(
    OnlinePlaylistSource source,
    String query, {
    int page = 1,
  }) async {
    OperationLog.event('playlist.search', {
      'source': source.name,
      'query': query,
      'page': page,
    });
    if (query.trim().isEmpty) {
      return const OnlinePlaylistSearchPage(items: [], hasMore: false);
    }
    if (page < 1) throw ArgumentError.value(page, 'page');
    if (source == OnlinePlaylistSource.qishui) {
      final data = await QishuiApi(
        httpClient: _http,
      ).search('playlist', query.trim(), offset: (page - 1) * pageSize);
      final rows = qishuiSearchRows(data, 'playlists');
      final group = (data['result_groups'] as List)
          .map(qishuiMap)
          .where((g) => g['id'] == 'playlists')
          .firstOrNull;
      return OnlinePlaylistSearchPage(
        items: [
          for (final row in rows)
            if (qishuiMap(qishuiMap(row['entity'])['playlist']) case final item
                when _text(item['id']).isNotEmpty &&
                    _text(item['title']).isNotEmpty)
              OnlinePlaylist(
                source: source,
                id: _text(item['id']),
                name: _text(item['title']),
                creator:
                    _text(qishuiMap(item['owner'])['public_name']).isNotEmpty
                    ? _text(qishuiMap(item['owner'])['public_name'])
                    : _text(qishuiMap(item['owner'])['nickname']),
                trackCount: _int(item['count_tracks']),
                coverUrl: qishuiCover(item['url_cover']),
                description: _text(item['desc']),
              ),
        ],
        hasMore: rows.isNotEmpty && group?['has_more'] == true,
      );
    }
    if (source == OnlinePlaylistSource.qq) {
      final data = await _qq(
        'music.search.SearchCgiService',
        'DoSearchForQQMusicDesktop',
        {
          'query': query.trim(),
          'search_type': 3,
          'page_num': page,
          'num_per_page': pageSize,
        },
      );
      final list = _map(_map(data['body'])['songlist'])['list'];
      if (list is! List) {
        throw const FormatException('Missing QQ playlist results');
      }
      final items = <OnlinePlaylist>[];
      for (final item in list) {
        final row = _map(item);
        final id = _text(row['dissid']);
        final name = _text(row['dissname']);
        if (id.isEmpty || name.isEmpty) continue;
        items.add(
          OnlinePlaylist(
            source: source,
            id: id,
            name: name,
            creator: _text(_map(row['creator'])['name']),
            trackCount: _int(row['song_count']),
            coverUrl: _text(row['imgurl']),
            description: _text(row['introduction']),
          ),
        );
      }
      return OnlinePlaylistSearchPage(
        items: items,
        hasMore:
            list.isNotEmpty &&
            page * pageSize < _int(_map(data['meta'])['sum']),
      );
    }
    final data = _decode(
      await _http.postForm(Uri.https('music.163.com', '/api/search/get'), {
        's': query.trim(),
        'type': '1000',
        'limit': '$pageSize',
        'offset': '${(page - 1) * pageSize}',
      }, headers: _neHeaders),
      200,
    );
    final result = _map(data['result']);
    final list = result['playlists'];
    if (list == null &&
        _int(result['playlistCount']) == 0 &&
        data['result'] is Map) {
      return const OnlinePlaylistSearchPage(items: [], hasMore: false);
    }
    if (list is! List) {
      throw const FormatException('Missing NetEase playlist results');
    }
    return OnlinePlaylistSearchPage(
      items: [
        for (final item in list)
          if (_text(_map(item)['id']).isNotEmpty &&
              _text(_map(item)['name']).isNotEmpty)
            OnlinePlaylist(
              source: source,
              id: _text(_map(item)['id']),
              name: _text(_map(item)['name']),
              creator: _text(_map(_map(item)['creator'])['nickname']),
              trackCount: _int(_map(item)['trackCount']),
              coverUrl: _text(_map(item)['coverImgUrl']),
              description: _text(_map(item)['description']),
            ),
      ],
      hasMore:
          list.isNotEmpty &&
          (result['hasMore'] == true ||
              page * pageSize < _int(result['playlistCount'])),
    );
  }

  /// Refresh the original identity of a legacy QQ playlist entry by its exact
  /// platform ID, never by fuzzy search. No audio or account access is involved.
  Future<OnlinePlaylistSong> loadQqSong(String id) async {
    if (!RegExp(r'^\d+$').hasMatch(id)) throw ArgumentError.value(id, 'id');
    final data = await _qq('music.pf_song_detail_svr', 'get_song_detail_yqq', {
      'song_id': int.parse(id),
    });
    final row = _map(data['track_info']);
    final title = _qqSongTitle(row);
    if (_text(row['id']) != id || title.isEmpty) {
      throw const FormatException('QQ returned another song identity');
    }
    return OnlinePlaylistSong(
      id: id,
      title: title,
      artist: _artists(row['singer']),
      durationSeconds: _int(row['interval']),
    );
  }

  Future<OnlinePlaylistDetail> load(
    OnlinePlaylist playlist, {
    bool Function()? isCanceled,
    void Function(int loaded, int total)? onProgress,
  }) async {
    OperationLog.event('playlist.load', {
      'source': playlist.source.name,
      'id': playlist.id,
      'title': playlist.name,
    });
    void checkCanceled() {
      if (isCanceled?.call() ?? false) throw StateError('Canceled');
    }

    if (playlist.source == OnlinePlaylistSource.qishui) {
      final api = QishuiApi(httpClient: _http);
      final songs = <OnlinePlaylistSong>[];
      final ids = <String>{};
      final cursors = <String>{};
      var cursor = '0';
      var total = playlist.trackCount;
      for (var window = 0; window < _maximumSongs; window += 100) {
        checkCanceled();
        if (!cursors.add(cursor)) {
          throw const FormatException('Repeated Qishui cursor');
        }
        final data = await api.playlist(playlist.id, cursor);
        checkCanceled();
        final metadata = qishuiMap(data['playlist']);
        if (_text(metadata['id']) != playlist.id ||
            data['media_resources'] is! List) {
          throw const FormatException('Missing Qishui playlist tracks');
        }
        total = math.max(total, _int(metadata['count_tracks']));
        for (final raw in data['media_resources'] as List) {
          final row = qishuiMap(raw);
          if (row['type'] != 'track') continue;
          final track = qishuiMap(
            qishuiMap(qishuiMap(row['entity'])['track_wrapper'])['track'],
          );
          final id = _text(track['id']);
          if (id.isEmpty || _text(track['name']).isEmpty || !ids.add(id)) {
            continue;
          }
          songs.add(
            OnlinePlaylistSong(
              id: id,
              title: _text(track['name']),
              artist: qishuiArtists(track['artists']),
              durationSeconds: (_int(track['duration']) / 1000).round(),
            ),
          );
        }
        onProgress?.call(songs.length, math.max(total, songs.length));
        // The API omits protobuf false fields on the last page.
        if (data['has_more'] == null || data['has_more'] == false) {
          return OnlinePlaylistDetail(
            songs: songs,
            total: math.max(total, songs.length),
          );
        }
        final next = _text(data['next_cursor']);
        if (data['has_more'] != true ||
            next.isEmpty ||
            cursors.contains(next)) {
          throw const FormatException('Invalid Qishui playlist pagination');
        }
        cursor = next;
      }
      throw StateError('Qishui playlist exceeds supported size');
    }

    if (playlist.source == OnlinePlaylistSource.qq) {
      final songs = <OnlinePlaylistSong>[];
      final seen = <String>{};
      var total = 0;
      for (var offset = 0; offset < _maximumSongs; offset += 20) {
        checkCanceled();
        final data =
            await _qq('music.srfDissInfo.aiDissInfo', 'uniform_get_Dissinfo', {
              'disstid': int.parse(playlist.id),
              'onlysong': 0,
              'song_begin': offset,
              'song_num': 20,
            });
        if (data['code'] != null && _int(data['code']) != 0) {
          throw StateError('QQ playlist unavailable');
        }
        if (data['songlist'] is! List || data['total_song_num'] == null) {
          throw const FormatException('Missing QQ playlist tracks');
        }
        total = math.max(total, _int(data['total_song_num']));
        for (final item in data['songlist'] as List) {
          final row = _map(item);
          final id = _text(row['id']);
          final title = _qqSongTitle(row);
          if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
          songs.add(
            OnlinePlaylistSong(
              id: id,
              title: title,
              artist: _artists(row['singer']),
              durationSeconds: _int(row['interval']),
            ),
          );
        }
        onProgress?.call(songs.length, total);
        // Advance by the requested window: QQ may filter songs from each page.
        if (offset + 20 >= total || _int(data['hasmore']) == 0) break;
      }
      checkCanceled();
      return OnlinePlaylistDetail(
        songs: songs,
        total: math.max(total, songs.length),
      );
    }
    checkCanceled();
    final data = _decode(
      await _http.get(
        Uri.https('music.163.com', '/api/v6/playlist/detail', {
          'id': playlist.id,
          'n': '100000',
          's': '0',
        }),
        headers: _neHeaders,
      ),
      200,
    );
    final info = _map(data['playlist']);
    if (info['trackIds'] is! List || info['tracks'] is! List) {
      throw const FormatException('Missing NetEase playlist tracks');
    }
    final ids = [
      for (final item in info['trackIds'] as List)
        if (_text(_map(item)['id']).isNotEmpty) _text(_map(item)['id']),
    ];
    final total = math.max(_int(info['trackCount']), ids.length);
    final byId = <String, OnlinePlaylistSong>{};
    void addSongs(List rows) {
      for (final item in rows) {
        final row = _map(item);
        final id = _text(row['id']);
        final title = _text(row['name']);
        if (id.isEmpty || title.isEmpty) continue;
        byId[id] = OnlinePlaylistSong(
          id: id,
          title: title,
          artist: _artists(row['ar'] ?? row['artists']),
          durationSeconds: (_int(row['dt'] ?? row['duration']) / 1000).round(),
        );
      }
    }

    addSongs(info['tracks'] as List);
    final wanted = ids.take(_maximumSongs).toList();
    final missing = wanted.where((id) => !byId.containsKey(id)).toList();
    onProgress?.call(wanted.where(byId.containsKey).length, total);
    for (var start = 0; start < missing.length; start += 100) {
      checkCanceled();
      final batch = missing.skip(start).take(100).map(int.parse).toList();
      final details = _decode(
        await _http.get(
          Uri.https('music.163.com', '/api/song/detail', {
            'ids': jsonEncode(batch),
          }),
          headers: _neHeaders,
        ),
        200,
      );
      if (details['songs'] is! List) {
        throw const FormatException('Missing song details');
      }
      addSongs(details['songs'] as List);
      onProgress?.call(wanted.where(byId.containsKey).length, total);
    }
    checkCanceled();
    return OnlinePlaylistDetail(
      songs: [
        for (final id in wanted)
          if (byId[id] != null) byId[id]!,
      ],
      total: total,
    );
  }

  Future<Map<String, dynamic>> _qq(
    String module,
    String method,
    Map<String, Object> param,
  ) async {
    final data = _decode(
      await _http.get(
        Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
          'format': 'json',
          'data': jsonEncode({
            'request': {'module': module, 'method': method, 'param': param},
          }),
        }),
        headers: _qqHeaders,
      ),
      0,
    );
    final request = _map(data['request']);
    if (request['code'] != 0 || request['data'] is! Map) {
      throw StateError('QQ Music request failed');
    }
    return _map(request['data']);
  }
}

Map<String, dynamic> _decode(ResolverHttpResponse response, int success) {
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}');
  }
  final data = _map(jsonDecode(response.body));
  if (data['code'] != success) {
    throw StateError('Playlist service: ${data['code']}');
  }
  return data;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : {};
int _int(Object? value) => int.tryParse('$value') ?? 0;
String _text(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();
String _artists(Object? value) => value is List
    ? value
          .map((item) => _text(_map(item)['name']))
          .where((name) => name.isNotEmpty)
          .join(' / ')
    : '';

String _qqSongTitle(Map<String, dynamic> row) {
  final full = _text(row['title']);
  return full.isNotEmpty ? full : _text(row['name']);
}
