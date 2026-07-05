import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metadata repository uses resolved cover url and caches it', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_meta_test_');
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final repository = TrackMetadataRepository(
      cacheStore: cache,
      providers: const [CandidateArtworkProvider()],
    );
    final track = _cachedTrack(
      coverUrl: 'https://cdn.example.test/cover.jpg',
      filePath: '${root.path}${Platform.pathSeparator}song.mp3',
    );

    try {
      final metadata = await repository.load(track);
      expect(
        metadata.artworkUri.toString(),
        'https://cdn.example.test/cover.jpg',
      );
      expect(metadata.lyrics, isEmpty);

      final cached = await cache.read(track.cacheId);
      expect(cached?.artworkUri.toString(), metadata.artworkUri.toString());
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('metadata cache persists lyrics for future providers', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_meta_lyrics_');
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack();
    final metadata = TrackMetadata(
      lyrics: const [LyricLine(time: Duration(seconds: 3), text: '第一句')],
    );

    try {
      await cache.write(track.cacheId, metadata);
      final restored = await cache.read(track.cacheId);
      expect(restored?.lyrics.single.text, '第一句');
      expect(restored?.lyrics.single.time, const Duration(seconds: 3));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('resolved lyrics provider reads lyrics from cached result', () async {
    final provider = const ResolvedLyricsProvider();
    final metadata = await provider.find(
      _cachedTrack(
        lyrics: const ResolvedLyrics(
          source: 'resolver:lrc',
          text: '[00:01.00]解析歌词',
          lines: 1,
          timed: true,
        ),
      ),
    );

    expect(metadata.lyrics.single.text, '解析歌词');
    expect(metadata.source, 'resolver:lrc');
  });

  test('resolved lyrics provider ignores audio urls', () async {
    final provider = const ResolvedLyricsProvider();
    final metadata = await provider.find(
      _cachedTrack(
        lyrics: const ResolvedLyrics(
          source: 'resolver:url',
          text: 'https://cdn.example.test/song.flac?token=abc',
          lines: 1,
          timed: false,
        ),
      ),
    );

    expect(metadata.lyrics, isEmpty);
  });

  test('resolved lyrics provider ignores untimed title text', () async {
    final provider = const ResolvedLyricsProvider();
    final metadata = await provider.find(
      _cachedTrack(
        lyrics: const ResolvedLyrics(
          source: 'resolver:title',
          text: '十年',
          lines: 1,
          timed: false,
        ),
      ),
    );

    expect(metadata.lyrics, isEmpty);
  });

  test('cached lyrics file provider reads sidecar lrc file', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lrc_file_');
    final lrc = File('${root.path}${Platform.pathSeparator}song.lrc');
    await lrc.writeAsString('[00:01.00]旁路歌词\n');
    final provider = const CachedLyricsFileProvider();

    try {
      final metadata = await provider.find(_cachedTrack(lyricsPath: lrc.path));
      expect(metadata.lyrics.single.text, '旁路歌词');
      expect(metadata.source, 'cache:lrc');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('metadata repository writes fetched lyrics to sidecar lrc', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_meta_sidecar_',
    );
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack(
      filePath: '${root.path}${Platform.pathSeparator}song.mp3',
    );
    final repository = TrackMetadataRepository(
      cacheStore: cache,
      providers: const [
        _StaticMetadataProvider(
          TrackMetadata(
            lyrics: [LyricLine(time: Duration(seconds: 1), text: '写入歌词')],
          ),
        ),
      ],
    );

    try {
      final metadata = await repository.load(track);
      final lrc = File(lyricsPathForAudioPath(track.filePath));

      expect(metadata.lyrics.single.text, '写入歌词');
      expect(await lrc.exists(), isTrue);
      expect(await lrc.readAsString(), '[00:01.00]写入歌词\n');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'metadata repository does not refetch lyrics when lyrics are cached',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_meta_skip_');
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      await cache.write(
        track.cacheId,
        const TrackMetadata(
          lyrics: [LyricLine(time: Duration(seconds: 1), text: '已缓存')],
        ),
      );
      final provider = BuguyyLyricsProvider(
        httpClient: _FakeResolverHttp(onGet: (_, _) async => fail('refetched')),
      );
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: [provider],
      );

      try {
        final metadata = await repository.load(track);

        expect(metadata.lyrics.single.text, '已缓存');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'metadata repository keeps lyric misses in memory for 30 minutes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_meta_miss_cache_',
      );
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack(
        filePath: '${root.path}${Platform.pathSeparator}song.mp3',
      );
      var now = DateTime(2026, 1, 1, 12);
      var calls = 0;
      final provider = BuguyyLyricsProvider(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            calls += 1;
            return _json(uri, {'lyric': ''});
          },
        ),
      );
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: [provider],
        now: () => now,
      );

      try {
        expect((await repository.load(track)).lyrics, isEmpty);
        expect(calls, 2);

        expect((await repository.load(track)).lyrics, isEmpty);
        expect(calls, 2);

        now = now.add(const Duration(minutes: 31));
        expect((await repository.load(track)).lyrics, isEmpty);
        expect(calls, 4);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'metadata repository keeps artwork and lyric misses independently',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_meta_field_miss_',
      );
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      var now = DateTime(2026, 1, 1, 12);
      final artworkProvider = _CountingArtworkProvider();
      final lyricsProvider = _CountingLyricsProvider();
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: [artworkProvider, lyricsProvider],
        now: () => now,
      );

      try {
        final first = await repository.load(track);
        expect(first.hasArtwork, isFalse);
        expect(first.hasLyrics, isFalse);
        expect(artworkProvider.calls, 1);
        expect(lyricsProvider.calls, 1);

        await cache.write(
          track.cacheId,
          const TrackMetadata(
            lyrics: [LyricLine(time: Duration(seconds: 1), text: '新歌词')],
          ),
        );
        final metadata = await repository.load(track);

        expect(metadata.lyrics.single.text, '新歌词');
        expect(artworkProvider.calls, 1);
        expect(lyricsProvider.calls, 1);

        now = now.add(const Duration(minutes: 31));
        await repository.load(track);

        expect(artworkProvider.calls, 2);
        expect(lyricsProvider.calls, 1);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('manual retry bypasses metadata miss ttl', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_meta_retry_miss_',
    );
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack();
    final artworkProvider = _CountingArtworkProvider();
    final lyricsProvider = _CountingLyricsProvider();
    final repository = TrackMetadataRepository(
      cacheStore: cache,
      providers: [artworkProvider, lyricsProvider],
    );

    try {
      await repository.load(track);
      await repository.load(track);
      expect(artworkProvider.calls, 1);
      expect(lyricsProvider.calls, 1);

      await repository.loadBypassingMetadataMiss(track);

      expect(artworkProvider.calls, 2);
      expect(lyricsProvider.calls, 2);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('metadata miss ttl survives repository restart', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_meta_persist_miss_',
    );
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack();
    var now = DateTime(2026, 1, 1, 12);
    final firstArtworkProvider = _CountingArtworkProvider();
    final firstLyricsProvider = _CountingLyricsProvider();

    try {
      await TrackMetadataRepository(
        cacheStore: cache,
        providers: [firstArtworkProvider, firstLyricsProvider],
        now: () => now,
      ).load(track);

      expect(firstArtworkProvider.calls, 1);
      expect(firstLyricsProvider.calls, 1);

      final persisted = await cache.read(track.cacheId);
      expect(persisted?.artworkMiss?.isActive(now), isTrue);
      expect(persisted?.lyricsMiss?.isActive(now), isTrue);
      expect(persisted?.artworkMiss?.provider, '_counting_artwork_provider');
      expect(persisted?.lyricsMiss?.provider, '_counting_lyrics_provider');

      final restartedArtworkProvider = _CountingArtworkProvider();
      final restartedLyricsProvider = _CountingLyricsProvider();
      await TrackMetadataRepository(
        cacheStore: cache,
        providers: [restartedArtworkProvider, restartedLyricsProvider],
        now: () => now,
      ).load(track);

      expect(restartedArtworkProvider.calls, 0);
      expect(restartedLyricsProvider.calls, 0);

      now = now.add(const Duration(minutes: 31));
      await TrackMetadataRepository(
        cacheStore: cache,
        providers: [restartedArtworkProvider, restartedLyricsProvider],
        now: () => now,
      ).load(track);

      expect(restartedArtworkProvider.calls, 1);
      expect(restartedLyricsProvider.calls, 1);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'lyrics provider miss does not block fallback provider after restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_meta_provider_miss_',
      );
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      final now = DateTime(2026, 1, 1, 12);
      final firstProvider = _PrimaryMissingLyricsProvider();

      try {
        await TrackMetadataRepository(
          cacheStore: cache,
          providers: [firstProvider],
          now: () => now,
        ).load(track);

        expect(firstProvider.calls, 1);
        final persisted = await cache.read(track.cacheId);
        expect(persisted?.lyricsProviderMisses, hasLength(1));
        expect(
          persisted?.lyricsProviderMisses.single.provider,
          '_primary_missing_lyrics_provider',
        );

        final restartedPrimary = _PrimaryMissingLyricsProvider();
        final fallback = _FallbackLyricsProvider();
        final metadata = await TrackMetadataRepository(
          cacheStore: cache,
          providers: [restartedPrimary, fallback],
          now: () => now,
        ).load(track);

        expect(restartedPrimary.calls, 0);
        expect(fallback.calls, 1);
        expect(metadata.lyrics.single.text, '兜底歌词');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('legacy lyrics miss only skips the matching provider', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_meta_legacy_provider_miss_',
    );
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack();
    final now = DateTime(2026, 1, 1, 12);

    try {
      await cache.write(
        track.cacheId,
        TrackMetadata(
          lyricsMiss: MetadataFieldMiss(
            until: now.add(const Duration(minutes: 30)),
            provider: '_primary_missing_lyrics_provider',
          ),
        ),
      );

      final primary = _PrimaryMissingLyricsProvider();
      final fallback = _FallbackLyricsProvider();
      final metadata = await TrackMetadataRepository(
        cacheStore: cache,
        providers: [primary, fallback],
        now: () => now,
      ).load(track);

      expect(primary.calls, 0);
      expect(fallback.calls, 1);
      expect(metadata.lyrics.single.text, '兜底歌词');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'metadata repository does not overwrite success with empty result',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_meta_no_empty_overwrite_',
      );
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      final artwork = Uri.parse('https://cdn.example.test/cached.jpg');
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: const [_StaticMetadataProvider(TrackMetadata())],
      );

      try {
        await cache.write(
          track.cacheId,
          TrackMetadata(
            artworkUri: artwork,
            lyrics: const [LyricLine(time: Duration(seconds: 1), text: '已成功')],
          ),
        );

        final metadata = await repository.loadBypassingMetadataMiss(track);

        expect(metadata.artworkUri, artwork);
        expect(metadata.lyrics.single.text, '已成功');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('metadata repository skips providers for complete cache', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_meta_full_');
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack();
    final provider = _CountingMetadataProvider();
    final cached = TrackMetadata(
      artworkUri: Uri.parse('https://cdn.example.test/cached.jpg'),
      lyrics: const [LyricLine(time: Duration(seconds: 3), text: '缓存歌词')],
    );
    final repository = TrackMetadataRepository(
      cacheStore: cache,
      providers: [provider],
    );

    try {
      await cache.write(track.cacheId, cached);

      final metadata = await repository.load(track);

      expect(metadata.artworkUri, cached.artworkUri);
      expect(metadata.lyrics.single.text, '缓存歌词');
      expect(provider.calls, 0);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'metadata repository stops providers after missing fields are filled',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_meta_fill_');
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      final lyricsProvider = _CountingMetadataProvider(
        metadata: const TrackMetadata(
          lyrics: [LyricLine(time: Duration(seconds: 3), text: '补全歌词')],
        ),
      );
      final networkProvider = _CountingMetadataProvider(
        metadata: const TrackMetadata(),
      );
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: [lyricsProvider, networkProvider],
      );

      try {
        await cache.write(
          track.cacheId,
          TrackMetadata(
            artworkUri: Uri.parse('https://cdn.example.test/cached.jpg'),
          ),
        );

        final metadata = await repository.load(track);

        expect(metadata.lyrics.single.text, '补全歌词');
        expect(lyricsProvider.calls, 1);
        expect(networkProvider.calls, 0);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'metadata repository skips artwork providers when artwork is already cached',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_meta_art_skip_',
      );
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      final artworkProvider = _CountingArtworkProvider(
        metadata: TrackMetadata(
          artworkUri: Uri.parse('https://cdn.example.test/refetched.jpg'),
        ),
      );
      final lyricsProvider = _CountingLyricsProvider(
        metadata: const TrackMetadata(
          lyrics: [LyricLine(time: Duration(seconds: 3), text: '补全歌词')],
        ),
      );
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: [artworkProvider, lyricsProvider],
      );

      try {
        final cachedArtwork = Uri.parse('https://cdn.example.test/cached.jpg');
        await cache.write(
          track.cacheId,
          TrackMetadata(artworkUri: cachedArtwork),
        );

        final metadata = await repository.load(track);

        expect(metadata.artworkUri, cachedArtwork);
        expect(metadata.lyrics.single.text, '补全歌词');
        expect(artworkProvider.calls, 0);
        expect(lyricsProvider.calls, 1);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'metadata repository runs artwork providers only when artwork is missing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_meta_art_fill_',
      );
      final cache = MetadataCacheStore(rootProvider: () async => root);
      final track = _cachedTrack();
      final artworkProvider = _CountingArtworkProvider(
        metadata: TrackMetadata(
          artworkUri: Uri.parse('https://cdn.example.test/fetched.jpg'),
        ),
      );
      final lyricsProvider = _CountingLyricsProvider(
        metadata: const TrackMetadata(
          lyrics: [LyricLine(time: Duration(seconds: 3), text: '补全歌词')],
        ),
      );
      final repository = TrackMetadataRepository(
        cacheStore: cache,
        providers: [artworkProvider, lyricsProvider],
      );

      try {
        final metadata = await repository.load(track);

        expect(
          metadata.artworkUri.toString(),
          'https://cdn.example.test/fetched.jpg',
        );
        expect(metadata.lyrics.single.text, '补全歌词');
        expect(artworkProvider.calls, 1);
        expect(lyricsProvider.calls, 1);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('LRC parser supports metadata, single and repeated timestamps', () {
    final lines = parseLrcLines('''
[ti:测试]
[00:01.50]第一句
[00:03.00][00:04.25]重复句

plain text
''');

    expect(lines, hasLength(3));
    expect(lines[0].time, const Duration(milliseconds: 1500));
    expect(lines[0].text, '第一句');
    expect(lines[1].time, const Duration(seconds: 3));
    expect(lines[2].time, const Duration(milliseconds: 4250));
    expect(lines[2].text, '重复句');
  });

  test('LRC parser rejects repeated html metadata garbage', () {
    final lines = parseLrcLines('''
[00:01.00]坏孩子<br />作词：Vae 作曲：Vae<br /> 演唱：许嵩
[00:03.00]坏孩子<br />作词：Vae 作曲：Vae<br /> 演唱：许嵩
[00:05.00]坏孩子<br />作词：Vae 作曲：Vae<br /> 演唱：许嵩
[00:07.00]坏孩子<br />作词：Vae 作曲：Vae<br /> 演唱：许嵩
[00:09.00]坏孩子<br />作词：Vae 作曲：Vae<br /> 演唱：许嵩
''');

    expect(lines, isEmpty);
  });

  test('buguyy lyrics provider reads lyrics fields when present', () async {
    final provider = BuguyyLyricsProvider(
      useAppleEndpoint: true,
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          expect(uri.scheme, 'http');
          expect(uri.host, 'buguyy.top');
          expect(uri.path, '/api/geturl');
          return _json(uri, {'lyric': '[00:02.00]布谷歌词'});
        },
      ),
    );

    final metadata = await provider.find(_cachedTrack());

    expect(metadata.lyrics.single.text, '布谷歌词');
    expect(metadata.source, 'buguyy');
  });

  test(
    'flac platform provider reads NetEase lyrics for wyy candidates',
    () async {
      final provider = FlacPlatformLyricsProvider(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            expect(uri.host, 'music.163.com');
            expect(uri.queryParameters['id'], '469065898');
            return _json(uri, {
              'lrc': {'lyric': '[00:01.00]网易歌词\n[00:03.00]第二句'},
            });
          },
        ),
      );

      final metadata = await provider.find(
        _cachedTrack(
          source: MusicDataSource.flac,
          platform: 'wyy',
          id: '469065898',
        ),
      );

      expect(metadata.lyrics.map((line) => line.text), ['网易歌词', '第二句']);
      expect(metadata.source, 'flac:wyy');
    },
  );

  test('flac platform provider reads Kuwo lyric rows', () async {
    final provider = FlacPlatformLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          expect(uri.host, 'm.kuwo.cn');
          expect(uri.queryParameters['musicId'], '37408886');
          return _json(uri, {
            'status': 200,
            'data': {
              'lrclist': [
                {'time': '0.0', 'lineLyric': '黑夜传说 - 姜杰'},
                {'time': '6.23', 'lineLyric': '词：姜杰'},
              ],
            },
          });
        },
      ),
    );

    final metadata = await provider.find(
      _cachedTrack(
        source: MusicDataSource.flac,
        platform: 'kuwo',
        id: '37408886',
      ),
    );

    expect(metadata.lyrics.first.text, '黑夜传说 - 姜杰');
    expect(metadata.lyrics[1].time, const Duration(milliseconds: 6230));
    expect(metadata.source, 'flac:kuwo');
  });

  test(
    'itunes artwork provider picks matching high resolution cover',
    () async {
      final provider = ItunesArtworkProvider(
        httpClient: _FakeResolverHttp(
          onGet: (uri, _) async {
            expect(uri.host, 'itunes.apple.com');
            expect(uri.queryParameters['entity'], 'song');
            expect(uri.queryParameters['country'], 'CN');
            return _json(uri, {
              'results': [
                {
                  'trackName': '稻香',
                  'artistName': '周杰伦',
                  'collectionName': '错误专辑',
                  'artworkUrl100':
                      'https://img.example.test/other/100x100bb.jpg',
                },
                {
                  'trackName': '稻香',
                  'artistName': '周杰伦',
                  'collectionName': '魔杰座',
                  'artworkUrl100':
                      'https://img.example.test/song/100x100bb.jpg',
                },
              ],
            });
          },
        ),
      );

      final metadata = await provider.find(_cachedTrack(album: '魔杰座'));

      expect(
        metadata.artworkUri.toString(),
        'https://img.example.test/song/600x600bb.jpg',
      );
      expect(metadata.source, 'itunes');
    },
  );

  test('lrclib lyrics provider reads synced lyrics response', () async {
    final provider = LrcLibLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          expect(uri.host, 'lrclib.net');
          expect(uri.queryParameters['track_name'], '稻香');
          return _json(uri, [
            {
              'trackName': '稻香',
              'artistName': '周杰伦',
              'albumName': '错误专辑',
              'syncedLyrics': '[00:02.00]错误歌词',
            },
            {
              'trackName': '稻香',
              'artistName': '周杰伦',
              'albumName': '魔杰座',
              'syncedLyrics': '[00:02.00]LRCLIB 歌词',
            },
          ]);
        },
      ),
    );

    final metadata = await provider.find(_cachedTrack(album: '魔杰座'));

    expect(metadata.lyrics.single.text, 'LRCLIB 歌词');
    expect(metadata.source, 'lrclib');
  });

  test('lrclib lyrics provider retries traditional aliases', () async {
    var calls = 0;
    final provider = LrcLibLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          calls += 1;
          if (calls == 1) {
            expect(uri.queryParameters['track_name'], '一絲不掛');
            expect(uri.queryParameters['artist_name'], '陳奕迅');
            return _json(uri, const []);
          }
          expect(uri.queryParameters['track_name'], '一丝不挂');
          expect(uri.queryParameters['artist_name'], '陈奕迅');
          return _json(uri, [
            {
              'trackName': '一絲不掛',
              'artistName': '陳奕迅',
              'duration': 242,
              'syncedLyrics': '[00:02.00]繁体命中',
            },
          ]);
        },
      ),
    );

    final metadata = await provider.find(
      _cachedTrack(name: '一丝不挂', artist: '陈奕迅', duration: 242),
    );

    expect(calls, 2);
    expect(metadata.lyrics.single.text, '繁体命中');
    expect(metadata.source, 'lrclib');
  });

  test('lrclib lyrics provider retries xu song traditional aliases', () async {
    var calls = 0;
    final provider = LrcLibLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          calls += 1;
          if (calls == 1) {
            expect(uri.queryParameters['track_name'], '壞孩子');
            expect(uri.queryParameters['artist_name'], '許嵩');
            return _json(uri, [
              {
                'trackName': '壞孩子',
                'artistName': '許嵩',
                'duration': 245,
                'syncedLyrics': '[00:02.00]坏孩子繁体命中',
              },
            ]);
          }
          fail('traditional alias query should match before simplified query');
        },
      ),
    );

    final metadata = await provider.find(
      _cachedTrack(name: '坏孩子', artist: '许嵩', duration: 245),
    );

    expect(calls, 1);
    expect(metadata.lyrics.single.text, '坏孩子繁体命中');
    expect(metadata.source, 'lrclib');
  });

  test('lrclib lyrics provider continues after one query fails', () async {
    var calls = 0;
    final provider = LrcLibLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          calls += 1;
          if (calls == 1) {
            throw const SocketException('timeout');
          }
          return _json(uri, [
            {
              'trackName': '一丝不挂',
              'artistName': '陈奕迅',
              'duration': 242,
              'syncedLyrics': '[00:02.00]第二路命中',
            },
          ]);
        },
      ),
    );

    final metadata = await provider.find(
      _cachedTrack(name: '一丝不挂', artist: '陈奕迅', duration: 242),
    );

    expect(calls, 2);
    expect(metadata.lyrics.single.text, '第二路命中');
  });

  test('lrclib lyrics provider rejects wrong live duration', () async {
    final provider = LrcLibLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          return _json(uri, [
            {
              'trackName': '一絲不掛',
              'artistName': '陳奕迅',
              'duration': 284,
              'syncedLyrics': '[00:02.00]Live 歌词',
            },
          ]);
        },
      ),
    );

    final metadata = await provider.find(
      _cachedTrack(name: '一丝不挂', artist: '陈奕迅', duration: 242),
    );

    expect(metadata.lyrics, isEmpty);
  });

  test('lrcapi lyrics provider reads single LRC response', () async {
    final provider = LrcApiLyricsProvider(
      httpClient: _FakeResolverHttp(
        onGet: (uri, _) async {
          expect(uri.path, '/api/v1/lyrics/single');
          expect(uri.queryParameters['title'], '稻香');
          return ResolverHttpResponse(
            statusCode: HttpStatus.ok,
            body: '[00:01.00]LRC API 歌词',
            finalUrl: uri,
          );
        },
      ),
    );

    final metadata = await provider.find(_cachedTrack());

    expect(metadata.lyrics.single.text, 'LRC API 歌词');
    expect(metadata.source, 'lrcapi');
  });

  test('metadata repository backs up corrupt cache and regenerates', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_meta_bad_');
    final cache = MetadataCacheStore(rootProvider: () async => root);
    final track = _cachedTrack();
    final repository = TrackMetadataRepository(
      cacheStore: cache,
      providers: const [
        _StaticMetadataProvider(
          TrackMetadata(
            lyrics: [LyricLine(time: Duration(seconds: 1), text: '恢复歌词')],
          ),
        ),
      ],
    );

    try {
      await File(
        '${root.path}${Platform.pathSeparator}${track.cacheId}.metadata.json',
      ).writeAsString('{bad json');

      final metadata = await repository.load(track);

      expect(metadata.lyrics.single.text, '恢复歌词');
      expect(
        root.listSync().where(
          (entry) => entry.path.contains('.metadata.json.corrupt-'),
        ),
        isNotEmpty,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}

CachedTrack _cachedTrack({
  String coverUrl = '',
  ResolvedLyrics? lyrics,
  String lyricsPath = '',
  String filePath = '/tmp/song-1.mp3',
  String album = '',
  String name = '稻香',
  String artist = '周杰伦',
  MusicDataSource source = MusicDataSource.buguyy,
  String platform = 'buguyy',
  String id = 'song-1',
  int duration = 0,
}) {
  final music = ResolvedMusic(
    query: '$artist $name',
    source: source,
    platform: platform,
    id: id,
    name: name,
    artist: artist,
    album: album,
    url: 'https://cdn.example.test/song-1.mp3',
    quality: const MusicQuality(format: 'mp3'),
    coverUrl: coverUrl,
    lyrics: lyrics,
    duration: duration,
  );
  return CachedTrack(
    cacheId: cacheIdForResolved(music),
    music: music,
    filePath: filePath,
    sizeBytes: 4,
    fromCache: true,
    lyricsPath: lyricsPath,
  );
}

ResolverHttpResponse _json(Uri uri, Object body) {
  return ResolverHttpResponse(
    statusCode: HttpStatus.ok,
    body: jsonEncode(body),
    finalUrl: uri,
  );
}

class _StaticMetadataProvider implements TrackMetadataProvider {
  const _StaticMetadataProvider(this.metadata);

  final TrackMetadata metadata;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    return metadata;
  }
}

class _CountingMetadataProvider implements TrackMetadataProvider {
  _CountingMetadataProvider({this.metadata = const TrackMetadata()});

  final TrackMetadata metadata;
  int calls = 0;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    calls += 1;
    return metadata;
  }
}

class _CountingArtworkProvider extends _CountingMetadataProvider
    implements ArtworkMetadataProvider, NetworkMetadataProvider {
  _CountingArtworkProvider({super.metadata});
}

class _CountingLyricsProvider extends _CountingMetadataProvider
    implements LyricsMetadataProvider, NetworkMetadataProvider {
  _CountingLyricsProvider({super.metadata});
}

class _PrimaryMissingLyricsProvider
    implements LyricsMetadataProvider, NetworkMetadataProvider {
  int calls = 0;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    calls += 1;
    return const TrackMetadata();
  }
}

class _FallbackLyricsProvider
    implements LyricsMetadataProvider, NetworkMetadataProvider {
  int calls = 0;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    calls += 1;
    return const TrackMetadata(
      lyrics: [LyricLine(time: Duration(seconds: 1), text: '兜底歌词')],
      source: 'fallback',
    );
  }
}

class _FakeResolverHttp implements MusicResolverHttp {
  const _FakeResolverHttp({this.onGet});

  final Future<ResolverHttpResponse> Function(
    Uri uri,
    Map<String, String> headers,
  )?
  onGet;

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
    fail('Unexpected HEAD $uri');
  }

  @override
  Future<ResolverHttpResponse> range(
    Uri uri, {
    int start = 0,
    int end = 0,
    Map<String, String> headers = const {},
  }) {
    fail('Unexpected range GET $uri');
  }

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) {
    fail('Unexpected form POST $uri');
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
