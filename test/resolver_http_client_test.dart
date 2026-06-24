import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/resolver_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP resolver retries transient connection failures', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      requests += 1;
      if (requests == 1) {
        final socket = await request.response.detachSocket();
        socket.destroy();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}));
      await request.response.close();
    });

    try {
      final client = HttpMusicResolverClient();
      final response = await client.get(
        Uri.parse('http://${server.address.host}:${server.port}/retry'),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, contains('ok'));
      expect(requests, 2);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
