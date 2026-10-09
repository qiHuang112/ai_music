import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_music/src/data/playlist_song.dart';

import 'package:ai_music/src/application/online_playlist_search.dart';
import 'package:ai_music/src/data/online_playlists.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'search parses both sources, correct paging and separate identities',
    () async {
      final http = _Http((uri, form) {
        if (uri.host == 'music.163.com') {
          expect(form, {
            's': '睡前',
            'type': '1000',
            'limit': '20',
            'offset': '20',
          });
          return {
            'code': 200,
            'result': {
              'playlistCount': 41,
              'playlists': [
                {
                  'id': 12,
                  'name': '睡前',
                  'creator': {'nickname': 'A'},
                  'trackCount': 76,
                },
              ],
            },
          };
        }
        final param =
            (jsonDecode(uri.queryParameters['data']!)
                as Map)['request']['param'];
        expect(param['page_num'], 2);
        expect(param['search_type'], 3);
        return _qq({
          'meta': {'sum': 40},
          'body': {
            'songlist': {
              'list': [
                {
                  'dissid': '12',
                  'dissname': '<em>睡前</em> &amp; 放松',
                  'creator': {'name': 'B'},
                  'song_count': 52,
                },
              ],
            },
          },
        });
      });
      final repo = OnlinePlaylistRepository(httpClient: http);
      final ne = await repo.search(
        OnlinePlaylistSource.netease,
        ' 睡前 ',
        page: 2,
      );
      final qq = await repo.search(OnlinePlaylistSource.qq, '睡前', page: 2);
      expect(ne.hasMore, true);
      expect(qq.hasMore, false);
      expect(ne.items.single.key, isNot(qq.items.single.key));
      expect(ne.items.single.creator, 'A');
      expect(qq.items.single.name, '睡前 & 放松');
    },
  );

  test('empty search differs from invalid service response', () async {
    var body = <String, dynamic>{
      'code': 200,
      'result': {'playlistCount': 0},
    };
    final repo = OnlinePlaylistRepository(httpClient: _Http((_, _) => body));
    expect(
      (await repo.search(OnlinePlaylistSource.netease, 'none')).items,
      isEmpty,
    );
    body = {'code': 301};
    await expectLater(
      repo.search(OnlinePlaylistSource.netease, 'none'),
      throwsStateError,
    );
    body = {'code': 200};
    await expectLater(
      repo.search(OnlinePlaylistSource.netease, 'none'),
      throwsFormatException,
    );
  });

  test(
    'NetEase fills missing metadata in batches and retains source order',
    () async {
      final batches = <List<dynamic>>[];
      final repo = OnlinePlaylistRepository(
        httpClient: _Http((uri, _) {
          if (uri.path.contains('playlist')) {
            return {
              'code': 200,
              'playlist': {
                'trackCount': 205,
                'trackIds': [
                  for (var i = 1; i <= 205; i++) {'id': i},
                ],
                'tracks': [_neSong(1)],
              },
            };
          }
          final ids = jsonDecode(uri.queryParameters['ids']!) as List;
          batches.add(ids);
          return {
            'code': 200,
            'songs': [
              for (final id in ids.reversed)
                if (id != 12) _neSong(id as int),
            ],
          };
        }),
      );
      final detail = await repo.load(_playlist(OnlinePlaylistSource.netease));
      expect(batches.map((batch) => batch.length), [100, 100, 4]);
      expect(detail.total, 205);
      expect(detail.unavailable, 1);
      expect(detail.songs.take(3).map((song) => song.id), ['1', '2', '3']);
      expect(detail.songs.last.id, '205');
      expect(detail.songs.first.artist, 'Artist');
    },
  );

  test(
    'QQ uses requested windows, keeps filtered gaps and guards repeated pages',
    () async {
      final offsets = <int>[];
      final repo = OnlinePlaylistRepository(
        httpClient: _Http((uri, _) {
          final param =
              (jsonDecode(uri.queryParameters['data']!)
                  as Map)['request']['param'];
          final offset = param['song_begin'] as int;
          expect(param['song_num'], 20);
          offsets.add(offset);
          return _qq({
            'code': 0,
            'total_song_num': 43,
            'hasmore': offset < 40 ? 1 : 0,
            'songlist': [
              for (var i = offset; i < offset + 20 && i < 43; i++)
                if (i != 3 && i != 24)
                  {
                    'id': i + 1,
                    'name': 'S$i',
                    'singer': [
                      {'name': 'A'},
                    ],
                  },
            ],
          });
        }),
      );
      final detail = await repo.load(_playlist(OnlinePlaylistSource.qq));
      expect(offsets, [0, 20, 40]);
      expect(detail.songs.length, 41);
      expect(detail.unavailable, 2);
      expect(detail.songs.last.id, '43');
    },
  );

  test(
    'actual QQ Fanren playlist keeps all four version annotations and durations',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/fixtures/qq_fanren_playlist.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final repo = OnlinePlaylistRepository(
        httpClient: _Http((_, _) => _qq(fixture)),
      );
      final detail = await repo.load(
        _playlist(OnlinePlaylistSource.qq, id: '9765682818'),
      );
      expect(detail.songs.map((s) => s.title), [
        '归零',
        '鸿门旋律 (Version)',
        'Time is Broken (浴室氛围版)',
        '回忆观影券 (伴奏)',
        '星游记进行曲',
        'Lost Control (feat. Bianca)',
        'Manestein (慢摇氛围版)',
      ]);
      expect(detail.songs.map((s) => s.durationSeconds), [
        126,
        89,
        241,
        172,
        143,
        269,
        153,
      ]);
      expect(detail.songs[3].artist, 'IN-K / 王忻辰');
    },
  );

  test(
    'QQ exact-ID metadata refresh prefers full title and rejects another ID',
    () async {
      var returnedId = 274967058;
      final repo = OnlinePlaylistRepository(
        httpClient: _Http((uri, _) {
          final req = jsonDecode(uri.queryParameters['data']!)['request'];
          expect(req['method'], 'get_song_detail_yqq');
          expect(req['param']['song_id'], 274967058);
          return _qq({
            'track_info': {
              'id': returnedId,
              'name': '回忆观影券',
              'title': '回忆观影券 (伴奏)',
              'singer': [
                {'name': 'IN-K'},
                {'name': '王忻辰'},
              ],
              'interval': 172,
            },
          });
        }),
      );
      final song = await repo.loadQqSong('274967058');
      expect(song.title, '回忆观影券 (伴奏)');
      expect(song.durationSeconds, 172);
      returnedId++;
      await expectLater(repo.loadQqSong('274967058'), throwsFormatException);
    },
  );

  test('QQ blank full title still falls back to a nonempty name', () async {
    final repo = OnlinePlaylistRepository(
      httpClient: _Http(
        (_, _) => _qq({
          'total_song_num': 1,
          'hasmore': 0,
          'songlist': [
            {'id': 42, 'title': '  ', 'name': '保留歌名', 'singer': []},
          ],
        }),
      ),
    );
    expect(
      (await repo.load(_playlist(OnlinePlaylistSource.qq))).songs.single.title,
      '保留歌名',
    );
  });

  test(
    'original metadata marks legacy JSON and round trips a repaired version',
    () {
      final legacy = PlaylistSong.fromJson({
        'key': 'qq:274967058',
        'title': '回忆观影券',
        'artist': 'IN-K / 王忻辰',
      })!;
      expect(legacy.metadataVersion, 0);
      expect(legacy.durationSeconds, 0);
      const updated = PlaylistSong(
        key: 'qq:274967058',
        title: '回忆观影券 (伴奏)',
        artist: 'IN-K / 王忻辰',
        durationSeconds: 172,
      );
      final restored = PlaylistSong.fromJson(updated.toJson())!;
      expect(restored.title, updated.title);
      expect(restored.metadataVersion, 1);
      expect(restored.durationSeconds, 172);
    },
  );

  test('detail cancellation prevents further metadata requests', () async {
    var canceled = false;
    var calls = 0;
    final repo = OnlinePlaylistRepository(
      httpClient: _Http((_, _) {
        calls++;
        canceled = true;
        return {
          'code': 200,
          'playlist': {
            'trackCount': 2,
            'trackIds': [
              {'id': 1},
              {'id': 2},
            ],
            'tracks': [],
          },
        };
      }),
    );
    await expectLater(
      repo.load(
        _playlist(OnlinePlaylistSource.netease),
        isCanceled: () => canceled,
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test(
    'one source completes without waiting for another; retry preserves results',
    () async {
      final pending = Completer<OnlinePlaylistSearchPage>();
      var qqCalls = 0;
      final state = OnlinePlaylistSearch(
        _Repo((source, query, page) {
          if (source == OnlinePlaylistSource.qq && qqCalls++ == 0) {
            return pending.future;
          }
          return Future.value(
            OnlinePlaylistSearchPage(
              items: [_playlist(source, id: '$page')],
              hasMore: false,
            ),
          );
        }),
      );
      final request = state.search('sleep');
      await Future<void>.delayed(Duration.zero);
      expect(state.items.length, 1);
      expect(state.isLoading, true);
      pending.completeError(StateError('offline'));
      await request;
      expect(state.errors, {OnlinePlaylistSource.qq});
      await state.retry(OnlinePlaylistSource.qq);
      expect(state.items.length, 2);
      expect(state.errors, isEmpty);
      state.dispose();
    },
  );

  test('stale query and cleared mode cannot overwrite new search', () async {
    final pending = <Completer<OnlinePlaylistSearchPage>>[];
    final state = OnlinePlaylistSearch(
      _Repo((source, query, page) {
        if (query == 'old') {
          final completer = Completer<OnlinePlaylistSearchPage>();
          pending.add(completer);
          return completer.future;
        }
        return Future.value(
          OnlinePlaylistSearchPage(
            items: [_playlist(source, id: query)],
            hasMore: false,
          ),
        );
      }),
    );
    final old = state.search('old');
    await state.search('new');
    for (final completer in pending) {
      completer.completeError(StateError('old failure'));
    }
    await old;
    expect(state.items.map((item) => item.id), ['new', 'new']);
    expect(state.errors, isEmpty);
    final another = state.search('old');
    state.clear();
    for (final completer in pending.where((item) => !item.isCompleted)) {
      completer.complete(
        OnlinePlaylistSearchPage(
          items: [_playlist(OnlinePlaylistSource.qq)],
          hasMore: false,
        ),
      );
    }
    await another;
    expect(state.items, isEmpty);
    state.dispose();
  });

  test(
    'paging retries only the failed page and deduplicates repeated entries',
    () async {
      var fail = true;
      final calls = <String>[];
      final state = OnlinePlaylistSearch(
        _Repo((source, query, page) async {
          calls.add('${source.name}:$page');
          if (source == OnlinePlaylistSource.qq && page == 2 && fail) {
            throw StateError('offline');
          }
          return OnlinePlaylistSearchPage(
            items: [
              _playlist(source, id: '1'),
              if (page == 2) _playlist(source, id: '2'),
            ],
            hasMore: page < 2,
          );
        }),
      );
      await state.search('query');
      await state.loadMore();
      expect(state.items.length, 3);
      fail = false;
      await state.retry(OnlinePlaylistSource.qq);
      expect(calls.where((call) => call == 'qq:2').length, 2);
      expect(state.items.length, 4);
      expect(state.hasMore, false);
      state.dispose();
    },
  );
}

OnlinePlaylist _playlist(OnlinePlaylistSource source, {String id = '1'}) =>
    OnlinePlaylist(
      source: source,
      id: id,
      name: 'Sleep',
      creator: 'A',
      trackCount: 1,
    );
Map<String, dynamic> _neSong(int id) => {
  'id': id,
  'name': 'S$id',
  'artists': [
    {'name': 'Artist'},
  ],
};
Map<String, dynamic> _qq(Map<String, dynamic> data) => {
  'code': 0,
  'request': {'code': 0, 'data': data},
};

class _Http implements MusicResolverHttp {
  _Http(this.respond);
  final Map<String, dynamic> Function(Uri, Map<String, String>?) respond;
  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async => ResolverHttpResponse(
    statusCode: 200,
    body: jsonEncode(respond(uri, null)),
    finalUrl: uri,
  );
  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async => ResolverHttpResponse(
    statusCode: 200,
    body: jsonEncode(respond(uri, form)),
    finalUrl: uri,
  );
  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) => throw UnimplementedError();
}

class _Repo extends OnlinePlaylistRepository {
  _Repo(this.respond);
  final Future<OnlinePlaylistSearchPage> Function(
    OnlinePlaylistSource,
    String,
    int,
  )
  respond;
  @override
  Future<OnlinePlaylistSearchPage> search(
    OnlinePlaylistSource source,
    String query, {
    int page = 1,
  }) => respond(source, query, page);
}
