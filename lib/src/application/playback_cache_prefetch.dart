import 'dart:async';

class CachePrefetchCancelled implements Exception {
  const CachePrefetchCancelled();
}

class CachePrefetchToken {
  final _cancelled = Completer<void>();
  final _callbacks = <void Function()>[];
  bool get isCancelled => _cancelled.isCompleted;

  void check() {
    if (isCancelled) throw const CachePrefetchCancelled();
  }

  Future<T> wait<T>(Future<T> work) => Future.any([
    work,
    _cancelled.future.then<T>((_) => throw const CachePrefetchCancelled()),
  ]);

  void onCancel(void Function() callback) {
    if (isCancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final callback in _callbacks) {
      callback();
    }
    _callbacks.clear();
  }
}

/// One low-priority transfer at a time, with a bounded rolling queue window.
class PlaybackCachePrefetch {
  PlaybackCachePrefetch({
    required this.prepare,
    this.startDelay = const Duration(seconds: 1),
  });
  final Future<void> Function(String id, CachePrefetchToken token) prepare;
  final Duration startDelay;
  Timer? _timer;
  String? _plan;
  String? activeTrackId;
  int _generation = 0;
  CachePrefetchToken? _token;
  Future<void> _tail = Future.value();

  void activate(List<String> ids) {
    final plan = ids.join('\u001f');
    if (_plan == plan) return;
    unawaited(cancel());
    if (ids.isEmpty) return;
    _plan = plan;
    final generation = _generation;
    _timer = Timer(startDelay, () {
      _timer = null;
      _tail = _tail.then((_) => _run(ids, generation));
    });
  }

  Future<void> _run(List<String> ids, int generation) async {
    for (final id in ids) {
      if (generation != _generation) return;
      activeTrackId = id;
      final token = _token = CachePrefetchToken();
      try {
        await prepare(id, token);
      } catch (_) {
        // A failing next song must neither stop current audio nor block others.
      } finally {
        if (identical(_token, token)) {
          _token = null;
          activeTrackId = null;
        }
      }
    }
  }

  Future<void> cancel() {
    _generation++;
    _plan = null;
    _timer?.cancel();
    _timer = null;
    _token?.cancel();
    return _tail;
  }
}
