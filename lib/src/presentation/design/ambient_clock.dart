import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_theme.dart';

/// Time for motion that never ends: rain, a turning record, a breathing lamp.
///
/// A [Ticker] would redraw these on every display refresh, 120 times a second
/// on recent iPhones, and every redraw makes the blurred glass above it blur
/// again. All ambient clocks instead step off one shared heartbeat of
/// [beat] per second, so however many of them run, the screen is redrawn at
/// most that often, and on the same frames. The heartbeat stops while the app
/// is in the background and when no clock is running.
class AmbientClock extends ChangeNotifier implements ValueListenable<double> {
  /// [fps] is rounded to a whole division of [beat]: 30, 15, 10…
  AmbientClock({int fps = beat}) : _every = (beat / fps).round().clamp(1, beat);

  /// Heartbeats per second, and so the most the screen redraws for ambient
  /// motion.
  static const beat = 30;

  final int _every;
  int _count = 0;
  double _seconds = 0;
  bool _running = false;

  /// Seconds this clock has run.
  @override
  double get value => _seconds;

  /// How long one step of this clock is.
  double get step => _every / beat;

  bool get running => _running;

  /// Whether ambient motion should run for [context]: not when the user asked
  /// for reduced motion, nor in a page or tab that is not showing.
  static bool wanted(BuildContext context) =>
      MusicMotion.allowsPerpetual(context) &&
      // flutter_ohos does not have TickerMode.valuesOf yet.
      // ignore: deprecated_member_use
      TickerMode.of(context);

  void run(bool on) {
    if (on == _running) return;
    _running = on;
    on ? _Heart.add(this) : _Heart.remove(this);
  }

  void _beat() {
    if (++_count % _every != 0) return;
    _seconds += step;
    notifyListeners();
  }

  @override
  void dispose() {
    run(false);
    super.dispose();
  }
}

/// The one timer behind every [AmbientClock].
class _Heart with WidgetsBindingObserver {
  _Heart._();

  static final _instance = _Heart._();
  static final _clocks = <AmbientClock>{};
  static Timer? _timer;
  static bool _foreground = true;
  static bool _observing = false;

  static void add(AmbientClock clock) {
    _clocks.add(clock);
    _sync();
  }

  static void remove(AmbientClock clock) {
    _clocks.remove(clock);
    _sync();
  }

  static void _sync() {
    final go = _clocks.isNotEmpty && _foreground;
    if (_clocks.isNotEmpty != _observing) {
      _observing = _clocks.isNotEmpty;
      _observing
          ? WidgetsBinding.instance.addObserver(_instance)
          : WidgetsBinding.instance.removeObserver(_instance);
    }
    if (go && _timer == null) {
      _timer = Timer.periodic(
        Duration(microseconds: (1e6 / AmbientClock.beat).round()),
        (_) {
          // A clock may stop itself, or another, while being stepped.
          for (final clock in _clocks.toList()) {
            if (clock._running) clock._beat();
          }
        },
      );
    } else if (!go) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }
}
