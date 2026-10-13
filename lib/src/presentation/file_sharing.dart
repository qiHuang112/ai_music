import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hands a downloaded file to the system share sheet (AirDrop, messaging
/// apps, Files). Implemented natively on iOS only for now.
abstract final class FileSharing {
  static const _channel = MethodChannel('ai_music/share');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> share(String path) async {
    if (path.isEmpty || !await File(path).exists()) {
      throw const FileSystemException('File is unavailable');
    }
    await _channel.invokeMethod<void>('file', {'path': path});
  }
}
