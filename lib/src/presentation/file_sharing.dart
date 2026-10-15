import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../data/operation_log.dart';
import '../platform/platform_detection.dart';

/// Hands a downloaded file to the system share sheet (AirDrop, messaging
/// apps, Files). Android grants a temporary read-only content URI.
abstract final class FileSharing {
  static const _channel = MethodChannel('ai_music/share');

  static bool get supported =>
      !kIsWeb &&
      !isOpenHarmonyPlatform &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<void> share(
    String path, {
    String? name,
    String? chooserTitle,
  }) async {
    OperationLog.event('file_share.request', {
      'name': name,
      'platform': defaultTargetPlatform.name,
    });
    try {
      if (!supported) throw UnsupportedError('File sharing is unavailable');
      if (path.isEmpty || !await File(path).exists()) {
        throw const FileSystemException('File is unavailable');
      }
      await _channel.invokeMethod<void>('file', {
        'path': path,
        'name': name,
        'chooserTitle': chooserTitle,
      });
      // Opening the chooser does not mean the user sent anything.
      OperationLog.event('file_share.opened', {'name': name});
    } catch (error) {
      OperationLog.event('file_share.failed', {
        'name': name,
        'error': error.toString(),
      });
      rethrow;
    }
  }
}
