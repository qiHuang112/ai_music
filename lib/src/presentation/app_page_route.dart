import 'package:flutter/material.dart';

import 'native_shell.dart';

/// The app's page route. Under the iOS shell UIKit animates its bars for the
/// same push, so the content slide runs at UIKit's pace (0.35 s) to stay in
/// step; elsewhere it is an ordinary Material page route.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  static const _shellPace = Duration(milliseconds: 350);

  @override
  Duration get transitionDuration =>
      NativeShell.active ? _shellPace : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      NativeShell.active ? _shellPace : super.reverseTransitionDuration;
}
