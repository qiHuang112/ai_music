import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/music_playlists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist store preserves favorites and custom playlists', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_playlists_');
    final store = PlaylistStore(rootProvider: () async => root);
    final now = DateTime(2026);

    try {
      await store.write(
        PlaylistLibrary(
          favoriteTrackIds: const ['a', 'a', 'missing', 'b'],
          playlists: [
            MusicPlaylist(
              id: 'road',
              name: 'Road trip',
              trackIds: const ['b', 'a', 'b', 'missing'],
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
        validTrackIds: const {'a', 'b'},
      );

      final library = await store.load(validTrackIds: const {'a', 'b'});

      expect(library.favoriteTrackIds, const ['a', 'b']);
      expect(library.playlists.single.name, 'Road trip');
      expect(library.playlists.single.trackIds, const ['b', 'a']);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'playlist store backs up corrupt json and returns empty library',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_playlists_bad_',
      );
      final store = PlaylistStore(rootProvider: () async => root);

      try {
        await root.create(recursive: true);
        await File(
          '${root.path}${Platform.pathSeparator}playlists.json',
        ).writeAsString('{bad');

        final library = await store.load();

        expect(library.favoriteTrackIds, isEmpty);
        expect(library.playlists, isEmpty);
        expect(
          root.listSync().where((entry) => entry.path.contains('.corrupt-')),
          isNotEmpty,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('playlist store migrates legacy ids into timed entries', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_playlists_migrate_',
    );
    final store = PlaylistStore(rootProvider: () async => root);
    final updatedAt = DateTime(2026, 2, 3, 4, 5);

    try {
      await root.create(recursive: true);
      await File(
        '${root.path}${Platform.pathSeparator}playlists.json',
      ).writeAsString(
        jsonEncode({
          'favoriteTrackIds': ['a', 'b'],
          'playlists': [
            {
              'id': 'road',
              'name': 'Road trip',
              'trackIds': ['b', 'a'],
              'createdAt': updatedAt.toIso8601String(),
              'updatedAt': updatedAt.toIso8601String(),
            },
          ],
        }),
      );

      final library = await store.load(validTrackIds: const {'a', 'b'});

      expect(library.favoriteTrackIds, const ['a', 'b']);
      expect(library.favoriteEntries, hasLength(2));
      expect(
        library.favoriteEntries.map((entry) => entry.addedAt),
        everyElement(isA<DateTime>()),
      );
      expect(library.playlists.single.trackIds, const ['b', 'a']);
      expect(library.playlists.single.entries.map((entry) => entry.addedAt), [
        updatedAt,
        updatedAt,
      ]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
