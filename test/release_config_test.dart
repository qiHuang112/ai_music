import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest does not globally allow cleartext traffic', () async {
    final mainManifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final debugManifest = await File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsString();

    expect(mainManifest, isNot(contains('usesCleartextTraffic="true"')));
    expect(debugManifest, contains('usesCleartextTraffic="true"'));
  });

  test('release build does not use debug signing config', () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();

    expect(gradle, contains('compileSdk = 36'));
    expect(
      gradle,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(gradle, contains('key.properties'));
    expect(gradle, contains('Release signing is not configured'));
  });

  test(
    'release signing secrets are ignored and dependency overrides removed',
    () async {
      final gitignore = await File('.gitignore').readAsString();
      final pubspec = await File('pubspec.yaml').readAsString();

      expect(await File('android/key.properties.example').exists(), isTrue);
      expect(gitignore, contains('/android/key.properties'));
      expect(gitignore, contains('/android/*.jks'));
      expect(pubspec, isNot(contains('dependency_overrides:')));
      expect(pubspec, isNot(contains('sqflite_android')));
    },
  );
}
