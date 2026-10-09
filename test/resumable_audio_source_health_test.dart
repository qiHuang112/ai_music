import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/playback/resumable_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'HTTP failures report source failure once before exposing stream',
    () async {
      final f = await _Fixture.create((request) async {
        request.response.statusCode = 503;
        await request.response.close();
      });
      try {
        await expectLater(f.source.request(), throwsA(isA<HttpException>()));
        expect(f.failures, hasLength(1));
        expect(f.successes, 0);
      } finally {
        await f.close();
      }
    },
  );

  test('invalid range response also reports source failure once', () async {
    final f = await _Fixture.create((request) async {
      request.response.statusCode = HttpStatus.partialContent;
      await request.response.close();
    });
    try {
      await expectLater(f.source.request(), throwsA(isA<HttpException>()));
      expect(f.failures, hasLength(1));
    } finally {
      await f.close();
    }
  });

  test(
    'only complete remote transfer reports success, not cached reads',
    () async {
      final f = await _Fixture.create((request) async {
        request.response
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..contentLength = 4
          ..add([1, 2, 3, 4]);
        await request.response.close();
      });
      try {
        final part = await f.source.request(0, 2);
        expect(await part.stream.expand((chunk) => chunk).toList(), [1, 2]);
        expect(f.successes, 0);
        final complete = await f.source.request();
        expect(await complete.stream.expand((chunk) => chunk).toList(), [
          1,
          2,
          3,
          4,
        ]);
        expect(f.successes, 1);
        final cached = await f.source.request();
        await cached.stream.drain<void>();
        expect(f.successes, 1);
        expect(f.failures, isEmpty);
      } finally {
        await f.close();
      }
    },
  );

  test('canceling pending request is not a source failure', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final f = await _Fixture.create((request) async {
      started.complete();
      await release.future;
      await request.response.close();
    });
    try {
      final pending = f.source.request();
      final result = expectLater(pending, throwsA(anything));
      await started.future;
      f.source.cancelRequests();
      await result;
      expect(f.failures, isEmpty);
      expect(f.successes, 0);
    } finally {
      release.complete();
      await f.close();
    }
  });

  test('consumer cancel does not downgrade a source', () async {
    final release = Completer<void>();
    final f = await _Fixture.create((request) async {
      request.response
        ..bufferOutput = false
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..contentLength = 100
        ..add([1, 2, 3, 4]);
      await request.response.flush();
      await release.future;
      try {
        await request.response.close();
      } catch (_) {}
    });
    try {
      final response = await f.source.request();
      await response.stream.first;
      expect(f.failures, isEmpty);
      expect(f.successes, 0);
    } finally {
      release.complete();
      await f.close();
    }
  });

  test('truncated remote stream reports failure instead of success', () async {
    final f = await _Fixture.create((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 200 OK\r\nContent-Length: 100\r\n'
        'Content-Type: audio/mpeg\r\nConnection: close\r\n\r\n',
      );
      socket.add([1, 2, 3, 4]);
      await socket.flush();
      socket.destroy();
    });
    try {
      final response = await f.source.request();
      await expectLater(response.stream.drain<void>(), throwsA(anything));
      expect(f.failures, hasLength(1));
      expect(f.successes, 0);
    } finally {
      await f.close();
    }
  });
}

class _Fixture {
  _Fixture(this.root, this.server);
  final Directory root;
  final HttpServer server;
  final failures = <Object>[];
  var successes = 0;
  late final source = ResumableAudioSource(
    url: Uri.parse('http://127.0.0.1:${server.port}/audio'),
    partFile: File('${root.path}/audio.mp3.part'),
    completeFile: File('${root.path}/audio.mp3'),
    tag: 'audio',
    onComplete: (_) async {},
    onStopped: () {},
    onStarted: () {},
    onFailure: failures.add,
    onSuccess: () => successes++,
  );

  static Future<_Fixture> create(
    Future<void> Function(HttpRequest) handle,
  ) async {
    final root = await Directory.systemTemp.createTemp('audio_source_health');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    return _Fixture(root, server);
  }

  Future<void> close() async {
    source.cancelRequests();
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}
