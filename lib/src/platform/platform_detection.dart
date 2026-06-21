import 'dart:io';

bool get isOpenHarmonyPlatform {
  final os = Platform.operatingSystem.toLowerCase();
  return os == 'ohos' || os == 'openharmony' || os == 'harmonyos';
}
