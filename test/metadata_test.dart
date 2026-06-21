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
    final repository = TrackMetadataRepository(cacheStore: cache);
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
}) {
  final music = ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'song-1',
    name: '稻香',
    artist: '周杰伦',
    album: '',
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
