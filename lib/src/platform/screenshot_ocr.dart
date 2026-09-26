import 'package:flutter/services.dart';

import '../application/screenshot_song_parser.dart';

abstract class ScreenshotOcr {
  Future<List<ScreenshotTextLine>> recognize(String imagePath);
}

class OnDeviceScreenshotOcr implements ScreenshotOcr {
  const OnDeviceScreenshotOcr();

  static const _channel = MethodChannel('ai_music/screenshot_ocr');

  @override
  Future<List<ScreenshotTextLine>> recognize(String imagePath) async {
    final response = await _channel.invokeListMethod<Object?>('recognize', {
      'path': imagePath,
    });
    return [
      for (final value in response ?? const [])
        if (value is Map)
          ScreenshotTextLine(
            text: value['text']?.toString() ?? '',
            bounds: Rect.fromLTRB(
              (value['left'] as num).toDouble() * _scale(value, 'imageWidth'),
              (value['top'] as num).toDouble() * _scale(value, 'imageHeight'),
              (value['right'] as num).toDouble() * _scale(value, 'imageWidth'),
              (value['bottom'] as num).toDouble() *
                  _scale(value, 'imageHeight'),
            ),
          ),
    ];
  }

  static double _scale(Map value, String key) =>
      (value[key] as num?)?.toDouble() ?? 1;
}
