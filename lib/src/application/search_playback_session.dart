import 'dart:math';

import '../data/resolver_models.dart';
import '../domain/music_models.dart';

class SearchPlaybackSession {
  SearchPlaybackSession({
    required this.request,
    required this.query,
    required Iterable<MusicSearchCandidate> candidates,
    Random? random,
  }) : _random = random ?? Random() {
    append(candidates);
  }

  final int request;
  final String query;
  final Random _random;
  final List<MusicSearchCandidate> _candidates = [];
  final List<String> _shuffleOrder = [];
  final Set<String> _keys = {};
  String? _currentKey;

  List<MusicSearchCandidate> get candidates =>
      List<MusicSearchCandidate>.unmodifiable(_candidates);

  MusicSearchCandidate? get current => _candidateForKey(_currentKey);

  int get currentIndex {
    final key = _currentKey;
    return key == null
        ? -1
        : _candidates.indexWhere((item) => keyFor(item) == key);
  }

  bool contains(MusicSearchCandidate candidate) =>
      _keys.contains(keyFor(candidate));

  void append(Iterable<MusicSearchCandidate> incoming) {
    final newKeys = <String>[];
    for (final candidate in incoming) {
      final key = keyFor(candidate);
      if (_keys.add(key)) {
        _candidates.add(candidate);
        newKeys.add(key);
      }
    }
    newKeys.shuffle(_random);
    _shuffleOrder.addAll(newKeys);
  }

  bool select(MusicSearchCandidate candidate) {
    final key = keyFor(candidate);
    if (!_keys.contains(key)) {
      return false;
    }
    _currentKey = key;
    return true;
  }

  MusicSearchCandidate? candidateAt(int index) {
    if (index < 0 || index >= _candidates.length) {
      return null;
    }
    return _candidates[index];
  }

  MusicSearchCandidate? next(PlaybackMode mode, {required bool automatic}) {
    if (_candidates.isEmpty) {
      return null;
    }
    if (_currentKey == null) {
      return _selectKey(keyFor(_candidates.first));
    }
    if (mode == PlaybackMode.repeatOne && automatic) {
      return current;
    }
    if (mode == PlaybackMode.shuffle) {
      return _moveInShuffle(1);
    }
    final index = currentIndex;
    if (index >= 0 && index + 1 < _candidates.length) {
      return _selectKey(keyFor(_candidates[index + 1]));
    }
    if (mode == PlaybackMode.loopAll || mode == PlaybackMode.repeatOne) {
      return _selectKey(keyFor(_candidates.first));
    }
    return null;
  }

  MusicSearchCandidate? previous(PlaybackMode mode) {
    if (_candidates.isEmpty || _currentKey == null) {
      return null;
    }
    if (mode == PlaybackMode.shuffle) {
      return _moveInShuffle(-1);
    }
    final index = currentIndex;
    if (index > 0) {
      return _selectKey(keyFor(_candidates[index - 1]));
    }
    if (mode == PlaybackMode.loopAll || mode == PlaybackMode.repeatOne) {
      return _selectKey(keyFor(_candidates.last));
    }
    return null;
  }

  MusicSearchCandidate? _moveInShuffle(int delta) {
    if (_shuffleOrder.isEmpty) {
      return null;
    }
    final currentShuffleIndex = _shuffleOrder.indexOf(_currentKey!);
    if (currentShuffleIndex == -1) {
      return _selectKey(_shuffleOrder.first);
    }
    final nextIndex = (currentShuffleIndex + delta) % _shuffleOrder.length;
    return _selectKey(_shuffleOrder[nextIndex]);
  }

  MusicSearchCandidate? _selectKey(String key) {
    _currentKey = key;
    return _candidateForKey(key);
  }

  MusicSearchCandidate? _candidateForKey(String? key) {
    if (key == null) {
      return null;
    }
    return _candidates.where((item) => keyFor(item) == key).firstOrNull;
  }

  static String keyFor(MusicSearchCandidate candidate) {
    return '${candidate.source.storageValue}|${candidate.platform}|${candidate.id}';
  }
}
