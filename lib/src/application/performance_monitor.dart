import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/operation_log.dart';

class ProcessCounters {
  const ProcessCounters({
    required this.cpuTimeMs,
    required this.elapsedTimeMs,
    required this.memoryBytes,
    required this.memoryKind,
  });
  final double cpuTimeMs, elapsedTimeMs;
  final int memoryBytes;
  final String memoryKind;

  double? cpuPercentSince(ProcessCounters? previous) {
    if (previous == null) return null;
    final elapsed = elapsedTimeMs - previous.elapsedTimeMs;
    final used = cpuTimeMs - previous.cpuTimeMs;
    return elapsed > 0 && used >= 0 ? used / elapsed * 100 : null;
  }
}

class NativePerformanceSampler {
  NativePerformanceSampler({bool? supported})
    : supported =
          supported ??
          (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS));
  static const channel = MethodChannel('ai_music/performance');
  final bool supported;

  Future<ProcessCounters?> sample() async {
    if (!supported) return null;
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('sample');
      if (data == null) return null;
      final cpu = (data['cpuTimeMs'] as num).toDouble();
      final elapsed = (data['elapsedTimeMs'] as num).toDouble();
      final memory = (data['memoryBytes'] as num).toInt();
      if (!cpu.isFinite ||
          !elapsed.isFinite ||
          cpu < 0 ||
          elapsed < 0 ||
          memory < 0) {
        throw const FormatException('Invalid process counters');
      }
      return ProcessCounters(
        cpuTimeMs: cpu,
        elapsedTimeMs: elapsed,
        memoryBytes: memory,
        memoryKind: data['memoryKind'] as String,
      );
    } on MissingPluginException {
      // A cached audio engine may start Dart before its Activity installs the
      // bridge. Retry on mobile rather than disabling counters for the session.
      return null;
    }
  }
}

class FrameObservation {
  const FrameObservation(this.uiMs, this.rasterMs, this.totalMs);
  final double uiMs, rasterMs, totalMs;
  double get busyMs => math.max(uiMs, rasterMs);
}

class FrameSummary {
  const FrameSummary({
    required this.fps,
    required this.frames,
    required this.slowFrames,
    required this.p95UiMs,
    required this.p95RasterMs,
    required this.worst,
    required this.periodMs,
    required this.refreshRate,
    required this.maxUiMs,
    required this.maxRasterMs,
  });
  final double fps, p95UiMs, p95RasterMs, periodMs, refreshRate;
  final double maxUiMs, maxRasterMs;
  final int frames, slowFrames;
  final FrameObservation worst;
  bool get idle => fps <= 2 && slowFrames == 0;
  Map<String, Object?> toJson() => {
    'fps': fps,
    'frames': frames,
    'slowFrames': slowFrames,
    'uiP95Ms': p95UiMs,
    'rasterP95Ms': p95RasterMs,
    'maxUiMs': maxUiMs,
    'maxRasterMs': maxRasterMs,
    'maxTotalMs': worst.totalMs,
    'periodMs': periodMs,
    'displayHz': refreshRate,
    'idle': idle,
  };
}

/// Bounded frame history. Engine timings are batched in release; a two-second
/// window avoids treating the arrival of a batch as an instantaneous FPS spike.
class FrameAccumulator {
  final _frames = <FrameObservation>[];
  int _count = 0;
  bool get hasFrames => _count > 0;

  void add(Iterable<FrameObservation> frames) {
    for (final frame in frames) {
      _count++;
      if (_frames.length == 2400) _frames.removeAt(0);
      _frames.add(frame);
    }
  }

  void clear() {
    _frames.clear();
    _count = 0;
  }

  FrameSummary drain(Duration elapsed, double hz) {
    final rate = hz.isFinite && hz > 0 ? hz : 60.0;
    final budget = 1000 / rate;
    double percentile(Iterable<double> values) {
      final sorted = values.toList()..sort();
      return sorted.isEmpty ? 0 : sorted[(sorted.length * .95).ceil() - 1];
    }

    var worst = const FrameObservation(0, 0, 0);
    var maxUi = 0.0, maxRaster = 0.0;
    for (final frame in _frames) {
      if (frame.totalMs > worst.totalMs) worst = frame;
      maxUi = math.max(maxUi, frame.uiMs);
      maxRaster = math.max(maxRaster, frame.rasterMs);
    }
    final result = FrameSummary(
      fps: elapsed.inMicroseconds <= 0
          ? 0
          : _count * 1000000 / elapsed.inMicroseconds,
      frames: _count,
      slowFrames: _frames.where((f) => f.busyMs > budget + .1).length,
      p95UiMs: percentile(_frames.map((f) => f.uiMs)),
      p95RasterMs: percentile(_frames.map((f) => f.rasterMs)),
      worst: worst,
      periodMs: elapsed.inMicroseconds / 1000,
      refreshRate: rate,
      maxUiMs: maxUi,
      maxRasterMs: maxRaster,
    );
    clear();
    return result;
  }
}

class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.frames,
    this.cpuPercent,
    this.memoryMiB,
    this.memoryKind,
  });
  final FrameSummary frames;
  final double? cpuPercent, memoryMiB;
  final String? memoryKind;
}

class PerformanceMonitor extends ChangeNotifier with WidgetsBindingObserver {
  PerformanceMonitor({
    Future<ProcessCounters?> Function()? sampleProcess,
    Duration Function()? now,
    double Function()? displayHz,
    Map<String, Object?> Function()? context,
    void Function(String, Map<String, Object?>)? log,
    this.automaticSampling = true,
  }) : _sampleProcess = sampleProcess ?? NativePerformanceSampler().sample,
       _nowProvider = now,
       _displayHz = displayHz ?? _currentDisplayHz,
       _context = context ?? (() => const {}),
       _log = log ?? OperationLog.event;

  final Future<ProcessCounters?> Function() _sampleProcess;
  final Duration Function()? _nowProvider;
  final double Function() _displayHz;
  final Map<String, Object?> Function() _context;
  final void Function(String, Map<String, Object?>) _log;
  final bool automaticSampling;
  final _clock = Stopwatch()..start();
  final _window = FrameAccumulator(), _logWindow = FrameAccumulator();
  late final routes = PerformanceRouteObserver(this);
  Timer? _timer;
  bool enabled = false, _active = false, _disposed = false, _sampling = false;
  bool _unavailableLogged = false;
  int _generation = 0;
  Duration _lastSample = Duration.zero, _lastLog = Duration.zero;
  Duration _lastHeartbeat = Duration.zero;
  Duration _lastJank = const Duration(seconds: -10);
  ProcessCounters? _previous;
  PerformanceSnapshot? snapshot;
  double? _peakCpu, _peakMemory;
  String route = '/', tab = 'home';
  Map<String, Object?> _sampleContext = const {};
  Duration get _now => _nowProvider?.call() ?? _clock.elapsed;
  bool get active => _active;

  static double _currentDisplayHz() =>
      WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .firstOrNull
          ?.display
          .refreshRate ??
      60;

  Map<String, Object?> get _details => {
    ..._context(),
    'route': route,
    'tab': tab,
  };

  void setEnabled(bool value) {
    if (_disposed || enabled == value) return;
    enabled = value;
    _unavailableLogged = false;
    _log('performance.monitor', {
      ..._details,
      'enabled': value,
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    });
    if (value) {
      WidgetsBinding.instance.addObserver(this);
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) _start();
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _stop();
    }
    notifyListeners();
  }

  void setTab(String value) {
    if (tab == value) return;
    contextWillChange('tab');
    tab = value;
    OperationLog.event('navigation.tab', {'tab': value});
  }

  void setRoute(String value) {
    if (route == value) return;
    contextWillChange('route');
    route = value;
    OperationLog.event('navigation.route', {'route': value, 'tab': tab});
  }

  /// Finish the frame log segment before its skin/page changes. Process CPU
  /// stays continuous across navigation; sample logs identify both ends of
  /// a measurement window that spans a page or skin change.
  void contextWillChange(String reason) {
    if (!_active || _disposed) return;
    final now = _now;
    if (_logWindow.hasFrames && now > _lastLog) {
      final frames = _logWindow.drain(now - _lastLog, _displayHz());
      _log('performance.sample', {
        ..._details,
        ...frames.toJson(),
        'reason': '${reason}_change',
        'cpuPercent': snapshot?.cpuPercent,
        'memoryMiB': snapshot?.memoryMiB,
        'memoryKind': snapshot?.memoryKind,
      });
    }
    _lastLog = now;
    _logWindow.clear();
    _peakCpu = _peakMemory = null;
  }

  void _start() {
    if (_active || _disposed || !enabled) return;
    _active = true;
    _generation++;
    _previous = null;
    snapshot = null;
    _peakCpu = _peakMemory = null;
    _lastSample = _lastLog = _now;
    _sampleContext = _details;
    _lastHeartbeat = _now;
    _lastJank = _now - const Duration(seconds: 10);
    _window.clear();
    _logWindow.clear();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    if (automaticSampling) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        final now = _now;
        final gap = now - _lastHeartbeat;
        _lastHeartbeat = now;
        if (gap > const Duration(milliseconds: 2500)) {
          _log('performance.stall', {
            ..._details,
            'delayMs': gap.inMilliseconds - 2000,
          });
        }
        unawaited(sampleNow());
      });
    }
  }

  void _stop() {
    _generation++;
    if (_active) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _active = false;
    _timer?.cancel();
    _timer = null;
    _previous = null;
    _window.clear();
    _logWindow.clear();
  }

  void _timings(List<FrameTiming> values) => recordFrames(
    values.map(
      (f) => FrameObservation(
        f.buildDuration.inMicroseconds / 1000,
        f.rasterDuration.inMicroseconds / 1000,
        f.totalSpan.inMicroseconds / 1000,
      ),
    ),
  );

  @visibleForTesting
  void recordFrames(Iterable<FrameObservation> values) {
    if (!_active) return;
    final frames = values.toList(growable: false);
    _window.add(frames);
    _logWindow.add(frames);
  }

  Future<void> sampleNow() async {
    if (!_active || _disposed || _sampling) return;
    _sampling = true;
    final generation = _generation;
    ProcessCounters? counters;
    try {
      counters = await _sampleProcess();
    } catch (error) {
      if (_active &&
          !_disposed &&
          generation == _generation &&
          !_unavailableLogged) {
        _unavailableLogged = true;
        _log('performance.unavailable', {
          ..._details,
          'error': error.toString(),
        });
      }
    } finally {
      _sampling = false;
    }
    if (!_active || _disposed || generation != _generation) return;
    if (counters == null && !_unavailableLogged) {
      _unavailableLogged = true;
      _log('performance.unavailable', {
        ..._details,
        'error': 'Process metrics are unavailable on this platform',
      });
    }
    final now = _now;
    final sceneWindow = <String, Object?>{
      'windowContextStart': _sampleContext,
      'windowContextEnd': _details,
    };
    _sampleContext = _details;
    final summary = _window.drain(now - _lastSample, _displayHz());
    _lastSample = now;
    final cpu = counters?.cpuPercentSince(_previous);
    final memory = counters == null
        ? null
        : counters.memoryBytes / (1024 * 1024);
    _previous = counters;
    if (cpu != null) _peakCpu = math.max(_peakCpu ?? cpu, cpu);
    if (memory != null) _peakMemory = math.max(_peakMemory ?? memory, memory);
    snapshot = PerformanceSnapshot(
      frames: summary,
      cpuPercent: cpu,
      memoryMiB: memory,
      memoryKind: counters?.memoryKind,
    );
    final resources = <String, Object?>{
      'cpuPercent': cpu,
      'memoryMiB': memory,
      'memoryKind': counters?.memoryKind,
    };
    if (summary.worst.totalMs >= 100 &&
        now - _lastJank >= const Duration(seconds: 5)) {
      _lastJank = now;
      _log('performance.jank', {
        ..._details,
        ...sceneWindow,
        ...summary.toJson(),
        ...resources,
      });
    }
    if (now - _lastLog >= const Duration(seconds: 10)) {
      final combined = _logWindow.drain(now - _lastLog, _displayHz());
      _lastLog = now;
      _log('performance.sample', {
        ..._details,
        ...sceneWindow,
        ...combined.toJson(),
        ...resources,
        'peakCpuPercent': _peakCpu,
        'peakMemoryMiB': _peakMemory,
      });
      _peakCpu = _peakMemory = null;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled || _disposed) return;
    _log('performance.lifecycle', {..._details, 'state': state.name});
    state == AppLifecycleState.resumed ? _start() : _stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (enabled) WidgetsBinding.instance.removeObserver(this);
    _stop();
    _clock.stop();
    super.dispose();
  }
}

class PerformanceRouteObserver extends NavigatorObserver {
  PerformanceRouteObserver(this.monitor);
  final PerformanceMonitor monitor;
  final _stack = <Route<dynamic>>[];
  void _update() {
    final route = _stack.lastOrNull;
    monitor.setRoute(
      route?.settings.name ?? (route is PopupRoute ? 'dialog' : 'page'),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _stack.removeAt(index);
      } else {
        _stack[index] = newRoute;
      }
    }
    _update();
  }
}
