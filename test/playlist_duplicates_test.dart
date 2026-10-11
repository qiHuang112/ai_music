import 'dart:io';

import 'package:ai_music/src/application/library_use_case.dart';
import 'package:ai_music/src/application/playlist_duplicates.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026);
PlaylistTrackEntry entry(String id, String title, [String artist = 'Beyond']) =>
    PlaylistTrackEntry(
      trackId: id,
      addedAt: _at,
      song: PlaylistSong(key: id, title: title, artist: artist),
    );
MusicPlaylist playlist(
  List<PlaylistTrackEntry> entries, [
  String id = 'mine',
]) => MusicPlaylist(
  id: id,
  name: 'Mine',
  entries: entries,
  createdAt: _at,
  updatedAt: _at,
);

void main() {
  test(
    'strict song identity retains order, versions, artists and incomplete metadata',
    () {
      final p = playlist([
        entry('first', '海阔天空'),
        entry('other-source', ' 海闊天空 ', 'BEYOND'),
        entry('third', '海阔天空 (Version)'),
        entry('live', '海阔天空(Live)'),
        entry('live2', '海阔天空(1991 Live)'),
        entry('live3', '海阔天空(1993 Live)'),
        entry('remix', '海阔天空(Remix)'),
        entry('cover', '海阔天空', '其它歌手'),
        entry('unknown', '海阔天空', ''),
        entry('unknown2', '海阔天空', ''),
      ]);
      final plan = findPlaylistDuplicates(p, []);
      expect(plan.groups.single.trackIds, ['first', 'other-source', 'third']);
      expect(plan.removedIds, {'other-source', 'third'});
      expect(plan.removeCount, 2);
    },
  );

  test('dedup preserves complete concert and trailing version labels', () {
    final p = playlist([
      entry('studio', '海阔天空'),
      entry('studio-copy', '海闊天空'),
      entry('live-1991', '海阔天空（《Beyond 1991演唱会》Live）'),
      entry('live-1993', '海阔天空（《Beyond 1993演唱会》Live）'),
      entry('live-1993-copy', '海闊天空(《Beyond 1993演唱会》Live)'),
      entry('soundtrack-live', '海阔天空（电影主题曲）（Live）'),
      entry('soundtrack-remix', '海阔天空（电影主题曲）（Remix）'),
    ]);
    final plan = findPlaylistDuplicates(p, []);
    expect(plan.groups.map((g) => g.trackIds), [
      ['studio', 'studio-copy'],
      ['live-1993', 'live-1993-copy'],
    ]);
    expect(plan.removedIds, {'studio-copy', 'live-1993-copy'});
  });

  test(
    'original metadata overrides a wrong selected song, cached-only entries work',
    () {
      final p = playlist([
        entry('a', '甲'),
        entry('b', '乙'),
        PlaylistTrackEntry(trackId: 'cache', addedAt: _at),
      ]);
      final plan = findPlaylistDuplicates(p, [
        const Track(id: 'a', title: 'Wrong', artist: 'X', album: ''),
        const Track(id: 'b', title: 'Wrong', artist: 'X', album: ''),
        const Track(id: 'cache', title: '甲', artist: 'Beyond', album: ''),
      ]);
      expect(plan.groups.single.trackIds, ['a', 'cache']);
    },
  );

  for (final change in ['unrelated', 'new-duplicate', 'reorder', 'delete']) {
    test('confirmation uses latest serialized library: $change', () async {
      final root = await Directory.systemTemp.createTemp('playlist_dedup_');
      final store = PlaylistStore(rootProvider: () async => root);
      final cache = CachedTrackStore(
        rootProvider: () async => Directory('${root.path}/audio'),
      );
      final useCase = LibraryUseCase(
        cacheStore: cache,
        playlistStore: store,
        metadataRepository: TrackMetadataRepository(),
      );
      final p = playlist([entry('a', '海阔天空'), entry('b', '海阔天空')]);
      final other = playlist([entry('b', '海阔天空')], 'other');
      try {
        await store.write(
          PlaylistLibrary(
            favoriteEntries: [entry('b', '海阔天空')],
            playlists: [p, other],
          ),
        );
        final base = await useCase.loadCache();
        final plan = useCase.playlistDuplicates(p.id, current: base);
        expect((await store.load()).playlists.first.trackIds, ['a', 'b']);
        final pending = switch (change) {
          'unrelated' => useCase.renamePlaylist(
            other,
            'Renamed',
            current: base,
          ),
          'new-duplicate' => useCase.importPlaylistSongs(
            'Mine',
            [const PlaylistSong(key: 'extra', title: '海阔天空', artist: 'Beyond')],
            current: base,
            target: p,
          ),
          'reorder' => useCase.reorderPlaylistTracks(p, [
            const Track(id: 'b', title: '', artist: '', album: ''),
            const Track(id: 'a', title: '', artist: '', album: ''),
          ], current: base),
          _ => useCase.deletePlaylist(p, current: base),
        };
        if (change == 'unrelated') {
          final saved = await useCase.removePlaylistDuplicates(
            plan,
            current: base,
          );
          await pending;
          expect(saved.playlistLibrary.playlists.first.trackIds, ['a']);
          expect(saved.playlistLibrary.playlists.last.name, 'Renamed');
          expect(saved.playlistLibrary.playlists.last.trackIds, ['b']);
          expect(saved.playlistLibrary.favoriteTrackIds, ['b']);
          final restarted = await useCase.loadCache();
          expect(restarted.playlistLibrary.playlists.first.trackIds, ['a']);
        } else {
          await expectLater(
            useCase.removePlaylistDuplicates(plan, current: base),
            throwsStateError,
          );
          await pending;
          final saved = await store.load();
          if (change == 'new-duplicate') {
            expect(saved.playlists.first.entries.length, 3);
          }
          if (change == 'reorder') {
            expect(saved.playlists.first.trackIds, ['b', 'a']);
          }
          if (change == 'delete') {
            expect(saved.playlists.map((p) => p.id), ['other']);
          }
        }
      } finally {
        await root.delete(recursive: true);
      }
    });
  }
}
