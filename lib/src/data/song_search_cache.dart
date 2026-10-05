import 'dart:async';
import 'dart:io';

import 'json_file_store.dart';
import 'music_resolver.dart';
import 'saved_online_track.dart';
import '../platform/app_storage.dart';

/// Candidate metadata only: media URLs must be resolved afresh before playback.
class SongSearchCache {
  SongSearchCache({
    Future<Directory> Function()? rootProvider,
    DateTime Function()? now,
    this.lifetime = const Duration(days: 1),
    this.maxEntries = 150,
  }) : _rootProvider = rootProvider ?? getAiMusicSupportDirectory,
       _now = now ?? DateTime.now;

  SongSearchCache.memory({DateTime Function()? now})
    : this(
        rootProvider: () async => throw UnsupportedError('Memory cache'),
        now: now,
      );

  final Future<Directory> Function() _rootProvider;
  final DateTime Function() _now;
  final Duration lifetime;
  final int maxEntries;
  final _entries =
      <String, ({DateTime at, List<MusicSearchCandidate> songs})>{};
  final _pending = <String, Future<List<MusicSearchCandidate>>>{};
  Future<void>? _loading;
  Future<void> _writeTail = Future.value();
  File? _file;

  static String searchKey(String query, MusicDataSource source) =>
      'search|${source.storageValue}|${query.trim().toLowerCase()}';

  Future<void> _load() => _loading ??= () async {
    try {
      _file = File('${(await _rootProvider()).path}/song_search_cache.json');
      final raw = await const JsonFileStore().read(_file!);
      if (raw is! Map || raw['schema'] != 1 || raw['entries'] is! List) return;
      for (final row in raw['entries'] as List) {
        try {
          if (row is! Map || row['key'] is! String || row['songs'] is! List) {
            continue;
          }
          final at = DateTime.parse(row['at'] as String);
          if (!_fresh(at)) continue;
          final songs = <MusicSearchCandidate>[];
          for (final item in row['songs'] as List) {
            final saved = SavedOnlineTrack.fromJson(item);
            if (saved == null) {
              throw const FormatException('Invalid candidate');
            }
            final c = saved.candidate;
            songs.add(
              MusicSearchCandidate(
                query: c.query,
                source: c.source,
                platform: c.platform,
                keyword: c.keyword,
                page: c.page,
                id: c.id,
                name: c.name,
                artist: c.artist,
                album: c.album,
                duration: c.duration,
                link: '',
                coverUrl: c.coverUrl,
                qualities: c.qualities,
                score: ((item as Map)['score'] as num?)?.toDouble() ?? 0,
                raw: c.raw,
              ),
            );
          }
          if (songs.isNotEmpty) {
            _entries[row['key'] as String] = (
              at: at,
              songs: List.unmodifiable(songs),
            );
          }
        } catch (_) {
          // One damaged record must not hide other cached searches.
        }
      }
      _prune();
    } catch (_) {
      // Disk cache failure never prevents an online search.
    }
  }();

  bool _fresh(DateTime at) =>
      !_now().isBefore(at) && _now().difference(at) < lifetime;

  Future<List<MusicSearchCandidate>> search(
    String key,
    Future<List<MusicSearchCandidate>> Function() loader, {
    bool refresh = false,
  }) async {
    await _load();
    final pending = _pending[key];
    if (pending != null) return pending;
    final entry = _entries[key];
    if (!refresh && entry != null && _fresh(entry.at)) return entry.songs;
    final work = () async {
      final songs = List<MusicSearchCandidate>.unmodifiable(await loader());
      // Empty/error responses must remain retryable, not a cached dead end.
      if (songs.isNotEmpty) {
        _entries[key] = (at: _now(), songs: songs);
        _prune();
        await _save();
      } else if (refresh) {
        _entries.remove(key);
        await _save();
      }
      return songs;
    }();
    _pending[key] = work;
    try {
      return await work;
    } finally {
      if (identical(_pending[key], work)) _pending.remove(key);
    }
  }

  void _prune() {
    _entries.removeWhere((_, entry) => !_fresh(entry.at));
    final keys = _entries.keys.toList()
      ..sort((a, b) => _entries[a]!.at.compareTo(_entries[b]!.at));
    for (final key in keys.take(
      (_entries.length - maxEntries).clamp(0, keys.length),
    )) {
      _entries.remove(key);
    }
  }

  Future<void> _save() {
    final data = {
      'schema': 1,
      'entries': [
        for (final row in _entries.entries)
          {
            'key': row.key,
            'at': row.value.at.toIso8601String(),
            'songs': [
              for (final c in row.value.songs)
                {...SavedOnlineTrack(candidate: c).toJson(), 'score': c.score},
            ],
          },
      ],
    };
    return _writeTail = _writeTail.then((_) async {
      try {
        if (_file != null) await const JsonFileStore().write(_file!, data);
      } catch (_) {
        /* Optional cache. */
      }
    });
  }
}
