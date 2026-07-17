import 'dart:io';

import 'package:ai_music/src/data/resolver_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interactive GET does not multiply a transient failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final subscription = server.listen((request) async {
      requests += 1;
      final socket = await request.response.detachSocket();
      socket.destroy();
    });
    final client = HttpMusicResolverClient();

    try {
      await expectLater(
        client.get(
          Uri.parse('http://${server.address.address}:${server.port}/search'),
        ),
        throwsA(anything),
      );
      expect(requests, 1);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
