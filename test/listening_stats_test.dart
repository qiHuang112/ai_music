import 'dart:io';

import 'package:ai_music/src/application/listening_recorder.dart';
import 'package:ai_music/src/data/listening_stats_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = DateTime(2026, 10, 6, 12);
  ListeningContext song(
    String id, {
    String? playlist = 'p',
    int? durationMs = 200000,
    String? trackId,
  }) => ListeningContext(
    ListeningSong(
      id: id,
      trackId: trackId ?? id,
      title: 'Song $id',
      artist: 'Artist',
      durationMs: durationMs,
    ),
    playlistId: playlist,
    playlistName: 'Playlist',
  );
  late ListeningStatsStore store;
  late ListeningTracker tracker;
  setUp(() {
    store = ListeningStatsStore.memory(now: () => date);
    tracker = ListeningTracker(store, visitPrefix: 'test');
  });
  tearDown(() => store.dispose());
  void sample(
    int wall,
    int position, {
    ListeningContext? context,
    bool ready = true,
    DateTime? at,
  }) => tracker.sample(
    context: context ?? song('a'),
    position: Duration(seconds: position),
    elapsed: Duration(seconds: wall),
    ready: ready,
    at: at ?? date.add(Duration(seconds: wall)),
  );

  test(
    'actual time and one qualified play survive pauses and metadata updates',
    () {
      sample(0, 0);
      sample(30, 30);
      sample(40, 40, ready: false);
      sample(340, 40, ready: false);
      sample(340, 40);
      sample(360, 60, context: song('a', trackId: 'new-source'));
      final report = store.report();
      expect(report.milliseconds, 60000);
      expect(report.plays, 1);
      expect(report.songCount, 1);
      expect(report.playlistRanks.single.id, 'p');
    },
  );
  test('buffered and failed sources do not invent time or plays', () {
    sample(0, 0, ready: false);
    sample(100, 0, ready: false);
    sample(101, 0);
    sample(103, 2);
    sample(104, 2, ready: false);
    expect(store.report().milliseconds, 2000);
    expect(store.report().plays, 0);
  });
  test(
    'seeking forward and backward changes baseline without another play',
    () {
      sample(0, 0);
      sample(20, 20);
      tracker.resetPosition();
      sample(21, 180);
      sample(26, 185);
      tracker.resetPosition();
      sample(27, 0);
      sample(32, 5);
      expect(store.report().milliseconds, 30000);
      expect(store.report().plays, 1);
    },
  );
  test('natural looping counts a new visit while same song updates do not', () {
    sample(0, 0);
    sample(40, 40);
    tracker.resetPosition(automatic: true);
    sample(40, 0);
    sample(70, 30);
    expect(store.report().milliseconds, 70000);
    expect(store.report().plays, 2);
    expect(store.report().songCount, 1);
    expect(store.records.length, 2);
  });
  test(
    'short tracks count halfway; unknown duration requires thirty seconds',
    () {
      sample(0, 0, context: song('short', durationMs: 18000));
      sample(9, 9, context: song('short', durationMs: 18000));
      sample(10, 0, context: song('unknown', durationMs: null));
      sample(39, 29, context: song('unknown', durationMs: null));
      expect(store.report().plays, 1);
      sample(40, 30, context: song('unknown', durationMs: null));
      expect(store.report().plays, 2);
    },
  );
  test(
    'same song in different playlist or single queue has only actual origin',
    () {
      sample(0, 0);
      sample(30, 30);
      sample(30, 30, context: song('a', playlist: 'q'));
      sample(60, 60, context: song('a', playlist: 'q'));
      sample(60, 60, context: song('a', playlist: null));
      sample(90, 90, context: song('a', playlist: null));
      final r = store.report();
      expect(r.plays, 3);
      expect(r.songCount, 1);
      expect(r.playlistRanks.map((p) => p.plays), [1, 1]);
      expect(r.playlistRanks.fold(0, (s, p) => s + p.milliseconds), 60000);
    },
  );
  test(
    'cross-midnight time splits into actual local days and threshold day',
    () {
      final before = DateTime(2026, 12, 31, 23, 59, 45);
      sample(0, 0, at: before);
      sample(30, 30, at: before.add(const Duration(seconds: 30)));
      expect(
        store
            .report(from: DateTime(2026, 12, 31), until: DateTime(2026, 12, 31))
            .milliseconds,
        15000,
      );
      final newYear = store.report(from: DateTime(2027), until: DateTime(2027));
      expect(newYear.milliseconds, 15000);
      expect(newYear.plays, 1);
      expect(store.report().dayCount, 2);
    },
  );
  test(
    'qualification exactly at midnight persists without fake duration',
    () async {
      final before = DateTime(2026, 10, 5, 23, 59, 30);
      sample(0, 0, at: before);
      sample(30, 30, at: DateTime(2026, 10, 6));
      final r = store.report(from: DateTime(2026, 10, 6));
      expect(r.milliseconds, 0);
      expect(r.plays, 1);
      for (final record in store.records) {
        expect(ListeningRecord.fromJson(record.toJson()), isNotNull);
      }
    },
  );
  test('rank count is default and duration sort uses actual time', () {
    sample(0, 0);
    sample(300, 300);
    sample(300, 0, context: song('b'));
    sample(330, 30, context: song('b'));
    tracker.resetPosition(automatic: true);
    sample(330, 0, context: song('b'));
    sample(360, 30, context: song('b'));
    expect(store.report().songRanks.first.id, 'b');
    expect(store.report(sortByTime: true).songRanks.first.id, 'a');
  });
  test('wall-clock jumps cannot inflate playback time', () {
    sample(0, 0);
    sample(1, 1, at: date.add(const Duration(days: 1)));
    expect(store.report().milliseconds, 1000);
  });
  test('speed changes count real elapsed time using the preceding speed', () {
    tracker.sample(
      context: song('a'),
      position: Duration.zero,
      ready: true,
      elapsed: Duration.zero,
      at: date,
      speed: 1,
    );
    tracker.sample(
      context: song('a'),
      position: const Duration(seconds: 10),
      ready: true,
      elapsed: const Duration(seconds: 10),
      at: date.add(const Duration(seconds: 10)),
      speed: 2,
    );
    tracker.sample(
      context: song('a'),
      position: const Duration(seconds: 30),
      ready: true,
      elapsed: const Duration(seconds: 20),
      at: date.add(const Duration(seconds: 20)),
      speed: 1,
    );
    expect(store.report().milliseconds, 20000);
    expect(store.report().plays, 0);
  });
  test('failed checkpoints and reset retain history and can retry', () async {
    final root = await Directory.systemTemp.createTemp('listening-retry-');
    var unavailable = false;
    final disk = ListeningStatsStore(
      rootProvider: () async {
        if (unavailable) throw const FileSystemException('storage unavailable');
        return root;
      },
      now: () => date,
    );
    try {
      await disk.load();
      disk.addInterval(
        'v',
        song('a'),
        date,
        date.add(const Duration(seconds: 40)),
        qualifiedAt: date.add(const Duration(seconds: 30)),
      );
      unavailable = true;
      await disk.flush();
      expect(disk.error, isNotNull);
      await expectLater(disk.clear(), throwsA(isA<FileSystemException>()));
      expect(disk.report().milliseconds, 40000);
      unavailable = false;
      await disk.retry();
      final reload = ListeningStatsStore(rootProvider: () async => root);
      await reload.load();
      expect(reload.report().plays, 1);
      expect(reload.report().milliseconds, 40000);
      reload.dispose();
    } finally {
      disk.dispose();
      await root.delete(recursive: true);
    }
  });

  test('streak uses consecutive calendar days and can end yesterday', () {
    for (final day in [4, 5]) {
      store.addInterval(
        'd$day',
        song('a'),
        DateTime(2026, 10, day),
        DateTime(2026, 10, day, 0, 1),
      );
    }
    expect(store.report().streak(DateTime(2026, 10, 6)), 2);
    expect(store.report().streak(DateTime(2026, 10, 7)), 0);
  });

  test(
    'month checkpoints, concurrent writes, reload and clear preserve other data',
    () async {
      final root = await Directory.systemTemp.createTemp('listening-store-');
      final disk = ListeningStatsStore(
        rootProvider: () async => root,
        now: () => date,
      );
      final other = File('${root.path}/playlists.json');
      await other.writeAsString('do not touch');
      try {
        await disk.load();
        disk.addInterval(
          'old',
          song('a'),
          DateTime(2025, 12, 31, 23, 59),
          DateTime(2026, 1, 1, 0, 1),
          qualifiedAt: DateTime(2025, 12, 31, 23, 59, 30),
        );
        final pending = disk.flush();
        disk.addInterval(
          'new',
          song('b'),
          date,
          date.add(const Duration(seconds: 45)),
          qualifiedAt: date.add(const Duration(seconds: 30)),
        );
        await Future.wait([pending, disk.flush()]);
        final reload = ListeningStatsStore(rootProvider: () async => root);
        await reload.load();
        expect(reload.report().milliseconds, 165000);
        expect(reload.identityForTrack('a'), 'a');
        expect(reload.report().plays, 2);
        expect(reload.records.map((r) => r.day).toSet(), {
          '2025-12-31',
          '2026-01-01',
          '2026-10-06',
        });
        await Future.wait([disk.flush(), disk.clear(), disk.flush()]);
        final empty = ListeningStatsStore(rootProvider: () async => root);
        await empty.load();
        expect(empty.records, isEmpty);
        expect(disk.identityForTrack('a'), isNull);
        expect(await other.readAsString(), 'do not touch');
        reload.dispose();
        empty.dispose();
      } finally {
        disk.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'damaged month and metadata are backed up and valid months survive',
    () async {
      final root = await Directory.systemTemp.createTemp('listening-damage-');
      final dir = Directory('${root.path}/listening_stats');
      await dir.create();
      final disk = ListeningStatsStore(
        rootProvider: () async => root,
        now: () => date,
      );
      try {
        await File('${dir.path}/index.json').writeAsString('{bad');
        await File('${dir.path}/2026-09.json').writeAsString('{bad');
        final seed = ListeningStatsStore(
          rootProvider: () async => root,
          now: () => date,
        );
        await seed.load();
        seed.addInterval(
          'valid',
          song('a'),
          date,
          date.add(const Duration(seconds: 31)),
        );
        await seed.flush();
        seed.dispose();
        await disk.load();
        expect(disk.report().milliseconds, 31000);
        final backups = await dir
            .list()
            .where((f) => f.path.contains('.corrupt-'))
            .length;
        expect(backups, 2);
      } finally {
        disk.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
