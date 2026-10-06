import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/app_storage.dart';
import 'json_file_store.dart';

String listeningDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime listeningDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class ListeningSong {
  const ListeningSong({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    this.artwork = '',
    this.durationMs,
  });
  final String id, trackId, title, artist, artwork;
  final int? durationMs;
  Map<String, Object?> toJson() => {
    'id': id,
    'trackId': trackId,
    'title': title,
    'artist': artist,
    'artwork': artwork,
    'durationMs': durationMs,
  };
  static ListeningSong? fromJson(Object? json) {
    if (json is! Map ||
        json['id'] is! String ||
        json['trackId'] is! String ||
        json['title'] is! String) {
      return null;
    }
    return ListeningSong(
      id: json['id'],
      trackId: json['trackId'],
      title: json['title'],
      artist: json['artist'] is String ? json['artist'] : '',
      artwork: json['artwork'] is String ? json['artwork'] : '',
      durationMs: json['durationMs'] is int ? json['durationMs'] : null,
    );
  }
}

class ListeningContext {
  const ListeningContext(this.song, {this.playlistId, this.playlistName = ''});
  final ListeningSong song;
  final String? playlistId;
  final String playlistName;
  bool sameVisit(ListeningContext other) =>
      song.id == other.song.id && playlistId == other.playlistId;
}

class ListeningRecord {
  const ListeningRecord({
    required this.id,
    required this.day,
    required this.song,
    required this.startedAt,
    required this.endedAt,
    required this.milliseconds,
    required this.plays,
    this.playlistId,
    this.playlistName = '',
  });
  final String id, day, playlistName;
  final String? playlistId;
  final ListeningSong song;
  final DateTime startedAt, endedAt;
  final int milliseconds, plays;
  Map<String, Object?> toJson() => {
    'id': id,
    'day': day,
    'song': song.toJson(),
    'start': startedAt.toIso8601String(),
    'end': endedAt.toIso8601String(),
    'ms': milliseconds,
    'plays': plays,
    'playlistId': playlistId,
    'playlistName': playlistName,
  };
  static ListeningRecord? fromJson(Object? j) {
    if (j is! Map ||
        j['id'] is! String ||
        j['day'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(j['day'])) {
      return null;
    }
    final day = DateTime.tryParse(j['day']);
    final song = ListeningSong.fromJson(j['song']);
    final start = DateTime.tryParse(j['start']?.toString() ?? '');
    final end = DateTime.tryParse(j['end']?.toString() ?? '');
    if (day == null ||
        listeningDayKey(day) != j['day'] ||
        song == null ||
        start == null ||
        end == null ||
        j['ms'] is! int ||
        j['ms'] < 0 ||
        j['plays'] is! int ||
        j['plays'] < 0 ||
        j['plays'] > 1 ||
        (j['ms'] == 0 && j['plays'] == 0)) {
      return null;
    }
    return ListeningRecord(
      id: j['id'],
      day: j['day'],
      song: song,
      startedAt: start,
      endedAt: end,
      milliseconds: j['ms'],
      plays: j['plays'],
      playlistId: j['playlistId'] is String ? j['playlistId'] : null,
      playlistName: j['playlistName'] is String ? j['playlistName'] : '',
    );
  }
}

class ListeningRank {
  ListeningRank(this.id, this.title, this.artwork, this.song);
  final String id, title, artwork;
  final ListeningSong? song;
  int milliseconds = 0, plays = 0;
  final songIds = <String>{};
  DateTime? lastPlayed;
  void add(ListeningRecord record) {
    milliseconds += record.milliseconds;
    plays += record.plays;
    songIds.add(record.song.id);
    if (lastPlayed == null || record.endedAt.isAfter(lastPlayed!)) {
      lastPlayed = record.endedAt;
    }
  }
}

class ListeningReport {
  ListeningReport(Iterable<ListeningRecord> source, {bool sortByTime = false}) {
    records = source.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final songs = <String, ListeningRank>{},
        playlists = <String, ListeningRank>{};
    for (final r in records) {
      milliseconds += r.milliseconds;
      plays += r.plays;
      if (r.milliseconds > 0) {
        days.update(
          r.day,
          (ms) => ms + r.milliseconds,
          ifAbsent: () => r.milliseconds,
        );
      }
      (songs[r.song.id] ??= ListeningRank(
        r.song.id,
        r.song.title,
        r.song.artwork,
        r.song,
      )).add(r);
      if (r.playlistId != null) {
        (playlists[r.playlistId!] ??= ListeningRank(
          r.playlistId!,
          r.playlistName,
          r.song.artwork,
          null,
        )).add(r);
      }
    }
    int compare(ListeningRank a, ListeningRank b) {
      final first = sortByTime
          ? b.milliseconds.compareTo(a.milliseconds)
          : b.plays.compareTo(a.plays);
      if (first != 0) return first;
      final second = sortByTime
          ? b.plays.compareTo(a.plays)
          : b.milliseconds.compareTo(a.milliseconds);
      return second != 0 ? second : (b.lastPlayed!).compareTo(a.lastPlayed!);
    }

    songRanks = songs.values.toList()..sort(compare);
    playlistRanks = playlists.values.toList()..sort(compare);
  }
  late final List<ListeningRecord> records;
  late final List<ListeningRank> songRanks, playlistRanks;
  int milliseconds = 0, plays = 0;
  final days = <String, int>{};
  int get songCount => songRanks.where((song) => song.milliseconds > 0).length;
  int get dayCount => days.length;
  int streak(DateTime today) {
    var day = listeningDay(today);
    if (!days.containsKey(listeningDayKey(day))) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var result = 0;
    while (days.containsKey(listeningDayKey(day))) {
      result++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return result;
  }
}

/// Month checkpoints, independent of audio files, playlists and usage ranking.
class ListeningStatsStore extends ChangeNotifier {
  ListeningStatsStore({
    Future<Directory> Function()? rootProvider,
    DateTime Function()? now,
  }) : _rootProvider = rootProvider ?? getAiMusicSupportDirectory,
       _now = now ?? DateTime.now;
  ListeningStatsStore.memory({DateTime Function()? now})
    : _rootProvider = null,
      _now = now ?? DateTime.now;
  final Future<Directory> Function()? _rootProvider;
  final DateTime Function() _now;
  final _records = <String, ListeningRecord>{};
  final _songIdentities = <String, String>{};
  String? identityForTrack(String trackId) => _songIdentities[trackId];
  final _dirty = <String>{};
  Future<void>? _loading;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  DateTime? startedAt;
  String? error;
  bool get loaded => startedAt != null;
  List<ListeningRecord> get records => List.unmodifiable(_records.values);
  Future<Directory> _directory() async =>
      Directory('${(await _rootProvider!()).path}/listening_stats');

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      if (_rootProvider != null) {
        final dir = await _directory();
        Object? index;
        try {
          index = await const JsonFileStore().read(
            File('${dir.path}/index.json'),
          );
        } on JsonFileStoreException {
          error = 'Listening history metadata was damaged';
        }
        if (index is Map) {
          startedAt = DateTime.tryParse(index['startedAt']?.toString() ?? '');
        }
        if (await dir.exists()) {
          await for (final f in dir.list()) {
            if (f is! File ||
                !RegExp(r'/\d{4}-\d{2}\.json$').hasMatch(f.path)) {
              continue;
            }
            try {
              final data = await const JsonFileStore().read(f);
              if (data is List) {
                for (final raw in data) {
                  final record = ListeningRecord.fromJson(raw);
                  if (record != null) {
                    _records.putIfAbsent(record.id, () => record);
                    _songIdentities.putIfAbsent(
                      record.song.trackId,
                      () => record.song.id,
                    );
                  }
                }
              }
            } on JsonFileStoreException {
              error = 'Some listening history could not be read';
            }
          }
        }
      }
      startedAt ??=
          _records.values.fold<DateTime?>(
            null,
            (first, record) => first == null || record.startedAt.isBefore(first)
                ? record.startedAt
                : first,
          ) ??
          _now();
    } catch (e) {
      error = e.toString();
    }
    _notify();
  }

  Future<void> retry() async {
    error = null;
    _loading = null;
    await load();
    await flush();
  }

  ListeningReport report({
    DateTime? from,
    DateTime? until,
    bool sortByTime = false,
  }) {
    final start = from == null ? null : listeningDayKey(from);
    final end = until == null ? null : listeningDayKey(until);
    return ListeningReport(
      _records.values.where(
        (r) =>
            (start == null || r.day.compareTo(start) >= 0) &&
            (end == null || r.day.compareTo(end) <= 0),
      ),
      sortByTime: sortByTime,
    );
  }

  void addInterval(
    String visit,
    ListeningContext context,
    DateTime start,
    DateTime end, {
    DateTime? qualifiedAt,
  }) {
    if (!start.isBefore(end)) return;
    _songIdentities.putIfAbsent(context.song.trackId, () => context.song.id);
    var cursor = start.toLocal();
    final finish = end.toLocal();
    while (cursor.isBefore(finish)) {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final edge = midnight.isBefore(finish) ? midnight : finish;
      final ms = edge.difference(cursor).inMilliseconds;
      if (ms <= 0) break;
      final day = listeningDayKey(cursor),
          id = '$visit|${listeningDayKey(cursor)}';
      final previous = _records[id];
      final qualifies =
          qualifiedAt != null && listeningDayKey(qualifiedAt.toLocal()) == day;
      _records[id] = ListeningRecord(
        id: id,
        day: day,
        song: context.song,
        startedAt: previous?.startedAt ?? cursor,
        endedAt: edge,
        milliseconds: (previous?.milliseconds ?? 0) + ms,
        plays: qualifies ? 1 : previous?.plays ?? 0,
        playlistId: context.playlistId,
        playlistName: context.playlistName,
      );
      _dirty.add(day.substring(0, 7));
      cursor = edge;
    }
    // Reaching the threshold exactly at midnight belongs to the new day.
    if (qualifiedAt != null) {
      final day = listeningDayKey(qualifiedAt.toLocal()),
          id = '$visit|${listeningDayKey(qualifiedAt.toLocal())}';
      if (!_records.containsKey(id)) {
        _records[id] = ListeningRecord(
          id: id,
          day: day,
          song: context.song,
          startedAt: qualifiedAt,
          endedAt: qualifiedAt,
          milliseconds: 0,
          plays: 1,
          playlistId: context.playlistId,
          playlistName: context.playlistName,
        );
        _dirty.add(day.substring(0, 7));
      }
    }
  }

  Future<void> flush() {
    final work = _tail.then((_) async {
      await load();
      if (_rootProvider == null) {
        _dirty.clear();
        _notify();
        return;
      }
      final months = _dirty.toList();
      _dirty.clear();
      try {
        final dir = await _directory();
        for (final month in months) {
          final snapshot = [
            for (final r in _records.values)
              if (r.day.startsWith(month)) r.toJson(),
          ];
          await const JsonFileStore().write(
            File('${dir.path}/$month.json'),
            snapshot,
          );
        }
        await const JsonFileStore().write(File('${dir.path}/index.json'), {
          'version': 1,
          'startedAt': (startedAt ??= _now()).toIso8601String(),
        });
        error = null;
      } catch (e) {
        _dirty.addAll(months);
        error = e.toString();
      }
      _notify();
    });
    _tail = work.then<void>((_) {}, onError: (_) {});
    return work;
  }

  Future<void> clear() {
    final work = _tail.then((_) async {
      await load();
      final resetAt = _now();
      if (_rootProvider != null) {
        final dir = await _directory();
        final suffix = DateTime.now().microsecondsSinceEpoch;
        final replacement = Directory('${dir.path}.reset-$suffix');
        final retired = Directory('${dir.path}.cleared-$suffix');
        var movedOld = false;
        try {
          // Prepare the empty checkpoint before replacing any existing history.
          await const JsonFileStore().write(
            File('${replacement.path}/index.json'),
            {'version': 1, 'startedAt': resetAt.toIso8601String()},
          );
          if (await dir.exists()) {
            await dir.rename(retired.path);
            movedOld = true;
          }
          try {
            await replacement.rename(dir.path);
          } catch (_) {
            if (movedOld) await retired.rename(dir.path);
            rethrow;
          }
        } finally {
          if (await replacement.exists()) {
            await replacement.delete(recursive: true);
          }
        }
        // Once swapped, abandoned files cannot reappear on the next launch.
        if (movedOld) {
          try {
            await retired.delete(recursive: true);
          } on FileSystemException {
            // Logical reset has committed; a cleanup failure must not restore it.
          }
        }
      }
      _records.clear();
      _songIdentities.clear();
      _dirty.clear();
      startedAt = resetAt;
      error = null;
      _notify();
    });
    _tail = work.then<void>((_) {}, onError: (_) {});
    return work;
  }

  void refresh() => _notify();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
