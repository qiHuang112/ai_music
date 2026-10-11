import 'dart:convert';
import 'dart:io';
import 'package:ai_music/src/data/playlist_usage_store.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late DateTime now;
  late PlaylistUsageStore store;
  MusicPlaylist playlist(String id, {DateTime? created}) => MusicPlaylist(
    id: id,
    name: id,
    createdAt: created ?? DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final playlists = [
    for (final id in ['a', 'b', 'c', 'd', 'e']) playlist(id),
  ];
  List<String> ranked(PlaylistUsageStore source) =>
      source.rank(playlists).map((p) => p.id).toList();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('playlist-usage-test-');
    now = DateTime(2026, 9, 27);
    store = PlaylistUsageStore(rootProvider: () async => root, now: () => now);
  });
  tearDown(() async => root.delete(recursive: true));
  test(
    'recent opens are default, playback does not promote a playlist',
    () async {
      await store.load();
      expect(ranked(store), ['a', 'b', 'c', 'd', 'e']);
      await store.record('d', played: false);
      now = now.add(const Duration(hours: 1));
      await store.record('c', played: false);
      for (var i = 0; i < 8; i++) {
        await store.record('a', played: true);
      }
      expect(ranked(store), ['c', 'd', 'a', 'b', 'e']);
      expect(
        store
            .rank([
              ...playlists,
              playlist('new', created: now.add(const Duration(seconds: 1))),
            ])
            .first
            .id,
        'new',
      );
    },
  );
  test('visits count opens in 30 days and uses recency for ties', () async {
    await store.record('b', played: false);
    await store.record('b', played: false);
    now = now.add(const Duration(hours: 1));
    await store.record('c', played: false);
    await store.setSortOrder(PlaylistSortOrder.visitCount);
    expect(ranked(store).take(2), ['b', 'c']);
    now = now.add(const Duration(days: 31));
    await store.record('e', played: false);
    expect(ranked(store), ['e', 'c', 'b', 'a', 'd']);
  });
  test(
    'queued opens, selected order and old last-open time survive reload',
    () async {
      await Future.wait([
        for (var i = 0; i < 8; i++) store.record('c', played: false),
      ]);
      now = now.add(const Duration(hours: 1));
      await store.record('a', played: false);
      await store.setSortOrder(PlaylistSortOrder.visitCount);
      final restored = PlaylistUsageStore(
        rootProvider: () async => root,
        now: () => now,
      );
      await restored.load();
      expect(restored.sortOrder, PlaylistSortOrder.visitCount);
      expect(ranked(restored), ranked(store));
      expect(
        restored.rank(playlists.where((p) => p.id != 'c').toList()).first.id,
        'a',
      );
      now = now.add(const Duration(days: 31));
      await restored.record(
        'e',
        played: true,
      ); // prunes events, preserves opens
      await restored.setSortOrder(PlaylistSortOrder.recentlyOpened);
      final again = PlaylistUsageStore(
        rootProvider: () async => root,
        now: () => now,
      );
      await again.load();
      expect(ranked(again).take(2), ['a', 'c']);
      expect(await File('${root.path}/playlists.json').exists(), false);
    },
  );
  test('legacy events migrate opens, ignoring more recent plays', () async {
    await File('${root.path}/playlist_usage.json').writeAsString(
      jsonEncode({
        'c': [
          {'at': now.toIso8601String(), 'played': false},
        ],
        'b': [
          {
            'at': now.add(const Duration(hours: 1)).toIso8601String(),
            'played': true,
          },
        ],
      }),
    );
    await store.load();
    expect(ranked(store), ['c', 'a', 'b', 'd', 'e']);
  });
  test(
    'corrupt optional stores are backed up without breaking display',
    () async {
      await File('${root.path}/playlist_usage.json').writeAsString('{broken');
      await File('${root.path}/playlist_sort.json').writeAsString('{broken');
      await store.load();
      expect(ranked(store), ['a', 'b', 'c', 'd', 'e']);
      await store.record('e', played: false);
      expect(ranked(store).first, 'e');
      expect(
        root.listSync().where((f) => f.path.contains('.corrupt-')),
        hasLength(2),
      );
    },
  );
}
