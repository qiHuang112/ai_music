import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback;

import '../application/transition_profiler.dart';
import 'design/ambient_clock.dart';
import 'mobile_chrome.dart';
import 'native_shell.dart';

/// The app's page route. Under the iOS shell UIKit animates its bars for the
/// same push, so the content slide runs at UIKit's pace (0.35 s) to stay in
/// step; phones with the Flutter floating bars keep the same pace.
/// Elsewhere it is an ordinary Material page route.
class AppPageRoute<T> extends MaterialPageRoute<T> implements NamedPageRoute {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    this.coversBackdrop = false,
  });

  /// The page paints an opaque backdrop of its own (the player, lyrics).
  ///
  /// On Android it slides in without fading. Skia draws a see-through page
  /// into a layer of its own on every frame of the fade, and for these
  /// full-screen pages that took 13–15 ms a frame on 77 against an 11 ms
  /// budget; opaque, the same frames take 7–8 ms.
  final bool coversBackdrop;

  bool get fadesIn =>
      !coversBackdrop || defaultTargetPlatform != TargetPlatform.android;

  /// This page's opacity when it does not fade in: whole, except that
  /// popped off another opaque page (lyrics over the player) it fades out as
  /// before. Drawn whole to the end, it and the player under it were both
  /// full pages on every frame of the pop.
  Animation<double> opacityWithoutFadeIn(Animation<double> animation) =>
      _opaqueTop ??= _PopFade(
        animation,
        navigator?.userGestureInProgressNotifier,
        (t) => _previousCovers ? pageFadeIn.transform(t) : 1,
      );
  _PopFade? _opaqueTop;
  bool _previousCovers = false;

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _previousCovers =
        previousRoute is AppPageRoute && previousRoute.coversBackdrop;
  }

  /// Whether this page fades out as the next one arrives: not when that one
  /// slides in opaque over it anyway, which would only pay for the layer.
  bool get fadesOut => !_nextCovers;
  bool _nextCovers = false;

  /// This page's opacity under an opaque next page: whole while that one
  /// slides in (or is dragged aside by a back swipe), and fading back in as
  /// it is popped, the way every page does. Drawn whole through a pop, the
  /// player under the lyrics doubled the cost of each frame.
  Animation<double> opacityUnderOpaque(Animation<double> secondary) =>
      _underOpaque ??= _PopFade(
        secondary,
        navigator?.userGestureInProgressNotifier,
        (t) => 1 - pageFadeOut.transform(t),
      );
  _PopFade? _underOpaque;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    final covers = nextRoute is AppPageRoute && !nextRoute.fadesIn;
    if (covers == _nextCovers) return;
    _nextCovers = covers;
    changedInternalState();
  }

  static const _shellPace = Duration(milliseconds: 350);

  static bool get _paced => NativeShell.active || MobileChrome.instance.enabled;

  /// The page's widget type, for the transition log when the route has no
  /// name.
  @override
  String? pageName;

  @override
  Widget buildContent(BuildContext context) {
    final page = super.buildContent(context);
    pageName ??= page.runtimeType.toString();
    return page;
  }

  /// On Android the slide's clock starts with the first frame that shows the
  /// page. A push lays the new page out in its first frame (offstage, for
  /// heroes) and that frame can take 30–45 ms on 77; counted from it, the
  /// first visible frame was already a seventh of the way across and the
  /// page jumped.
  @override
  AnimationController createAnimationController() {
    final controller = defaultTargetPlatform != TargetPlatform.android
        ? super.createAnimationController()
        : AnimationController(
            duration: transitionDuration,
            reverseDuration: reverseTransitionDuration,
            debugLabel: debugLabel,
            vsync: SlowFirstFrameVsync(navigator!),
          );
    // Tells the transition log in which frame the slide ended, so what
    // happens just after it is not counted as part of it.
    return controller..addStatusListener((status) {
      if (status.isAnimating) {
        // The sky and lights behind the pages wait for the slide.
        AmbientClock.quietBackdrops(
          (status == AnimationStatus.forward
                  ? transitionDuration
                  : reverseTransitionDuration) +
              const Duration(milliseconds: 100),
        );
      } else {
        TransitionProfiler.noteSettled();
      }
    });
  }

  @override
  Duration get transitionDuration =>
      _paced ? _shellPace : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _paced ? _shellPace : super.reverseTransitionDuration;
}

/// How a page fades in as it arrives, and under another as that one comes
/// and goes.
const pageFadeIn = Interval(.15, .75);
const pageFadeOut = Interval(0, .45);

/// Whole while a route animation runs forward (or a back swipe drags it),
/// and [fade] of its value while it is popped.
class _PopFade extends Animation<double> with AnimationWithParentMixin<double> {
  _PopFade(this.parent, this.gesture, this.fade);

  @override
  final Animation<double> parent;
  final ValueListenable<bool>? gesture;
  final double Function(double) fade;

  AnimationStatus? _seen;
  bool _fading = false;

  @override
  double get value {
    final status = parent.status;
    if (status != _seen) {
      _seen = status;
      if (status == AnimationStatus.reverse) {
        // A swipe the finger let go of keeps the look it had while dragged.
        _fading = !(gesture?.value ?? false);
      } else if (status != AnimationStatus.dismissed) {
        _fading = false;
      }
    }
    return _fading ? fade(parent.value) : 1;
  }
}

/// Hands out tickers whose clock leaves out what a run's first frame took
/// beyond an ordinary frame, so an animation that starts with a slow frame
/// still moves one frame's worth on the next one instead of jumping ahead.
@visibleForTesting
class SlowFirstFrameVsync implements TickerProvider {
  const SlowFirstFrameVsync(this.vsync);

  final TickerProvider vsync;

  /// An ordinary frame at 60 Hz; faster screens fit two inside it.
  static const _frame = Duration(microseconds: 16667);

  /// At most this much is left out: a first frame that slow is a stall, and
  /// the slide should still end about when it would have.
  static const _most = Duration(milliseconds: 150);

  @override
  Ticker createTicker(TickerCallback onTick) {
    Duration? lost;
    return vsync.createTicker((elapsed) {
      if (elapsed == Duration.zero) {
        // A new run (push, pop or a settling swipe) starts its clock here.
        lost = null;
      } else {
        lost ??= elapsed <= _frame
            ? Duration.zero
            : elapsed - _frame > _most
            ? _most
            : elapsed - _frame;
      }
      onTick(elapsed - (lost ?? Duration.zero));
    });
  }
}

/// Runs [action] once the page around [context] has finished sliding in, or
/// after this frame when it is already in place. Work that notifies the whole
/// app (loading lyrics, recording usage) waits for it, so the push itself
/// only draws frames.
void afterRouteEntrance(BuildContext context, VoidCallback action) {
  final route = ModalRoute.of(context);
  if (route == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
    return;
  }
  _afterEntrance(route, action);
}

void _afterEntrance(ModalRoute<Object?> route, VoidCallback action) {
  if (!route.isActive) return;
  // A pushed page's first frame is laid out offstage so heroes can measure
  // it, and meanwhile its animation reads as complete: look again once it is
  // on stage rather than run in the middle of the slide.
  if (route.offstage) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _afterEntrance(route, action),
    );
    WidgetsBinding.instance.scheduleFrame();
    return;
  }
  final animation = route.animation;
  if (animation == null || animation.isCompleted) {
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
    return;
  }
  void listener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      animation.removeStatusListener(listener);
      action();
    } else if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      // Closed before it opened: nothing to do.
      animation.removeStatusListener(listener);
    }
  }

  animation.addStatusListener(listener);
}
