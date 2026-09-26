import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/platform/screenshot_ocr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai_music/screenshot_ocr');

  test('iOS normalized Vision boxes are converted to image pixels', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => [
        {
          'text': '1',
          'left': 0.05,
          'top': 0.2,
          'right': 0.08,
          'bottom': 0.214,
          'imageWidth': 1000,
          'imageHeight': 2000,
        },
        {
          'text': '晴天',
          'left': 0.15,
          'top': 0.185,
          'right': 0.34,
          'bottom': 0.206,
          'imageWidth': 1000,
          'imageHeight': 2000,
        },
        {
          'text': '周杰伦·叶惠美',
          'left': 0.28,
          'top': 0.215,
          'right': 0.5,
          'bottom': 0.227,
          'imageWidth': 1000,
          'imageHeight': 2000,
        },
      ],
    );
    try {
      final lines = await const OnDeviceScreenshotOcr().recognize('/image.png');
      expect(lines.first.bounds.left, 50);
      final songs = const ScreenshotSongParser().parse([('image', lines)]);
      expect(songs.single.title, '晴天');
      expect(songs.single.artist, '周杰伦');
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
