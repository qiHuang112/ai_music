import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buguyy endpoint is HTTPS off Apple platforms and HTTP on Apple', () {
    expect(defaultBuguyyBaseUrl(isApplePlatform: false), 'https://buguyy.top');
    expect(defaultBuguyyBaseUrl(isApplePlatform: true), 'http://buguyy.top');
  });

  test(
    'buguyy search normalizes candidates and resolves direct URLs',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          expect(uri.scheme, 'http');
          expect(uri.host, 'buguyy.top');
          if (uri.path == '/api/search') {
            return _json(uri, {
              'data': [
                {
                  'id': 'song-1',
                  'title': '稻香',
                  'singer': '周杰伦',
                  'about': '[1.50]搜索歌词',
                },
              ],
            });
          }
          if (uri.path == '/api/geturl') {
            return _json(uri, {
              'success': true,
              'name': '稻香',
              'url': 'https://cdn.example.test/daoxiang.mp3',
              'lyric': '<p>[00:02]布谷歌词</p>',
            });
          }
          fail('Unexpected GET $uri');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        useAppleBuguyyEndpoint: true,
      );

      final candidates = await resolver.search('周杰伦', MusicDataSource.buguyy);
      expect(candidates, hasLength(1));
      expect(candidates.single.name, '稻香');
      expect(candidates.single.artist, '周杰伦');
      expect(candidates.single.source, MusicDataSource.buguyy);

      final resolved = await resolver.resolve(candidates.single);
      expect(resolved.url, 'https://cdn.example.test/daoxiang.mp3');
      expect(resolved.quality.format, 'mp3');
      expect(resolved.panLink, isFalse);
      expect(resolved.lyrics?.text, '[00:02.00]布谷歌词');
      expect(resolved.lyrics?.source, 'buguyy:geturl:lyric');
    },
  );

  test('buguyy resolve ignores placeholder lyrics', () async {
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path == '/api/geturl') {
          return _json(uri, {
            'success': true,
            'name': '稻香',
            'url': 'https://cdn.example.test/daoxiang.mp3',
            'lyric': '暂无歌词',
          });
        }
        fail('Unexpected GET $uri');
      },
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final resolved = await resolver.resolve(
      MusicSearchCandidate(
        query: '周杰伦 稻香',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        keyword: '周杰伦',
        page: 1,
        id: 'song-1',
        name: '稻香',
        artist: '周杰伦',
        album: '',
        duration: 200,
        link: '',
        coverUrl: '',
        qualities: const [MusicQuality(format: 'mp3')],
        score: 100,
        raw: const {},
      ),
    );

    expect(resolved.lyrics, isNull);
  });

  test('buguyy transient network errors retry the same request', () async {
    var attempts = 0;
    final retryHeaders = <Map<String, String>>[];
    final resolver = BuguyyResolver(
      httpClient: _FakeResolverHttp(
        onGet: (uri, headers) async {
          attempts += 1;
          retryHeaders.add(headers);
          expect(uri.scheme, 'http');
          expect(uri.host, 'buguyy.top');
          if (attempts < 3) {
            throw const HttpException(
              'HttpConnection closed before full header was received',
            );
          }
          return _json(uri, {
            'data': [
              {'id': 'song-1', 'title': '泸沽湖', 'singer': '麻园诗人'},
            ],
          });
        },
      ),
      useAppleEndpoint: true,
      retryDelay: Duration.zero,
    );

    final candidates = await resolver.search('泸沽湖');

    expect(candidates.single.name, '泸沽湖');
    expect(attempts, 3);
    expect(retryHeaders.first.containsKey('connection'), isFalse);
    expect(retryHeaders[1]['connection'], 'close');
    expect(retryHeaders[2]['connection'], 'close');
  });

  test(
    'buguyy transient failure reports friendly error without flac fallback',
    () async {
      var getAttempts = 0;
      var flacRequests = 0;
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onGet: (_, _) async {
            getAttempts += 1;
            throw const HttpException(
              'HttpConnection closed before full header was received',
            );
          },
          onPostForm: (_, _, _) async {
            flacRequests += 1;
            return _json(Uri.parse('https://flac.example.test'), {});
          },
        ),
        useAppleBuguyyEndpoint: true,
      );

      await expectLater(
        resolver.search('泸沽湖', MusicDataSource.buguyy),
        throwsA(isA<BuguyyConnectionException>()),
      );
      expect(getAttempts, 3);
      expect(flacRequests, 0);
    },
  );

  test(
    'flac search ranks exact short titles and resolves preferred quality',
    () async {
      final getUrlForms = <Map<String, String>>[];
      final http = _FakeResolverHttp(
        onPostForm: (uri, form, _) async {
          final act = uri.queryParameters['act'];
          if (act == 'search') {
            final rows = form['platform'] == 'kuwo'
                ? [
                    {
                      'id': 'long',
                      'name': '四季圈',
                      'artist': '陈奕迅',
                      'duration': 220,
                      'minfo': [
                        {'format': 'mp3', 'bitrate': '320', 'size': '9M'},
                      ],
                    },
                    {
                      'id': 'exact',
                      'name': '四季',
                      'artist': '陈奕迅',
                      'pic_url': 'https://img.example.test/flac-cover.jpg',
                      'duration': 210,
                      'minfo': [
                        {'format': 'mp3', 'bitrate': '320', 'size': '9M'},
                        {'format': 'flac', 'bitrate': '900', 'size': '24M'},
                      ],
                      'time': 't',
                      'sign': 's',
                    },
                  ]
                : const [];
            return _json(uri, {
              'data': {'list': rows},
            });
          }
          if (act == 'getUrl') {
            getUrlForms.add(form);
            return _json(uri, {
              'data': {
                'url': 'https://cdn.example.test/exact.flac',
                'pic_url': 'https://img.example.test/geturl-cover.jpg',
                'lyrics': {'content': '[3.50]FLAC 歌词'},
              },
            });
          }
          fail('Unexpected POST $uri');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
      );

      final candidates = await resolver.search('陈奕迅 四季', MusicDataSource.flac);
      expect(candidates.first.name, '四季');
      expect(
        isStrictArtistCandidate(
          candidates.firstWhere((candidate) => candidate.name == '四季'),
          '陈奕迅 四季',
        ),
        isTrue,
      );
      expect(
        isStrictArtistCandidate(
          candidates.firstWhere((candidate) => candidate.name == '四季圈'),
          '陈奕迅 四季',
        ),
        isFalse,
      );

      final resolved = await resolver.resolve(candidates.first);
      expect(resolved.url, 'https://cdn.example.test/exact.flac');
      expect(resolved.coverUrl, 'https://img.example.test/geturl-cover.jpg');
      expect(getUrlForms.single['format'], 'flac');
      expect(resolved.lyrics?.text, '[00:03.50]FLAC 歌词');
      expect(resolved.lyrics?.source, 'flac:getUrl:lyrics');
    },
  );

  test(
    'auto searches buguyy and flac then merges concrete candidates',
    () async {
      var buguyyRequests = 0;
      var flacRequests = 0;
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          buguyyRequests += 1;
          return _json(uri, {
            'data': [
              {'id': 'song-1', 'title': '晴天', 'singer': '周杰伦'},
            ],
          });
        },
        onPostForm: (uri, form, _) async {
          flacRequests += 1;
          if (uri.queryParameters['act'] == 'search') {
            return _json(uri, {
              'data': {
                'list': form['platform'] == 'kuwo'
                    ? [
                        {
                          'id': 'flac-1',
                          'name': '晴天',
                          'artist': '周杰伦',
                          'pic_url': 'https://img.example.test/qingtian.jpg',
                          'duration': 240,
                          'minfo': [
                            {'format': 'flac', 'bitrate': '900'},
                          ],
                        },
                      ]
                    : const [],
              },
            });
          }
          return _json(uri, {});
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
      );

      final candidates = await resolver.search('周杰伦', MusicDataSource.auto);
      expect(
        candidates.map((candidate) => candidate.source).toSet(),
        containsAll([MusicDataSource.buguyy, MusicDataSource.flac]),
      );
      expect(
        candidates
            .firstWhere((candidate) => candidate.source == MusicDataSource.flac)
            .coverUrl,
        'https://img.example.test/qingtian.jpg',
      );
      expect(buguyyRequests, greaterThan(0));
      expect(flacRequests, greaterThan(0));
    },
  );

  test('auto keeps flac results when buguyy has no candidates', () async {
    var flacRequests = 0;
    final http = _FakeResolverHttp(
      onGet: (uri, _) async => _json(uri, {'data': const []}),
      onPostForm: (uri, form, _) async {
        flacRequests += 1;
        if (uri.queryParameters['act'] == 'search') {
          return _json(uri, {
            'data': {
              'list': form['platform'] == 'kuwo'
                  ? [
                      {
                        'id': 'flac-1',
                        'name': '十年',
                        'artist': '陈奕迅',
                        'duration': 230,
                        'minfo': [
                          {'format': 'flac', 'bitrate': '900'},
                        ],
                      },
                    ]
                  : const [],
            },
          });
        }
        return _json(uri, {});
      },
    );
    final resolver = RemoteMusicResolver(
      httpClient: http,
      initialFlacCookie: 'sl-session=test',
    );

    final candidates = await resolver.search('陈奕迅', MusicDataSource.auto);
    expect(candidates.first.source, MusicDataSource.flac);
    expect(flacRequests, greaterThan(0));
  });

  test('auto keeps buguyy results when flac fails', () async {
    var buguyyRequests = 0;
    var flacRequests = 0;
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        buguyyRequests += 1;
        return _json(uri, {
          'data': [
            {'id': 'song-1', 'title': '晴天', 'singer': '周杰伦'},
          ],
        });
      },
      onPostForm: (_, _, _) async {
        flacRequests += 1;
        throw const HttpException('flac offline');
      },
    );
    final resolver = RemoteMusicResolver(
      httpClient: http,
      initialFlacCookie: 'sl-session=test',
    );

    final candidates = await resolver.search('周杰伦', MusicDataSource.auto);

    expect(candidates, hasLength(1));
    expect(candidates.single.source, MusicDataSource.buguyy);
    expect(buguyyRequests, greaterThan(0));
    expect(flacRequests, greaterThan(0));
  });
}

ResolverHttpResponse _json(Uri uri, Object body) {
  return ResolverHttpResponse(
    statusCode: HttpStatus.ok,
    body: jsonEncode(body),
    finalUrl: uri,
  );
}

class _FakeResolverHttp implements MusicResolverHttp {
  // ignore: unused_element_parameter
  _FakeResolverHttp({this.onGet, this.onPostForm, this.onPostJson});

  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Map<String, String> headers,
  )?
  onGet;
  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Map<String, String> form,
    Map<String, String> headers,
  )?
  onPostForm;
  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Object body,
    Map<String, String> headers,
  )?
  onPostJson;

  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    final handler = onGet;
    if (handler == null) {
      fail('Unexpected GET $uri');
    }
    return handler(uri, headers);
  }

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) {
    final handler = onPostForm;
    if (handler == null) {
      fail('Unexpected form POST $uri');
    }
    return handler(uri, form, headers);
  }

  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) {
    final handler = onPostJson;
    if (handler == null) {
      fail('Unexpected JSON POST $uri');
    }
    return handler(uri, body, headers);
  }
}
