import 'dart:io';

import 'package:ai_music/src/presentation/file_sharing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai_music/share');
  late Directory root;
  final calls = <MethodCall>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('share_audio_');
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '${platform.name} opens native sharing with the audio file and readable name',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final file = File('${root.path}/hashed-name.mp3');
        await file.writeAsBytes([1, 2, 3]);
        expect(FileSharing.supported, isTrue);
        await FileSharing.share(
          file.path,
          name: '海阔天空 - beyond',
          chooserTitle: '分享音频',
        );
        expect(calls.single.method, 'file');
        expect(calls.single.arguments, {
          'path': file.path,
          'name': '海阔天空 - beyond',
          'chooserTitle': '分享音频',
        });
        expect(await file.readAsBytes(), [1, 2, 3]);
      },
    );
  }
  test('missing file is not handed to the system', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(
      FileSharing.share('${root.path}/missing.mp3'),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, isEmpty);
  });
  test(
    'native failure propagates instead of reporting a successful share',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final file = File('${root.path}/audio.mp3');
      await file.writeAsBytes([1]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'share_failed'),
          );
      await expectLater(
        FileSharing.share(file.path),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
