import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';

import '../data/listening_stats_store.dart';
import '../playback/music_audio_handler.dart';

/// Counts confirmed playback advance, capped by monotonic elapsed real time.
/// Seeking only changes the baseline; a natural loop starts a new visit.
class ListeningTracker {
  ListeningTracker(this.store, {String? visitPrefix})
    : _prefix =
          visitPrefix ??
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  final ListeningStatsStore store;
  final String _prefix;
  ListeningContext? _context;
  String? _visit;
  int _serial = 0, _heardMs = 0;
  bool _qualified = false, _ready = false;
  double _speed = 1;
  Duration? _position, _elapsed;
  void resetPosition({bool automatic = false}) {
    _position = null;
    _elapsed = null;
    _ready = false;
    if (automatic) _context = null;
  }

  void reset() {
    _context = null;
    resetPosition();
  }

  void sample({
    required ListeningContext? context,
    required Duration position,
    required bool ready,
    required Duration elapsed,
    required DateTime at,
    double speed = 1,
  }) {
    if (context == null) {
      reset();
      return;
    }
    if (_context == null || !_context!.sameVisit(context)) {
      _visit = '$_prefix-${++_serial}';
      _heardMs = 0;
      _qualified = false;
      _position = null;
      _elapsed = null;
      _ready = false;
    }
    if (_ready && _position != null && _elapsed != null && _speed > 0) {
      final wallMs = (elapsed - _elapsed!).inMilliseconds;
      final audioMs = ((position - _position!).inMilliseconds / _speed).floor();
      final ms = min(wallMs, audioMs);
      if (ms > 0) {
        final start = at.subtract(Duration(milliseconds: ms));
        final duration = context.song.durationMs;
        final threshold = duration != null && duration > 0 && duration < 30000
            ? (duration / 2).ceil()
            : 30000;
        DateTime? qualifiedAt;
        if (!_qualified && _heardMs + ms >= threshold) {
          qualifiedAt = start.add(
            Duration(milliseconds: max(0, threshold - _heardMs)),
          );
          _qualified = true;
        }
        _heardMs += ms;
        store.addInterval(
          _visit!,
          context,
          start,
          at,
          qualifiedAt: qualifiedAt,
        );
      }
    }
    _context = context;
    _position = position;
    _elapsed = elapsed;
    _ready = ready;
    _speed = speed;
  }
}

class ListeningRecorder with WidgetsBindingObserver {
  ListeningRecorder({
    required this.handler,
    required this.store,
    required this.contextFor,
    DateTime Function()? now,
    Duration Function()? elapsed,
  }) : _now = now ?? DateTime.now,
       _elapsed = elapsed,
       tracker = ListeningTracker(store) {
    _clock.start();
    WidgetsBinding.instance.addObserver(this);
    _media = handler.mediaItem.listen((_) {
      capture();
      unawaited(store.flush());
    });
    _state = handler.playbackState.listen((_) {
      capture();
      if (!handler.playbackState.value.playing) unawaited(store.flush());
    });
    _discontinuities = handler.listeningDiscontinuities.listen((automatic) {
      tracker.resetPosition(automatic: automatic);
      capture();
      unawaited(store.flush());
    });
  }
  final MusicAudioHandler handler;
  final ListeningStatsStore store;
  final ListeningContext? Function(MediaItem) contextFor;
  final ListeningTracker tracker;
  final Stopwatch _clock = Stopwatch();
  final DateTime Function() _now;
  final Duration Function()? _elapsed;
  Duration get elapsed => _elapsed?.call() ?? _clock.elapsed;
  late final StreamSubscription<MediaItem?> _media;
  late final StreamSubscription<PlaybackState> _state;
  late final StreamSubscription<bool> _discontinuities;
  Timer? _timer;
  Duration _lastFlush = Duration.zero;
  bool _closed = false, _clearing = false;
  void capture() {
    if (_closed || _clearing) return;
    final state = handler.playbackState.value, item = handler.mediaItem.value;
    final terminal =
        state.processingState == AudioProcessingState.idle ||
        state.processingState == AudioProcessingState.completed ||
        state.processingState == AudioProcessingState.error;
    final ready =
        state.playing &&
        state.processingState == AudioProcessingState.ready &&
        handler.hasConsistentPlaybackItem;
    tracker.sample(
      context: item == null ? null : contextFor(item),
      position: handler.currentPosition,
      ready: ready,
      elapsed: elapsed,
      at: _now(),
      speed: state.speed,
    );
    if (terminal) tracker.reset();
    if (ready) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        capture();
        if (elapsed - _lastFlush >= const Duration(seconds: 10)) {
          _lastFlush = elapsed;
          unawaited(store.flush());
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> clear() async {
    capture();
    _clearing = true;
    tracker.reset();
    try {
      await store.clear();
    } finally {
      _clearing = false;
      capture();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    capture();
    unawaited(store.flush());
  }

  Future<void> close() async {
    capture();
    _closed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await Future.wait([
      _media.cancel(),
      _state.cancel(),
      _discontinuities.cancel(),
    ]);
    await store.flush();
    store.dispose();
  }
}
