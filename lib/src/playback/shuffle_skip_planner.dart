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
  List<String> _order = const [];
  final Set<String> _earlySkippedIds = <String>{};

  List<String> get order => List.unmodifiable(_order);
  Set<String> get earlySkippedIds => Set.unmodifiable(_earlySkippedIds);

  void reset(List<String> ids) {
    _queueIds = List<String>.of(ids);
    _order = List<String>.of(ids);
    _shuffle(_order);
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

  String? _nextAfter(String currentId, {required bool markEarlySkip}) {
    if (_order.length <= 1 || !_order.contains(currentId)) {
      return null;
    }
    if (markEarlySkip) {
      _earlySkippedIds.add(currentId);
    }
    if (_earlySkippedIds.length >= _order.length) {
      _earlySkippedIds.clear();
    }

    var next = _nextAllowedAfter(currentId);
    if (next != null) {
      return next;
    }

    // 如果剩余候选都被本轮短跳过，释放这一轮，继续沿用同一个随机顺序。
    _earlySkippedIds.clear();
    return _nextAllowedAfter(currentId);
  }

  String? _nextAllowedAfter(String currentId) {
    final currentIndex = _order.indexOf(currentId);
    for (var offset = 1; offset < _order.length; offset += 1) {
      final candidate = _order[(currentIndex + offset) % _order.length];
      if (candidate != currentId && !_earlySkippedIds.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  void _shuffle(List<String> values) {
    for (var i = values.length - 1; i > 0; i -= 1) {
      final j = _random.nextInt(i + 1);
      final value = values[i];
      values[i] = values[j];
      values[j] = value;
    }
  }
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
