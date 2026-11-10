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
  ///
  /// A [backdrop] clock moves what lies behind the pages (sky, lights,
  /// rain) and holds still while a page change animates; see
  /// [quietBackdrops].
  AmbientClock({int fps = beat, this.backdrop = false})
    : _every = (beat / fps).round().clamp(1, beat);

  final bool backdrop;

  static final _uptime = Stopwatch()..start();
  static Duration _quietUntil = Duration.zero;

  /// Monotonic time, replaceable in tests.
  @visibleForTesting
  static Duration Function() now = () => _uptime.elapsed;

  /// Holds the backdrop clocks for [length], from now.
  ///
  /// A step of the aurora repaints the whole sky and makes the glass bars
  /// blur it again: about 14 ms of raster on 77. At rest that is fifteen
  /// frames a second nobody misses, but during a page change at 90 Hz it
  /// landed on every fifth or sixth frame, and each one came late. The sky
  /// moves slowly, so a third of a second still is not seen; it resumes
  /// where it stopped.
  static void quietBackdrops(Duration length) {
    final until = now() + length;
    if (until > _quietUntil) _quietUntil = until;
  }

  static bool get _quiet => now() < _quietUntil;

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
          final quiet = AmbientClock._quiet;
          for (final clock in _clocks.toList()) {
            if (clock._running && !(quiet && clock.backdrop)) clock._beat();
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
