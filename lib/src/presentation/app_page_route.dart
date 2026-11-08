import 'package:flutter/material.dart';

import 'mobile_chrome.dart';
import 'native_shell.dart';

/// The app's page route. Under the iOS shell UIKit animates its bars for the
/// same push, so the content slide runs at UIKit's pace (0.35 s) to stay in
/// step; phones with the Flutter floating bars keep the same pace.
/// Elsewhere it is an ordinary Material page route.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  static const _shellPace = Duration(milliseconds: 350);

  static bool get _paced => NativeShell.active || MobileChrome.instance.enabled;

  @override
  Duration get transitionDuration =>
      _paced ? _shellPace : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _paced ? _shellPace : super.reverseTransitionDuration;
}
