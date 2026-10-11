import 'dart:math';

/// 管理随机播放里的“短时间跳过”候选。
///
/// 它只保存下一首选择策略，不修改真实播放队列、歌单或缓存列表。
class ShuffleSkipPlanner {
  ShuffleSkipPlanner({
    this.earlySkipThreshold = const Duration(seconds: 10),
    int? seed,
  }) : _random = Random(seed);

  final Duration earlySkipThreshold;
  final Random _random;
  List<String> _queueIds = const [];
  final Map<String, String> _plannedNext = {};
  final Set<String> _earlySkippedIds = <String>{};

  Set<String> get earlySkippedIds => Set.unmodifiable(_earlySkippedIds);

  void reset(List<String> ids) {
    _queueIds = List<String>.of(ids);
    _plannedNext.clear();
    _earlySkippedIds.clear();
  }

  void updateQueue(List<String> ids) {
    if (_sameIds(ids, _queueIds)) {
      return;
    }
    reset(ids);
  }

  String? nextAfter(String currentId, {required Duration position}) {
    return _nextAfter(currentId, markEarlySkip: position < earlySkipThreshold);
  }

  String? nextAfterCompleted(String currentId) {
    return _nextAfter(currentId, markEarlySkip: false);
  }

  String? peekNextAfter(String currentId) => _nextAllowedAfter(currentId);

  String? _nextAfter(String currentId, {required bool markEarlySkip}) {
    if (_queueIds.length <= 1 || !_queueIds.contains(currentId)) {
      return null;
    }
    if (markEarlySkip) {
      _earlySkippedIds.add(currentId);
    }
    if (_earlySkippedIds.length >= _queueIds.length) {
      _earlySkippedIds.clear();
    }

    if (_eligible(currentId).isEmpty) {
      _earlySkippedIds.clear();
    }
    final next = _nextAllowedAfter(currentId);
    // A peek reserves the next draw for preloading. Consume it exactly once,
    // so returning to this song draws again rather than repeating a fixed loop.
    _plannedNext.remove(currentId);
    return next;
  }

  String? _nextAllowedAfter(String currentId) {
    if (!_queueIds.contains(currentId)) return null;
    var eligible = _eligible(currentId);
    if (eligible.isEmpty) {
      // Predict the same release that the next actual skip will perform.
      eligible = _queueIds.where((id) => id != currentId).toList();
    }
    if (eligible.isEmpty) return null;
    final planned = _plannedNext[currentId];
    if (planned != null && eligible.contains(planned)) return planned;
    return _plannedNext[currentId] = eligible[_random.nextInt(eligible.length)];
  }

  List<String> _eligible(String currentId) => _queueIds
      .where((id) => id != currentId && !_earlySkippedIds.contains(id))
      .toList();
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
