import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../data/operation_log.dart';

/// Watches every page change (push, pop, back swipe, tab and section
/// switch) for dropped frames, and logs the ones that stuttered with hints
/// at why, so a stutter someone felt can be found in their uploaded logs.
///
/// Always on, release included: between page changes it costs one null
/// check a frame. Release reports frame timings in batches up to a second
/// late, so each change keeps the engine's numbers of the frames it drew and
/// is judged once those frames' timings arrive.
///
/// What a log entry's `hints` mean, and what fixed each before, is in
/// `docs/performance-diagnostics.md`.
class TransitionProfiler extends NavigatorObserver with WidgetsBindingObserver {
  TransitionProfiler({
    void Function(String, Map<String, Object?>)? log,
    Map<String, Object?> Function()? context,
    double Function()? displayHz,
    int Function()? frameNumber,
    @visibleForTesting this.summaryEvery = 40,
  }) : _log = log ?? OperationLog.event,
       _context = context ?? (() => const {}),
       _displayHz = displayHz ?? _currentDisplayHz,
       _frameNumber =
           frameNumber ??
           (() => PlatformDispatcher.instance.frameData.frameNumber);

  /// The app's profiler, once [install]ed.
  static TransitionProfiler? instance;

  /// The page change's animation finished in this frame.
  static void noteSettled() => instance?._noteSettled();

  /// Writes the per-page summary now, so an uploaded log has it.
  static void flushSummary() => instance?._summarize('upload');

  /// Something app-wide notified its listeners. Inside a page change that
  /// rebuilds pages mid-slide; the caller is kept to say who did it.
  static void noteNotify(Object source) => instance?._noteNotify(source);

  /// A change inside a page that animates like a page change, such as the
  /// downloads page's sections.
  static void noteSwitch(String from, String to, {String kind = 'section'}) {
    if (from != to) instance?.begin(kind, from: from, to: to);
  }

  final void Function(String, Map<String, Object?>) _log;
  final Map<String, Object?> Function() _context;
  final double Function() _displayHz;
  final int Function() _frameNumber;
  final int summaryEvery;

  _Window? _open;
  final _waiting = <_Window>[];
  final _opened = <String>{};
  final _stats = <String, _Stats>{};
  int _sinceSummary = 0;
  bool _installed = false;
  Timer? _close;

  static double _currentDisplayHz() {
    final hz = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .firstOrNull
        ?.display
        .refreshRate;
    return hz != null && hz.isFinite && hz > 0 ? hz : 60;
  }

  void install() {
    if (_installed) return;
    _installed = true;
    instance = this;
    SchedulerBinding.instance
      ..addTimingsCallback(addTimings)
      ..addPersistentFrameCallback((_) => recordFrame());
    WidgetsBinding.instance.addObserver(this);
  }

  static const _grace = Duration(milliseconds: 200);

  /// Opens a window over a change from [from] to [to] whose animation runs
  /// [duration]. A change still open is closed first.
  void begin(
    String kind, {
    required String from,
    required String to,
    Duration duration = const Duration(milliseconds: 450),
  }) {
    _finishOpen();
    final key = '$kind:$to';
    _open = _Window(
      kind: kind,
      from: from,
      to: to,
      firstOpen: _opened.add(key),
      slide: duration,
    );
    // Room after the animation for its last frames and what follows them.
    _close = Timer(duration + _grace, _finishOpen);
    // A change that draws nothing (it was instant) still closes.
    SchedulerBinding.instance.scheduleFrame();
  }

  /// Closes the open change now, as its timer would.
  @visibleForTesting
  void finish() => _finishOpen();

  void _finishOpen() {
    _close?.cancel();
    _close = null;
    final window = _open;
    _open = null;
    if (window == null || window.first == null) return;
    window.closedAt = DateTime.now();
    _waiting.add(window);
    _judgeWaiting();
  }

  /// Called once a frame, inside the frame.
  @visibleForTesting
  void recordFrame() {
    final window = _open;
    if (window == null) return;
    final number = _frameNumber();
    if (number < 0) return;
    window.first ??= number;
    window.last = number;
  }

  void _noteSettled() {
    final window = _open;
    if (window == null || window.settled != null) return;
    final number = _frameNumber();
    if (number >= 0) window.settled = number;
  }

  void _noteNotify(Object source) {
    final window = _open;
    if (window == null || window.notifies.length >= 8) return;
    window.notifies.add(
      _Notify(
        source: source.runtimeType.toString(),
        afterFrame: _frameNumber(),
        caller: _caller(StackTrace.current),
      ),
    );
  }

  /// The first frame of [trace] outside the notifier machinery, as
  /// `Class.method`, which is what someone fixing it needs to see.
  static String? _caller(StackTrace trace) {
    for (final line in trace.toString().split('\n')) {
      final match = RegExp(r'#\d+\s+(\S+)').firstMatch(line);
      final member = match?.group(1);
      if (member == null ||
          member.contains('notifyListeners') ||
          member.contains('noteNotify') ||
          member.contains('_noteNotify') ||
          member.contains('TransitionProfiler') ||
          member.startsWith('<')) {
        continue;
      }
      return member;
    }
    return null;
  }

  /// The engine's timings, in batches.
  @visibleForTesting
  void addTimings(List<FrameTiming> timings) {
    if (_waiting.isEmpty && _open == null) return;
    for (final timing in timings) {
      final number = timing.frameNumber;
      for (final window in [..._waiting, ?_open]) {
        final first = window.first;
        if (first == null) continue;
        final last = identical(window, _open) ? number : window.last!;
        if (number >= first && number <= last) window.frames[number] = timing;
        if (number > window.seen) window.seen = number;
      }
    }
    _judgeWaiting();
  }

  void _judgeWaiting() {
    final now = DateTime.now();
    _waiting.removeWhere((window) {
      if (window.seen >= window.last!) {
        _judge(window);
        return true;
      }
      // Timings that never came (the app went to the background).
      return now.difference(window.closedAt!) > const Duration(seconds: 5);
    });
  }

  void _judge(_Window window) {
    final frames = [
      for (var n = window.first!; n <= window.last!; n++) ?window.frames[n],
    ];
    if (frames.isEmpty) return;
    final hz = _displayHz();
    final budget = 1000 / hz;
    double ms(Duration value) => value.inMicroseconds / 1000;
    int vsync(FrameTiming f) =>
        f.timestampInMicroseconds(FramePhase.vsyncStart);
    double gap(FrameTiming a, FrameTiming b) => (vsync(b) - vsync(a)) / 1000;
    // The frames of the change itself: those within its animation, less a
    // tail that has thinned out (a settled page redraws a few times a second,
    // and those gaps are not drops).
    final end =
        vsync(frames.first) +
        window.slide.inMicroseconds +
        (budget * 1000).round();
    // Routes say in which frame their animation ended; for the rest it is
    // reckoned from its length.
    final settled = window.settled;
    final during = frames
        .where(
          (f) => settled != null ? f.frameNumber <= settled : vsync(f) <= end,
        )
        .toList();
    while (settled == null &&
        during.length > 2 &&
        gap(during[during.length - 2], during.last) > 1.5 * budget) {
      during.removeLast();
    }
    final after = frames.skip(during.length).toList();
    final first = frames.first;
    final slide = during.skip(1).toList();
    var dropped = 0;
    for (var i = 1; i < slide.length; i++) {
      dropped += math.max(
        0,
        (gap(slide[i - 1], slide[i]) / budget).round() - 1,
      );
    }
    final overUi = slide.where((f) => ms(f.buildDuration) > budget).length;
    final overRaster = slide.where((f) => ms(f.rasterDuration) > budget).length;
    final worstUi = slide.fold(0.0, (m, f) => math.max(m, ms(f.buildDuration)));
    final worstRaster = slide.fold(
      0.0,
      (m, f) => math.max(m, ms(f.rasterDuration)),
    );
    final afterUi = after.fold(0.0, (m, f) => math.max(m, ms(f.buildDuration)));
    final firstUi = ms(first.buildDuration);
    final firstRaster = ms(first.rasterDuration);
    // A notification affects the frame after the one drawn when it came.
    final lastDuring = during.last.frameNumber;
    final midSlide = window.notifies.where((n) => n.afterFrame < lastDuring);
    final afterSlide = window.notifies.where((n) => n.afterFrame >= lastDuring);
    final hints = <String>[
      if (firstUi > 3 * budget) 'first_frame_build',
      if (overUi > 0 && midSlide.isNotEmpty) 'notify_mid_slide',
      if (overUi > 0 && midSlide.isEmpty) 'ui_mid_slide',
      if (window.firstOpen && math.max(firstRaster, worstRaster) > 2 * budget)
        'raster_first_open',
      if (overRaster >= 2 && !window.firstOpen) 'raster_heavy',
      if (afterUi > 3 * budget && afterSlide.isNotEmpty) 'notify_after_slide',
    ];
    final janky =
        dropped >= 2 ||
        overUi + overRaster >= 3 ||
        firstUi > 4 * budget ||
        math.max(firstRaster, worstRaster) > 3 * budget ||
        afterUi > 3 * budget;
    final key = '${window.kind}:${window.to}';
    _stats
        .putIfAbsent(key, _Stats.new)
        .add(
          janky,
          dropped,
          math.max(firstUi, worstUi),
          math.max(firstRaster, worstRaster),
        );
    String round(double value) => value.toStringAsFixed(1);
    if (janky) {
      _log('perf.transition', {
        ..._context(),
        'kind': window.kind,
        'from': window.from,
        'to': window.to,
        'firstOpen': window.firstOpen,
        'frames': during.length,
        'dropped': dropped,
        'overBudgetUi': overUi,
        'overBudgetRaster': overRaster,
        'firstUiMs': round(firstUi),
        'firstRasterMs': round(firstRaster),
        'worstUiMs': round(worstUi),
        'worstRasterMs': round(worstRaster),
        if (after.isNotEmpty) 'afterSlideWorstUiMs': round(afterUi),
        'budgetMs': round(budget),
        'hints': hints,
        if (window.notifies.isNotEmpty)
          'notifies': [
            for (final n in window.notifies)
              {
                'source': n.source,
                'frame': n.afterFrame - window.first!,
                'caller': ?n.caller,
              },
          ],
      });
    }
    if (++_sinceSummary >= summaryEvery) _summarize('count');
  }

  void _summarize(String reason) {
    if (_stats.isEmpty) return;
    _sinceSummary = 0;
    _log('perf.transitions', {
      'reason': reason,
      'displayHz': _displayHz(),
      'pages': {for (final e in _stats.entries) e.key: e.value.toJson()},
    });
    _stats.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _summarize('background');
    // Coming back is a change too: the first frames redraw the whole page.
    // On the way back the states run hidden, inactive, resumed.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasHidden = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wasHidden) begin('resume', from: 'background', to: _top ?? 'app');
      _wasHidden = false;
    }
  }

  bool _wasHidden = false;
  String? _top;

  // Route changes.

  static String nameOf(Route<dynamic>? route) {
    if (route == null) return 'none';
    final name = route.settings.name;
    if (name == '/') return 'home';
    if (name != null) return name;
    if (route case NamedPageRoute(:final pageName)) return pageName ?? 'page';
    final type = route.runtimeType.toString();
    final generic = type.indexOf('<');
    return generic < 0 ? type : type.substring(0, generic);
  }

  static Duration _length(Route<dynamic> route, {bool reverse = false}) {
    final base = route is TransitionRoute
        ? (reverse ? route.reverseTransitionDuration : route.transitionDuration)
        : Duration.zero;
    // Room for the first frame, which can be slow, and the last ones.
    return base + const Duration(milliseconds: 150);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _top = nameOf(route);
    // The first route is the app starting, not a change someone makes.
    if (previousRoute == null) return;
    begin(
      route is PopupRoute ? 'popup' : 'push',
      from: nameOf(previousRoute),
      to: nameOf(route),
      duration: _length(route),
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _top = nameOf(previousRoute);
    if (_gesture) return;
    begin(
      route is PopupRoute ? 'popup_close' : 'pop',
      from: nameOf(route),
      to: nameOf(previousRoute),
      duration: _length(route, reverse: true),
    );
  }

  bool _gesture = false;

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    _gesture = true;
    begin(
      'swipe_back',
      from: nameOf(route),
      to: nameOf(previousRoute),
      // Held open until the finger lifts and the page settles.
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void didStopUserGesture() {
    _gesture = false;
    final window = _open;
    if (window == null || window.kind != 'swipe_back') return;
    _close?.cancel();
    _close = Timer(const Duration(milliseconds: 350) + _grace, _finishOpen);
  }
}

/// A page route that can say what page it shows, for routes pushed without
/// a name.
abstract interface class NamedPageRoute {
  String? get pageName;
}

class _Window {
  _Window({
    required this.kind,
    required this.from,
    required this.to,
    required this.firstOpen,
    required this.slide,
  });

  final String kind, from, to;
  final bool firstOpen;
  final Duration slide;
  final frames = <int, FrameTiming>{};
  final notifies = <_Notify>[];
  int? first, last, settled;
  int seen = -1;
  DateTime? closedAt;
}

class _Notify {
  const _Notify({required this.source, required this.afterFrame, this.caller});

  final String source;
  final int afterFrame;
  final String? caller;
}

class _Stats {
  int count = 0, janky = 0, dropped = 0;
  double worstUiMs = 0, worstRasterMs = 0;

  void add(bool isJanky, int droppedFrames, double ui, double raster) {
    count++;
    if (isJanky) janky++;
    dropped += droppedFrames;
    worstUiMs = math.max(worstUiMs, ui);
    worstRasterMs = math.max(worstRasterMs, raster);
  }

  Map<String, Object?> toJson() => {
    'n': count,
    'janky': janky,
    'dropped': dropped,
    'worstUiMs': double.parse(worstUiMs.toStringAsFixed(1)),
    'worstRasterMs': double.parse(worstRasterMs.toStringAsFixed(1)),
  };
}
