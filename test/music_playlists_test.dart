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
      expect(library.playlists.single.lanFolderKey, '');
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
      expect(library.playlists.single.lanFolderKey, '');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('playlist store round-trips optional LAN folder ownership', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_playlists_lan_folder_',
    );
    final store = PlaylistStore(rootProvider: () async => root);
    final now = DateTime(2026, 8, 6);

    try {
      final playlist = MusicPlaylist(
        id: 'playlist-lamaze',
        name: 'Lamaze',
        lanFolderKey: 'lan:library-test:folder:lamaze',
        trackIds: const ['track-1'],
        createdAt: now,
        updatedAt: now,
      );

      await store.write(
        PlaylistLibrary(playlists: [playlist]),
        validTrackIds: const {'track-1'},
      );
      final loaded = await store.load(validTrackIds: const {'track-1'});

      expect(
        loaded.playlists.single.lanFolderKey,
        'lan:library-test:folder:lamaze',
      );
      expect(playlist.copyWith(name: '呼吸').lanFolderKey, playlist.lanFolderKey);
      expect(playlist.copyWith(clearLanFolderKey: true).lanFolderKey, '');
    } finally {
      await root.delete(recursive: true);
    }
  });
}
