import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/playback/resumable_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts yielding audio before the remote body is complete', () async {
    final root = await Directory.systemTemp.createTemp('stream_early_');
    final payload = List<int>.generate(20000, (i) => i % 251);
    final release = Completer<void>();
    final firstChunk = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response
        ..statusCode = HttpStatus.partialContent
        ..contentLength = payload.length
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-${payload.length - 1}/${payload.length}',
        )
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..add(payload.sublist(0, 4096));
      await request.response.flush();
      await release.future;
      request.response.add(payload.sublist(4096));
      await request.response.close();
    });
    final complete = File('${root.path}/song.mp3');
    final source = ResumableAudioSource(
      url: Uri.parse('http://127.0.0.1:${server.port}/song'),
      partFile: File('${complete.path}.part'),
      completeFile: complete,
      tag: 'song',
      onStarted: () {},
      onStopped: () {},
      onComplete: (_) async {},
    );
    try {
      final response = await source.request();
      final received = <int>[];
      final done = response.stream.listen((chunk) {
        received.addAll(chunk);
        if (!firstChunk.isCompleted) firstChunk.complete();
      }).asFuture<void>();
      await firstChunk.future.timeout(const Duration(seconds: 2));
      expect(received, isNotEmpty);
      expect(await complete.exists(), isFalse);
      release.complete();
      await done;
      expect(await complete.readAsBytes(), payload);
    } finally {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });

  test('streams a prefix and resumes the remaining bytes with Range', () async {
    final root = await Directory.systemTemp.createTemp('resumable_audio_');
    final payload = List<int>.generate(20000, (i) => i % 251);
    final ranges = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      ranges.add(range);
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
      final from = int.parse(match.group(1)!);
      final to = match.group(2)!.isEmpty
          ? payload.length
          : int.parse(match.group(2)!) + 1;
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $from-${to - 1}/${payload.length}',
        )
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..add(payload.sublist(from, to));
      await request.response.close();
    });
    final part = File('${root.path}/song.mp3.part');
    final complete = File('${root.path}/song.mp3');
    var completed = 0;
    ResumableAudioSource source() => ResumableAudioSource(
      url: Uri.parse('http://127.0.0.1:${server.port}/song'),
      partFile: part,
      completeFile: complete,
      tag: 'song',
      onStarted: () {},
      onStopped: () {},
      onComplete: (_) async => completed++,
    );
    try {
      final first = await source().request(0, 4096);
      expect(
        await first.stream.expand((chunk) => chunk).toList(),
        payload.sublist(0, 4096),
      );
      expect(await part.length(), 4096);
      expect(await complete.exists(), false);

      final second = await source().request(0);
      expect(await second.stream.expand((chunk) => chunk).toList(), payload);
      expect(ranges, ['bytes=0-4095', 'bytes=4096-']);
      expect(await complete.readAsBytes(), payload);
      expect(await part.exists(), false);
      expect(completed, 1);
    } finally {
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });

  test('restarts from zero when the source ignores Range', () async {
    final root = await Directory.systemTemp.createTemp('no_range_audio_');
    final payload = List<int>.generate(20000, (i) => i % 251);
    final part = File('${root.path}/song.mp3.part');
    final complete = File('${root.path}/song.mp3');
    await part.writeAsBytes(payload.sublist(0, 4096));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..add(payload);
      await request.response.close();
    });
    try {
      final source = ResumableAudioSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/song'),
        partFile: part,
        completeFile: complete,
        tag: 'song',
        onStarted: () {},
        onStopped: () {},
        onComplete: (_) async {},
      );
      final response = await source.request();
      expect(response.rangeRequestsSupported, false);
      expect(await response.stream.expand((chunk) => chunk).toList(), payload);
      expect(await complete.readAsBytes(), payload);
    } finally {
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });

  test(
    'a bounded request stays bounded when the source ignores Range',
    () async {
      final root = await Directory.systemTemp.createTemp('bounded_no_range_');
      final payload = List<int>.generate(20000, (i) => i % 251);
      final part = File('${root.path}/song.mp3.part');
      final complete = File('${root.path}/song.mp3');
      await part.writeAsBytes(payload.sublist(0, 1024));
      final ranges = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        ranges.add(request.headers.value(HttpHeaders.rangeHeader) ?? '');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..contentLength = payload.length
          ..add(payload);
        await request.response.close();
      });
      final source = ResumableAudioSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/song'),
        partFile: part,
        completeFile: complete,
        tag: 'song',
        onStarted: () {},
        onStopped: () {},
        onComplete: (_) async {},
      );
      try {
        final first = await source.request(0, 4096);
        final firstBytes = await first.stream.expand((chunk) => chunk).toList();
        expect(first.rangeRequestsSupported, false);
        expect(first.offset, 0);
        expect(first.sourceLength, payload.length);
        expect(first.contentLength, 4096);
        expect(firstBytes, payload.sublist(0, 4096));
        expect(await part.length(), 4096);
        expect(await complete.exists(), false);

        final second = await source.request();
        final secondBytes = await second.stream
            .expand((chunk) => chunk)
            .toList();
        expect(second.contentLength, payload.length);
        expect(secondBytes, payload);
        expect(await complete.readAsBytes(), payload);
        expect(ranges, ['bytes=1024-4095', 'bytes=4096-']);
      } finally {
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );

  test('a 206 response that ignores the upper bound is capped', () async {
    final root = await Directory.systemTemp.createTemp('oversized_range_');
    final payload = List<int>.generate(20000, (i) => i % 251);
    final part = File('${root.path}/song.mp3.part');
    final complete = File('${root.path}/song.mp3');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      final from = int.parse(
        RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
      );
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $from-${payload.length - 1}/${payload.length}',
        )
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..add(payload.sublist(from));
      await request.response.close();
    });
    final source = ResumableAudioSource(
      url: Uri.parse('http://127.0.0.1:${server.port}/song'),
      partFile: part,
      completeFile: complete,
      tag: 'song',
      onStarted: () {},
      onStopped: () {},
      onComplete: (_) async {},
    );
    try {
      final first = await source.request(0, 4096);
      expect(first.offset, 0);
      expect(first.contentLength, 4096);
      expect(
        await first.stream.expand((chunk) => chunk).toList(),
        payload.sublist(0, 4096),
      );
      expect(await part.length(), 4096);
      expect(await complete.exists(), false);

      final rest = await source.request();
      expect(await rest.stream.expand((chunk) => chunk).toList(), payload);
      expect(await complete.readAsBytes(), payload);
    } finally {
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });

  test(
    'a seek past the cached prefix respects a bounded 206 response',
    () async {
      final root = await Directory.systemTemp.createTemp('bounded_seek_');
      final payload = List<int>.generate(20000, (i) => i % 251);
      final part = File('${root.path}/song.mp3.part');
      final complete = File('${root.path}/song.mp3');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader)!;
        final from = int.parse(
          RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
        );
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $from-${payload.length - 1}/${payload.length}',
          )
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..add(payload.sublist(from));
        await request.response.close();
      });
      final source = ResumableAudioSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/song'),
        partFile: part,
        completeFile: complete,
        tag: 'song',
        onStarted: () {},
        onStopped: () {},
        onComplete: (_) async {},
      );
      try {
        for (final prefix in [0, 1000]) {
          if (prefix > 0) await part.writeAsBytes(payload.sublist(0, prefix));
          final seek = await source.request(5000, 6000);
          final bytes = await seek.stream.expand((chunk) => chunk).toList();
          expect(seek.offset, 5000);
          expect(seek.contentLength, 1000);
          expect(bytes, payload.sublist(5000, 6000));
          expect(await part.exists() ? await part.length() : 0, prefix);
        }

        final prefixRequest = await source.request(0, 4096);
        expect(
          await prefixRequest.stream.expand((chunk) => chunk).toList(),
          payload.sublist(0, 4096),
        );
        expect(await part.length(), 4096);
        final rest = await source.request();
        expect(await rest.stream.expand((chunk) => chunk).toList(), payload);
        expect(await complete.readAsBytes(), payload);
      } finally {
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
