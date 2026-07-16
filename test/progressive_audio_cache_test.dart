import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/progressive_audio_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'proxy returns 206 before download completes and part file grows',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_prog_');
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(64 * 1024),
        chunkSize: 4096,
        chunkDelay: const Duration(milliseconds: 35),
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final logs = <String>[];
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
        logger: logs.add,
      );

      try {
        final music = _resolvedMusic(url: source.audioUri.toString());
        final session = await progressive.open(music);
        final client = HttpClient();
        final download = Stopwatch()..start();
        final firstSound = Stopwatch()..start();
        final request = await client.getUrl(session.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
        final response = await request.close();
        final bytes = await response.fold<int>(
          0,
          (sum, chunk) => sum + chunk.length,
        );
        firstSound.stop();
        debugPrint(
          'progressive evidence first_byte_ms=${firstSound.elapsedMilliseconds}',
        );

        expect(response.statusCode, HttpStatus.partialContent);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 0-1023/${source.bytes.length}',
        );
        expect(bytes, 1024);
        expect(session.isComplete, isFalse);
        expect(await session.partFile.exists(), isTrue);
        expect(logs.single, contains('progressive proxy url='));
        expect(logs.single, contains(session.proxyUri.toString()));
        final firstSize = await session.partFile.length();
        await session.changes.first.timeout(const Duration(seconds: 2));
        expect(await session.partFile.length(), greaterThan(firstSize));
        await session.changes
            .firstWhere((_) => session.isComplete)
            .timeout(const Duration(seconds: 3));
        download.stop();
        expect(firstSound.elapsed, lessThan(download.elapsed));

        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('valid initial 206 stays on the ranged upstream response', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_prog_valid_range_',
    );
    final source = await _SlowAudioSource.start(
      _validMp3Bytes(32 * 1024),
      chunkSize: 4096,
      chunkDelay: Duration.zero,
    );
    final cacheStore = CachedTrackStore(rootProvider: () async => root);
    final progressive = ProgressiveAudioCache(
      cacheStore: cacheStore,
      rootProvider: () async => root,
    );

    try {
      final session = await progressive.open(
        _resolvedMusic(url: source.audioUri.toString()),
      );
      final client = HttpClient();
      final request = await client.getUrl(session.proxyUri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final response = await request.close();

      expect(response.statusCode, HttpStatus.partialContent);
      await response.drain<void>();
      await session.promoteWhenComplete();
      expect(source.rangeRequests, 1);
      expect(source.fullRequests, 0);
      client.close(force: true);
    } finally {
      await progressive.close();
      await source.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'capped initial 206 fails closed and never promotes a partial file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_capped_initial_range_',
      );
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(96 * 1024),
        chunkSize: 4096,
        chunkDelay: Duration.zero,
        initialRangeCapBytes: 32 * 1024,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );

        await expectLater(
          session.promoteWhenComplete(),
          throwsA(isA<StateError>()),
        );

        expect(session.isComplete, isFalse);
        expect(
          session.fetchError,
          isA<SourceDownloadException>().having(
            (error) => error.failureCode,
            'failureCode',
            'incomplete_audio_response',
          ),
        );
        expect(session.downloadedBytes, 32 * 1024);
        expect(session.totalBytes, source.bytes.length);
        expect(await cacheStore.listCached(), isEmpty);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'far seek proxies an aligned upstream range before background catches up',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_far_seek_',
      );
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(256 * 1024),
        chunkSize: 1024,
        chunkDelay: const Duration(milliseconds: 80),
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
        firstByteTimeout: const Duration(milliseconds: 180),
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        const start = 128 * 1024;
        const end = start + 1023;
        final request = await client.getUrl(session.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final response = await request.close();
        final bytes = await response.expand((chunk) => chunk).toList();

        expect(response.statusCode, HttpStatus.partialContent);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes $start-$end/${source.bytes.length}',
        );
        expect(bytes, source.bytes.sublist(start, end + 1));
        expect(source.requestedRanges, contains('bytes=$start-$end'));
        expect(session.isComplete, isFalse);
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'far seek rejects a 206 whose total differs from the known stream length',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_range_total_mismatch_',
      );
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(256 * 1024),
        chunkSize: 1024,
        chunkDelay: const Duration(milliseconds: 80),
        rangeTotalDeltaAfterFirst: 1,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final logs = <String>[];
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
        firstByteTimeout: const Duration(milliseconds: 180),
        logger: logs.add,
      );
      final client = HttpClient();

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final warmup = await client.getUrl(session.proxyUri);
        warmup.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        await (await warmup.close()).drain<void>();
        expect(session.totalBytes, source.bytes.length);

        const start = 192 * 1024;
        const end = start + 1023;
        final request = await client.getUrl(session.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final response = await request.close();
        await response.drain<void>();

        expect(response.statusCode, HttpStatus.badGateway);
        expect(
          logs,
          contains(
            contains(
              'knownTotal=${source.bytes.length} '
              'receivedTotal=${source.bytes.length + 1}',
            ),
          ),
        );
        expect(await cacheStore.listCached(), isEmpty);
      } finally {
        client.close(force: true);
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'far seek is not blocked by an active open-ended proxy request',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_concurrent_seek_',
      );
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(256 * 1024),
        chunkSize: 1024,
        chunkDelay: const Duration(milliseconds: 80),
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );
      final client = HttpClient();
      StreamIterator<List<int>>? initialChunks;

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final initialRequest = await client.getUrl(session.proxyUri);
        initialRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
        final initialResponse = await initialRequest.close();
        initialChunks = StreamIterator<List<int>>(initialResponse);
        expect(await initialChunks.moveNext(), isTrue);

        const start = 192 * 1024;
        const end = start + 1023;
        final seekRequest = await client.getUrl(session.proxyUri);
        seekRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final seekResponse = await seekRequest.close().timeout(
          const Duration(seconds: 1),
        );
        final bytes = await seekResponse.expand((chunk) => chunk).toList();

        expect(seekResponse.statusCode, HttpStatus.partialContent);
        expect(bytes, source.bytes.sublist(start, end + 1));
        expect(session.isComplete, isFalse);
      } finally {
        await initialChunks?.cancel();
        client.close(force: true);
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'proxy returns 416 for unsatisfiable ranges after total is known',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_prog_416_');
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(24 * 1024),
        chunkSize: 8192,
        chunkDelay: Duration.zero,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        final warmup = await client.getUrl(session.proxyUri);
        warmup.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        await (await warmup.close()).drain<void>();

        final request = await client.getUrl(session.proxyUri);
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${source.bytes.length + 100}-',
        );
        final response = await request.close();

        expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes */${source.bytes.length}',
        );
        await response.drain<void>();
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'new sessions retire old proxy URLs instead of reusing /audio',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_token_',
      );
      final source = await _SlowAudioSource.start(
        _validMp3Bytes(24 * 1024),
        chunkSize: 8192,
        chunkDelay: Duration.zero,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );

      try {
        final first = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final second = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        expect(first.proxyUri.path, isNot(second.proxyUri.path));

        final client = HttpClient();
        final oldResponse = await (await client.getUrl(first.proxyUri)).close();
        expect(oldResponse.statusCode, HttpStatus.gone);
        await oldResponse.drain<void>();

        final unknown = second.proxyUri.replace(path: '/audio/not-a-token');
        final unknownResponse = await (await client.getUrl(unknown)).close();
        expect(unknownResponse.statusCode, HttpStatus.notFound);
        await unknownResponse.drain<void>();

        final request = await client.getUrl(second.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final activeResponse = await request.close();
        expect(activeResponse.statusCode, HttpStatus.partialContent);
        await activeResponse.drain<void>();
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('cancel during weak network leaves no cache index row', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_prog_cancel_');
    final source = await _SlowAudioSource.start(
      _validMp3Bytes(96 * 1024),
      chunkSize: 4096,
      chunkDelay: const Duration(milliseconds: 60),
    );
    final cacheStore = CachedTrackStore(rootProvider: () async => root);
    final logs = <String>[];
    final progressive = ProgressiveAudioCache(
      cacheStore: cacheStore,
      rootProvider: () async => root,
      logger: logs.add,
    );

    try {
      final session = await progressive.open(
        _resolvedMusic(url: source.audioUri.toString()),
      );
      final client = HttpClient();
      final request = await client.getUrl(session.proxyUri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      await (await request.close()).drain<void>();
      await session.changes.first.timeout(const Duration(seconds: 2));
      expect(await session.partFile.exists(), isTrue);

      await session.cancel(deletePartFile: true);

      expect(await session.partFile.exists(), isFalse);
      expect(await cacheStore.listCached(), isEmpty);
      expect(logs.any((log) => log.startsWith('progressive canceled')), isTrue);
      client.close(force: true);
    } finally {
      await progressive.close();
      await source.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'upstream failure returns fallback signal and leaves cache empty',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_prog_fail_');
      final source = await _FailingAudioSource.start();
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
        firstByteTimeout: const Duration(milliseconds: 100),
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        final request = await client.getUrl(session.proxyUri);
        final response = await request.close();

        expect(response.statusCode, HttpStatus.badGateway);
        expect(session.fetchError, isA<HttpException>());
        expect(await cacheStore.listCached(), isEmpty);
        await response.drain<void>();
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'failed stream leaves no formal cache and same cache key can recover',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_recover_',
      );
      final failingSource = await _FailingAudioSource.start();
      final workingSource = await _SlowAudioSource.start(
        _validMp3Bytes(24 * 1024),
        chunkSize: 4096,
        chunkDelay: Duration.zero,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );
      final client = HttpClient();

      try {
        final failed = await progressive.open(
          _resolvedMusic(url: failingSource.audioUri.toString()),
        );
        final failedResponse = await (await client.getUrl(
          failed.proxyUri,
        )).close();

        expect(failedResponse.statusCode, HttpStatus.badGateway);
        expect(failed.fetchError, isA<HttpException>());
        expect(await cacheStore.listCached(), isEmpty);
        await failedResponse.drain<void>();

        final recovered = await progressive.open(
          _resolvedMusic(url: workingSource.audioUri.toString()),
        );
        final request = await client.getUrl(recovered.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
        final recoveredResponse = await request.close();

        expect(recoveredResponse.statusCode, HttpStatus.partialContent);
        await recoveredResponse.drain<void>();
        final cached = await recovered.promoteWhenComplete();

        expect(cached.cacheId, cacheIdForResolved(recovered.music));
        expect(await cacheStore.listCached(), hasLength(1));
        expect(await File(cached.filePath).exists(), isTrue);
      } finally {
        client.close(force: true);
        await progressive.close();
        await failingSource.close();
        await workingSource.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'upstream range failure falls back to full GET for seekable proxy playback',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_range_fallback_',
      );
      final source = await _RangeFailingAudioSource.start(
        _validMp3Bytes(48 * 1024),
        chunkSize: 8192,
        chunkDelay: Duration.zero,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        final request = await client.getUrl(session.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=32768-33791');
        final response = await request.close();
        final bytes = await response.fold<int>(
          0,
          (sum, chunk) => sum + chunk.length,
        );

        expect(source.rangeRequests, 2);
        expect(source.fullRequests, 1);
        expect(response.statusCode, HttpStatus.partialContent);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 32768-33791/${source.bytes.length}',
        );
        expect(bytes, 1024);
        expect(session.fetchError, isNull);
        expect(await cacheStore.listCached(), isEmpty);
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'misaligned upstream 206 falls back to full GET before proxying byte zero',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_misaligned_range_',
      );
      final source = await _MisalignedRangeAudioSource.start(
        _validMp3Bytes(48 * 1024),
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        final request = await client.getUrl(session.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
        final response = await request.close();
        final bytes = await response.expand((chunk) => chunk).toList();

        expect(source.rangeRequests, 1);
        expect(source.fullRequests, 1);
        expect(response.statusCode, HttpStatus.partialContent);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 0-1023/${source.bytes.length}',
        );
        expect(bytes, source.bytes.take(1024));
        expect(session.fetchError, isNull);
        expect(await cacheStore.listCached(), isEmpty);
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('first byte timeout returns fallback signal without hanging', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_prog_timeout_',
    );
    final source = await _SlowAudioSource.start(
      _validMp3Bytes(24 * 1024),
      chunkSize: 8192,
      chunkDelay: const Duration(milliseconds: 300),
    );
    final cacheStore = CachedTrackStore(rootProvider: () async => root);
    final progressive = ProgressiveAudioCache(
      cacheStore: cacheStore,
      rootProvider: () async => root,
      firstByteTimeout: const Duration(milliseconds: 50),
    );

    try {
      final session = await progressive.open(
        _resolvedMusic(url: source.audioUri.toString()),
      );
      final client = HttpClient();
      final request = await client.getUrl(session.proxyUri);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.gatewayTimeout);
      expect(await cacheStore.listCached(), isEmpty);
      await response.drain<void>();
      client.close(force: true);
    } finally {
      await progressive.close();
      await source.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'non-audio content type fails before playback and leaves cache empty',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_prog_html_');
      final source = await _StaticAudioSource.start(
        '<html><title>challenge</title></html>'.codeUnits,
        contentType: ContentType.html,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
        firstByteTimeout: const Duration(milliseconds: 100),
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        final response = await (await client.getUrl(session.proxyUri)).close();

        expect(response.statusCode, HttpStatus.badGateway);
        expect(session.fetchError, isA<AudioValidationException>());
        expect(await session.partFile.exists(), isFalse);
        expect(await cacheStore.listCached(), isEmpty);
        await response.drain<void>();
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('audio content type with text first chunk is rejected', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_prog_fake_audio_',
    );
    final source = await _StaticAudioSource.start(
      '{"error":"captcha"}'.codeUnits,
      contentType: ContentType('audio', 'mpeg'),
    );
    final cacheStore = CachedTrackStore(rootProvider: () async => root);
    final progressive = ProgressiveAudioCache(
      cacheStore: cacheStore,
      rootProvider: () async => root,
      firstByteTimeout: const Duration(milliseconds: 100),
    );

    try {
      final session = await progressive.open(
        _resolvedMusic(url: source.audioUri.toString()),
      );
      final client = HttpClient();
      final response = await (await client.getUrl(session.proxyUri)).close();

      expect(response.statusCode, HttpStatus.badGateway);
      expect(session.fetchError, isA<AudioValidationException>());
      expect(await cacheStore.listCached(), isEmpty);
      await response.drain<void>();
      client.close(force: true);
    } finally {
      await progressive.close();
      await source.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'missing content type can stream when first chunk has audio magic',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_prog_magic_',
      );
      final source = await _StaticAudioSource.start(
        _validMp3Bytes(24 * 1024),
        contentType: null,
      );
      final cacheStore = CachedTrackStore(rootProvider: () async => root);
      final progressive = ProgressiveAudioCache(
        cacheStore: cacheStore,
        rootProvider: () async => root,
      );

      try {
        final session = await progressive.open(
          _resolvedMusic(url: source.audioUri.toString()),
        );
        final client = HttpClient();
        final request = await client.getUrl(session.proxyUri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final response = await request.close();

        expect(response.statusCode, HttpStatus.partialContent);
        await response.drain<void>();
        client.close(force: true);
      } finally {
        await progressive.close();
        await source.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('complete progressive file is promoted to normal cache', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_prog_done_');
    final source = await _SlowAudioSource.start(
      _validMp3Bytes(32 * 1024),
      chunkSize: 8192,
      chunkDelay: Duration.zero,
    );
    final cacheStore = CachedTrackStore(rootProvider: () async => root);
    final logs = <String>[];
    final progressive = ProgressiveAudioCache(
      cacheStore: cacheStore,
      rootProvider: () async => root,
      logger: logs.add,
    );

    try {
      final music = _resolvedMusic(url: source.audioUri.toString());
      final session = await progressive.open(music);
      final client = HttpClient();
      final request = await client.getUrl(session.proxyUri);
      await (await request.close()).drain<void>();
      final cached = await session.promoteWhenComplete();
      final listed = await cacheStore.listCached();

      expect(session.isComplete, isTrue);
      expect(cached.cacheId, cacheIdForResolved(music));
      expect(cached.filePath.endsWith('.part'), isFalse);
      expect(await File(cached.filePath).exists(), isTrue);
      expect(await session.partFile.exists(), isFalse);
      expect(listed, hasLength(1));
      expect(listed.single.filePath, cached.filePath);
      expect(logs.any((log) => log.startsWith('progressive complete')), isTrue);
      expect(logs.any((log) => log.startsWith('progressive promoted')), isTrue);

      final promotedRequest = await client.getUrl(session.proxyUri);
      promotedRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=1024-2047');
      final promotedResponse = await promotedRequest.close();
      final promotedBytes = await promotedResponse
          .expand((chunk) => chunk)
          .toList();
      expect(promotedResponse.statusCode, HttpStatus.partialContent);
      expect(promotedBytes, source.bytes.sublist(1024, 2048));

      client.close(force: true);
    } finally {
      await progressive.close();
      await source.close();
      await root.delete(recursive: true);
    }
  });
}

ResolvedMusic _resolvedMusic({required String url}) {
  return ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'progressive-song',
    name: '稻香',
    artist: '周杰伦',
    album: '',
    url: url,
    quality: const MusicQuality(format: 'mp3'),
  );
}

List<int> _validMp3Bytes(int size) {
  return [
    0x49,
    0x44,
    0x33,
    0x04,
    0x00,
    0x00,
    ...List<int>.filled(max(size, 16 * 1024), 0),
  ];
}

class _RangeFailingAudioSource {
  _RangeFailingAudioSource._(this._server, this.bytes, this.audioUri);

  final HttpServer _server;
  final List<int> bytes;
  final Uri audioUri;
  int rangeRequests = 0;
  int fullRequests = 0;

  static Future<_RangeFailingAudioSource> start(
    List<int> bytes, {
    required int chunkSize,
    required Duration chunkDelay,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = _RangeFailingAudioSource._(
      server,
      bytes,
      Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/song.mp3',
      ),
    );
    unawaited(source._serve(chunkSize: chunkSize, chunkDelay: chunkDelay));
    return source;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve({
    required int chunkSize,
    required Duration chunkDelay,
  }) async {
    await for (final request in _server) {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        rangeRequests += 1;
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
        continue;
      }
      fullRequests += 1;
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.contentLength = bytes.length;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        if (chunkDelay > Duration.zero) {
          await Future<void>.delayed(chunkDelay);
        }
        final end = min(offset + chunkSize, bytes.length);
        request.response.add(bytes.sublist(offset, end));
        await request.response.flush();
      }
      await request.response.close();
    }
  }
}

class _MisalignedRangeAudioSource {
  _MisalignedRangeAudioSource._(this._server, this.bytes, this.audioUri);

  final HttpServer _server;
  final List<int> bytes;
  final Uri audioUri;
  int rangeRequests = 0;
  int fullRequests = 0;

  static Future<_MisalignedRangeAudioSource> start(List<int> bytes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = _MisalignedRangeAudioSource._(
      server,
      bytes,
      Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/song.mp3',
      ),
    );
    unawaited(source._serve());
    return source;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        rangeRequests += 1;
        const start = 4096;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.headers.contentLength = bytes.length - start;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${bytes.length - 1}/${bytes.length}',
        );
        request.response.add(bytes.sublist(start));
        await request.response.close();
        continue;
      }
      fullRequests += 1;
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    }
  }
}

class _FailingAudioSource {
  const _FailingAudioSource._(this._server, this.audioUri);

  final HttpServer _server;
  final Uri audioUri;

  static Future<_FailingAudioSource> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = _FailingAudioSource._(
      server,
      Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/song.mp3',
      ),
    );
    unawaited(source._serve());
    return source;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
}

class _StaticAudioSource {
  const _StaticAudioSource._(this._server, this.audioUri);

  final HttpServer _server;
  final Uri audioUri;

  static Future<_StaticAudioSource> start(
    List<int> bytes, {
    required ContentType? contentType,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = _StaticAudioSource._(
      server,
      Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/song.mp3',
      ),
    );
    unawaited(source._serve(bytes: bytes, contentType: contentType));
    return source;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve({
    required List<int> bytes,
    required ContentType? contentType,
  }) async {
    await for (final request in _server) {
      request.response.statusCode = HttpStatus.ok;
      if (contentType != null) {
        request.response.headers.contentType = contentType;
      }
      request.response.add(bytes);
      await request.response.close();
    }
  }
}

class _SlowAudioSource {
  _SlowAudioSource._(
    this._server,
    this.bytes,
    this.audioUri, {
    this.rangeTotalDeltaAfterFirst,
    this.initialRangeCapBytes,
  });

  final HttpServer _server;
  final List<int> bytes;
  final Uri audioUri;
  int rangeRequests = 0;
  int fullRequests = 0;
  final int? rangeTotalDeltaAfterFirst;
  final int? initialRangeCapBytes;
  final List<String> requestedRanges = <String>[];

  static Future<_SlowAudioSource> start(
    List<int> bytes, {
    required int chunkSize,
    required Duration chunkDelay,
    int? rangeTotalDeltaAfterFirst,
    int? initialRangeCapBytes,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = _SlowAudioSource._(
      server,
      bytes,
      Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/song.mp3',
      ),
      rangeTotalDeltaAfterFirst: rangeTotalDeltaAfterFirst,
      initialRangeCapBytes: initialRangeCapBytes,
    );
    unawaited(source._serve(chunkSize: chunkSize, chunkDelay: chunkDelay));
    return source;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve({
    required int chunkSize,
    required Duration chunkDelay,
  }) async {
    await for (final request in _server) {
      unawaited(
        _serveRequest(request, chunkSize: chunkSize, chunkDelay: chunkDelay),
      );
    }
  }

  Future<void> _serveRequest(
    HttpRequest request, {
    required int chunkSize,
    required Duration chunkDelay,
  }) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final rangeMatch = range == null
        ? null
        : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    final start = rangeMatch == null ? 0 : int.parse(rangeMatch.group(1)!);
    final requestedEnd = rangeMatch?.group(2);
    final requestedRangeEnd = requestedEnd == null || requestedEnd.isEmpty
        ? bytes.length - 1
        : min(int.parse(requestedEnd), bytes.length - 1);
    if (range == null) {
      fullRequests += 1;
    } else {
      rangeRequests += 1;
      requestedRanges.add(range);
    }
    final end =
        range != null &&
            rangeRequests == 1 &&
            (requestedEnd == null || requestedEnd.isEmpty) &&
            initialRangeCapBytes != null
        ? min(start + initialRangeCapBytes! - 1, requestedRangeEnd)
        : requestedRangeEnd;
    if (start >= bytes.length) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );
      await request.response.close();
      return;
    }
    request.response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    request.response.headers.contentType = ContentType('audio', 'mpeg');
    request.response.headers.contentLength = end - start + 1;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range != null) {
      final reportedTotal =
          rangeRequests > 1 && rangeTotalDeltaAfterFirst != null
          ? bytes.length + rangeTotalDeltaAfterFirst!
          : bytes.length;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$reportedTotal',
      );
    }
    for (var offset = start; offset <= end; offset += chunkSize) {
      if (chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      }
      final chunkEnd = min(offset + chunkSize, end + 1);
      request.response.add(bytes.sublist(offset, chunkEnd));
      await request.response.flush();
    }
    await request.response.close();
  }
}
