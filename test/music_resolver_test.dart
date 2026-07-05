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

  test(
    'buguyy preferred resolve chooses mp3 over default flac direct URL',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path == '/api/geturl') {
            return _json(uri, {
              'success': true,
              'name': '稻香',
              'url': 'https://cdn.example.test/daoxiang.flac',
            });
          }
          if (uri.path == '/api/getdown') {
            return _json(uri, {
              'success': true,
              'kuakedownurl': {
                'flac': 'https://cdn.example.test/daoxiang.flac',
                'mp3': 'https://cdn.example.test/daoxiang.mp3',
              },
            });
          }
          fail('Unexpected GET $uri');
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);
      const candidate = MusicSearchCandidate(
        query: '稻香 周杰伦',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        keyword: '稻香 周杰伦',
        page: 1,
        id: 'song-1',
        name: '稻香',
        artist: '周杰伦',
        album: '',
        duration: 180,
        link: '',
        coverUrl: '',
        qualities: [
          MusicQuality(format: 'flac'),
          MusicQuality(format: 'mp3', bitrate: '128'),
        ],
        score: 100,
        raw: {},
      );

      final defaultResolved = await resolver.resolve(candidate);
      final preferredResolved = await resolver.resolveWithPrefer(
        candidate,
        prefer: 'mp3',
      );

      expect(defaultResolved.quality.format, 'flac');
      expect(defaultResolved.url, endsWith('.flac'));
      expect(preferredResolved.quality.format, 'mp3');
      expect(preferredResolved.url, endsWith('.mp3'));
    },
  );

  test(
    'buguyy preferred resolve keeps mp3 direct URL when getdown fails',
    () async {
      var getdownRequests = 0;
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path == '/api/geturl') {
            return _json(uri, {
              'success': true,
              'name': '稻香',
              'url': 'https://cdn.example.test/daoxiang.mp3',
            });
          }
          if (uri.path == '/api/getdown') {
            getdownRequests += 1;
            return _json(uri, {
              'success': false,
              'message': 'getdown unavailable',
            });
          }
          fail('Unexpected GET $uri');
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);
      const candidate = MusicSearchCandidate(
        query: '稻香 周杰伦',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        keyword: '稻香 周杰伦',
        page: 1,
        id: 'song-1',
        name: '稻香',
        artist: '周杰伦',
        album: '',
        duration: 180,
        link: '',
        coverUrl: '',
        qualities: [MusicQuality(format: 'mp3', bitrate: '128')],
        score: 100,
        raw: {},
      );

      final resolved = await resolver.resolveWithPrefer(
        candidate,
        prefer: 'mp3',
      );

      expect(resolved.url, 'https://cdn.example.test/daoxiang.mp3');
      expect(resolved.quality.format, 'mp3');
      expect(getdownRequests, 0);
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

  test(
    'buguyy Quark links are classified as external pan and flac defender HTML is logged',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path == '/api/geturl') {
            return _json(uri, {'success': false});
          }
          if (uri.path == '/api/getdown') {
            return _json(uri, {
              'success': true,
              'kuakedownurl': 'flac#https://pan.quark.cn/s/example',
              'lrc': '[00:01]BuguYY 歌词',
            });
          }
          fail('Unexpected GET $uri');
        },
        onPostForm: (uri, _, _) async {
          expect(uri.queryParameters['act'], 'search');
          return ResolverHttpResponse(
            statusCode: HttpStatus.ok,
            body: '<html><title>SafeLine</title></html>',
            finalUrl: uri,
          );
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
        platforms: const ['kuwo'],
      );

      await expectLater(
        resolver.resolve(
          MusicSearchCandidate(
            query: '陈奕迅 一丝不挂',
            source: MusicDataSource.buguyy,
            platform: 'buguyy',
            keyword: '一丝不挂',
            page: 1,
            id: 'buguyy-1',
            name: '一丝不挂',
            artist: '陈奕迅',
            album: '',
            duration: 240,
            link: '',
            coverUrl: 'https://img.example.test/cover.jpg',
            qualities: const [MusicQuality(format: 'flac')],
            score: 150,
            raw: const {},
          ),
        ),
        throwsA(
          isA<SourceDownloadException>()
              .having(
                (error) => error.failureCode,
                'failureCode',
                'external_pan_link',
              )
              .having(
                (error) => error.sourceAttempts.first.mediaUrlType,
                'buguyy urlType',
                MediaUrlType.externalPan,
              )
              .having(
                (error) => error.sourceAttempts.last.failureCode,
                'flac failure',
                'defender_challenge',
              ),
        ),
      );
    },
  );

  test(
    'buguyy external pan fallback skips untrusted flac title artist matches',
    () async {
      var getUrlRequests = 0;
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path == '/api/geturl') {
            return _json(uri, {'success': false});
          }
          if (uri.path == '/api/getdown') {
            return _json(uri, {
              'success': true,
              'kuakedownurl': 'mp3#https://pan.quark.cn/s/fukua',
            });
          }
          fail('Unexpected GET $uri');
        },
        onPostForm: (uri, form, _) async {
          final act = uri.queryParameters['act'];
          if (act == 'search') {
            return _json(uri, {
              'data': {
                'list': [
                  {
                    'id': 'wrong',
                    'name': '浮夸 (DJ版)',
                    'artist': '王心凌',
                    'duration': 200,
                    'minfo': [
                      {'format': 'flac', 'bitrate': '900'},
                    ],
                  },
                ],
              },
            });
          }
          if (act == 'getUrl') {
            getUrlRequests += 1;
            return _json(uri, {
              'data': {'url': 'https://cdn.example.test/wrong.flac'},
            });
          }
          fail('Unexpected POST $uri $form');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
        platforms: const ['kuwo'],
      );

      await expectLater(
        resolver.resolve(
          MusicSearchCandidate(
            query: '陈奕迅 浮夸',
            source: MusicDataSource.buguyy,
            platform: 'buguyy',
            keyword: '浮夸',
            page: 1,
            id: 'buguyy-fukua',
            name: '浮夸',
            artist: '陈奕迅',
            album: '',
            duration: 240,
            link: '',
            coverUrl: '',
            qualities: const [MusicQuality(format: 'mp3')],
            score: 150,
            raw: const {},
          ),
        ),
        throwsA(
          isA<SourceDownloadException>().having(
            (error) => error.sourceAttempts.last.failureCode,
            'flac fallback failure',
            'no_trusted_artist_title_match',
          ),
        ),
      );
      expect(getUrlRequests, 0);
    },
  );

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
    'flac plain HTML ajax responses are classified as anti-CC non JSON',
    () async {
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onPostForm: (uri, _, _) async {
            expect(uri.queryParameters['act'], 'search');
            return ResolverHttpResponse(
              statusCode: HttpStatus.ok,
              body: '<html><title>anti cc</title></html>',
              finalUrl: uri,
            );
          },
        ),
        initialFlacCookie: 'sl-session=test',
        platforms: const ['kuwo'],
      );

      await expectLater(
        resolver.search('陈奕迅 浮夸', MusicDataSource.flac),
        throwsA(
          isA<SourceDownloadException>().having(
            (error) => error.failureCode,
            'failureCode',
            'anticc_non_json',
          ),
        ),
      );
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

  test(
    'itunes preview search resolves preview audio with lrclib lyrics',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'itunes.apple.com') {
            expect(uri.queryParameters['media'], 'music');
            expect(uri.queryParameters['entity'], 'song');
            return _json(uri, {
              'resultCount': 1,
              'results': [
                {
                  'trackId': 1001,
                  'trackName': '稻香',
                  'artistName': '周杰伦',
                  'collectionName': '魔杰座',
                  'trackTimeMillis': 30000,
                  'artworkUrl100':
                      'https://is1-ssl.mzstatic.com/image/100x100bb.jpg',
                  'previewUrl':
                      'https://audio-ssl.itunes.apple.com/itunes-assets/MusicPreview.m4a',
                },
              ],
            });
          }
          if (uri.host == 'lrclib.net') {
            return _json(uri, [
              {'syncedLyrics': '[00:01.00]对这个世界如果你有太多的抱怨'},
            ]);
          }
          fail('Unexpected GET $uri');
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search(
        '周杰伦 稻香',
        MusicDataSource.itunesPreview,
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.source, MusicDataSource.itunesPreview);
      expect(candidates.single.coverUrl, contains('600x600bb'));
      expect(candidates.single.qualityLabel, 'PREVIEW AAC 30s');

      final resolved = await resolver.resolve(candidates.single);
      expect(resolved.urlType, MediaUrlType.previewAudio);
      expect(resolved.canCacheAudio, isFalse);
      expect(resolved.sourceAttempts.single.status, SourceAttemptStatus.ok);
      expect(resolved.sourceAttempts.single.failureCode, isEmpty);
      expect(
        resolved.sourceAttempts.single.reasonCode,
        'preview_audio_available',
      );
      expect(resolved.lyrics?.source, 'lrclib:syncedLyrics');
    },
  );

  test(
    'auto includes itunes preview candidates when legacy sources fail',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'buguyy.top') {
            return _json(uri, {'data': const []});
          }
          if (uri.host == 'itunes.apple.com') {
            return _json(uri, {
              'results': [
                {
                  'trackId': 2001,
                  'trackName': '龙的传人',
                  'artistName': '王力宏',
                  'trackTimeMillis': 30000,
                  'previewUrl':
                      'https://audio-ssl.itunes.apple.com/itunes-assets/long.m4a',
                },
              ],
            });
          }
          fail('Unexpected GET $uri');
        },
        onPostForm: (_, _, _) async {
          throw const HttpException('SafeLine challenge');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
        platforms: const ['kuwo'],
      );

      final candidates = await resolver.search(
        '王力宏 龙的传人',
        MusicDataSource.auto,
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.source, MusicDataSource.itunesPreview);
    },
  );

  test(
    '22a5 guarded provider resolves only client ready direct audio',
    () async {
      const audioUrl = 'https://car-lv.kuwo.cn/path/song.m4a?from=vip';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (Uri.decodeComponent(uri.path) == '/so/黑夜传说.html') {
            return _html(
              uri,
              '<a href="/mp3/gslelxsl.html">麻园诗人《黑夜传说》[MP3_LRC]</a>',
            );
          }
          if (uri.path == '/mp3/gslelxsl.html') {
            return _html(uri, '''
              <html>
                <img src="http://img2.kuwo.cn/star/albumcover/500/cover.jpg">
                <script>var media = "$audioUrl";</script>
                <a href="/plug/down.php?ac=music&lk=lrc&id=gslelxsl">LRC动态歌词免费下载</a>
              </html>
            ''');
          }
          if (uri.path == '/plug/down.php') {
            return _html(uri, '[00:01.00]黑夜传说 - 麻园诗人');
          }
          fail('Unexpected GET $uri');
        },
        onHead: (uri, _) async {
          expect(uri.toString(), audioUrl);
          return _response(
            uri,
            HttpStatus.ok,
            headers: const {
              'content-type': 'audio/mp4',
              'content-length': '1658856',
              'accept-ranges': 'bytes',
            },
          );
        },
        onRange: (uri, start, end, _) async {
          expect(uri.toString(), audioUrl);
          expect((start, end), (0, 0));
          return _response(
            uri,
            HttpStatus.partialContent,
            headers: const {
              'content-type': 'audio/mp4',
              'content-length': '1',
              'content-range': 'bytes 0-0/1658856',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search(
        '黑夜传说',
        MusicDataSource.source22a5,
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.name, '黑夜传说');
      expect(candidates.single.artist, '麻园诗人');

      final resolved = await resolver.resolve(candidates.single);
      expect(resolved.url, audioUrl);
      expect(resolved.urlType, MediaUrlType.directAudio);
      expect(resolved.canCacheAudio, isTrue);
      expect(resolved.lyrics?.source, '22a5:lrc');
      expect(resolved.sourceAttempts.single.reasonCode, 'direct_audio_ready');
      expect(resolved.sourceAttempts.single.clientReady, isTrue);
      expect(
        resolved.sourceAttempts.single.mediaValidation,
        contains('range=206'),
      );
    },
  );

  test('22a5 guarded provider fails closed on media validation 403', () async {
    const audioUrl = 'https://car-er.kuwo.cn/path/blocked.m4a?from=vip';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path == '/mp3/eexmdc.html') {
          return _html(uri, '<script>let url = "$audioUrl";</script>');
        }
        fail('Unexpected GET $uri');
      },
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.forbidden,
        headers: const {'content-length': '0'},
      ),
      onRange: (uri, start, end, _) async => _response(
        uri,
        HttpStatus.forbidden,
        headers: const {'content-length': '0'},
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    await expectLater(
      resolver.resolve(
        MusicSearchCandidate(
          query: '浮夸',
          source: MusicDataSource.source22a5,
          platform: '22a5',
          keyword: '浮夸',
          page: 1,
          id: 'eexmdc',
          name: '浮夸',
          artist: '陈奕迅',
          album: '',
          duration: 0,
          link: 'https://www.22a5.com/mp3/eexmdc.html',
          coverUrl: '',
          qualities: const [MusicQuality(format: 'guarded')],
          score: 100,
          raw: const {},
        ),
      ),
      throwsA(
        isA<SourceDownloadException>()
            .having(
              (error) => error.failureCode,
              'failureCode',
              'audio_validation_failed',
            )
            .having(
              (error) => error.sourceAttempts.single.mediaUrlType,
              'urlType',
              MediaUrlType.directAudioCandidate,
            )
            .having(
              (error) => error.sourceAttempts.single.clientReady,
              'clientReady',
              isFalse,
            ),
      ),
    );
  });

  test('22a5 guarded provider fails closed when detail has no audio URL', () {
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path == '/mp3/ddxleg.html') {
          return _html(uri, '<html><img src="/cover.jpg"></html>');
        }
        fail('Unexpected GET $uri');
      },
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    expect(
      resolver.resolve(
        MusicSearchCandidate(
          query: '稻香',
          source: MusicDataSource.source22a5,
          platform: '22a5',
          keyword: '稻香',
          page: 1,
          id: 'ddxleg',
          name: '稻香',
          artist: '周杰伦',
          album: '',
          duration: 0,
          link: 'https://www.22a5.com/mp3/ddxleg.html',
          coverUrl: '',
          qualities: const [MusicQuality(format: 'guarded')],
          score: 100,
          raw: const {},
        ),
      ),
      throwsA(
        isA<SourceDownloadException>().having(
          (error) => error.failureCode,
          'failureCode',
          'no_audio_url',
        ),
      ),
    );
  });
}

ResolverHttpResponse _json(Uri uri, Object body) {
  return ResolverHttpResponse(
    statusCode: HttpStatus.ok,
    body: jsonEncode(body),
    finalUrl: uri,
  );
}

ResolverHttpResponse _html(Uri uri, String body) {
  return _response(
    uri,
    HttpStatus.ok,
    body: body,
    headers: const {'content-type': 'text/html; charset=UTF-8'},
  );
}

ResolverHttpResponse _response(
  Uri uri,
  int statusCode, {
  String body = '',
  Map<String, String> headers = const {},
}) {
  return ResolverHttpResponse(
    statusCode: statusCode,
    body: body,
    finalUrl: uri,
    headers: headers,
  );
}

class _FakeResolverHttp implements MusicResolverHttp {
  _FakeResolverHttp({this.onGet, this.onHead, this.onRange, this.onPostForm});

  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Map<String, String> headers,
  )?
  onGet;
  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Map<String, String> headers,
  )?
  onHead;
  final Future<ResolverHttpResponse> Function(
    Uri uri,
    int start,
    int end,
    Map<String, String> headers,
  )?
  onRange;
  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Map<String, String> form,
    Map<String, String> headers,
  )?
  onPostForm;
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
  Future<ResolverHttpResponse> head(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    final handler = onHead;
    if (handler == null) {
      fail('Unexpected HEAD $uri');
    }
    return handler(uri, headers);
  }

  @override
  Future<ResolverHttpResponse> range(
    Uri uri, {
    int start = 0,
    int end = 0,
    Map<String, String> headers = const {},
  }) {
    final handler = onRange;
    if (handler == null) {
      fail('Unexpected range GET $uri');
    }
    return handler(uri, start, end, headers);
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
    fail('Unexpected JSON POST $uri');
  }
}
