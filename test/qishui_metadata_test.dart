import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/application/online_playlist_search.dart';
import 'package:ai_music/src/data/online_playlists.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:ai_music/src/data/song_comments.dart';
import 'package:flutter_test/flutter_test.dart';

const _playlist = OnlinePlaylist(
  source: OnlinePlaylistSource.qishui,
  id: '7661483391803523099',
  name: '公开歌单',
  creator: '用户',
  trackCount: 2,
);
Map<String, Object> _track(
  String id, {
  String title = '枫',
  String artist = '等天黑',
}) => {
  'id': id,
  'name': title,
  'artists': [
    {'name': artist},
  ],
  'duration': 220000,
  'album': {'name': '专辑'},
};
Map<String, Object> _search(
  String kind,
  List<Map<String, Object>> rows, {
  bool more = false,
}) => {
  'result_groups': [
    {
      'id': '${kind}s',
      'has_more': more,
      'next_cursor': '20',
      'data': [
        for (final row in rows)
          {
            'entity': {kind: row},
          },
      ],
    },
  ],
};

void main() {
  test('Qishui successful zero-count response may omit its comments list', () {
    expect(
      parseSongComments(
        jsonEncode({
          'status_info': {},
          'count': 0,
          'cursor': 0,
          'has_more': false,
        }),
        SongCommentPlatform.qishui,
      ),
      isEmpty,
    );
  });

  test(
    'Qishui search preserves platform identity and uses public metadata paging',
    () async {
      final http = _Http((uri) async {
        expect(uri.path, '/luna/search/playlist');
        expect(uri.queryParameters['cursor'], '20');
        return _search('playlist', [
          {
            'id': _playlist.id,
            'title': '公开歌单',
            'count_tracks': 2,
            'owner': {'nickname': '用户'},
            'url_cover': {
              'urls': ['https://p3-luna.douyinpic.com/img/'],
              'uri': 'cover',
              'template_prefix': 'tplv-cover',
            },
          },
        ], more: true);
      });
      final result = await OnlinePlaylistRepository(
        httpClient: http,
      ).search(OnlinePlaylistSource.qishui, '公开', page: 2);
      expect(result.items.single.key, 'qishui:${_playlist.id}');
      expect(result.items.single.creator, '用户');
      expect(
        result.items.single.coverUrl,
        'https://p3-luna.douyinpic.com/img/cover~tplv-cover-resize:300:300.png',
      );
      expect(result.hasMore, true);
      expect(http.calls.single.queryParameters.containsKey('device_id'), false);
    },
  );

  test(
    'Qishui detail follows opaque cursor, filters video and preserves audio order',
    () async {
      final http = _Http((uri) async {
        final first = uri.queryParameters['cursor'] == '0';
        return {
          'playlist': {'id': _playlist.id, 'count_tracks': 2},
          'has_more': first,
          'next_cursor': first ? 'opaque-next' : '',
          'media_resources': [
            if (first) {'type': 'video', 'id': 'video'},
            {
              'type': 'track',
              'entity': {
                'track_wrapper': {'track': _track(first ? '11' : '22')},
              },
            },
          ],
        };
      });
      final result = await OnlinePlaylistRepository(
        httpClient: http,
      ).load(_playlist);
      expect(result.songs.map((s) => s.id), ['11', '22']);
      expect(result.songs.first.durationSeconds, 220);
      expect(result.unavailable, 0);
      expect(http.calls.last.queryParameters['cursor'], 'opaque-next');
    },
  );

  test(
    'Qishui detail rejects repeated cursors and honors cancellation after response',
    () async {
      var canceled = false;
      final http = _Http(
        (_) async => {
          'playlist': {'id': _playlist.id, 'count_tracks': 2},
          'media_resources': [],
          'has_more': true,
          'next_cursor': '0',
        },
      );
      final repository = OnlinePlaylistRepository(httpClient: http);
      await expectLater(repository.load(_playlist), throwsFormatException);
      http.respond = (_) async {
        canceled = true;
        return {
          'playlist': {'id': _playlist.id},
          'media_resources': [],
          'has_more': false,
        };
      };
      await expectLater(
        repository.load(_playlist, isCanceled: () => canceled),
        throwsStateError,
      );
      expect(http.calls, hasLength(2));
    },
  );

  test('Qishui remains visible when the other playlist sources fail', () async {
    final http = _Http((uri) async {
      if (uri.host != 'api.qishui.com') throw const SocketException('offline');
      return _search('playlist', [
        {'id': '77', 'title': '公开', 'count_tracks': 0},
      ]);
    });
    final search = OnlinePlaylistSearch(
      OnlinePlaylistRepository(httpClient: http),
    );
    await search.search('公开');
    expect(search.items.single.source, OnlinePlaylistSource.qishui);
    expect(search.errors, {
      OnlinePlaylistSource.qq,
      OnlinePlaylistSource.netease,
    });
    search.dispose();
  });

  test(
    'Qishui comments verify recording and use the upstream cursor across cached pages',
    () async {
      final http = _Http((uri) async {
        if (uri.path == '/luna/search/track') {
          return _search('track', [
            _track('wrong', title: '枫 (Live)'),
            _track('cover', artist: '另一位'),
            _track('42'),
          ]);
        }
        expect(uri.path, '/luna/pc/comments');
        expect(uri.queryParameters['group_id'], '42');
        expect(uri.queryParameters['group_type'], '1');
        final first = uri.queryParameters['cursor'] == '0';
        return {
          'comments': [
            {
              'id': first ? 'a' : 'b',
              'content': first ? '第一条' : '第二条',
              'user': {'nickname': '听众'},
              'count_digged': 12,
              'time_created': 1700000000,
            },
          ],
          'has_more': first,
          'cursor': first ? 'cursor-next' : 'done',
        };
      });
      final repository = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => throw UnsupportedError('memory'),
      );
      const query = SongCommentQuery(
        title: '枫',
        artist: '等天黑',
        durationSeconds: 220,
      );
      final first = await repository.load(query, SongCommentPlatform.qishui);
      expect(first.status, SongCommentsStatus.ready);
      expect(first.song?.id, '42');
      expect(first.comments.single.author, '听众');
      expect(
        first.comments.single.createdAt?.millisecondsSinceEpoch,
        1700000000000,
      );
      expect(first.nextCursor, 'cursor-next');
      final second = await repository.load(
        query,
        SongCommentPlatform.qishui,
        page: 1,
        cursor: first.nextCursor,
      );
      expect(second.comments.single.id, 'b');
      expect(second.hasMore, false);
      expect(
        (await repository.load(query, SongCommentPlatform.qishui)).fromCache,
        true,
      );
      expect(http.calls, hasLength(3));
    },
  );

  test(
    'Qishui empty search is no match while malformed comments are unavailable',
    () async {
      final http = _Http((_) async => _search('track', []));
      final repository = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => throw UnsupportedError('memory'),
      );
      const query = SongCommentQuery(title: '枫', artist: '等天黑');
      expect(
        (await repository.load(query, SongCommentPlatform.qishui)).status,
        SongCommentsStatus.noMatch,
      );
      http.respond = (uri) async => uri.path.contains('/search/')
          ? _search('track', [_track('42')])
          : {'status_code': 1000004};
      expect(
        (await repository.load(
          query,
          SongCommentPlatform.qishui,
          refresh: true,
        )).status,
        SongCommentsStatus.unavailable,
      );
      expect(
        parseSongComments(
          jsonEncode({'comments': [], 'cursor': '0', 'has_more': false}),
          SongCommentPlatform.qishui,
        ),
        isEmpty,
      );
    },
  );
}

class _Http implements MusicResolverHttp {
  _Http(this.respond);
  Future<Map<String, dynamic>> Function(Uri) respond;
  final calls = <Uri>[];
  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    calls.add(uri);
    return ResolverHttpResponse(
      statusCode: 200,
      body: jsonEncode(await respond(uri)),
      finalUrl: uri,
    );
  }

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) => get(uri, headers: headers);
  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) => throw UnsupportedError('POST');
}
