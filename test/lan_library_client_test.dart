import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/lan_library_client.dart';
import 'package:ai_music/src/data/lan_library_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'tests health and parses a library from the configured origin',
    () async {
      final handling = server.forEach((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/api/v1/health') {
          request.response.write(
            jsonEncode({'status': 'ok', 'schemaVersion': 1, 'trackCount': 1}),
          );
        } else if (request.uri.path == '/api/v1/library') {
          request.response.write(jsonEncode(_manifestJson()));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      final client = LanLibraryClient();

      try {
        final health = await client.testConnection(baseUrl);
        final manifest = await client.fetchLibrary(baseUrl);

        expect(health.trackCount, 1);
        expect(manifest.tracks.single.title, '慢呼放松');
        expect(
          client
              .resolveAssetUri(baseUrl, manifest.tracks.single.audio)
              .toString(),
          '$baseUrl/api/v1/files/Lamaze/01.mp3',
        );
      } finally {
        client.close();
        await server.close(force: true);
        await handling;
      }
    },
  );

  test('reports non-2xx and invalid health payloads', () async {
    final handling = server.forEach((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('offline');
      await request.response.close();
    });
    final client = LanLibraryClient();

    try {
      await expectLater(
        client.testConnection(baseUrl),
        throwsA(isA<LanLibraryException>()),
      );
    } finally {
      client.close();
      await server.close(force: true);
      await handling;
    }
  });

  test('rejects a manifest response larger than the client limit', () async {
    final padding = ' ' * (2 * 1024 * 1024);
    final handling = server.forEach((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{$padding}');
      await request.response.close();
    });
    final client = LanLibraryClient();

    try {
      await expectLater(
        client.fetchLibrary(baseUrl),
        throwsA(isA<LanLibraryException>()),
      );
    } finally {
      client.close();
      await server.close(force: true);
      await handling;
    }
  });

  test(
    'rejects and removes a download larger than the manifest asset',
    () async {
      final handling = server.forEach((request) async {
        request.response.headers.chunkedTransferEncoding = true;
        request.response.add(List<int>.filled(65, 1));
        await request.response.close();
      });
      final client = LanLibraryClient();
      final root = await Directory.systemTemp.createTemp('lan_client_limit_');
      final target = File('${root.path}${Platform.pathSeparator}asset.tmp');
      final asset = LanAsset(
        url: Uri.parse('/api/v1/files/test.mp3'),
        sizeBytes: 64,
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        format: 'mp3',
      );

      try {
        await expectLater(
          client.downloadAsset(baseUrl, asset, target),
          throwsA(isA<LanLibraryException>()),
        );
        expect(await target.exists(), isFalse);
      } finally {
        client.close();
        await server.close(force: true);
        await handling;
        await root.delete(recursive: true);
      }
    },
  );
}

Map<String, Object?> _manifestJson() {
  return {
    'schemaVersion': 1,
    'libraryId': 'library-test',
    'generatedAt': '2026-08-02T00:00:00Z',
    'tracks': <Object?>[
      {
        'id': 'lamaze-slow-breathing',
        'title': '慢呼放松',
        'artist': 'AI Home',
        'album': '拉玛泽呼吸引导',
        'audio': {
          'url': '/api/v1/files/Lamaze/01.mp3',
          'sizeBytes': 64000,
          'sha256': 'a' * 64,
          'format': 'mp3',
        },
      },
    ],
  };
}
