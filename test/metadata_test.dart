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
}) {
  final music = ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'song-1',
    name: '稻香',
    artist: '周杰伦',
    album: album,
    url: 'https://cdn.example.test/song-1.mp3',
    quality: const MusicQuality(format: 'mp3'),
    coverUrl: coverUrl,
    lyrics: lyrics,
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
