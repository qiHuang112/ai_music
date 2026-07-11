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

  test('auto searches only validated gequhai full audio candidates', () async {
    const audioUrl = 'https://cdn.gequhai.test/audio/6330.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          return _html(uri, '''
              <table>
                <tr><td><a href="/play/6330">外婆</a></td><td>周杰伦</td></tr>
              </table>
            ''');
        }
        if (uri.path == '/play/6330') {
          return _html(uri, '''
              <script>
                window.play_id = '6330';
                window.mp3_title = '外婆';
                window.mp3_author = '周杰伦';
                window.mp3_cover = 'https://img.gequhai.test/cover.jpg';
              </script>
              <div id="content-lrc2">[00:01.00]外婆</div>
            ''');
        }
        fail('Unexpected GET $uri');
      },
      onPostForm: (uri, form, _) async {
        expect(uri.toString(), 'https://www.gequhai.com/api/music');
        expect(form, {'id': '6330', 'type': '0'});
        return _json(uri, {
          'code': 200,
          'data': {'url': audioUrl},
        });
      },
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-length': '3913543',
        },
      ),
      onRange: (uri, _, _, _) async => _response(
        uri,
        HttpStatus.partialContent,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-range': 'bytes 0-8191/3913543',
        },
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('外婆', MusicDataSource.auto);

    expect(candidates, hasLength(1));
    expect(candidates.single.source, MusicDataSource.gequhai);
    expect(candidates.single.raw['clientReady'], isTrue);
    expect(
      candidates.single.raw['urlType'],
      MediaUrlType.directAudio.storageValue,
    );
  });

  test('auto returns no candidates for gequhai no search match', () async {
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        expect(
          uri.toString(),
          contains('/s/%E4%B8%9C%E6%96%B9%E8%B4%A2%E5%AF%8C'),
        );
        return _html(uri, '<table></table>');
      },
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('东方财富', MusicDataSource.auto);

    expect(candidates, isEmpty);
  });

  test('auto keeps gequhai artist-only search results visible', () async {
    const audioUrl = 'https://cdn.gequhai.test/audio/326.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          return _html(uri, '''
              <table>
                <tr><td><a href="/play/326">晴天</a></td><td>周杰伦</td></tr>
                <tr><td><a href="/play/553">青花瓷</a></td><td>周杰伦</td></tr>
              </table>
            ''');
        }
        if (uri.path == '/play/326') {
          return _html(uri, '''
              <script>
                window.play_id = '326';
                window.mp3_title = '晴天';
                window.mp3_author = '周杰伦';
              </script>
              <div id="content-lrc2">[00:01.00]晴天</div>
            ''');
        }
        if (uri.path == '/play/553') {
          return _html(uri, '''
              <script>
                window.play_id = '553';
                window.mp3_title = '青花瓷';
                window.mp3_author = '周杰伦';
              </script>
              <div id="content-lrc2">[00:01.00]青花瓷</div>
            ''');
        }
        fail('Unexpected GET $uri');
      },
      onPostForm: (uri, form, _) async => _json(uri, {
        'code': 200,
        'data': {'url': audioUrl.replaceFirst('326', form['id'] ?? '')},
      }),
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-length': '3913543',
        },
      ),
      onRange: (uri, _, _, _) async => _response(
        uri,
        HttpStatus.partialContent,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-range': 'bytes 0-8191/3913543',
        },
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('周杰伦', MusicDataSource.auto);

    expect(candidates.map((candidate) => candidate.name), contains('晴天'));
    expect(candidates.map((candidate) => candidate.artist).toSet(), {'周杰伦'});
    expect(candidates.first.source, MusicDataSource.gequhai);
  });

  test(
    'auto tries later gequhai candidates when the top match fails validation',
    () async {
      const goodAudioUrl = 'https://cdn.gequhai.test/audio/5553349.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path.startsWith('/s/')) {
            return _html(uri, '''
              <table>
                <tr><td><a href="/play/5553351">剩下的果实</a></td><td>陈玖术</td></tr>
                <tr><td><a href="/play/5553349">剩下的果实</a></td><td>小羊</td></tr>
              </table>
            ''');
          }
          if (uri.path == '/play/5553351') {
            return _html(uri, '''
              <script>
                window.play_id = '5553351';
                window.mp3_title = '剩下的果实';
                window.mp3_author = '陈玖术';
              </script>
            ''');
          }
          if (uri.path == '/play/5553349') {
            return _html(uri, '''
              <script>
                window.play_id = '5553349';
                window.mp3_title = '剩下的果实';
                window.mp3_author = '小羊';
              </script>
              <div id="content-lrc2">[00:01.00]剩下的果实</div>
            ''');
          }
          fail('Unexpected GET $uri');
        },
        onPostForm: (uri, form, _) async {
          if (form['id'] == '5553351') {
            return _json(uri, {
              'code': 200,
              'data': {'url': 'https://cdn.gequhai.test/not-audio.html'},
            });
          }
          return _json(uri, {
            'code': 200,
            'data': {'url': goodAudioUrl},
          });
        },
        onHead: (uri, _) async => _response(
          uri,
          HttpStatus.ok,
          headers: {
            'content-type': uri.path.endsWith('.html')
                ? 'text/html'
                : 'audio/mpeg',
            'content-length': '3913543',
          },
        ),
        onRange: (uri, _, _, _) async => _response(
          uri,
          HttpStatus.partialContent,
          headers: const {
            'content-type': 'audio/mpeg',
            'content-range': 'bytes 0-8191/3913543',
          },
        ),
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search('剩下的果实', MusicDataSource.auto);

      expect(candidates.map((candidate) => candidate.id), contains('5553349'));
      expect(
        candidates.map((candidate) => candidate.id),
        isNot(contains('5553351')),
      );
      expect(
        candidates.single.raw['urlType'],
        MediaUrlType.directAudio.storageValue,
      );
    },
  );

  test(
    'auto does not fall back to old sources when gequhai media fails',
    () async {
      const audioUrl = 'https://cdn.gequhai.test/audio/6330.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path.startsWith('/s/')) {
            return _html(uri, '''
            <table>
              <tr><td><a href="/play/6330">外婆</a></td><td>周杰伦</td></tr>
            </table>
          ''');
          }
          if (uri.path == '/play/6330') {
            return _html(uri, '''
            <script>
              window.play_id = '6330';
              window.mp3_title = '外婆';
              window.mp3_author = '周杰伦';
            </script>
            <div id="content-lrc2">[00:01.00]外婆</div>
          ''');
          }
          fail('Unexpected GET $uri');
        },
        onPostForm: (_, _, _) async =>
            _json(Uri.https('www.gequhai.com', '/api/music'), {
              'code': 200,
              'data': {'url': audioUrl},
            }),
        onHead: (uri, _) async => _response(
          uri,
          HttpStatus.ok,
          headers: const {'content-type': 'text/html', 'content-length': '128'},
        ),
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search('外婆', MusicDataSource.auto);

      expect(candidates, isEmpty);
    },
  );

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
    'auto hides itunes preview candidates when full audio sources fail',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'buguyy.top') {
            return _json(uri, {'data': const []});
          }
          if (uri.host == 'search.kuwo.cn') {
            return _json(uri, {'abslist': const []});
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

      expect(
        () => resolver.search('王力宏 龙的传人', MusicDataSource.auto),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'product sources fail closed except scoped gequhai player audio',
    () async {
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            if (uri.host == 'www.gequhai.com' && uri.path.startsWith('/s/')) {
              return _html(uri, '<table></table>');
            }
            fail('Unexpected GET $uri');
          },
        ),
      );

      await expectLater(
        resolver.search('稻香', MusicDataSource.source2t58),
        throwsA(
          isA<SourceDownloadException>().having(
            (error) => error.failureCode,
            'failureCode',
            'security_verification',
          ),
        ),
      );
      final gequhai = await resolver.search('稻香', MusicDataSource.gequhai);
      expect(gequhai, isEmpty);
      await expectLater(
        resolver.search('稻香', MusicDataSource.gequbao),
        throwsA(
          isA<SourceDownloadException>().having(
            (error) => error.failureCode,
            'failureCode',
            'security_verification',
          ),
        ),
      );
    },
  );

  test('gequhai search returns exact playable result', () async {
    const audioUrl = 'https://cdn.gequhai.test/audio/6330.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          expect(
            uri.toString(),
            'https://www.gequhai.com/s/%E5%A4%96%E5%A9%86',
          );
          return _html(uri, '''
            <table>
              <tr>
                <td>1</td>
                <td><a href="/play/6330">外婆</a></td>
                <td>周杰伦</td>
              </tr>
              <tr>
                <td>2</td>
                <td><a href="/play/9999">外婆</a></td>
                <td>赵雷</td>
              </tr>
            </table>
          ''');
        }
        if (uri.path == '/play/6330') {
          return _html(uri, '''
            <script>
              window.play_id = 'fee9695329fa13015c0bb274d17fed3e';
              window.mp3_title = '外婆';
              window.mp3_author = '周杰伦';
            </script>
            <div id="content-lrc2">[00:01.00]外婆</div>
          ''');
        }
        fail('Unexpected GET $uri');
      },
      onPostForm: (uri, form, _) async {
        expect(form, {'id': 'fee9695329fa13015c0bb274d17fed3e', 'type': '0'});
        return _json(uri, {
          'code': 200,
          'data': {'url': audioUrl},
        });
      },
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-length': '3913543',
        },
      ),
      onRange: (uri, _, _, _) async => _response(
        uri,
        HttpStatus.partialContent,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-range': 'bytes 0-8191/3913543',
        },
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('外婆', MusicDataSource.gequhai);

    expect(candidates, hasLength(1));
    expect(candidates.single.name, '外婆');
    expect(candidates.single.artist, '周杰伦');
    expect(candidates.single.id, '6330');
    expect(candidates.single.link, 'https://www.gequhai.com/play/6330');
    expect(candidates.single.source, MusicDataSource.gequhai);
  });

  test('gequhai search hides media validation failures', () async {
    const audioUrl = 'https://cdn.gequhai.test/audio/6330.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          return _html(uri, '''
            <table>
              <tr>
                <td><a href="/play/6330">外婆</a></td>
                <td>周杰伦</td>
              </tr>
            </table>
          ''');
        }
        if (uri.path == '/play/6330') {
          return _html(uri, '''
            <script>
              window.play_id = '6330';
              window.mp3_title = '外婆';
              window.mp3_author = '周杰伦';
              window.mp3_cover = 'https://img.gequhai.test/cover.jpg';
            </script>
            <div id="content-lrc2">[00:01.00]外婆</div>
          ''');
        }
        fail('Unexpected GET $uri');
      },
      onPostForm: (uri, form, _) async {
        expect(uri.toString(), 'https://www.gequhai.com/api/music');
        expect(form, {'id': '6330', 'type': '0'});
        return _json(uri, {
          'code': 200,
          'data': {'url': audioUrl},
        });
      },
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        headers: const {'content-type': 'text/html', 'content-length': '128'},
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('外婆', MusicDataSource.gequhai);

    expect(candidates, isEmpty);
  });

  test(
    'gequhai api returns validated direct audio with lyrics and cover',
    () async {
      const audioUrl = 'https://cdn.gequhai.test/audio/6330.mp3';
      late Map<String, String> apiHeaders;
      late Map<String, String> headHeaders;
      late Map<String, String> rangeHeaders;
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.path.startsWith('/s/')) {
            return _html(uri, '''
              <table>
                <tr>
                  <td><a href="/play/6330">外婆</a></td>
                  <td>周杰伦</td>
                </tr>
              </table>
            ''');
          }
          if (uri.path == '/play/6330') {
            return _response(
              uri,
              HttpStatus.ok,
              body: '''
                <script>
                window.play_id = '6330';
                window.mp3_title = '外婆';
                window.mp3_author = '周杰伦';
                window.mp3_cover = 'https://img.gequhai.test/cover.jpg';
                  window.mp3_extra_url = 'a#R0c#M6Ly9wYW4ucXVhcmsuY24vcy9iYXNlNjQ=';
                </script>
                <div id="content-lrc2">[00:01.00]外婆\n[00:02.00]周杰伦</div>
              ''',
              headers: const {'content-type': 'text/html; charset=utf-8'},
              cookies: [Cookie('PHPSESSID', 'abc')],
            );
          }
          fail('Unexpected GET $uri');
        },
        onPostForm: (uri, form, headers) async {
          apiHeaders = headers;
          expect(uri.toString(), 'https://www.gequhai.com/api/music');
          expect(form, {'id': '6330', 'type': '0'});
          return _json(uri, {
            'code': 200,
            'data': {'url': audioUrl},
          });
        },
        onHead: (uri, headers) async {
          headHeaders = headers;
          expect(uri.toString(), audioUrl);
          return _response(
            uri,
            HttpStatus.ok,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '3913543',
            },
          );
        },
        onRange: (uri, start, end, headers) async {
          rangeHeaders = headers;
          expect(uri.toString(), audioUrl);
          expect(start, 0);
          expect(end, 8191);
          return _response(
            uri,
            HttpStatus.partialContent,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-range': 'bytes 0-8191/3913543',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search('外婆', MusicDataSource.gequhai);

      expect(candidates, hasLength(1));
      expect(apiHeaders['cookie'], contains('PHPSESSID=abc'));
      expect(apiHeaders['x-requested-with'], 'Http');
      expect(apiHeaders['x-custom-header'], 'Key');
      expect(headHeaders.containsKey('referer'), isFalse);
      expect(rangeHeaders.containsKey('referer'), isFalse);
      expect(candidates.single.name, '外婆');
      expect(candidates.single.artist, '周杰伦');
      expect(candidates.single.coverUrl, 'https://img.gequhai.test/cover.jpg');
      expect(candidates.single.raw['clientReady'], isTrue);
      expect(candidates.single.raw['lyricsLines'], 2);
      expect(candidates.single.raw['mediaValidation'], contains('Range 206'));

      final resolved = await resolver.resolve(candidates.single);
      expect(
        resolved.sourceAttempts.first.mediaUrlType,
        MediaUrlType.externalPan,
      );
      expect(
        resolved.sourceAttempts.first.mediaUrl,
        'https://pan.quark.cn/s/base64',
      );
    },
  );

  test('gequhai validates the four product sample full audio matrix', () async {
    const samples = [
      _GequhaiSample('外婆', '周杰伦', '6330', 3913543, 83),
      _GequhaiSample('一丝不挂', '陈奕迅', '434800', 3877617, 52),
      _GequhaiSample('稻香', '周杰伦', '333', 3576668, 48),
      _GequhaiSample('哎呀', '王蓉', '38173', 3468831, 87),
    ];
    final byTitle = {for (final sample in samples) sample.title: sample};
    final byId = {for (final sample in samples) sample.id: sample};
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          final query = uri.pathSegments.last.replaceFirst(
            RegExp(r'\.html$'),
            '',
          );
          final sample = byTitle[query];
          if (sample == null) {
            return _html(uri, '<table></table>');
          }
          return _html(uri, '''
            <table>
              <tr>
                <td><a href="/play/${sample.id}">${sample.title}</a></td>
                <td>${sample.artist}</td>
              </tr>
            </table>
          ''');
        }
        if (uri.path.startsWith('/play/')) {
          final sample = byId[uri.pathSegments.last]!;
          return _html(uri, '''
            <script>
              window.play_id = '${sample.id}';
              window.mp3_title = '${sample.title}';
              window.mp3_author = '${sample.artist}';
              window.mp3_cover = 'https://img.gequhai.test/${sample.id}.jpg';
            </script>
            <div id="content-lrc2">${_lyricsLines(sample.lyricsLines, sample.title)}</div>
          ''');
        }
        fail('Unexpected GET $uri');
      },
      onPostForm: (uri, form, _) async => _json(uri, {
        'code': 200,
        'data': {'url': 'https://cdn.gequhai.test/audio/${form['id']}.mp3'},
      }),
      onHead: (uri, _) async {
        final id = uri.pathSegments.last.split('.').first;
        final sample = byId[id]!;
        return _response(
          uri,
          HttpStatus.ok,
          headers: {
            'content-type': 'audio/mpeg',
            'content-length': '${sample.length}',
          },
        );
      },
      onRange: (uri, _, _, _) async {
        final id = uri.pathSegments.last.split('.').first;
        final sample = byId[id]!;
        return _response(
          uri,
          HttpStatus.partialContent,
          headers: {
            'content-type': 'audio/mpeg',
            'content-range': 'bytes 0-8191/${sample.length}',
          },
        );
      },
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    for (final sample in samples) {
      final candidates = await resolver.search(
        sample.title,
        MusicDataSource.gequhai,
      );
      expect(candidates, hasLength(1), reason: sample.title);
      expect(candidates.single.name, sample.title);
      expect(candidates.single.artist, sample.artist);
      expect(candidates.single.id, sample.id);
      expect(candidates.single.raw['clientReady'], isTrue);
      expect(
        candidates.single.raw['urlType'],
        MediaUrlType.directAudio.storageValue,
      );
      expect(candidates.single.raw['lyricsLines'], sample.lyricsLines);
      expect(candidates.single.raw['mediaContentLength'], sample.length);
    }
  });

  test('gequhai hides candidates when detail title or artist drifts', () async {
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          return _html(uri, '''
            <table>
              <tr><td><a href="/play/6330">外婆</a></td><td>周杰伦</td></tr>
            </table>
          ''');
        }
        if (uri.path == '/play/6330') {
          return _html(uri, '''
            <script>
              window.play_id = '6330';
              window.mp3_title = '外婆';
              window.mp3_author = '赵雷';
            </script>
            <div id="content-lrc2">[00:01.00]外婆</div>
          ''');
        }
        fail('Unexpected GET $uri');
      },
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('外婆', MusicDataSource.gequhai);

    expect(candidates, isEmpty);
  });

  test('gequhai search parser excludes wrong artist rows', () async {
    const audioUrl = 'https://cdn.gequhai.test/audio/6330.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.path.startsWith('/s/')) {
          return _html(uri, '''
            <table>
              <tr>
                <td><a href="/play/6330">外婆</a></td>
                <td>周杰伦</td>
              </tr>
              <tr>
                <td><a href="/play/9999">外婆</a></td>
                <td>赵雷</td>
              </tr>
            </table>
          ''');
        }
        if (uri.path == '/play/6330') {
          return _html(uri, '''
            <script>
              window.play_id = '6330';
              window.mp3_title = '外婆';
              window.mp3_author = '周杰伦';
            </script>
            <div id="content-lrc2">[00:01.00]外婆</div>
          ''');
        }
        fail('Unexpected GET $uri');
      },
      onPostForm: (uri, form, _) async {
        expect(form, {'id': '6330', 'type': '0'});
        return _json(uri, {
          'code': 200,
          'data': {'url': audioUrl},
        });
      },
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-length': '3913543',
        },
      ),
      onRange: (uri, _, _, _) async => _response(
        uri,
        HttpStatus.partialContent,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-range': 'bytes 0-8191/3913543',
        },
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    final candidates = await resolver.search('外婆', MusicDataSource.gequhai);

    expect(candidates, hasLength(1));
    expect(candidates.single.artist, '周杰伦');
  });

  test(
    'gequhai player audio resolves page api and validated CDN media',
    () async {
      const audioUrl = 'https://cdn.gequhai.test/audio/38173.mp3';
      final calls = <String>[];
      late Map<String, String> apiHeaders;
      late Map<String, String> headHeaders;
      late Map<String, String> rangeHeaders;
      final http = _FakeResolverHttp(
        onGet: (uri, headers) async {
          calls.add('GET ${uri.path}');
          expect(uri.toString(), 'https://www.gequhai.com/play/38173');
          return _response(
            uri,
            HttpStatus.ok,
            body: '''
            <script>
              window.play_id = '38173';
              window.mp3_title = '哎呀';
              window.mp3_author = '王蓉';
              window.mp3_cover = 'https://img2.kuwo.cn/star/albumcover/120/cover.jpg';
            </script>
            <div id="content-lrc2">[00:01.00]哎呀\n[00:02.00]王蓉</div>
            <a href="https://pan.quark.cn/s/ignore">夸克网盘</a>
          ''',
            headers: const {'content-type': 'text/html; charset=utf-8'},
            cookies: [Cookie('PHPSESSID', 'abc')],
          );
        },
        onPostForm: (uri, form, headers) async {
          calls.add('POST ${uri.path}');
          apiHeaders = headers;
          expect(uri.toString(), 'https://www.gequhai.com/api/music');
          expect(form, {'id': '38173', 'type': '0'});
          return _json(uri, {
            'code': 200,
            'data': {'url': audioUrl},
          });
        },
        onHead: (uri, headers) async {
          calls.add('HEAD ${uri.host}');
          headHeaders = headers;
          expect(uri.toString(), audioUrl);
          return _response(
            uri,
            HttpStatus.ok,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '3468831',
            },
          );
        },
        onRange: (uri, start, end, headers) async {
          calls.add('RANGE $start-$end');
          rangeHeaders = headers;
          expect(uri.toString(), audioUrl);
          expect(start, 0);
          expect(end, 8191);
          return _response(
            uri,
            HttpStatus.partialContent,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-range': 'bytes 0-8191/3468831',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final resolved = await resolver.resolve(_gequhaiCandidate());

      expect(calls, [
        'GET /play/38173',
        'POST /api/music',
        'HEAD cdn.gequhai.test',
        'RANGE 0-8191',
      ]);
      expect(apiHeaders['referer'], 'https://www.gequhai.com/play/38173');
      expect(apiHeaders['cookie'], contains('PHPSESSID=abc'));
      expect(apiHeaders['x-requested-with'], 'Http');
      expect(apiHeaders['x-custom-header'], 'Key');
      expect(headHeaders.containsKey('referer'), isFalse);
      expect(rangeHeaders.containsKey('referer'), isFalse);
      expect(resolved.source, MusicDataSource.gequhai);
      expect(resolved.name, '哎呀');
      expect(resolved.artist, '王蓉');
      expect(resolved.url, audioUrl);
      expect(resolved.urlType, MediaUrlType.directAudio);
      expect(resolved.canCacheAudio, isTrue);
      expect(resolved.lyrics?.lines, 2);
      expect(resolved.coverUrl, contains('albumcover'));
      expect(resolved.sourceAttempts.map((attempt) => attempt.stage), [
        'page',
        'api',
        'media_validation',
      ]);
      expect(
        resolved.sourceAttempts.last.reasonCode,
        'direct_full_audio_ready',
      );
      expect(resolved.sourceAttempts.last.mediaContentLength, 3468831);
      expect(resolved.sourceAttempts.last.clientReady, isTrue);
    },
  );

  test(
    'gequhai retry carries merged page cookies to api but not CDN media',
    () async {
      const audioUrl = 'https://cdn.gequhai.test/audio/38173.mp3';
      var getCount = 0;
      late Map<String, String> retryHeaders;
      late Map<String, String> apiHeaders;
      late Map<String, String> headHeaders;
      late Map<String, String> rangeHeaders;
      final http = _FakeResolverHttp(
        onGet: (uri, headers) async {
          getCount += 1;
          if (getCount == 1) {
            return _response(
              uri,
              HttpStatus.forbidden,
              body: '<html>安全验证</html>',
              headers: const {'content-type': 'text/html'},
              cookies: [Cookie('guard', 'a')],
            );
          }
          retryHeaders = headers;
          expect(headers['cookie'], contains('guard=a'));
          return _response(
            uri,
            HttpStatus.ok,
            body: '''
              <script>
                window.play_id = '38173';
                window.mp3_title = '哎呀';
                window.mp3_author = '王蓉';
                window.mp3_cover = 'https://img2.kuwo.cn/star/albumcover/120/cover.jpg';
                window.mp3_extra_url = 'https%3A%2F%2Fpan.quark.cn%2Fs%2Fencoded';
              </script>
              <div id="content-lrc2">[00:01.00]哎呀</div>
            ''',
            headers: const {'content-type': 'text/html; charset=utf-8'},
            cookies: [Cookie('session', 'b')],
          );
        },
        onPostForm: (uri, form, headers) async {
          apiHeaders = headers;
          expect(form, {'id': '38173', 'type': '0'});
          return _json(uri, {
            'code': 200,
            'data': {'url': audioUrl},
          });
        },
        onHead: (uri, headers) async {
          headHeaders = headers;
          return _response(
            uri,
            HttpStatus.ok,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '3468831',
            },
          );
        },
        onRange: (uri, start, end, headers) async {
          rangeHeaders = headers;
          return _response(
            uri,
            HttpStatus.partialContent,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-range': 'bytes 0-8191/3468831',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final resolved = await resolver.resolve(_gequhaiCandidate());

      expect(getCount, 2);
      expect(retryHeaders['cookie'], contains('guard=a'));
      expect(apiHeaders['cookie'], contains('guard=a'));
      expect(apiHeaders['cookie'], contains('session=b'));
      expect(apiHeaders['referer'], 'https://www.gequhai.com/play/38173');
      expect(headHeaders.containsKey('referer'), isFalse);
      expect(rangeHeaders.containsKey('referer'), isFalse);
      expect(resolved.source, MusicDataSource.gequhai);
      expect(resolved.urlType, MediaUrlType.directAudio);
      expect(resolved.canCacheAudio, isTrue);
    },
  );

  test('gequhai player audio fails closed for invalid range total', () async {
    const audioUrl = 'https://cdn.gequhai.test/audio/38173.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        body: '''
          <script>
            window.play_id = '38173';
            window.mp3_title = '哎呀';
            window.mp3_author = '王蓉';
          </script>
          <div id="content-lrc2">[00:01.00]哎呀</div>
        ''',
        headers: const {'content-type': 'text/html'},
      ),
      onPostForm: (uri, _, _) async => _json(uri, {
        'code': 200,
        'data': {'url': audioUrl},
      }),
      onHead: (uri, _) async => _response(
        uri,
        HttpStatus.ok,
        headers: const {'content-type': 'audio/mpeg'},
      ),
      onRange: (uri, _, _, _) async => _response(
        uri,
        HttpStatus.partialContent,
        headers: const {
          'content-type': 'audio/mpeg',
          'content-range': 'bytes 0-8191/*',
        },
      ),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    await expectLater(
      resolver.resolve(_gequhaiCandidate()),
      throwsA(
        isA<SourceDownloadException>()
            .having(
              (error) => error.failureCode,
              'failureCode',
              'range_not_supported',
            )
            .having(
              (error) => error.sourceAttempts.last.clientReady,
              'clientReady',
              isFalse,
            ),
      ),
    );
  });

  test('auto combined errors only report gequhai mainline failures', () async {
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        throw HttpException('GET failed ${uri.host}', uri: uri);
      },
      onPostForm: (uri, _, _) async {
        throw HttpException('POST failed ${uri.host}', uri: uri);
      },
    );
    final resolver = RemoteMusicResolver(
      httpClient: http,
      initialFlacCookie: 'sl-session=test',
      platforms: const ['kuwo'],
    );

    await expectLater(
      resolver.search('全部失败', MusicDataSource.auto),
      throwsA(
        isA<StateError>()
            .having(
              (error) => error.message,
              'message',
              contains('GET failed www.gequhai.com'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('buguyy failed:')),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('flac failed:')),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('kuwo full audio failed:')),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('itunes preview failed:')),
            ),
      ),
    );
  });

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

  test(
    'kuwo full audio provider resolves exact scoped songs with HEAD and Range gate',
    () async {
      const audioUrl = 'https://kuwo.example.test/daoxiang.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'search.kuwo.cn') {
            expect(uri.queryParameters['all'], '稻香');
            return _json(uri, {
              'abslist': [
                {
                  'name': '稻香',
                  'artist': '周杰伦',
                  'album': '魔杰座',
                  'duration': '187',
                  'musicRid': 'MUSIC_351583919',
                  'formats': 'MP3128',
                  'minfo': 'level:h,bitrate:128,format:mp3,size:2.86Mb',
                  'online': '1',
                  'pay': '0',
                  'copyright': '0',
                },
              ],
            });
          }
          if (uri.host == 'antiserver.kuwo.cn') {
            expect(uri.queryParameters['type'], 'convert_url3');
            expect(uri.queryParameters['rid'], 'MUSIC_351583919');
            return _json(uri, {'url': audioUrl});
          }
          fail('Unexpected GET $uri');
        },
        onHead: (uri, _) async {
          expect(uri.toString(), audioUrl);
          return _response(
            uri,
            HttpStatus.ok,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '2860000',
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
            body: 'x',
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '1',
              'content-range': 'bytes 0-0/2860000',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search(
        '周杰伦 稻香',
        MusicDataSource.kuwoFullAudio,
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.source, MusicDataSource.kuwoFullAudio);
      expect(candidates.single.name, '稻香');
      expect(candidates.single.artist, '周杰伦');

      final resolved = await resolver.resolve(candidates.single);
      expect(resolved.source, MusicDataSource.kuwoFullAudio);
      expect(resolved.url, audioUrl);
      expect(resolved.urlType, MediaUrlType.directAudio);
      expect(resolved.canCacheAudio, isTrue);
      expect(resolved.sourceAttempts.single.reasonCode, 'direct_audio_ready');
      expect(resolved.sourceAttempts.single.clientReady, isTrue);
      expect(
        resolved.sourceAttempts.single.mediaValidation,
        contains('Range 206 bytes 0-0/2860000'),
      );
    },
  );

  test(
    'kuwo full audio provider accepts missing HEAD length only with positive Range total',
    () async {
      const audioUrl = 'https://kuwo.example.test/yisibugua.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'antiserver.kuwo.cn') {
            return _json(uri, {'url': audioUrl});
          }
          fail('Unexpected GET $uri');
        },
        onHead: (uri, _) async => _response(
          uri,
          HttpStatus.ok,
          headers: const {'content-type': 'audio/mpeg'},
        ),
        onRange: (uri, start, end, _) async {
          expect((start, end), (0, 0));
          return _response(
            uri,
            HttpStatus.partialContent,
            body: 'x',
            headers: const {
              'content-type': 'audio/mpeg',
              'content-range': 'bytes 0-0/3078864',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final resolved = await resolver.resolve(_kuwoFullAudioCandidate());

      expect(resolved.canCacheAudio, isTrue);
      expect(resolved.sourceAttempts.single.clientReady, isTrue);
      expect(resolved.sourceAttempts.single.mediaContentLength, 3078864);
      expect(
        resolved.sourceAttempts.single.mediaValidation,
        contains('HEAD 200 audio/mpeg length=3078864'),
      );
    },
  );

  for (final scenario in const [
    ('missing HEAD length and unknown Range total', 'bytes 0-0/*'),
    ('missing HEAD length and non numeric Range total', 'bytes 0-0/unknown'),
    ('missing HEAD length and zero Range total', 'bytes 0-0/0'),
  ]) {
    test('kuwo full audio provider fails closed on ${scenario.$1}', () async {
      const audioUrl = 'https://kuwo.example.test/yisibugua.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'antiserver.kuwo.cn') {
            return _json(uri, {'url': audioUrl});
          }
          fail('Unexpected GET $uri');
        },
        onHead: (uri, _) async => _response(
          uri,
          HttpStatus.ok,
          headers: const {'content-type': 'audio/mpeg'},
        ),
        onRange: (uri, start, end, _) async => _response(
          uri,
          HttpStatus.partialContent,
          body: 'x',
          headers: {'content-type': 'audio/mpeg', 'content-range': scenario.$2},
        ),
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      await expectLater(
        resolver.resolve(_kuwoFullAudioCandidate()),
        throwsA(
          isA<SourceDownloadException>()
              .having(
                (error) => error.failureCode,
                'failureCode',
                'audio_validation_failed',
              )
              .having(
                (error) => error.sourceAttempts.single.clientReady,
                'clientReady',
                isFalse,
              )
              .having(
                (error) => error.sourceAttempts.single.mediaValidation,
                'mediaValidation',
                contains(scenario.$2),
              ),
        ),
      );
    });
  }

  for (final scenario in const [
    ('non numeric HEAD content length', 'unknown'),
    ('zero HEAD content length', '0'),
  ]) {
    test('kuwo full audio provider fails closed on ${scenario.$1}', () async {
      const audioUrl = 'https://kuwo.example.test/yisibugua.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'antiserver.kuwo.cn') {
            return _json(uri, {'url': audioUrl});
          }
          fail('Unexpected GET $uri');
        },
        onHead: (uri, _) async => _response(
          uri,
          HttpStatus.ok,
          headers: {
            'content-type': 'audio/mpeg',
            'content-length': scenario.$2,
          },
        ),
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      await expectLater(
        resolver.resolve(_kuwoFullAudioCandidate()),
        throwsA(
          isA<SourceDownloadException>()
              .having(
                (error) => error.failureCode,
                'failureCode',
                'audio_validation_failed',
              )
              .having(
                (error) => error.sourceAttempts.single.clientReady,
                'clientReady',
                isFalse,
              )
              .having(
                (error) => error.sourceAttempts.single.mediaValidation,
                'mediaValidation',
                contains('HEAD invalid content-length'),
              ),
        ),
      );
    });
  }

  test(
    'kuwo full audio provider filters songs outside the two-song PoC scope',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'search.kuwo.cn') {
            return _json(uri, {
              'abslist': [
                {
                  'name': '浮夸',
                  'artist': '陈奕迅',
                  'album': 'U87',
                  'duration': '286',
                  'musicRid': 'MUSIC_123',
                  'formats': 'MP3128',
                  'minfo': 'level:h,bitrate:128,format:mp3,size:4.3Mb',
                  'online': '1',
                  'pay': '0',
                  'copyright': '0',
                },
              ],
            });
          }
          fail('Unexpected GET $uri');
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search(
        '浮夸',
        MusicDataSource.kuwoFullAudio,
      );

      expect(candidates, isEmpty);
    },
  );

  test(
    'kuwo full audio provider parses legacy single-quoted abslist',
    () async {
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'search.kuwo.cn') {
            return _response(
              uri,
              HttpStatus.ok,
              body:
                  "{'TOTAL':'1','abslist':[{'ALBUM':'U87','ARTIST':'陈奕迅',"
                  "'COPYRIGHT':'0','DURATION':'192','FORMATS':'MP3128',"
                  "'MINFO':'level:h,bitrate:128,format:mp3,size:2.93Mb',"
                  "'MUSICRID':'MUSIC_475511188','NAME':'一丝不挂',"
                  "'ONLINE':'1','PAY':'0'}],'PN':'0'}",
              headers: const {'content-type': 'text/plain; charset=utf-8'},
            );
          }
          fail('Unexpected GET $uri');
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search(
        '陈奕迅 一丝不挂',
        MusicDataSource.kuwoFullAudio,
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.id, 'MUSIC_475511188');
      expect(candidates.single.name, '一丝不挂');
      expect(candidates.single.artist, '陈奕迅');
    },
  );

  test(
    'kuwo full audio provider seeds exact scoped musicrid when live search drifts',
    () async {
      const audioUrl = 'https://kuwo.example.test/yisibugua.mp3';
      final http = _FakeResolverHttp(
        onGet: (uri, _) async {
          if (uri.host == 'search.kuwo.cn') {
            expect(uri.queryParameters['all'], '一丝不挂');
            return _json(uri, {
              'abslist': [
                {
                  'name': '一丝不挂',
                  'artist': '岁月无痕',
                  'album': '',
                  'duration': '180',
                  'musicRid': 'MUSIC_WRONG',
                  'formats': 'MP3128',
                  'minfo': 'level:h,bitrate:128,format:mp3,size:2.93Mb',
                  'online': '1',
                  'pay': '0',
                  'copyright': '0',
                },
              ],
            });
          }
          if (uri.host == 'antiserver.kuwo.cn') {
            expect(uri.queryParameters['rid'], 'MUSIC_475511188');
            return _json(uri, {'url': audioUrl});
          }
          fail('Unexpected GET $uri');
        },
        onHead: (uri, _) async {
          expect(uri.toString(), audioUrl);
          return _response(
            uri,
            HttpStatus.ok,
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '3078864',
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
            body: 'x',
            headers: const {
              'content-type': 'audio/mpeg',
              'content-length': '1',
              'content-range': 'bytes 0-0/3078864',
            },
          );
        },
      );
      final resolver = RemoteMusicResolver(httpClient: http);

      final candidates = await resolver.search(
        '一丝不挂',
        MusicDataSource.kuwoFullAudio,
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.id, 'MUSIC_475511188');
      expect(candidates.single.name, '一丝不挂');
      expect(candidates.single.artist, '陈奕迅');
      expect(candidates.single.raw['seed'], 'scoped_musicrid');

      final resolved = await resolver.resolve(candidates.single);
      expect(resolved.url, audioUrl);
      expect(resolved.urlType, MediaUrlType.directAudio);
      expect(resolved.canCacheAudio, isTrue);
      expect(resolved.sourceAttempts.single.clientReady, isTrue);
      expect(
        resolved.sourceAttempts.single.mediaValidation,
        contains('Range 206 bytes 0-0/3078864'),
      );
    },
  );

  test('kuwo full audio provider fails closed on browser-only media', () async {
    const audioUrl = 'https://kuwo.example.test/blocked.mp3';
    final http = _FakeResolverHttp(
      onGet: (uri, _) async {
        if (uri.host == 'antiserver.kuwo.cn') {
          return _json(uri, {'url': audioUrl});
        }
        fail('Unexpected GET $uri');
      },
      onHead: (uri, _) async => _response(uri, HttpStatus.gone),
      onRange: (uri, start, end, _) async => _response(uri, HttpStatus.gone),
    );
    final resolver = RemoteMusicResolver(httpClient: http);

    await expectLater(
      resolver.resolve(
        MusicSearchCandidate(
          query: '一丝不挂',
          source: MusicDataSource.kuwoFullAudio,
          platform: 'kuwo',
          keyword: '一丝不挂',
          page: 0,
          id: 'MUSIC_475511188',
          name: '一丝不挂',
          artist: '陈奕迅',
          album: '',
          duration: 192,
          link: 'MUSIC_475511188',
          coverUrl: '',
          qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
          score: 300,
          raw: const {},
        ),
      ),
      throwsA(
        isA<SourceDownloadException>()
            .having((error) => error.failureCode, 'failureCode', 'browser_only')
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
  List<Cookie> cookies = const [],
}) {
  return ResolverHttpResponse(
    statusCode: statusCode,
    body: body,
    finalUrl: uri,
    headers: headers,
    cookies: cookies,
  );
}

class _GequhaiSample {
  const _GequhaiSample(
    this.title,
    this.artist,
    this.id,
    this.length,
    this.lyricsLines,
  );

  final String title;
  final String artist;
  final String id;
  final int length;
  final int lyricsLines;
}

String _lyricsLines(int count, String word) {
  return [
    for (var i = 0; i < count; i += 1)
      '[00:${(i % 60).toString().padLeft(2, '0')}.00]$word $i',
  ].join('\n');
}

MusicSearchCandidate _gequhaiCandidate({
  String id = '38173',
  String name = '哎呀',
  String artist = '王蓉',
}) {
  return MusicSearchCandidate(
    query: name,
    source: MusicDataSource.gequhai,
    platform: 'gequhai',
    keyword: name,
    page: 0,
    id: id,
    name: name,
    artist: artist,
    album: '',
    duration: 0,
    link: 'https://www.gequhai.com/play/$id',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3', bitrate: 'validated')],
    score: 240,
    raw: const {},
  );
}

MusicSearchCandidate _kuwoFullAudioCandidate() {
  return MusicSearchCandidate(
    query: '一丝不挂',
    source: MusicDataSource.kuwoFullAudio,
    platform: 'kuwo',
    keyword: '一丝不挂',
    page: 0,
    id: 'MUSIC_475511188',
    name: '一丝不挂',
    artist: '陈奕迅',
    album: '',
    duration: 192,
    link: 'MUSIC_475511188',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
    score: 300,
    raw: const {},
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
