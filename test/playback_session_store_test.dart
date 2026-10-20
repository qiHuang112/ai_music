import 'dart:convert';
import 'dart:io';
import 'package:ai_music/src/data/playback_session_store.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PlaybackSessionStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('playback-session-test');
    store = PlaybackSessionStore(rootProvider: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));

  PlaybackSession session({
    int seconds = 47,
    String id = 'b',
    List<Track>? tracks,
  }) => PlaybackSession(
    tracks:
        tracks ??
        const [
          Track(
            id: 'a',
            title: 'A',
            artist: 'Artist',
            album: '',
            filePath: '/a.mp3',
          ),
          Track(
            id: 'b',
            title: 'B',
            artist: 'Artist',
            album: '',
            filePath: '/b.mp3',
          ),
        ],
    currentId: id,
    position: Duration(seconds: seconds),
    playlistId: favoritePlaylistId,
    followingPlaylistId: favoritePlaylistId,
    mode: PlaybackMode.shuffle,
    removedIds: {'removed'},
  );

  test(
    'round trips exact queue, favorites ownership, mode and progress',
    () async {
      await store.save(session());
      final restored = await PlaybackSessionStore(
        rootProvider: () async => root,
      ).load();
      expect(restored!.tracks.map((t) => t.id), ['a', 'b']);
      expect(restored.currentId, 'b');
      expect(restored.position, const Duration(seconds: 47));
      expect(restored.playlistId, favoritePlaylistId);
      expect(restored.followingPlaylistId, favoritePlaylistId);
      expect(restored.mode, PlaybackMode.shuffle);
      expect(restored.removedIds, {'removed'});
    },
  );

  test('progress checkpoint does not rewrite the queue structure', () async {
    await store.save(session());
    final file = File('${root.path}/playback_session.json');
    final before = await file.readAsString();
    await store.save(session(seconds: 53));
    expect(await file.readAsString(), before);
    expect((await store.load())!.position, const Duration(seconds: 53));
  });

  test('checkpoint from an older queue cannot override a new queue', () async {
    await store.save(session());
    final progress = File('${root.path}/playback_position.json');
    final stale = await progress.readAsString();
    await store.save(
      session(
        id: 'c',
        tracks: const [Track(id: 'c', title: 'C', artist: '', album: '')],
      ),
    );
    await progress.writeAsString(stale);
    expect((await store.load())!.currentId, 'c');
  });

  test('invalid checkpoint falls back to the last complete snapshot', () async {
    await store.save(session());
    final progress = File('${root.path}/playback_position.json');
    final json = jsonDecode(await progress.readAsString()) as Map;
    json['currentId'] = 'missing';
    await progress.writeAsString(jsonEncode(json));
    expect((await store.load())!.currentId, 'b');
  });

  test(
    'clear is serialized after saves and prevents stale resurrection',
    () async {
      await Future.wait([
        store.save(session()),
        store.save(session(seconds: 54)),
        store.save(null),
      ]);
      expect(await store.load(), isNull);
    },
  );

  test('corrupt session is backed up without touching the library', () async {
    final library = File('${root.path}/playlists.json');
    await library.writeAsString('keep me');
    await File('${root.path}/playback_session.json').writeAsString('{bad');
    expect(await store.load(), isNull);
    expect(await library.readAsString(), 'keep me');
    expect(
      root.listSync().where((f) => f.path.contains('.corrupt-')),
      hasLength(1),
    );
  });

  test(
    'online preview identities survive without retaining an expired audio URL',
    () async {
      await store.save(
        PlaybackSession(
          tracks: const [
            Track(
              id: 'preview-song',
              title: 'Song',
              artist: 'Artist',
              album: '',
              source: 'https://expired.test/audio',
            ),
          ],
          currentId: 'preview-song',
          position: Duration.zero,
          entries: [
            PlaylistTrackEntry(
              trackId: 'preview-song',
              addedAt: DateTime(2026),
              song: const PlaylistSong(
                key: 'netease:123',
                title: 'Song',
                artist: 'Artist',
              ),
            ),
          ],
        ),
      );
      final restored = (await store.load())!;
      expect(restored.tracks.single.source, '');
      expect(restored.entries.single.song!.key, 'netease:123');
    },
  );
}
