import 'package:flutter/foundation.dart';

/// A saved prefix is distinct from a verified, playable complete file.
class SongCacheProgress {
  const SongCacheProgress({
    this.fraction = 0,
    this.offline = false,
    this.active = false,
  });
  final double? fraction;
  final bool offline;
  final bool active;
  @override
  bool operator ==(Object other) =>
      other is SongCacheProgress &&
      fraction == other.fraction &&
      offline == other.offline &&
      active == other.active;
  @override
  int get hashCode => Object.hash(fraction, offline, active);
}

class SongCacheProgressController {
  final _values = <String, ValueNotifier<SongCacheProgress>>{};
  final _partial = <String, SongCacheProgress>{};
  final _downloads = <String, SongCacheProgress>{};
  Set<String> _complete = {};

  ValueListenable<SongCacheProgress> listenable(String key) =>
      _values.putIfAbsent(key, () => ValueNotifier(_value(key)));
  SongCacheProgress _value(String key) {
    final offline = _complete.contains(key);
    final download = _downloads[key];
    if (download != null) {
      return SongCacheProgress(
        fraction: download.fraction,
        active: true,
        offline: offline,
      );
    }
    if (offline) return const SongCacheProgress(fraction: 1, offline: true);
    return _partial[key] ?? const SongCacheProgress();
  }

  void _publish(String key) => _values[key]?.value = _value(key);
  void completeKeys(Set<String> keys) {
    final changed = {..._complete, ...keys};
    _complete = keys;
    for (final key in changed) {
      _publish(key);
    }
  }

  void download(String key, {required bool active, int bytes = 0, int? total}) {
    if (active) {
      _downloads[key] = SongCacheProgress(
        active: true,
        fraction: total == null || total <= 0
            ? null
            : (bytes / total).clamp(0, 1),
      );
    } else {
      _downloads.remove(key);
    }
    _publish(key);
  }

  void streaming(
    String key, {
    required int bytes,
    int? total,
    required bool active,
  }) {
    _partial[key] = SongCacheProgress(
      active: active,
      fraction: total == null || total <= 0
          ? (bytes == 0 ? 0 : null)
          : (bytes / total).clamp(0, 1),
    );
    _publish(key);
  }

  void stopStreaming(String key) {
    final prior = _partial[key];
    if (prior == null) return;
    _partial[key] = SongCacheProgress(fraction: prior.fraction);
    _publish(key);
  }

  void removePartial(String key) {
    _partial.remove(key);
    _publish(key);
  }

  void clearParts() {
    for (final key in _partial.keys.toList()) {
      removePartial(key);
    }
  }

  void replaceInactiveParts(Map<String, ({int bytes, int? total})> parts) {
    for (final key in {..._partial.keys, ...parts.keys}) {
      if (_partial[key]?.active == true) continue;
      final part = parts[key];
      if (part == null) {
        removePartial(key);
      } else {
        streaming(key, bytes: part.bytes, total: part.total, active: false);
      }
    }
  }

  void dispose() {
    for (final value in _values.values) {
      value.dispose();
    }
    _values.clear();
  }
}
