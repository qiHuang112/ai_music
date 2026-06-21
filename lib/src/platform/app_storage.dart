import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'platform_detection.dart';

const _supportDirOverride = String.fromEnvironment('AI_MUSIC_SUPPORT_DIR');
const _ohosSupportDir = '/data/storage/el2/base/haps/entry/files/ai_music';

Future<Directory> getAiMusicSupportDirectory() async {
  final override = _supportDirOverride.trim();
  if (override.isNotEmpty) {
    return Directory(override);
  }

  try {
    return await getApplicationSupportDirectory();
  } catch (_) {
    return Directory(_fallbackSupportPath());
  }
}

Future<Directory> getAiMusicSupportSubdirectory(String name) async {
  final root = await getAiMusicSupportDirectory();
  return Directory('${root.path}${Platform.pathSeparator}$name');
}

String _fallbackSupportPath() {
  if (isOpenHarmonyPlatform) {
    // HarmonyOS denies apps access to /storage/Users/currentUser. When
    // path_provider is unavailable, stay inside the app EL2 sandbox.
    return _ohosSupportDir;
  }

  final home = Platform.environment['HOME']?.trim().isNotEmpty == true
      ? Platform.environment['HOME']!.trim()
      : Platform.environment['USERPROFILE']?.trim();
  if (home != null && home.isNotEmpty) {
    return '$home${Platform.pathSeparator}.ai_music';
  }
  return '${Directory.systemTemp.path}${Platform.pathSeparator}ai_music';
}
