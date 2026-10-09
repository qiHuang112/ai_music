import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'auto failures are shared by search, progressive and playlist lookup',
    () async {
      var buguyyCalls = 0;
      var buguyyOnline = false;
      final resolver = RemoteMusicResolver(
        pages: 1,
        platforms: const ['kuwo'],
        initialFlacCookie: 'sl-session=test',
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            buguyyCalls++;
            if (!buguyyOnline) throw const HttpException('HTTP 503');
            if (uri.path == '/api/geturl') {
              return _json(uri, {
                'success': true,
                'url': 'https://audio.example/song.mp3',
              });
            }
            return _json(uri, {
              'data': [
                {'id': 'buguyy-1', 'title': '梧桐灯', 'singer': '许嵩'},
              ],
            });
          },
          onPostForm: (uri, _, _) async => _json(uri, {
            'data': {
              'list': [
                {'id': 'flac-1', 'name': '梧桐灯', 'artist': '许嵩'},
              ],
            },
          }),
        ),
      );

      expect(
        (await resolver.search('梧桐灯', MusicDataSource.auto)).single.source,
        MusicDataSource.flac,
      );
      final progress = await resolver
          .searchProgressively('梧桐灯', MusicDataSource.auto)
          .toList();
      expect(progress.last.isComplete, isTrue);
      expect(progress.last.error, isNull);
      await expectLater(
        resolver.searchScreenshotPrimary('梧桐灯'),
        throwsA(isA<HttpException>()),
      );
      expect(buguyyCalls, 3);
      expect(resolver.availableAutoSources, [MusicDataSource.flac]);

      expect(await resolver.searchScreenshotPrimary('梧桐灯'), isEmpty);
      expect(
        (await resolver.searchScreenshot('梧桐灯', '许嵩')).single.source,
        MusicDataSource.flac,
      );
      final laterProgress = await resolver
          .searchProgressively('梧桐灯', MusicDataSource.auto)
          .toList();
      expect(laterProgress, hasLength(1));
      await expectLater(
        resolver.resolveForSourceMode(
          _encryptedBuguyyCandidate(),
          MusicDataSource.auto,
        ),
        throwsA(isA<AutoSourceUnavailableException>()),
      );
      expect(buguyyCalls, 3);

      // The user's explicit choice remains usable, but does not silently reopen auto.
      buguyyOnline = true;
      expect(
        (await resolver.search('梧桐灯', MusicDataSource.buguyy)).single.source,
        MusicDataSource.buguyy,
      );
      expect(
        (await resolver.resolveForSourceMode(
          _encryptedBuguyyCandidate(),
          MusicDataSource.buguyy,
        )).url,
        endsWith('song.mp3'),
      );
      expect(buguyyCalls, 5);
      await resolver.search('梧桐灯', MusicDataSource.auto);
      expect(buguyyCalls, 5);
      expect(
        resolver.isSourceAvailableForAuto(MusicDataSource.buguyy),
        isFalse,
      );
    },
  );

  test(
    'auto counts a retried resolver operation once, not each HTTP attempt',
    () async {
      var attempts = 0;
      final resolver = RemoteMusicResolver(
        initialFlacCookie: 'sl-session=test',
        pages: 1,
        platforms: const ['kuwo'],
        httpClient: _FakeResolverHttp(
          onGet: (_, _) async {
            attempts++;
            if (attempts > 3) throw const HttpException('HTTP 503');
            throw const SocketException('connection reset');
          },
          onPostForm: (uri, _, _) async => _json(uri, {
            'data': {'list': const []},
          }),
        ),
      );
      await expectLater(
        resolver.search('song', MusicDataSource.auto),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 3);
      expect(resolver.isSourceAvailableForAuto(MusicDataSource.buguyy), isTrue);
      await expectLater(
        resolver.search('song', MusicDataSource.auto),
        throwsA(isA<StateError>()),
      );
      expect(resolver.isSourceAvailableForAuto(MusicDataSource.buguyy), isTrue);
      await expectLater(
        resolver.search('song', MusicDataSource.auto),
        throwsA(isA<StateError>()),
      );
      expect(
        resolver.isSourceAvailableForAuto(MusicDataSource.buguyy),
        isFalse,
      );
    },
  );

  test(
    'successful empty search resets failures and is never a source outage',
    () async {
      var offline = true;
      final resolver = RemoteMusicResolver(
        pages: 1,
        platforms: const ['kuwo'],
        initialFlacCookie: 'sl-session=test',
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            if (offline) throw const HttpException('HTTP 503');
            return _json(uri, {'data': const []});
          },
          onPostForm: (uri, _, _) async => _json(uri, {
            'data': {'list': const []},
          }),
        ),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          resolver.search('song', MusicDataSource.auto),
          throwsA(isA<StateError>()),
        );
      }
      offline = false;
      for (var i = 0; i < 4; i++) {
        expect(await resolver.search('song', MusicDataSource.auto), isEmpty);
      }
      offline = true;
      for (var i = 0; i < 2; i++) {
        await expectLater(
          resolver.search('song', MusicDataSource.auto),
          throwsA(isA<StateError>()),
        );
      }
      expect(resolver.isSourceAvailableForAuto(MusicDataSource.buguyy), isTrue);
    },
  );

  test(
    'resolve failure opens auto circuit and manual resolution still works',
    () async {
      var calls = 0;
      var offline = true;
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            calls++;
            if (offline) throw const HttpException('HTTP 503');
            return _json(uri, {
              'success': true,
              'url': 'https://audio.example/song.mp3',
            });
          },
        ),
      );
      for (var i = 0; i < 3; i++) {
        await expectLater(
          resolver.resolveForSourceMode(
            _encryptedBuguyyCandidate(),
            MusicDataSource.auto,
          ),
          throwsA(isA<HttpException>()),
        );
      }
      expect(calls, 3);
      await expectLater(
        resolver.resolveForSourceMode(
          _encryptedBuguyyCandidate(),
          MusicDataSource.auto,
        ),
        throwsA(isA<AutoSourceUnavailableException>()),
      );
      expect(calls, 3);
      offline = false;
      await resolver.resolve(_encryptedBuguyyCandidate());
      expect(calls, 4);
      expect(
        resolver.isSourceAvailableForAuto(MusicDataSource.buguyy),
        isFalse,
      );
    },
  );

  test(
    'both unavailable sources finish progressive search without more HTTP',
    () async {
      final resolver = RemoteMusicResolver(httpClient: _FakeResolverHttp());
      for (final source in [MusicDataSource.flac, MusicDataSource.buguyy]) {
        for (var i = 0; i < 3; i++) {
          resolver.reportSourceFailure(source, const HttpException('HTTP 503'));
        }
      }
      await expectLater(
        resolver.search('song', MusicDataSource.auto),
        throwsA(isA<StateError>()),
      );
      final progress = await resolver
          .searchProgressively('song', MusicDataSource.auto)
          .toList();
      expect(progress, hasLength(1));
      expect(progress.single.isComplete, isTrue);
      expect(progress.single.error.toString(), contains('两个音源'));
    },
  );

  test('encrypted BuguYY audio uses the sole exact playable result', () async {
    final actions = <String>[];
    final resolver = RemoteMusicResolver(
      initialFlacCookie: 'sl-session=test',
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          expect(uri.path, '/api/geturl');
          return _json(uri, {
            'success': true,
            'name': '梧桐灯',
            'url': 'https://car-er.kuwo.cn/resource/encrypted.mflac',
          });
        },
        onPostForm: (uri, form, _) async {
          actions.add(uri.queryParameters['act']!);
          if (uri.queryParameters['act'] == 'search') {
            expect(form['keyword'], '梧桐灯');
            return _json(uri, {
              'code': 0,
              'data': {
                'list': form['platform'] == 'kuwo'
                    ? [
                        {
                          'id': 'kuwo-1',
                          'name': '梧桐灯',
                          'artist': '许嵩',
                          'album': '不如吃茶去',
                          'time': 'fresh',
                          'sign': 'sig',
                          'minfo': [
                            {'format': 'mp3', 'bitrate': '128', 'size': '4M'},
                          ],
                        },
                      ]
                    : [],
              },
            });
          }
          expect(uri.queryParameters['act'], 'getUrl');
          expect(form['songid'], 'kuwo-1');
          return _json(uri, {
            'code': 0,
            'data': {'url': 'https://cdn.example.test/playable.mp3'},
          });
        },
      ),
    );

    final result = await resolver.resolve(_encryptedBuguyyCandidate());
    expect(result.url, 'https://cdn.example.test/playable.mp3');
    expect(result.source, MusicDataSource.buguyy);
    expect(result.id, 'buguyy-1');
    expect(result.quality.format, 'mp3');
    expect(result.panLink, isFalse);
    expect(actions, ['search', 'search', 'getUrl']);
  });

  test('encrypted BuguYY audio never chooses an ambiguous recording', () async {
    final resolver = RemoteMusicResolver(
      initialFlacCookie: 'sl-session=test',
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async => _json(uri, {
          'success': true,
          'url': 'https://car-er.kuwo.cn/resource/encrypted.mflac',
        }),
        onPostForm: (uri, form, _) async {
          expect(uri.queryParameters['act'], 'search');
          return _json(uri, {
            'code': 0,
            'data': {
              'list': form['platform'] == 'kuwo'
                  ? [
                      for (final id in ['version-1', 'version-2'])
                        {'id': id, 'name': '梧桐灯', 'artist': '许嵩'},
                    ]
                  : [],
            },
          });
        },
      ),
    );

    await expectLater(
      resolver.resolve(_encryptedBuguyyCandidate()),
      throwsA(isA<UnsupportedEncryptedAudioException>()),
    );
  });

  test('encrypted audio rejects exact matches across both platforms', () async {
    final searched = <String>[];
    final resolver = RemoteMusicResolver(
      initialFlacCookie: 'sl-session=test',
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async => _json(uri, {
          'success': true,
          'url': 'https://car-er.kuwo.cn/resource/encrypted.mflac',
        }),
        onPostForm: (uri, form, _) async {
          expect(uri.queryParameters['act'], 'search');
          searched.add(form['platform']!);
          return _json(uri, {
            'code': 0,
            'data': {
              'list': [
                {
                  'id': '${form['platform']}-1',
                  'name': '梧桐灯',
                  'artist': '许嵩',
                  'minfo': [
                    {'format': 'mp3', 'bitrate': '128'},
                  ],
                },
              ],
            },
          });
        },
      ),
    );

    await expectLater(
      resolver.resolve(_encryptedBuguyyCandidate()),
      throwsA(isA<UnsupportedEncryptedAudioException>()),
    );
    expect(searched, ['kuwo', 'wyy']);
  });

  test(
    'encrypted audio fallback requests MP3 even when FLAC is listed',
    () async {
      final requestedFormats = <String>[];
      final resolver = RemoteMusicResolver(
        initialFlacCookie: 'sl-session=test',
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async => _json(uri, {
            'success': true,
            'url': 'https://car-er.kuwo.cn/resource/encrypted.mflac',
          }),
          onPostForm: (uri, form, _) async {
            if (uri.queryParameters['act'] == 'search') {
              return _json(uri, {
                'code': 0,
                'data': {
                  'list': form['platform'] == 'kuwo'
                      ? [
                          {
                            'id': 'kuwo-1',
                            'name': '梧桐灯',
                            'artist': '许嵩',
                            'minfo': [
                              {'format': 'flac', 'bitrate': '900'},
                              {'format': 'mp3', 'bitrate': '128'},
                            ],
                          },
                        ]
                      : [],
                },
              });
            }
            requestedFormats.add(form['format']!);
            return _json(uri, {
              'code': 0,
              'data': {'url': 'https://cdn.example.test/playable.mp3'},
            });
          },
        ),
      );

      final result = await resolver.resolve(_encryptedBuguyyCandidate());
      expect(requestedFormats, ['mp3']);
      expect(result.url, 'https://cdn.example.test/playable.mp3');
      expect(result.quality.format, 'mp3');
    },
  );

  test('buguyy endpoint is HTTPS off Apple platforms and HTTP on Apple', () {
    expect(defaultBuguyyBaseUrl(isApplePlatform: false), 'https://buguyy.top');
    expect(defaultBuguyyBaseUrl(isApplePlatform: true), 'http://buguyy.top');
  });

  test(
    'screenshot search returns first nonempty source batch without filling ten choices',
    () async {
      final requests = <Uri>[];
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            requests.add(uri);
            return _json(uri, {
              'data': [
                {'id': 'song-0', 'title': '稻香', 'singer': '周杰伦'},
              ],
            });
          },
        ),
      );

      final found = await resolver.searchScreenshot('稻香', '周杰伦');

      expect(found, hasLength(1));
      expect(requests, hasLength(1));
      expect(requests.single.path, '/api/search');
      expect(requests.single.queryParameters['keyword'], '稻香');
    },
  );

  test(
    'screenshot fallback stops after its first nonempty provider page',
    () async {
      final platforms = <String>[];
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async => _json(uri, {'data': const []}),
          onPostForm: (uri, form, _) async {
            platforms.add(form['platform']!);
            return _json(uri, {
              'data': {
                'list': [
                  {
                    'id': 'flac-1',
                    'name': '稻香',
                    'artist': '别的歌手',
                    'duration': 220,
                    'minfo': [
                      {'format': 'mp3', 'bitrate': '320', 'size': '9M'},
                    ],
                  },
                ],
              },
            });
          },
        ),
        initialFlacCookie: 'sl-session=test',
      );

      final found = await resolver.searchScreenshot('稻香', '周杰伦');

      expect(found, hasLength(1));
      expect(found.single.artist, '别的歌手');
      expect(platforms, ['kuwo']);
    },
  );

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

  test(
    'Buguyy playback quality request keeps its playable direct URL',
    () async {
      final paths = <String>[];
      final resolver = RemoteMusicResolver(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            paths.add(uri.path);
            expect(uri.path, '/api/geturl');
            return _json(uri, {
              'success': true,
              'url': 'https://cdn.example.test/song.mp3',
            });
          },
        ),
      );
      final candidate = _encryptedBuguyyCandidate();
      final result = await resolver.resolveAtQuality(
        candidate,
        MusicQualityLevel.low,
      );
      expect(result.panLink, isFalse);
      expect(result.url, 'https://cdn.example.test/song.mp3');
      expect(paths, ['/api/geturl']);
    },
  );

  test('FLAC source requests the selected bitrate', () async {
    final requested = <String>[];
    final resolver = RemoteMusicResolver(
      initialFlacCookie: 'sl-session=test',
      httpClient: _FakeResolverHttp(
        onPostForm: (uri, form, _) async {
          expect(uri.queryParameters['act'], 'getUrl');
          requested.add('${form['format']}:${form['bitrate']}');
          return _json(uri, {
            'code': 0,
            'data': {'url': 'https://cdn.example.test/song.mp3'},
          });
        },
      ),
    );
    const candidate = MusicSearchCandidate(
      query: 'song',
      source: MusicDataSource.flac,
      platform: 'kuwo',
      keyword: 'song',
      page: 1,
      id: 'song-1',
      name: 'song',
      artist: 'artist',
      album: '',
      duration: 0,
      link: '',
      coverUrl: '',
      qualities: [
        MusicQuality(format: 'flac'),
        MusicQuality(format: 'mp3', bitrate: '320'),
        MusicQuality(format: 'mp3', bitrate: '128'),
      ],
      score: 1,
      raw: {},
    );
    final low = await resolver.resolveAtQuality(
      candidate,
      MusicQualityLevel.low,
    );
    final medium = await resolver.resolveAtQuality(
      candidate,
      MusicQualityLevel.medium,
    );
    final high = await resolver.resolveAtQuality(
      candidate,
      MusicQualityLevel.high,
    );
    expect(requested, ['mp3:128', 'mp3:320', 'flac:']);
    expect(low.quality.bitrate, '128');
    expect(medium.quality.bitrate, '320');
    expect(high.quality.format, 'flac');
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
    'flac refreshes an expired saved candidate once before resolving',
    () async {
      final forms = <Map<String, String>>[];
      var searches = 0;
      final http = _FakeResolverHttp(
        onPostForm: (uri, form, _) async {
          if (uri.queryParameters['act'] == 'search') {
            searches += 1;
            expect(form['platform'], 'kuwo');
            expect(form['keyword'], '偏向(摇滚版)');
            return _json(uri, {
              'data': {
                'list': [
                  {
                    'id': 'song-1',
                    'name': '偏向',
                    'artist': '孟维来',
                    'duration': 210,
                    'time': 'fresh-time',
                    'sign': 'fresh-sign',
                    'minfo': [
                      {'format': 'mp3', 'bitrate': '320'},
                    ],
                  },
                ],
              },
            });
          }
          if (uri.queryParameters['act'] == 'getUrl') {
            forms.add(form);
            return _json(
              uri,
              form['sign'] == 'fresh-sign'
                  ? {
                      'data': {'url': 'https://cdn.example.test/fresh.mp3'},
                    }
                  : {'msg': '请求已过期'},
            );
          }
          fail('Unexpected POST $uri');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
      );

      final resolved = await resolver.resolve(_expiredFlacCandidate());

      expect(resolved.url, 'https://cdn.example.test/fresh.mp3');
      expect(resolved.lyrics, isNull);
      expect(searches, 1);
      expect(forms.map((form) => form['sign']), ['old-sign', 'fresh-sign']);
    },
  );

  test(
    'flac does not substitute a different song for an expired one',
    () async {
      var searches = 0;
      var getUrls = 0;
      final http = _FakeResolverHttp(
        onPostForm: (uri, _, _) async {
          if (uri.queryParameters['act'] == 'search') {
            searches += 1;
            return _json(uri, {
              'data': {
                'list': [
                  {
                    'id': 'different-song',
                    'name': '偏向',
                    'artist': '孟维来',
                    'duration': 210,
                    'time': 'fresh-time',
                    'sign': 'fresh-sign',
                    'minfo': [
                      {'format': 'mp3', 'bitrate': '320'},
                    ],
                  },
                ],
              },
            });
          }
          if (uri.queryParameters['act'] == 'getUrl') {
            getUrls += 1;
            return _json(uri, {'msg': '请求已过期'});
          }
          fail('Unexpected POST $uri');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
      );

      await expectLater(
        resolver.resolve(_expiredFlacCandidate()),
        throwsA(isA<StateError>()),
      );
      expect(searches, 1);
      expect(getUrls, 1);
    },
  );

  test(
    'flac stops after one refresh when fresh credentials also expire',
    () async {
      var searches = 0;
      var getUrls = 0;
      final http = _FakeResolverHttp(
        onPostForm: (uri, _, _) async {
          if (uri.queryParameters['act'] == 'search') {
            searches += 1;
            return _json(uri, {
              'data': {
                'list': [
                  {
                    'id': 'song-1',
                    'name': '偏向',
                    'artist': '孟维来',
                    'duration': 210,
                    'time': 'fresh-time',
                    'sign': 'fresh-sign',
                    'minfo': [
                      {'format': 'mp3', 'bitrate': '320'},
                    ],
                  },
                ],
              },
            });
          }
          if (uri.queryParameters['act'] == 'getUrl') {
            getUrls += 1;
            return _json(uri, {'msg': '请求已过期'});
          }
          fail('Unexpected POST $uri');
        },
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'sl-session=test',
      );

      await expectLater(
        resolver.resolve(_expiredFlacCandidate()),
        throwsA(isA<StateError>()),
      );
      expect(searches, 1);
      expect(getUrls, 2);
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

MusicSearchCandidate _encryptedBuguyyCandidate() => const MusicSearchCandidate(
  query: '梧桐灯',
  source: MusicDataSource.buguyy,
  platform: 'buguyy',
  keyword: '梧桐灯',
  page: 1,
  id: 'buguyy-1',
  name: '梧桐灯',
  artist: '许嵩',
  album: '',
  duration: 0,
  link: '',
  coverUrl: '',
  qualities: [MusicQuality(format: 'mp3')],
  score: 1,
  raw: {},
);

ResolverHttpResponse _json(Uri uri, Object body) {
  return ResolverHttpResponse(
    statusCode: HttpStatus.ok,
    body: jsonEncode(body),
    finalUrl: uri,
  );
}

MusicSearchCandidate _expiredFlacCandidate() => const MusicSearchCandidate(
  query: '偏向(摇滚版)',
  source: MusicDataSource.flac,
  platform: 'kuwo',
  keyword: '偏向(摇滚版)',
  page: 1,
  id: 'song-1',
  name: '偏向',
  artist: '孟维来',
  album: '',
  duration: 210,
  link: '',
  coverUrl: '',
  qualities: [MusicQuality(format: 'mp3', bitrate: '320')],
  score: 0,
  raw: {'time': 'old-time', 'sign': 'old-sign'},
);

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
