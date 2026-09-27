import 'dart:io';
import 'package:ai_music/src/data/playlist_usage_store.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late DateTime now;
  late PlaylistUsageStore store;
  final playlists = [
    for (final id in ['a', 'b', 'c', 'd', 'e'])
      MusicPlaylist(
        id: id,
        name: id,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
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
    'new installs preserve order; frequent playback outranks recent browsing',
    () async {
      await store.load();
      expect(ranked(store), ['a', 'b', 'c', 'd', 'e']);
      await store.record('d', played: true);
      await store.record('d', played: true);
      now = now.add(const Duration(hours: 1));
      await store.record('c', played: true);
      for (var i = 0; i < 6; i++) {
        await store.record('e', played: false);
      }
      expect(ranked(store), ['d', 'c', 'e', 'a', 'b']);
      expect(store.rank(playlists).take(4).map((p) => p.id), [
        'd',
        'c',
        'e',
        'a',
      ]);
    },
  );

  test('equal plays use latest use and old popularity ages out', () async {
    await store.record('b', played: true);
    now = now.add(const Duration(hours: 1));
    await store.record('c', played: true);
    expect(ranked(store).take(2), ['c', 'b']);
    now = now.add(const Duration(days: 31));
    await store.record('e', played: false);
    expect(ranked(store), ['e', 'a', 'b', 'c', 'd']);
  });

  test(
    'queued usage writes survive reload and exclude deleted playlists',
    () async {
      await Future.wait([
        for (var i = 0; i < 8; i++) store.record('c', played: true),
      ]);
      await store.record('a', played: true);
      final restored = PlaylistUsageStore(
        rootProvider: () async => root,
        now: () => now,
      );
      await restored.load();
      expect(ranked(restored), ranked(store));
      expect(
        restored.rank(playlists.where((p) => p.id != 'c').toList()).first.id,
        'a',
      );
      expect(await File('${root.path}/playlists.json').exists(), false);
    },
  );

  test(
    'corrupt usage is backed up without breaking playlist display',
    () async {
      await File('${root.path}/playlist_usage.json').writeAsString('{broken');
      await store.load();
      expect(ranked(store), ['a', 'b', 'c', 'd', 'e']);
      await store.record('e', played: true);
      expect(ranked(store).first, 'e');
      expect(
        root.listSync().where((f) => f.path.contains('.corrupt-')),
        hasLength(1),
      );
    },
  );
}
