import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../data/music_cache.dart';

class PrefetchRetryPolicy {
  const PrefetchRetryPolicy();

  Duration delay(int failureIndex, {Duration? retryAfter, int jitterMs = 0}) {
    final lowerBound = switch (failureIndex) {
      0 => const Duration(seconds: 5),
      1 => const Duration(seconds: 15),
      2 => const Duration(seconds: 30),
      _ => const Duration(seconds: 60),
    };
    final server = retryAfter ?? Duration.zero;
    final base = server > lowerBound ? server : lowerBound;
    return base + Duration(milliseconds: jitterMs.clamp(0, 1000));
  }
}

class PrefetchFailure {
  const PrefetchFailure({this.definitive = false, this.retryAfter});

  final bool definitive;
  final Duration? retryAfter;
}

PrefetchFailure classifyAudioPrefetchFailure(Object error) {
  if (error is AudioRetryAfterException) {
    return PrefetchFailure(retryAfter: error.retryAfter);
  }
  if (error is AudioTruncatedException) {
    return const PrefetchFailure();
  }
  if (error is AudioValidationException || error is UnsupportedError) {
    return const PrefetchFailure(definitive: true);
  }
  if (error is HttpException &&
      RegExp(r'\b(404|410)\b').hasMatch(error.message)) {
    return const PrefetchFailure(definitive: true);
  }
  return const PrefetchFailure();
}

class NextTrackPrefetch {
  NextTrackPrefetch({
    required this.prepare,
    required this.classify,
    this.nextAfterDefinitive,
    this.onCancel,
    Timer Function(Duration, void Function())? schedule,
    int Function()? jitterMs,
    DateTime Function()? now,
    PrefetchRetryPolicy policy = const PrefetchRetryPolicy(),
  }) : _schedule = schedule ?? ((delay, action) => Timer(delay, action)),
       _jitterMs = jitterMs ?? (() => Random().nextInt(501)),
       _now = now ?? DateTime.now,
       _policy = policy;

  final Future<void> Function(String trackId) prepare;
  final PrefetchFailure Function(Object error) classify;
  final String? Function(String failedTrackId)? nextAfterDefinitive;
  final void Function(String trackId)? onCancel;
  final Timer Function(Duration, void Function()) _schedule;
  final int Function() _jitterMs;
  final DateTime Function() _now;
  final PrefetchRetryPolicy _policy;

  Timer? _timer;
  int _generation = 0;
  String? _trackId;
  bool _online = true;
  bool _waitingForNetwork = false;
  bool _inFlight = false;
  int _failures = 0;
  DateTime? _nextAllowedAt;

  String? get trackId => _trackId;

  void activate(String trackId) {
    if (_trackId == trackId) return;
    cancel();
    _trackId = trackId;
    if (_online && !_inFlight) _attempt(_generation);
    if (!_online) _waitingForNetwork = true;
  }

  void setOnline(bool online) {
    if (_online == online) return;
    _online = online;
    if (!online) {
      _timer?.cancel();
      _timer = null;
      _waitingForNetwork = _trackId != null;
    } else if (_waitingForNetwork && _trackId != null) {
      _waitingForNetwork = false;
      if (!_inFlight) _scheduleOrAttempt(_generation);
    }
  }

  void cancel() {
    _generation += 1;
    if (_inFlight && _trackId != null) onCancel?.call(_trackId!);
    _timer?.cancel();
    _timer = null;
    _trackId = null;
    _waitingForNetwork = false;
    _failures = 0;
    _nextAllowedAt = null;
  }

  void _scheduleOrAttempt(int generation) {
    final remaining = _nextAllowedAt?.difference(_now()) ?? Duration.zero;
    if (remaining <= Duration.zero) {
      _attempt(generation);
    } else {
      _timer = _schedule(remaining, () {
        _timer = null;
        _attempt(generation);
      });
    }
  }

  Future<void> _attempt(int generation) async {
    final track = _trackId;
    if (track == null || generation != _generation || !_online || _inFlight) {
      return;
    }
    _inFlight = true;
    try {
      await prepare(track);
      if (generation == _generation) {
        _trackId = null;
        _timer = null;
      }
    } catch (error) {
      if (generation != _generation) return;
      final failure = classify(error);
      if (failure.definitive) {
        _trackId = null;
        final following = nextAfterDefinitive?.call(track);
        if (following != null && following != track) activate(following);
        return;
      }
      final delay = _policy.delay(
        _failures++,
        retryAfter: failure.retryAfter,
        jitterMs: _jitterMs(),
      );
      _nextAllowedAt = _now().add(delay);
      if (!_online) {
        _waitingForNetwork = true;
        return;
      }
      _timer = _schedule(delay, () {
        _timer = null;
        _attempt(generation);
      });
    } finally {
      _inFlight = false;
      if (generation != _generation && _trackId != null && _online) {
        _scheduleOrAttempt(_generation);
      }
    }
  }
}
