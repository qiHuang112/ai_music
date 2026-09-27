import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release version and Android cleartext opt-in are configured', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(pubspec, contains('version: 1.0.1+6108'));
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
  });
}
