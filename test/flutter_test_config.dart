import 'dart:async';

import 'package:ai_music/src/presentation/app_theme.dart';

/// A playing record, drifting backdrop and level meter never settle. Tests run
/// with them still, so pumpAndSettle can finish; a test that checks the motion
/// itself turns it back on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MusicMotion.perpetual = false;
  await testMain();
}
