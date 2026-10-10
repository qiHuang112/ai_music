import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:ai_music/src/data/song_comments.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:flutter_test/flutter_test.dart';

const query = SongCommentQuery(title: '不再犹豫', artist: 'Beyond');
const song = CommentSong(id: '42', title: '不再犹豫', artist: 'Beyond');

void main() {
  test(
    'QQ quick lookup verifies details and skips slow search, then caches',
    () async {
      final http = _Http(
        (uri, _) async {
          expect(uri.host, 'u.y.qq.com');
          if (_qqRequest(uri)['method'] == 'get_song_detail_yqq') {
            expect(_qqParams(uri)['song_id'], 42);
            return _qqDetails();
          }
          expect(_qqParams(uri)['BizId'], '42');
          return _qqComments(rows: [_qqComment('quick', '', 1)]);
        },
        quickReply: (uri) async {
          expect(uri.queryParameters['key'], query.searchText);
          return _qqSuggestions();
        },
      );
      final repo = _repo(http);
      final result = await repo.load(query, SongCommentPlatform.qq);
      expect(result.status, SongCommentsStatus.ready);
      expect(result.comments.single.id, 'quick');
      expect(http.calls, hasLength(3));
      expect(http.calls.any((u) => u.path.contains('client_search_cp')), false);
      expect((await repo.load(query, SongCommentPlatform.qq)).fromCache, true);
      expect(http.calls, hasLength(3));
    },
  );

  for (final mismatch in ['artist', 'version', 'duration']) {
    test('QQ quick hint cannot bypass $mismatch verification', () async {
      final http = _Http(
        (uri, _) async {
          if (uri.path.contains('client_search_cp')) return _qqSearch();
          if (_qqRequest(uri)['method'] == 'get_song_detail_yqq') {
            return _qqDetails(
              id: 99,
              artist: mismatch == 'artist' ? '其他歌手' : 'Beyond',
              title: mismatch == 'version' ? '不再犹豫 (Live)' : '不再犹豫',
              duration: mismatch == 'duration' ? 100 : 255,
            );
          }
          expect(_qqParams(uri)['BizId'], '42');
          return _qqComments();
        },
        quickReply: (_) async => _qqSuggestions([
          {'id': '99', 'name': '不再犹豫', 'singer': 'Beyond'},
        ]),
      );
      final result = await _repo(http).load(
        const SongCommentQuery(
          title: '不再犹豫',
          artist: 'Beyond',
          durationSeconds: 255,
        ),
        SongCommentPlatform.qq,
      );
      expect(result.status, SongCommentsStatus.ready);
      expect(result.song!.id, '42');
      expect(
        http.calls.where((u) => u.path.contains('client_search_cp')),
        hasLength(1),
      );
    });
  }

  test('QQ quick lookup checks at most two distinct matching hints', () async {
    final http = _Http(
      (uri, _) async {
        if (uri.path.contains('client_search_cp')) return _qqSearch();
        if (_qqRequest(uri)['method'] == 'get_song_detail_yqq') {
          return _qqDetails(title: '不再犹豫 (Live)');
        }
        return _qqComments();
      },
      quickReply: (_) async => _qqSuggestions([
        for (final id in ['99', '99', '100', '101'])
          {'id': id, 'name': '不再犹豫', 'singer': 'Beyond'},
      ]),
    );
    final result = await _repo(http).load(query, SongCommentPlatform.qq);
    expect(result.status, SongCommentsStatus.ready);
    final details = http.calls.where(
      (u) =>
          u.host == 'u.y.qq.com' &&
          _qqRequest(u)['method'] == 'get_song_detail_yqq',
    );
    expect(details.map((u) => _qqParams(u)['song_id']), [99, 100]);
  });

  test(
    'QQ hung quick lookup reserves time for the strict legacy fallback',
    () async {
      final http = _Http(
        (uri, _) async =>
            uri.path.contains('client_search_cp') ? _qqSearch() : _qqComments(),
        quickReply: (_) => Completer<Map<String, Object?>>().future,
      );
      final repo = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => throw UnsupportedError('memory'),
        requestTimeout: const Duration(milliseconds: 200),
      );
      final result = await repo
          .load(query, SongCommentPlatform.qq)
          .timeout(const Duration(seconds: 1));
      expect(result.status, SongCommentsStatus.ready);
      expect(http.calls, hasLength(3));
    },
  );

  test(
    '9420 finds the original recording beyond the first 20 results',
    () async {
      final rows = [
        {
          'id': 3391243991,
          'name': '9420',
          'duration': 157178,
          'artists': [
            {'name': '麦小兜'},
          ],
          'album': {'name': '9420'},
        },
        for (var i = 1; i < 56; i++)
          {
            'id': 1000 + i,
            'name': i.isEven ? '9420' : '9420 (Live)',
            'duration': 229156,
            'artists': [
              {'name': i.isEven ? '其他歌手' : '麦小兜'},
            ],
            'album': {'name': '9420'},
          },
        {
          'id': 515143305,
          'name': '9420',
          'duration': 229156,
          'artists': [
            {'name': '麦小兜'},
          ],
          'album': {'name': '9420'},
        },
      ];
      final http = _Http((uri, form) async {
        if (uri.path == '/api/search/get') {
          expect(form!['s'], '9420 麦小兜');
          final limit = int.parse(form['limit']!);
          return {
            'code': 200,
            'result': {'songs': rows.take(limit).toList(), 'songCount': 150},
          };
        }
        expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_515143305');
        return _comments();
      });
      final repo = _repo(http);
      const original = SongCommentQuery(
        title: '9420',
        artist: '麦小兜',
        album: '9420',
        durationSeconds: 229,
        platformIds: {SongCommentPlatform.qq: '205000888'},
      );
      final result = await repo.load(original, SongCommentPlatform.netease);
      expect(result.status, SongCommentsStatus.ready);
      expect(result.song!.id, '515143305');
      expect(result.comments, hasLength(1));
      expect(http.calls, hasLength(3));
      expect(
        (await repo.load(original, SongCommentPlatform.netease)).fromCache,
        isTrue,
      );
      expect(http.calls, hasLength(3));
    },
  );

  test(
    'expanded NetEase search stays bounded and rejects other recordings',
    () async {
      final httpSearchLimits = ['20', '100'];
      final http = _Http((uri, form) async {
        expect(uri.path, '/api/search/get');
        expect(form!['limit'], httpSearchLimits.removeAt(0));
        return {
          'code': 200,
          'result': {
            'songs': [
              for (var i = 0; i < 100; i++)
                {
                  'id': 1000 + i,
                  'name': i % 3 == 0 ? '9420 (Live)' : '9420',
                  'duration': i % 3 == 1 ? 157178 : 229156,
                  'artists': [
                    {'name': i % 3 == 2 ? '其他歌手' : '麦小兜'},
                  ],
                },
              // Even if a service ignores its requested limit, do not expand
              // beyond the documented bound or weaken recording checks.
              {
                'id': 515143305,
                'name': '9420',
                'duration': 229156,
                'artists': [
                  {'name': '麦小兜'},
                ],
              },
            ],
          },
        };
      });
      final result = await _repo(http).load(
        const SongCommentQuery(
          title: '9420',
          artist: '麦小兜',
          durationSeconds: 229,
        ),
        SongCommentPlatform.netease,
      );
      expect(result.status, SongCommentsStatus.noMatch);
      expect(http.calls, hasLength(2));
    },
  );

  test('9420 uses an existing lyric clue before widening search', () async {
    final searches = <String>[];
    final http = _Http((uri, form) async {
      if (uri.path != '/api/search/get') {
        expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_515143305');
        return _comments();
      }
      expect(form!['limit'], '20');
      searches.add(form['s']!);
      return {
        'code': 200,
        'result': {
          'songCount': 150,
          'songs': [
            {
              'id': 3391243991,
              'name': '9420',
              'duration': 157178,
              'artists': [
                {'name': '麦小兜'},
              ],
            },
            if (searches.length == 2)
              {
                'id': 515143305,
                'name': '9420',
                'duration': 229156,
                'artists': [
                  {'name': '麦小兜'},
                ],
              },
          ],
        },
      };
    });
    final result = await _repo(http).load(
      const SongCommentQuery(
        title: '9420',
        artist: '麦小兜',
        durationSeconds: 229,
        lyricsHint: '手牵手一起走在幸福的大街 微风缓缓的吹来你我相依偎 爱的目光如此的热烈',
      ),
      SongCommentPlatform.netease,
    );
    expect(result.status, SongCommentsStatus.ready);
    expect(result.song!.id, '515143305');
    expect(searches, ['9420 麦小兜', '手牵手一起走在幸福的大街 微风缓缓的吹来你我相依偎 爱的目光如此的热烈']);
    expect(http.calls, hasLength(3));
  });

  test(
    'lyric hints omit credits and do not change recording cache identity',
    () {
      const track = Track(
        id: '9420',
        title: '9420',
        artist: '麦小兜',
        album: '9420',
      );
      final withLyrics = SongCommentQuery.fromTrack(
        track,
        lyrics: const [
          LyricLine(time: Duration.zero, text: '9420 -麦小兜'),
          LyricLine(time: Duration(seconds: 5), text: '词：可泽'),
          LyricLine(time: Duration(seconds: 10), text: '曲：可泽'),
          LyricLine(time: Duration(seconds: 15), text: '编曲：杨栋梁'),
          LyricLine(time: Duration(seconds: 20), text: '制作公司：Hikoon Music'),
          LyricLine(time: Duration(seconds: 25), text: '手牵手一起走在幸福的大街'),
          LyricLine(time: Duration(seconds: 28), text: '微风缓缓的吹来你我相依偎'),
          LyricLine(time: Duration(seconds: 31), text: '爱的目光如此的热烈'),
          LyricLine(time: Duration(seconds: 36), text: '这份爱就像是在燃烧的火堆'),
        ],
      );
      expect(withLyrics.lyricsHint, '手牵手一起走在幸福的大街 微风缓缓的吹来你我相依偎 爱的目光如此的热烈');
      expect(
        withLyrics.key(SongCommentPlatform.netease),
        SongCommentQuery.fromTrack(track).key(SongCommentPlatform.netease),
      );
    },
  );

  test(
    'search fallbacks share a deadline and do not multiply timeout waits',
    () async {
      final http = _Http((uri, form) async {
        if (form!['s'] == '歌词线索') {
          return Completer<Map<String, dynamic>>().future;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return {
          'code': 200,
          'result': {
            'songCount': 150,
            'songs': [
              for (var i = 0; i < 20; i++)
                {
                  'id': 1000 + i,
                  'name': '不再犹豫 (Live)',
                  'artists': [
                    {'name': 'Beyond'},
                  ],
                },
            ],
          },
        };
      });
      final repo = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => throw UnsupportedError('memory only'),
        requestTimeout: const Duration(milliseconds: 200),
      );
      final result = await repo
          .load(
            const SongCommentQuery(
              title: '不再犹豫',
              artist: 'Beyond',
              lyricsHint: '歌词线索',
            ),
            SongCommentPlatform.netease,
          )
          .timeout(const Duration(seconds: 2));
      expect(result.status, SongCommentsStatus.unavailable);
      expect(
        http.calls,
        hasLength(2),
        reason: 'No further request after the shared deadline',
      );
    },
  );

  test(
    'Fresh Flowers resolves the verified Hui Chun Dan artist alias',
    () async {
      final http = _Http((uri, form) async {
        if (uri.path == '/api/search/get') {
          expect(form!['s'], '鲜花 回春丹乐队');
          return {
            'code': 200,
            'result': {
              'songs': [
                {
                  'id': 2088079571,
                  'name': '鲜花 (Live)',
                  'duration': 465472,
                  'artists': [
                    {'name': '回春丹'},
                  ],
                  'album': {'name': '乐队的夏天3 第9期'},
                },
                {
                  'id': 2086327879,
                  'name': '鲜花',
                  'duration': 341377,
                  'artists': [
                    {'name': '回春丹'},
                  ],
                  'album': {'name': '鲜花'},
                },
              ],
            },
          };
        }
        expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_2086327879');
        return _comments();
      });
      final result = await _repo(http).load(
        const SongCommentQuery(
          title: '鲜花',
          artist: '回春丹乐队',
          album: '鲜花',
          durationSeconds: 341,
        ),
        SongCommentPlatform.netease,
      );
      expect(result.status, SongCommentsStatus.ready);
      expect(result.song!.id, '2086327879');
      expect(result.comments, hasLength(1));
      expect(http.calls, hasLength(2));
    },
  );

  test(
    'verified artist alias works in both directions and keeps collaborators',
    () {
      const track = CommentSong(
        id: '2611541866',
        title: '鲜花 (Live)',
        artist: '那英 / 回春丹乐队',
        durationSeconds: 464,
      );
      expect(
        selectCommentSong(
          const SongCommentQuery(
            title: '鲜花 (Live)',
            artist: '回春丹 / 那英',
            durationSeconds: 464,
          ),
          [track],
        ),
        same(track),
      );
      expect(
        selectCommentSong(
          const SongCommentQuery(title: '鲜花 (Live)', artist: '回春丹'),
          [track],
        ),
        isNull,
      );
    },
  );

  test(
    'artist alias does not relax recording version or unrelated band names',
    () {
      const flowers = SongCommentQuery(
        title: '鲜花',
        artist: '回春丹乐队',
        durationSeconds: 341,
      );
      expect(
        selectCommentSong(flowers, [
          const CommentSong(
            id: '1',
            title: '鲜花 (Live)',
            artist: '回春丹',
            durationSeconds: 341,
          ),
          const CommentSong(
            id: '2',
            title: '鲜花',
            artist: '回春丹',
            durationSeconds: 465,
          ),
          const CommentSong(
            id: '3',
            title: '鲜花',
            artist: '回春丹乐队翻唱',
            durationSeconds: 341,
          ),
        ]),
        isNull,
      );
      expect(
        selectCommentSong(const SongCommentQuery(title: '鲜花', artist: '未知乐队'), [
          const CommentSong(id: '4', title: '鲜花', artist: '未知'),
        ]),
        isNull,
      );
    },
  );

  test(
    'original song duration survives storage while legacy entries stay compatible',
    () {
      final original = PlaylistSong.fromJson({
        'key': 'qq:105393420',
        'title': '关键词',
        'artist': '林俊杰',
        'durationSeconds': 210,
      })!;
      expect(PlaylistSong.fromJson(original.toJson())!.durationSeconds, 210);
      final legacy = PlaylistSong.fromJson({
        'key': 'qq:42',
        'title': '旧歌单歌曲',
        'artist': '歌手',
      })!;
      expect(legacy.durationSeconds, 0);
      expect(legacy.toJson()['durationSeconds'], 0);
    },
  );

  group('original duration and optional ID recovery', () {
    for (final platform in SongCommentPlatform.values) {
      test(
        'Keyword uses its 210-second original identity despite 130-second Kuwo source on ${platform.name}',
        () async {
          final keyword = SongCommentQuery.fromTrack(
            const Track(
              id: 'keyword',
              title: '关键词',
              artist: '林俊杰',
              album: '',
              duration: Duration(seconds: 130),
            ),
            original: const PlaylistSong(
              key: 'qq:105393420',
              title: '关键词',
              artist: '林俊杰',
              durationSeconds: 210,
            ),
            candidate: const MusicSearchCandidate(
              query: '关键词 林俊杰',
              source: MusicDataSource.flac,
              platform: 'kuwo',
              keyword: '关键词',
              page: 1,
              id: '184342650',
              name: '关键词',
              artist: '林俊杰',
              album: '',
              duration: 130,
              link: '',
              coverUrl: '',
              qualities: [],
              score: 100,
              raw: {},
            ),
          );
          final http = _Http((uri, _) async {
            final qqSong = {
              'id': 105393420,
              'title': '关键词',
              'interval': 210,
              'singer': [
                {'name': '林俊杰'},
              ],
            };
            if (uri.path == '/api/search/get') {
              return {
                'code': 200,
                'result': {
                  'songs': [
                    {
                      'id': 40147554,
                      'name': '关键词',
                      'duration': 210266,
                      'artists': [
                        {'name': '林俊杰'},
                      ],
                    },
                  ],
                },
              };
            }
            if (uri.path.contains('client_search_cp')) {
              return {
                'code': 0,
                'data': {
                  'song': {
                    'list': [qqSong],
                  },
                },
              };
            }
            if (uri.host == 'u.y.qq.com' &&
                _qqRequest(uri)['method'] == 'get_song_detail_yqq') {
              expect(_qqParams(uri)['song_id'], 105393420);
              return {
                'code': 0,
                'request': {
                  'code': 0,
                  'data': {'track_info': qqSong},
                },
              };
            }
            if (platform == SongCommentPlatform.netease) {
              expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_40147554');
              return _comments();
            }
            expect(_qqParams(uri)['BizId'], '105393420');
            return _qqComments(rows: [_qqComment('keyword', 'seq', 1)]);
          });
          final result = await _repo(http).load(keyword, platform);
          expect(result.status, SongCommentsStatus.ready);
          expect(result.comments, hasLength(1));
          expect(keyword.durationSeconds, 210);
          expect(
            result.song?.id,
            platform == SongCommentPlatform.qq ? '105393420' : '40147554',
          );
          expect(http.calls, hasLength(2));
        },
      );
    }

    for (final identity in [
      ('关键词 (Live)', '林俊杰'),
      ('关键词 (伴奏)', '林俊杰'),
      ('关键词', '任然'),
      ('关键词', '林俊杰 / 任然'),
      ('关键词', ''),
      ('', '林俊杰'),
    ]) {
      test(
        'original duration cannot override another title or artist: $identity',
        () {
          final value = SongCommentQuery.fromTrack(
            const Track(
              id: 'track',
              title: '关键词',
              artist: '林俊杰',
              album: '',
              duration: Duration(seconds: 130),
            ),
            original: PlaylistSong(
              key: 'qq:105393420',
              title: identity.$1,
              artist: identity.$2,
              durationSeconds: 210,
            ),
          );
          expect(value.durationSeconds, 130);
          expect(
            selectCommentSong(value, const [
              CommentSong(
                id: '105393420',
                title: '关键词',
                artist: '林俊杰',
                durationSeconds: 210,
              ),
            ]),
            isNull,
          );
        },
      );
    }

    test(
      'matching normalized title and artist set can use original duration',
      () {
        final value = SongCommentQuery.fromTrack(
          const Track(
            id: 'duet',
            title: ' 合唱（Live） ',
            artist: 'BEYOND / 甲',
            album: '',
            duration: Duration(seconds: 130),
          ),
          original: const PlaylistSong(
            key: 'qq:42',
            title: '合唱 (live)',
            artist: '甲 / beyond',
            durationSeconds: 210,
          ),
        );
        expect(value.durationSeconds, 210);
        final unknown = SongCommentQuery.fromTrack(
          const Track(
            id: 'track',
            title: '关键词',
            artist: '林俊杰',
            album: '',
            duration: Duration(seconds: 130),
          ),
          original: const PlaylistSong(
            key: 'qq:42',
            title: '关键词',
            artist: '林俊杰',
          ),
        );
        expect(unknown.durationSeconds, 130);
      },
    );

    for (final platform in SongCommentPlatform.values) {
      for (final wrongArtist in [false, true]) {
        test(
          'optional ${platform.name} ID failure falls back to strict search (wrong artist: $wrongArtist)',
          () async {
            final http = _Http((uri, _) async {
              if (uri.path == '/api/song/detail' ||
                  (uri.host == 'u.y.qq.com' &&
                      _qqRequest(uri)['method'] == 'get_song_detail_yqq')) {
                throw const SocketException('ID detail unavailable');
              }
              if (uri.path == '/api/search/get') {
                return {
                  'code': 200,
                  'result': {
                    'songs': [_neSong(artist: wrongArtist ? '翻唱歌手' : 'Beyond')],
                  },
                };
              }
              if (uri.path.contains('client_search_cp')) {
                return {
                  'code': 0,
                  'data': {
                    'song': {
                      'list': [
                        {
                          'id': 42,
                          'title': '不再犹豫',
                          'singer': [
                            {'name': wrongArtist ? '翻唱歌手' : 'Beyond'},
                          ],
                        },
                      ],
                    },
                  },
                };
              }
              expect(wrongArtist, false);
              return platform == SongCommentPlatform.netease
                  ? _comments()
                  : _qqComments(rows: [_qqComment('hot', 'seq', 1)]);
            });
            final result = await _repo(http).load(
              SongCommentQuery(
                title: '不再犹豫',
                artist: 'Beyond',
                platformIds: {platform: '999'},
              ),
              platform,
            );
            expect(
              result.status,
              wrongArtist
                  ? SongCommentsStatus.noMatch
                  : SongCommentsStatus.ready,
            );
            expect(
              http.calls,
              hasLength(
                (wrongArtist ? 2 : 3) +
                    (platform == SongCommentPlatform.qq ? 1 : 0),
              ),
            );
            if (!wrongArtist) expect(result.song?.id, '42');
          },
        );
      }
    }
  });

  test(
    'pre-version-aware QQ mapping cache is discarded before lookup',
    () async {
      final dir = await Directory.systemTemp.createTemp('old-comment-mapping-');
      addTearDown(() => dir.delete(recursive: true));
      const original = SongCommentQuery(title: '回忆观影券', artist: '版本歌手');
      await File('${dir.path}/song_comments_cache.json').writeAsString(
        jsonEncode({
          'schema': 1,
          'entries': [
            {
              'key': original.key(SongCommentPlatform.qq),
              'at': DateTime.now().toIso8601String(),
              'song': const CommentSong(
                id: '42',
                title: '回忆观影券',
                artist: '版本歌手',
              ).toJson(),
              'comments': [
                const SongComment(
                  id: 'wrong',
                  author: '听众',
                  content: '旧伴奏歌曲的评论',
                  likes: 1,
                ).toJson(),
              ],
            },
          ],
        }),
      );
      final http = _Http((uri, _) async {
        expect(uri.path, '/soso/fcgi-bin/client_search_cp');
        return {
          'code': 0,
          'data': {
            'song': {'list': []},
          },
        };
      });
      final repo = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => dir,
      );
      final result = await repo.load(original, SongCommentPlatform.qq);
      expect(result.status, SongCommentsStatus.noMatch);
      expect(result.comments, isEmpty);
      expect(http.calls, hasLength(2));
    },
  );

  for (final version in const [
    ('回忆观影券', '回忆观影券 (伴奏)'),
    ('Time is Broken', 'Time is Broken (浴室氛围版)'),
    ('Manestein', 'Manestein (慢摇氛围版)'),
  ]) {
    test('QQ comments preserve title version for ${version.$2}', () async {
      final http = _Http((uri, form) async {
        if (uri.path.contains('client_search_cp')) {
          return {
            'code': 0,
            'data': {
              'song': {
                'list': [
                  {
                    'songid': 1,
                    'name': version.$1,
                    'songname': version.$1,
                    'title': version.$1,
                    'singer': [
                      {'name': '版本歌手'},
                    ],
                  },
                  {
                    'songid': 2,
                    'name': version.$1,
                    'songname': version.$1,
                    'title': version.$2,
                    'singer': [
                      {'name': '版本歌手'},
                    ],
                  },
                ],
              },
            },
          };
        }
        expect(_qqParams(uri)['BizId'], '2');
        return _qqComments();
      });
      final result = await _repo(http).load(
        SongCommentQuery(title: version.$2, artist: '版本歌手'),
        SongCommentPlatform.qq,
      );
      expect(result.status, SongCommentsStatus.ready);
      expect(result.song?.id, '2');
      expect(result.song?.title, version.$2);
    });
  }

  test(
    'QQ versioned details cannot supply instrumental comments to vocal song',
    () async {
      final http = _Http((uri, form) async {
        if (uri.host == 'u.y.qq.com' &&
            _qqRequest(uri)['method'] == 'get_song_detail_yqq') {
          return {
            'code': 0,
            'request': {
              'code': 0,
              'data': {
                'track_info': {
                  'id': 42,
                  'name': '回忆观影券',
                  'title': '回忆观影券 (伴奏)',
                  'singer': [
                    {'name': '版本歌手'},
                  ],
                },
              },
            },
          };
        }
        expect(uri.path, '/soso/fcgi-bin/client_search_cp');
        return {
          'code': 0,
          'data': {
            'song': {'list': []},
          },
        };
      });
      final result = await _repo(http).load(
        const SongCommentQuery(
          title: '回忆观影券',
          artist: '版本歌手',
          platformIds: {SongCommentPlatform.qq: '42'},
        ),
        SongCommentPlatform.qq,
      );
      expect(result.status, SongCommentsStatus.noMatch);
      expect(http.calls.any((uri) => uri.path.contains('comment')), false);
    },
  );

  for (final useSongname in [true, false]) {
    test(
      'QQ blank title falls back to ${useSongname ? 'songname' : 'name'}',
      () async {
        final http = _Http((uri, form) async {
          if (uri.path.contains('client_search_cp')) {
            return {
              'code': 0,
              'data': {
                'song': {
                  'list': [
                    {
                      'id': 42,
                      'title': '  ',
                      'songname': useSongname ? '回忆观影券 (伴奏)' : '<em></em>',
                      'name': '回忆观影券 (伴奏)',
                      'singer': [
                        {'name': '版本歌手'},
                      ],
                    },
                  ],
                },
              },
            };
          }
          expect(_qqParams(uri)['BizId'], '42');
          return _qqComments();
        });
        final result = await _repo(http).load(
          const SongCommentQuery(title: '回忆观影券 (伴奏)', artist: '版本歌手'),
          SongCommentPlatform.qq,
        );
        expect(result.status, SongCommentsStatus.ready);
        expect(result.song?.title, '回忆观影券 (伴奏)');
      },
    );
  }

  test(
    'comment identity rejects covers, live versions, medleys and wrong duration',
    () {
      expect(
        selectCommentSong(query, const [
          CommentSong(id: '1', title: '不再犹豫', artist: '翻唱歌手'),
          CommentSong(id: '2', title: '不再犹豫 (Live)', artist: 'Beyond'),
          CommentSong(id: '3', title: '不再犹豫 / 光辉岁月', artist: 'Beyond'),
          CommentSong(id: '4', title: '不再犹豫', artist: 'Beyond / 别人'),
        ]),
        isNull,
      );
      expect(
        selectCommentSong(const SongCommentQuery(title: '不再犹豫', artist: ''), [
          song,
        ]),
        isNull,
      );
      expect(
        selectCommentSong(
          const SongCommentQuery(
            title: '不再犹豫',
            artist: 'Beyond',
            durationSeconds: 254,
          ),
          const [
            CommentSong(
              id: '42',
              title: '不再犹豫',
              artist: 'Beyond',
              durationSeconds: 120,
            ),
          ],
        ),
        isNull,
      );
    },
  );

  test('matching tolerates artist case/order and prefers original album', () {
    final actual = selectCommentSong(
      const SongCommentQuery(title: '合唱', artist: '甲 / BEYOND', album: '原版'),
      const [
        CommentSong(id: '1', title: '合唱', artist: 'beyond / 甲', album: '精选'),
        CommentSong(id: '2', title: '合唱', artist: 'Beyond / 甲', album: '原版'),
      ],
    );
    expect(actual?.id, '2');
  });

  test(
    'original playlist identity is preserved and provider IDs remain untrusted hints',
    () {
      const track = Track(
        id: 'local',
        title: '不再犹豫',
        artist: 'Beyond',
        album: '',
      );
      final value = SongCommentQuery.fromTrack(
        track,
        original: const PlaylistSong(
          key: 'qq:0039MnYb0qxYhV',
          title: '不再犹豫',
          artist: 'Beyond',
        ),
        candidate: _candidate(MusicDataSource.buguyy, 'qq', '99'),
      );
      expect(value.platformIds, {SongCommentPlatform.qq: '0039MnYb0qxYhV'});
      final flac = SongCommentQuery.fromTrack(
        track,
        candidate: _candidate(MusicDataSource.flac, 'wyy', '42'),
      );
      expect(flac.platformIds, {SongCommentPlatform.netease: '42'});
    },
  );

  test(
    'parsers read hot section only, preserve multiline text and deduplicate',
    () {
      final ne = parseSongComments(
        jsonEncode({
          'code': 200,
          'hotComments': [
            _neComment('1', 5),
            _neComment('1', 5),
            _neComment('2', 9),
          ],
          'comments': [_neComment('recent', 0)],
        }),
        SongCommentPlatform.netease,
      );
      expect(ne.map((c) => c.id), ['2', '1']);
      expect(ne.first.content, '第一行\n第二行 & 音乐');
      expect(ne.first.createdAt?.millisecondsSinceEpoch, 1700000000000);
      final qq = parseSongComments(
        jsonEncode({
          'code': 0,
          'hot_comment': {
            'commentlist': [
              {
                'commentid': 'a',
                'nick': '甲',
                'rootcommentcontent': '一条热评',
                'praisenum': 17,
                'time': 1700000000,
              },
            ],
          },
        }),
        SongCommentPlatform.qq,
      );
      expect(qq.single.author, '甲');
      expect(qq.single.likes, 17);
      expect(qq.single.createdAt, ne.first.createdAt);
      expect(
        () => parseSongComments(
          '{"code":200,"comments":[]}',
          SongCommentPlatform.netease,
        ),
        throwsFormatException,
      );
      expect(
        () => parseSongComments(
          '{"code":401,"hotComments":[]}',
          SongCommentPlatform.netease,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'original NetEase ID is verified and comments survive repository restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('song-comments-');
      addTearDown(() => dir.delete(recursive: true));
      final http = _Http((uri, form) async {
        if (uri.path == '/api/song/detail') {
          return {
            'code': 200,
            'songs': [_neSong()],
          };
        }
        expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_42');
        return _comments();
      });
      final repo = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => dir,
      );
      const withId = SongCommentQuery(
        title: '不再犹豫',
        artist: 'Beyond',
        platformIds: {SongCommentPlatform.netease: '42'},
      );
      final first = await repo.load(withId, SongCommentPlatform.netease);
      expect(first.status, SongCommentsStatus.ready);
      expect(first.comments.single.id, '1');
      expect(http.calls.length, 2);
      final reopened = SongCommentsRepository(
        httpClient: _Http((_, _) async => throw StateError('must use cache')),
        rootProvider: () async => dir,
      );
      final second = await reopened.load(withId, SongCommentPlatform.netease);
      expect(second.fromCache, true);
      expect(second.pageUrl.queryParameters['id'], '42');
    },
  );

  test(
    'incorrect provider ID cannot silently fetch someone else comments',
    () async {
      final http = _Http((uri, form) async {
        if (uri.path == '/api/song/detail') {
          return {
            'code': 200,
            'songs': [_neSong(id: 99, artist: '其他歌手')],
          };
        }
        if (uri.path == '/api/search/get') return _search();
        expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_42');
        return _comments();
      });
      final result = await _repo(http).load(
        const SongCommentQuery(
          title: '不再犹豫',
          artist: 'Beyond',
          platformIds: {SongCommentPlatform.netease: '99'},
        ),
        SongCommentPlatform.netease,
      );
      expect(result.song?.id, '42');
      expect(http.calls.length, 3);
    },
  );

  test(
    'QQ MID maps to verified numeric comment ID and official link',
    () async {
      final http = _Http((uri, form) async {
        if (uri.host == 'u.y.qq.com' &&
            _qqRequest(uri)['method'] == 'get_song_detail_yqq') {
          final request =
              (jsonDecode(uri.queryParameters['data']!) as Map)['request']
                  as Map;
          expect((request['param'] as Map)['song_mid'], '0039MnYb0qxYhV');
          return {
            'code': 0,
            'request': {
              'code': 0,
              'data': {
                'track_info': {
                  'id': 42,
                  'mid': '0039MnYb0qxYhV',
                  'name': '不再犹豫',
                  'singer': [
                    {'name': 'Beyond'},
                  ],
                },
              },
            },
          };
        }
        expect(_qqParams(uri)['BizId'], '42');
        return _qqComments();
      });
      final result = await _repo(http).load(
        const SongCommentQuery(
          title: '不再犹豫',
          artist: 'Beyond',
          platformIds: {SongCommentPlatform.qq: '0039MnYb0qxYhV'},
        ),
        SongCommentPlatform.qq,
      );
      expect(result.status, SongCommentsStatus.ready);
      expect(result.pageUrl.path, '/n/ryqq/songDetail/0039MnYb0qxYhV');
      expect(result.comments, isEmpty);
    },
  );

  test('QQ search uses numeric ID, not MID, for comments', () async {
    final http = _Http((uri, form) async {
      if (uri.path.contains('client_search_cp')) {
        return {
          'code': 0,
          'data': {
            'song': {
              'list': [
                {
                  'songid': 42,
                  'songmid': '0039MnYb0qxYhV',
                  'songname': '不再犹豫',
                  'singer': [
                    {'name': 'Beyond'},
                  ],
                },
              ],
            },
          },
        };
      }
      expect(_qqParams(uri)['BizId'], '42');
      return _qqComments();
    });
    final result = await _repo(http).load(query, SongCommentPlatform.qq);
    expect(result.status, SongCommentsStatus.ready);
    expect(http.calls.length, 3);
  });

  test('unmatched songs never request comments', () async {
    final http = _Http((uri, form) async {
      expect(uri.path, '/api/search/get');
      return {
        'code': 200,
        'result': {
          'songs': [_neSong(artist: '错误歌手')],
        },
      };
    });
    final result = await _repo(http).load(query, SongCommentPlatform.netease);
    expect(result.status, SongCommentsStatus.noMatch);
    expect(http.calls.length, 1);
    expect(result.pageUrl.host, 'music.163.com');
  });

  test(
    'unavailable and malformed APIs produce retryable failure rather than fake empty success',
    () async {
      var fail = true;
      final http = _Http((uri, form) async {
        if (fail) throw const SocketException('offline');
        return uri.path == '/api/search/get' ? _search() : _comments();
      });
      final repo = _repo(http);
      expect(
        (await repo.load(query, SongCommentPlatform.netease)).status,
        SongCommentsStatus.unavailable,
      );
      fail = false;
      expect(
        (await repo.load(query, SongCommentPlatform.netease)).status,
        SongCommentsStatus.ready,
      );
    },
  );

  test(
    'concurrent requests share work and expired comments retain verified mapping',
    () async {
      final gate = Completer<void>();
      var now = DateTime(2026, 10, 8);
      final http = _Http((uri, form) async {
        await gate.future;
        return uri.path == '/api/search/get' ? _search() : _comments();
      });
      final repo = _repo(http, now: () => now);
      final a = repo.load(query, SongCommentPlatform.netease);
      final b = repo.load(query, SongCommentPlatform.netease);
      gate.complete();
      final results = await Future.wait([a, b]);
      expect(results.every((r) => r.status == SongCommentsStatus.ready), true);
      expect(http.calls.length, 2);
      now = now.add(const Duration(hours: 7));
      await repo.load(query, SongCommentPlatform.netease);
      expect(http.calls.length, 3);
      expect(http.calls.last.path, '/api/v1/resource/hotcomments/R_SO_4_42');
    },
  );

  test('offline refresh retains good cache with explicit stale flag', () async {
    var now = DateTime(2026, 10, 8);
    var offline = false;
    final http = _Http((uri, form) async {
      if (offline) throw const SocketException('offline');
      return uri.path == '/api/search/get' ? _search() : _comments();
    });
    final repo = _repo(http, now: () => now);
    await repo.load(query, SongCommentPlatform.netease);
    now = now.add(const Duration(hours: 7));
    offline = true;
    final result = await repo.load(
      query,
      SongCommentPlatform.netease,
      refresh: true,
    );
    expect(result.status, SongCommentsStatus.ready);
    expect(result.stale, true);
    expect(result.fromCache, true);
    expect(result.comments, hasLength(1));
  });

  test(
    'NetEase hot pages use offsets and reuse the verified mapping',
    () async {
      final http = _Http((uri, _) async {
        if (uri.path == '/api/search/get') return _search();
        expect(uri.path, '/api/v1/resource/hotcomments/R_SO_4_42');
        expect(uri.queryParameters['limit'], '20');
        final offset = int.parse(uri.queryParameters['offset']!);
        return _comments(
          rows: [_neComment('$offset', 10)],
          hasMore: offset < 40,
        );
      });
      final repo = _repo(http);
      final first = await repo.load(query, SongCommentPlatform.netease);
      final second = await repo.load(
        query,
        SongCommentPlatform.netease,
        page: 1,
      );
      final last = await repo.load(query, SongCommentPlatform.netease, page: 2);
      expect(first.hasMore, true);
      expect(first.nextCursor, isNull);
      expect(second.comments.single.id, '20');
      expect(last.comments.single.id, '40');
      expect(last.hasMore, false);
      expect(
        http.calls.where((u) => u.path == '/api/search/get'),
        hasLength(1),
      );
      final cached = await repo.load(
        query,
        SongCommentPlatform.netease,
        page: 1,
      );
      expect(cached.fromCache, true);
      expect(cached.comments.single.id, '20');
      expect(http.calls, hasLength(4));
    },
  );

  test(
    'QQ hot pages use the last wire SeqNo, not comment ID or sorted order',
    () async {
      final http = _Http((uri, _) async {
        if (uri.path.contains('client_search_cp')) return _qqSearch();
        final request = _qqRequest(uri);
        expect(request['module'], 'music.globalComment.CommentRead');
        expect(request['method'], 'GetHotCommentList');
        final param = _qqParams(uri);
        expect(param['BizId'], '42');
        expect(param['BizType'], 1);
        expect(param['PageSize'], 20);
        expect(param['HotType'], 1);
        if (param['PageNum'] == 0) {
          expect(param['LastCommentSeqNo'], '');
          return _qqComments(
            rows: [_qqComment('a', 'seq-a', 10), _qqComment('b', 'seq-b', 99)],
            hasMore: true,
          );
        }
        expect(param['PageNum'], 1);
        expect(param['LastCommentSeqNo'], 'seq-b');
        return _qqComments(rows: [_qqComment('c', 'seq-c', 5)]);
      });
      final repo = _repo(http);
      final first = await repo.load(query, SongCommentPlatform.qq);
      expect(first.comments.map((c) => c.id), ['b', 'a']);
      expect(first.comments.first.author, '测试听众');
      expect(
        first.comments.first.createdAt?.millisecondsSinceEpoch,
        1700000000000,
      );
      expect(first.hasMore, true);
      expect(first.nextCursor, 'seq-b');
      final second = await repo.load(
        query,
        SongCommentPlatform.qq,
        page: 1,
        cursor: first.nextCursor,
      );
      expect(second.comments.single.id, 'c');
      expect(second.hasMore, false);
      expect(second.nextCursor, isNull);
      expect(http.calls, hasLength(4));
      final invalid = await repo.load(query, SongCommentPlatform.qq, page: 2);
      expect(invalid.status, SongCommentsStatus.unavailable);
      expect(http.calls, hasLength(4));
    },
  );

  test('QQ cache and concurrent work distinguish page cursors', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final http = _Http((uri, _) async {
      if (uri.path.contains('client_search_cp')) return _qqSearch();
      final param = _qqParams(uri);
      final cursor = param['LastCommentSeqNo'] as String;
      if (cursor == 'a') {
        if (!started.isCompleted) started.complete();
        await gate.future;
      }
      return _qqComments(
        rows: [_qqComment('id-$cursor', 'next-$cursor', 1)],
        hasMore: true,
      );
    });
    final repo = _repo(http);
    await repo.load(query, SongCommentPlatform.qq);
    final first = repo.load(
      query,
      SongCommentPlatform.qq,
      page: 1,
      cursor: 'a',
    );
    await started.future;
    final joined = repo.load(
      query,
      SongCommentPlatform.qq,
      page: 1,
      cursor: 'a',
    );
    final other = await repo.load(
      query,
      SongCommentPlatform.qq,
      page: 1,
      cursor: 'b',
    );
    gate.complete();
    final results = await Future.wait([first, joined]);
    expect(results.every((r) => r.comments.single.id == 'id-a'), true);
    expect(other.comments.single.id, 'id-b');
    expect(http.calls, hasLength(5));
    expect(
      (await repo.load(
        query,
        SongCommentPlatform.qq,
        page: 1,
        cursor: 'b',
      )).fromCache,
      true,
    );
    expect(http.calls, hasLength(5));
  });

  test('empty pages and nonadvancing QQ cursors stop pagination', () async {
    final ne = _repo(
      _Http(
        (uri, _) async => uri.path == '/api/search/get'
            ? _search()
            : _comments(rows: [], hasMore: true),
      ),
    );
    expect((await ne.load(query, SongCommentPlatform.netease)).hasMore, false);
    final qq = _repo(
      _Http(
        (uri, _) async => uri.path.contains('client_search_cp')
            ? _qqSearch()
            : _qqComments(rows: [_qqComment('a', 'same', 1)], hasMore: true),
      ),
    );
    final first = await qq.load(query, SongCommentPlatform.qq);
    final next = await qq.load(
      query,
      SongCommentPlatform.qq,
      page: 1,
      cursor: first.nextCursor,
    );
    expect(next.hasMore, false);
    expect(next.nextCursor, isNull);
    final noSeq = _repo(
      _Http(
        (uri, _) async => uri.path.contains('client_search_cp')
            ? _qqSearch()
            : _qqComments(rows: [_qqComment('a', '', 1)], hasMore: true),
      ),
    );
    expect((await noSeq.load(query, SongCommentPlatform.qq)).hasMore, false);
  });

  test(
    'later page duplicate IDs are deduplicated without importing latest comments',
    () async {
      final repo = _repo(
        _Http((uri, _) async {
          if (uri.path == '/api/search/get') return _search();
          return {
            ..._comments(
              rows: [
                _neComment('a', 3),
                _neComment('a', 3),
                _neComment('b', 2),
              ],
              hasMore: true,
            ),
            'comments': [_neComment('latest-not-hot', 100)],
          };
        }),
      );
      await repo.load(query, SongCommentPlatform.netease);
      final page = await repo.load(query, SongCommentPlatform.netease, page: 1);
      expect(page.comments.map((c) => c.id), ['a', 'b']);
      expect(page.hasMore, true);
    },
  );

  test(
    'first refresh invalidates page cache and prevents a late old page overwriting it',
    () async {
      var songId = 42;
      final oldPage = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      final http = _Http((uri, _) async {
        if (uri.path == '/api/search/get') {
          return {
            'code': 200,
            'result': {
              'songs': [_neSong(id: songId)],
            },
          };
        }
        final offset = uri.queryParameters['offset'];
        if (uri.path.endsWith('_42') && offset == '20') {
          if (!started.isCompleted) started.complete();
          return oldPage.future;
        }
        return _comments(
          rows: [_neComment('${songId}_$offset', 1)],
          hasMore: true,
        );
      });
      final repo = _repo(http);
      await repo.load(query, SongCommentPlatform.netease);
      final old = repo.load(query, SongCommentPlatform.netease, page: 1);
      await started.future;
      songId = 43;
      final fresh = await repo.load(
        query,
        SongCommentPlatform.netease,
        refresh: true,
      );
      expect(fresh.comments.single.id, '43_0');
      final newPage = await repo.load(
        query,
        SongCommentPlatform.netease,
        page: 1,
      );
      expect(newPage.comments.single.id, '43_20');
      oldPage.complete(
        _comments(rows: [_neComment('old-late', 1)], hasMore: true),
      );
      expect((await old).status, SongCommentsStatus.unavailable);
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.netease,
        )).comments.single.id,
        '43_0',
      );
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.netease,
          page: 1,
        )).comments.single.id,
        '43_20',
      );
    },
  );

  test(
    'refresh replaces an in-flight old first page and coalesces concurrent refreshes',
    () async {
      final gate = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      var commentsCalls = 0;
      final http = _Http((uri, _) async {
        if (uri.path == '/api/search/get') return _search();
        if (++commentsCalls == 1) {
          started.complete();
          return gate.future;
        }
        return _comments(rows: [_neComment('fresh', 1)], hasMore: true);
      });
      final repo = _repo(http);
      final old = repo.load(query, SongCommentPlatform.netease);
      await started.future;
      final fresh = repo.load(
        query,
        SongCommentPlatform.netease,
        refresh: true,
      );
      final joined = repo.load(
        query,
        SongCommentPlatform.netease,
        refresh: true,
      );
      expect((await fresh).comments.single.id, 'fresh');
      expect((await joined).comments.single.id, 'fresh');
      gate.complete(_comments(rows: [_neComment('old', 1)]));
      expect((await old).status, SongCommentsStatus.unavailable);
      expect(commentsCalls, 2);
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.netease,
        )).comments.single.id,
        'fresh',
      );
    },
  );

  test(
    'later page error preserves first cache and is retryable; stale page can still be read',
    () async {
      var fail = false;
      var now = DateTime(2026, 10, 8);
      final http = _Http((uri, _) async {
        if (uri.path == '/api/search/get') return _search();
        if (fail && uri.queryParameters['offset'] != '0') {
          throw const SocketException('offline');
        }
        return _comments(
          rows: [_neComment(uri.queryParameters['offset']!, 1)],
          hasMore: true,
        );
      });
      final repo = _repo(http, now: () => now);
      await repo.load(query, SongCommentPlatform.netease);
      fail = true;
      expect(
        (await repo.load(query, SongCommentPlatform.netease, page: 1)).status,
        SongCommentsStatus.unavailable,
      );
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.netease,
        )).comments.single.id,
        '0',
      );
      fail = false;
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.netease,
          page: 1,
        )).comments.single.id,
        '20',
      );
      now = now.add(const Duration(hours: 7));
      fail = true;
      final stale = await repo.load(
        query,
        SongCommentPlatform.netease,
        page: 1,
      );
      expect(stale.comments.single.id, '20');
      expect(stale.stale, true);
      expect(stale.fromCache, true);
    },
  );

  test(
    'only first page is persisted with QQ cursor and later pages are memory bounded',
    () async {
      final dir = await Directory.systemTemp.createTemp('comment-pages-');
      addTearDown(() => dir.delete(recursive: true));
      final http = _Http((uri, _) async {
        if (uri.path.contains('client_search_cp')) return _qqSearch();
        final page = _qqParams(uri)['PageNum'];
        return _qqComments(
          rows: [_qqComment('page-$page', 'next-$page', 1)],
          hasMore: true,
        );
      });
      final repo = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => dir,
      );
      await repo.load(query, SongCommentPlatform.qq);
      for (var page = 1; page <= 101; page++) {
        await repo.load(
          query,
          SongCommentPlatform.qq,
          page: page,
          cursor: 'next-${page - 1}',
        );
      }
      final calls = http.calls.length;
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.qq,
          page: 101,
          cursor: 'next-100',
        )).fromCache,
        true,
      );
      expect(http.calls.length, calls);
      expect(
        (await repo.load(
          query,
          SongCommentPlatform.qq,
          page: 1,
          cursor: 'next-0',
        )).fromCache,
        false,
      );
      expect(http.calls.length, calls + 1);
      final disk =
          jsonDecode(
                await File(
                  '${dir.path}/song_comments_cache.json',
                ).readAsString(),
              )
              as Map;
      expect(disk['schema'], 3);
      final entry = (disk['entries'] as List).single as Map;
      expect((entry['comments'] as List).single['id'], 'page-0');
      expect(entry['hasMore'], true);
      expect(entry['nextCursor'], 'next-0');
      final reopened = SongCommentsRepository(
        httpClient: http,
        rootProvider: () async => dir,
      );
      final first = await reopened.load(query, SongCommentPlatform.qq);
      expect(first.fromCache, true);
      expect(first.nextCursor, 'next-0');
      expect(
        (await reopened.load(
          query,
          SongCommentPlatform.qq,
          page: 1,
          cursor: first.nextCursor,
        )).fromCache,
        false,
      );
      expect(http.calls.length, calls + 2);
    },
  );

  test('QQ business errors never become an empty successful page', () async {
    final repo = _repo(
      _Http(
        (uri, _) async => uri.path.contains('client_search_cp')
            ? _qqSearch()
            : {
                'code': 0,
                'request': {
                  'code': -1,
                  'data': {
                    'CommentList': {'Comments': [], 'HasMore': 0},
                  },
                },
              },
      ),
    );
    expect(
      (await repo.load(query, SongCommentPlatform.qq)).status,
      SongCommentsStatus.unavailable,
    );
  });

  test('hung upstream respects request deadline', () async {
    final http = _Http((_, _) => Completer<Map<String, Object?>>().future);
    final repo = SongCommentsRepository(
      httpClient: http,
      rootProvider: () async => throw UnsupportedError('memory'),
      requestTimeout: const Duration(milliseconds: 5),
    );
    final result = await repo.load(query, SongCommentPlatform.netease);
    expect(result.status, SongCommentsStatus.unavailable);
  });
}

SongCommentsRepository _repo(_Http http, {DateTime Function()? now}) =>
    SongCommentsRepository(
      httpClient: http,
      rootProvider: () async => throw UnsupportedError('memory'),
      now: now,
    );
Map<String, Object?> _neSong({int id = 42, String artist = 'Beyond'}) => {
  'id': id,
  'name': '不再犹豫',
  'artists': [
    {'name': artist},
  ],
};
Map<String, Object?> _neComment(String id, int likes) => {
  'commentId': id,
  'content': '第一行\n第二行 &amp; 音乐',
  'user': {'nickname': '听众'},
  'time': 1700000000000,
  'likedCount': likes,
};
Map<String, Object?> _comments({
  List<Map<String, Object?>>? rows,
  bool hasMore = false,
}) => {
  'code': 200,
  'hotComments': rows ?? [_neComment('1', 10)],
  'hasMore': hasMore,
};
Map<String, dynamic> _qqRequest(Uri uri) =>
    (jsonDecode(uri.queryParameters['data']!) as Map)['request']
        as Map<String, dynamic>;
Map<String, dynamic> _qqParams(Uri uri) =>
    _qqRequest(uri)['param'] as Map<String, dynamic>;
Map<String, Object?> _qqComment(String id, String seq, int likes) => {
  'CmId': id,
  'SeqNo': seq,
  'Content': '测试热评',
  'Nick': '测试听众',
  'PraiseNum': likes,
  'PubTime': 1700000000,
};
Map<String, Object?> _qqComments({
  List<Map<String, Object?>> rows = const [],
  bool hasMore = false,
}) => {
  'code': 0,
  'request': {
    'code': 0,
    'data': {
      'CommentList': {
        'Comments': rows,
        'HasMore': hasMore ? 1 : 0,
        'NextOffset': 0,
      },
    },
  },
};
Map<String, Object?> _search() => {
  'code': 200,
  'result': {
    'songs': [_neSong()],
  },
};
Map<String, Object?> _qqSearch() => {
  'code': 0,
  'data': {
    'song': {
      'list': [
        {
          'songid': 42,
          'title': '不再犹豫',
          'singer': [
            {'name': 'Beyond'},
          ],
        },
      ],
    },
  },
};
Map<String, Object?> _qqSuggestions([
  List<Map<String, Object?>> rows = const [
    {'id': '42', 'name': '不再犹豫', 'singer': 'Beyond'},
  ],
]) => {
  'code': 0,
  'data': {
    'song': {'itemlist': rows},
  },
};
Map<String, Object?> _qqDetails({
  int id = 42,
  String title = '不再犹豫',
  String artist = 'Beyond',
  int duration = 255,
}) => {
  'code': 0,
  'request': {
    'code': 0,
    'data': {
      'track_info': {
        'id': id,
        'title': title,
        'singer': [
          {'name': artist},
        ],
        'interval': duration,
      },
    },
  },
};
MusicSearchCandidate _candidate(
  MusicDataSource source,
  String platform,
  String id,
) => MusicSearchCandidate(
  query: '',
  source: source,
  platform: platform,
  keyword: '',
  page: 1,
  id: id,
  name: '不再犹豫',
  artist: 'Beyond',
  album: '',
  duration: 0,
  link: '',
  coverUrl: '',
  qualities: const [],
  score: 0,
  raw: const {},
);

class _Http implements MusicResolverHttp {
  _Http(this.reply, {this.quickReply});
  final Future<Map<String, Object?>> Function(Uri, Map<String, String>?) reply;
  final Future<Map<String, Object?>> Function(Uri)? quickReply;
  final calls = <Uri>[];
  Future<ResolverHttpResponse> _send(Uri uri, Map<String, String>? form) async {
    calls.add(uri);
    return ResolverHttpResponse(
      statusCode: 200,
      body: jsonEncode(
        uri.path.endsWith('/smartbox_new.fcg')
            ? await (quickReply?.call(uri) ?? Future.value(_qqSuggestions([])))
            : await reply(uri, form),
      ),
      finalUrl: uri,
    );
  }

  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) => _send(uri, null);
  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) => _send(uri, form);
  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) => throw UnimplementedError();
}
