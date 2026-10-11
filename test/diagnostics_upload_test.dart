import 'dart:convert';
import 'dart:io';
import 'package:ai_music/src/data/operation_log.dart';
import 'package:ai_music/src/data/listening_stats_store.dart';
import 'package:ai_music/src/application/diagnostics_upload_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'persistent logs redact credentials and survive restart/rotation',
    () async {
      final dir = await Directory.systemTemp.createTemp('music-logs');
      try {
        final log = OperationLog(
          rootProvider: () async => dir,
          maxFileBytes: 1,
        );
        log.record('first', {
          'token': 'secret-token',
          'message':
              'https://user:pass@audio.test/file?signature=abc Bearer dangerous',
        });
        log.record('second');
        log.record('third');
        final restarted = OperationLog(rootProvider: () async => dir);
        await log.flush();
        final data = await restarted.export();
        final json = jsonEncode(data);
        expect(data.length, 3);
        for (final secret in [
          'secret-token',
          'user:pass',
          'signature=abc',
          'dangerous',
        ]) {
          expect(json, isNot(contains(secret)));
        }
        expect(json, contains('audio.test'));
        log.record('fourth');
        await log.flush();
        expect((await log.export()).length, 3);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('upload includes original stats JSON and requires discovery', () async {
    final dir = await Directory.systemTemp.createTemp('music-report');
    final stats = ListeningStatsStore.memory();
    final client = _Client();
    final operations = OperationLog(rootProvider: () async => dir);
    final upload = DiagnosticsUploadController(
      stats: stats,
      captureListening: () {},
      version: () async => null,
      client: client,
      operations: operations,
    );
    try {
      await upload.probe();
      expect(upload.available, false);
      await upload.upload();
      expect(client.payload, isNull);
      client.found = true;
      await upload.probe();
      operations.record('search', {'query': '晴天'});
      await upload.upload();
      expect(upload.reportId, isNotNull);
      expect(client.payload!['listeningStats'], await stats.exportJsonFiles());
      expect(client.payload!['operations'], isNotEmpty);
      expect(upload.error, isNull);
      client.failUpload = true;
      await upload.upload();
      expect(upload.reportId, isNull);
      expect(upload.error, isNotNull);
    } finally {
      upload.dispose();
      stats.dispose();
      await operations.flush();
      await dir.delete(recursive: true);
    }
  });
  test(
    'real client requires correct service and persisted payload hash',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var correct = false, acknowledge = false;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          request.response.write(
            jsonEncode({
              'service': correct ? 'ai-music-diagnostics' : 'wrong',
              'schemaVersion': 1,
            }),
          );
        } else {
          final payload =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          request.response.write(
            jsonEncode({
              'saved': true,
              'reportId': payload['reportId'],
              'sha256': acknowledge ? 'wrong-hash' : null,
            }),
          );
        }
        await request.response.close();
      });
      try {
        final client = DiagnosticsClient(
          base: Uri.parse('http://127.0.0.1:${server.port}'),
        );
        expect(await client.probe(), false);
        correct = true;
        expect(await client.probe(), true);
        acknowledge = true;
        await expectLater(
          client.upload({'reportId': 'test'}),
          throwsStateError,
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}

class _Client extends DiagnosticsClient {
  bool found = false, failUpload = false;
  Map<String, Object?>? payload;
  @override
  Future<bool> probe() async => found;
  @override
  Future<Map<String, dynamic>> upload(Map<String, Object?> payload) async {
    if (failUpload) throw const HttpException('HTTP 503');
    this.payload = payload;
    return {'saved': true, 'reportId': payload['reportId']};
  }
}
