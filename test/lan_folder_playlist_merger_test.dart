import 'dart:io';

import 'package:ai_music/src/application/lan_folder_playlist_merger.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PlaylistStore store;
  late LanFolderPlaylistMerger merger;
  final now = DateTime(2026, 8, 6, 12);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai_music_lan_playlists_');
    store = PlaylistStore(rootProvider: () async => root);
    var nextId = 0;
    merger = LanFolderPlaylistMerger(
      store: store,
      now: () => now,
      playlistIdFactory: () => 'lan-playlist-${++nextId}',
    );
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('creates one ordered playlist for each non-root song folder', () async {
    final result = await merger.merge(
      libraryId: 'library-one',
      tracks: const [
        LanFolderTrack(index: 3, folderPath: 'Lamaze', trackId: 'd'),
        LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'a'),
        LanFolderTrack(index: 2, folderPath: '胎教/钢琴', trackId: 'c'),
        LanFolderTrack(index: 1, folderPath: '', trackId: 'root'),
      ],
      validTrackIds: const {'a', 'c', 'd', 'root'},
    );

    expect(result.created, 2);
    expect(result.updated, 0);
    final playlists = (await store.load()).playlists;
    expect(playlists.map((playlist) => playlist.name), ['Lamaze', '胎教/钢琴']);
    expect(playlists.first.trackIds, const ['a', 'd']);
    expect(playlists.first.lanFolderKey, 'lan:library-one:folder:lamaze');
    expect(playlists.last.trackIds, const ['c']);
  });

  test(
    'adopts an unbound same-name playlist and preserves its order',
    () async {
      await store.write(
        PlaylistLibrary(
          playlists: [
            MusicPlaylist(
              id: 'manual',
              name: 'Lamaze',
              trackIds: const ['manual-track'],
              createdAt: now.subtract(const Duration(days: 1)),
              updatedAt: now.subtract(const Duration(days: 1)),
            ),
          ],
        ),
      );

      final result = await merger.merge(
        libraryId: 'library-one',
        tracks: const [
          LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'a'),
          LanFolderTrack(index: 1, folderPath: 'Lamaze', trackId: 'b'),
        ],
        validTrackIds: const {'manual-track', 'a', 'b'},
      );

      expect(result.created, 0);
      expect(result.updated, 1);
      final playlist = (await store.load()).playlists.single;
      expect(playlist.id, 'manual');
      expect(playlist.trackIds, const ['manual-track', 'a', 'b']);
      expect(playlist.lanFolderKey, 'lan:library-one:folder:lamaze');
    },
  );

  test(
    'stable folder key survives rename and repeat sync is idempotent',
    () async {
      await merger.merge(
        libraryId: 'library-one',
        tracks: const [
          LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'a'),
        ],
        validTrackIds: const {'a'},
      );
      final first = await store.load();
      await store.write(
        first.copyWith(
          playlists: [first.playlists.single.copyWith(name: '我的呼吸练习')],
        ),
      );

      final changed = await merger.merge(
        libraryId: 'library-one',
        tracks: const [
          LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'a'),
          LanFolderTrack(index: 1, folderPath: 'Lamaze', trackId: 'b'),
        ],
        validTrackIds: const {'a', 'b'},
      );
      final repeated = await merger.merge(
        libraryId: 'library-one',
        tracks: const [
          LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'a'),
          LanFolderTrack(index: 1, folderPath: 'Lamaze', trackId: 'b'),
        ],
        validTrackIds: const {'a', 'b'},
      );

      expect(changed.created, 0);
      expect(changed.updated, 1);
      expect(repeated.created, 0);
      expect(repeated.updated, 0);
      final playlist = (await store.load()).playlists.single;
      expect(playlist.name, '我的呼吸练习');
      expect(playlist.trackIds, const ['a', 'b']);
    },
  );

  test(
    'keeps removed tracks and separates a folder owned by another library',
    () async {
      await store.write(
        PlaylistLibrary(
          playlists: [
            MusicPlaylist(
              id: 'other-library',
              name: 'Lamaze',
              lanFolderKey: 'lan:library-other:folder:lamaze',
              trackIds: const ['old'],
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );

      final result = await merger.merge(
        libraryId: 'library-one',
        tracks: const [
          LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'new'),
        ],
        validTrackIds: const {'old', 'new'},
      );

      expect(result.created, 1);
      final playlists = (await store.load()).playlists;
      expect(playlists, hasLength(2));
      expect(playlists.first.trackIds, const ['old']);
      expect(playlists.last.name, 'Lamaze（局域网 2）');
      expect(playlists.last.trackIds, const ['new']);
    },
  );
}
