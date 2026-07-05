import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloadOrReuse keeps a long-lived cached file', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_cache_test_');
    final downloader = _FakeDownloader();
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: downloader,
    );

    try {
      final first = await store.downloadOrReuse(_resolvedMusic());
      final second = await store.downloadOrReuse(_resolvedMusic());

      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(first.filePath, second.filePath);
      expect(downloader.calls, 1);
      final bytes = await File(first.filePath).readAsBytes();
      expect(bytes.take(3), [0x49, 0x44, 0x33]);
      expect(bytes.length, greaterThanOrEqualTo(16 * 1024));
      expect(await store.listCached(), hasLength(1));
      expect(first.cacheId, cacheIdForResolved(_resolvedMusic()));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('downloadOrReuse removes temp files after failed downloads', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_cache_fail_');
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: _FakeDownloader(fail: true),
    );

    try {
      await expectLater(
        store.downloadOrReuse(_resolvedMusic()),
        throwsA(isA<StateError>()),
      );
      final files = root
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .toList();
      expect(files.where((path) => path.endsWith('.tmp')), isEmpty);
      expect(files, isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'downloadOrReuse separates same artist and title by stable id',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_cache_keys_',
      );
      final downloader = _FakeDownloader();
      final store = CachedTrackStore(
        rootProvider: () async => root,
        downloader: downloader,
      );

      try {
        final first = await store.downloadOrReuse(_resolvedMusic(id: 'song-1'));
        final second = await store.downloadOrReuse(
          _resolvedMusic(id: 'song-2'),
        );

        expect(first.cacheId, isNot(second.cacheId));
        expect(first.filePath, isNot(second.filePath));
        expect(downloader.calls, 2);
        expect(await store.listCached(), hasLength(2));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('listCached backs up damaged index and exposes the error', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_cache_bad_');
    final store = CachedTrackStore(rootProvider: () async => root);
    final index = File(
      '${root.path}${Platform.pathSeparator}_cache_index.json',
    );
    await index.writeAsString('{not-json');

    try {
      await expectLater(
        store.listCached(),
        throwsA(isA<CacheIndexException>()),
      );
      final backups = root
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.corrupt-'))
          .toList();
      expect(backups, hasLength(1));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('downloadOrReuse writes resolved lyrics beside audio', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_cache_lrc_');
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: _FakeDownloader(),
    );

    try {
      final cached = await store.downloadOrReuse(_resolvedMusicWithLyrics());
      final lyricsFile = File(cached.lyricsPath);

      expect(cached.lyricsPath, endsWith('.lrc'));
      expect(await lyricsFile.exists(), isTrue);
      expect(await lyricsFile.readAsString(), '[00:01.00]第一句\n');

      final listed = await store.listCached();
      expect(listed.single.lyricsPath, cached.lyricsPath);
      expect(listed.single.music.lyrics?.source, 'test:lrc');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'downloadOrReuse cancellation removes temp files and skips index',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_cache_cancel_',
      );
      final token = DownloadCancelToken();
      final store = CachedTrackStore(
        rootProvider: () async => root,
        downloader: _FakeDownloader(cancelToken: token),
      );

      try {
        await expectLater(
          store.downloadOrReuse(_resolvedMusic(), cancelToken: token),
          throwsA(isA<DownloadCancelledException>()),
        );
        final files = root.listSync().whereType<File>().toList();
        expect(files, isEmpty);
        expect(await store.listCached(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('downloadOrReuse rejects html json and tiny audio responses', () async {
    final cases = {
      'html': '<html><title>SafeLine</title></html>'.codeUnits,
      'json': '{"error":"captcha"}'.codeUnits,
      'tiny': [0x49, 0x44, 0x33, 1, 2, 3],
    };

    for (final entry in cases.entries) {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_cache_bad_${entry.key}_',
      );
      final store = CachedTrackStore(
        rootProvider: () async => root,
        downloader: _BytesDownloader(entry.value),
      );

      try {
        await expectLater(
          store.downloadOrReuse(_resolvedMusic(id: entry.key)),
          throwsA(
            isA<SourceDownloadException>().having(
              (error) => error.failureCode,
              'failureCode',
              'non_audio_content',
            ),
          ),
        );
        final files = root.listSync().whereType<File>().toList();
        expect(files, isEmpty);
        expect(await store.listCached(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    }
  });

  test('downloadOrReuse skips external pan links before downloader', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_cache_pan_');
    final downloader = _FakeDownloader();
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: downloader,
    );

    try {
      await expectLater(
        store.downloadOrReuse(
          _resolvedMusic(
            url: 'https://pan.quark.cn/s/example',
            urlType: MediaUrlType.externalPan,
            panLink: true,
          ),
        ),
        throwsA(
          isA<SourceDownloadException>().having(
            (error) => error.failureCode,
            'failureCode',
            'external_pan_link',
          ),
        ),
      );
      expect(downloader.calls, 0);
      expect(root.listSync().whereType<File>(), isEmpty);
      expect(await store.listCached(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'downloadOrReuse rejects preview audio before downloader and index',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_cache_preview_',
      );
      final downloader = _FakeDownloader();
      final store = CachedTrackStore(
        rootProvider: () async => root,
        downloader: downloader,
      );

      try {
        await expectLater(
          store.downloadOrReuse(
            _resolvedMusic(
              url: 'https://audio-ssl.itunes.apple.com/preview.m4a',
              urlType: MediaUrlType.previewAudio,
              canCacheAudio: false,
            ),
          ),
          throwsA(
            isA<SourceDownloadException>().having(
              (error) => error.failureCode,
              'failureCode',
              'preview_audio_available',
            ),
          ),
        );
        expect(downloader.calls, 0);
        expect(root.listSync().whereType<File>(), isEmpty);
        expect(await store.listCached(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'downloadOrReuse lets unknown extensionless audio pass HEAD and GET',
    () async {
      final audioBytes = _validMp3Bytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      final serving = server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = audioBytes.length;
        if (request.method != 'HEAD') {
          request.response.add(audioBytes);
        }
        await request.response.close();
      });
      final root = await Directory.systemTemp.createTemp(
        'ai_music_cache_unknown_audio_',
      );
      final store = CachedTrackStore(
        rootProvider: () async => root,
        downloader: HttpAudioDownloader(requireHttps: false),
      );

      try {
        final cached = await store.downloadOrReuse(
          _resolvedMusic(
            url: 'http://${server.address.host}:${server.port}/stream',
            urlType: MediaUrlType.unknown,
          ),
        );

        expect(cached.fromCache, isFalse);
        expect(await File(cached.filePath).exists(), isTrue);
        expect(await File(cached.filePath).readAsBytes(), audioBytes);
        expect(requests, ['HEAD /stream', 'GET /stream']);
        expect(await store.listCached(), hasLength(1));
      } finally {
        await serving.cancel();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );

  test('downloadOrReuse maps GET html response to non_audio_content', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>{"error":"captcha"}</html>');
      }
      await request.response.close();
    });
    final root = await Directory.systemTemp.createTemp(
      'ai_music_cache_get_html_',
    );
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: HttpAudioDownloader(requireHttps: false),
    );

    try {
      await expectLater(
        store.downloadOrReuse(
          _resolvedMusic(
            url: 'http://${server.address.host}:${server.port}/stream',
            urlType: MediaUrlType.unknown,
          ),
        ),
        throwsA(
          isA<SourceDownloadException>().having(
            (error) => error.failureCode,
            'failureCode',
            'non_audio_content',
          ),
        ),
      );
      expect(root.listSync().whereType<File>(), isEmpty);
      expect(await store.listCached(), isEmpty);
    } finally {
      await serving.cancel();
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });

  test(
    'HttpAudioDownloader rejects cleartext URLs when HTTPS is required',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_https_');
      final target = File('${root.path}${Platform.pathSeparator}song.mp3');
      final downloader = HttpAudioDownloader(requireHttps: true);

      try {
        await expectLater(
          downloader.download(
            Uri.parse('http://cdn.example.test/song.mp3'),
            target,
          ),
          throwsA(isA<AudioValidationException>()),
        );
        expect(await target.exists(), isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('deleteCached removes audio lyrics and index row', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_cache_delete_',
    );
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: _FakeDownloader(),
    );

    try {
      final cached = await store.downloadOrReuse(_resolvedMusicWithLyrics());
      final audio = File(cached.filePath);
      final lyrics = File(cached.lyricsPath);

      expect(await audio.exists(), isTrue);
      expect(await lyrics.exists(), isTrue);

      await store.deleteCached(cached.cacheId);

      expect(await audio.exists(), isFalse);
      expect(await lyrics.exists(), isFalse);
      expect(await store.listCached(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'listCached deduplicates repeated index rows and rewrites index',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_cache_dupe_',
      );
      final store = CachedTrackStore(rootProvider: () async => root);
      final music = _resolvedMusic();
      final audio = File(
        '${root.path}${Platform.pathSeparator}duplicate-${DateTime.now().microsecondsSinceEpoch}.mp3',
      );
      final index = File(
        '${root.path}${Platform.pathSeparator}_cache_index.json',
      );

      try {
        await audio.writeAsBytes(_validMp3Bytes());
        final older = CachedTrack(
          cacheId: cacheIdForResolved(music),
          music: music,
          filePath: audio.path,
          sizeBytes: 1,
          fromCache: true,
          cachedAt: DateTime(2026, 1, 1),
        );
        final newer = older.copyWith(
          sizeBytes: 2,
          cachedAt: DateTime(2026, 1, 2),
        );
        await index.writeAsString(jsonEncode([older.toJson(), newer.toJson()]));

        final listed = await store.listCached();
        final rewritten = jsonDecode(await index.readAsString()) as List;

        expect(listed, hasLength(1));
        expect(listed.single.sizeBytes, audio.lengthSync());
        expect(listed.single.cachedAt, DateTime(2026, 1, 2));
        expect(rewritten, hasLength(1));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

ResolvedMusic _resolvedMusic({
  String id = 'song-1',
  String? url,
  MediaUrlType urlType = MediaUrlType.directAudio,
  bool panLink = false,
  bool canCacheAudio = true,
}) {
  return ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: id,
    name: '稻香',
    artist: '周杰伦',
    album: '',
    url: url ?? 'https://cdn.example.test/$id.mp3',
    quality: const MusicQuality(format: 'mp3'),
    panLink: panLink,
    urlType: urlType,
    canCacheAudio: canCacheAudio,
  );
}

ResolvedMusic _resolvedMusicWithLyrics() {
  return const ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'song-lrc',
    name: '稻香',
    artist: '周杰伦',
    album: '',
    url: 'https://cdn.example.test/song-lrc.mp3',
    quality: MusicQuality(format: 'mp3'),
    lyrics: ResolvedLyrics(
      source: 'test:lrc',
      text: '[00:01.00]第一句',
      lines: 1,
      timed: true,
    ),
  );
}

class _FakeDownloader implements AudioDownloader {
  _FakeDownloader({this.fail = false, this.cancelToken});

  final bool fail;
  final DownloadCancelToken? cancelToken;
  int calls = 0;

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCanceled();
    calls += 1;
    await target.writeAsBytes([1, 2]);
    if (fail) {
      throw StateError('network failed');
    }
    this.cancelToken?.cancel();
    cancelToken?.throwIfCanceled();
    final bytes = _validMp3Bytes();
    await target.writeAsBytes(bytes);
    onProgress?.call(
      CachedDownloadProgress(bytes: bytes.length, totalBytes: bytes.length),
    );
    return bytes.length;
  }
}

class _BytesDownloader implements AudioDownloader {
  const _BytesDownloader(this.bytes);

  final List<int> bytes;

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCanceled();
    await target.writeAsBytes(bytes);
    onProgress?.call(
      CachedDownloadProgress(bytes: bytes.length, totalBytes: bytes.length),
    );
    return bytes.length;
  }
}

List<int> _validMp3Bytes() {
  return [
    0x49,
    0x44,
    0x33,
    0x04,
    0x00,
    0x00,
    ...List<int>.filled(16 * 1024, 0),
  ];
}
