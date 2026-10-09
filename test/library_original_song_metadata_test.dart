import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/library_use_case.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:flutter_test/flutter_test.dart';

const _songKey = 'qq:123';
const _songTitle = '不能说的秘密';
const _songArtist = '周杰伦';

void main() {
  for (final example in const [
    (
      oldTitle: '鸿门旋律',
      title: '鸿门旋律 (Version)',
      artist: 'GTR7',
      candidateTitle: '鸿门旋律',
      candidateArtist: '钰哈哈',
    ),
    (
      oldTitle: '星游记进行曲',
      title: '星游记进行曲',
      artist: 'LUCHANGSHENG',
      candidateTitle: '星游记进行曲',
      candidateArtist: '其他艺人',
    ),
    (
      oldTitle: '鸿门旋律',
      title: '鸿门旋律',
      artist: 'GTR7',
      candidateTitle: 'My Love',
      candidateArtist: 'GTR7',
    ),
    (
      oldTitle: '回忆观影券 (伴奏)',
      title: '回忆观影券 (伴奏)',
      artist: 'IN-K / 王忻辰',
      candidateTitle: '回忆观影券 (Live)',
      candidateArtist: 'IN-K / 王忻辰',
    ),
  ]) {
    test(
      'metadata refresh clears contradictory cached auto source for ${example.title} / ${example.candidateArtist}',
      () async {
        final old = PlaylistSong(
          key: _songKey,
          title: example.oldTitle,
          artist: example.artist,
          metadataVersion: 0,
        );
        final updated = PlaylistSong(
          key: _songKey,
          title: example.title,
          artist: example.artist,
          metadataVersion: 1,
          durationSeconds: 150,
        );
        final fixture = await _Fixture.create(
          original: old,
          automatic: _source(example.candidateTitle, example.candidateArtist),
          validAudio: true,
        );
        expect(
          await fixture.cache.isValidCachedAudio(fixture.cache.record),
          isTrue,
        );
        expect(
          fixture.current.favoriteTracks.single.filePath,
          fixture.audio.path,
        );
        final snapshot = await fixture.library.updateOriginalSongMetadata(
          old: old,
          updated: updated,
          current: fixture.current,
        );
        final automatic = _all(
          snapshot,
        ).where((e) => e.song?.key == _songKey && !e.manualSource);
        expect(automatic.map((e) => e.onlineTrack), everyElement(isNull));
        expect(snapshot.favoriteTracks.single.filePath, isEmpty);
        expect(
          _all(
            snapshot,
          ).singleWhere((e) => e.manualSource).onlineTrack!.candidate.id,
          'chosen-manually',
        );
        expect(
          await fixture.cache.isValidCachedAudio(fixture.cache.record),
          isTrue,
        );
        expect(fixture.cache.deletions, 0);
        expect(
          (await fixture.newLibrary().loadCache())
              .favoriteTracks
              .single
              .filePath,
          isEmpty,
        );
      },
    );
  }

  for (final example in const [
    (
      title: '回忆观影券 (伴奏)',
      artist: 'IN-K / 王忻辰',
      candidateTitle: '回忆观影券 (伴奏)',
      candidateArtist: 'IN-K',
    ),
    (
      title: 'Manestein (慢摇氛围版)',
      artist: 'TF',
      candidateTitle: 'Manestein',
      candidateArtist: 'TF',
    ),
  ]) {
    test(
      'metadata refresh keeps uncertain but non-contradictory candidate ${example.candidateTitle}',
      () async {
        final old = PlaylistSong(
          key: _songKey,
          title: example.title,
          artist: example.artist,
          metadataVersion: 0,
        );
        final updated = PlaylistSong(
          key: _songKey,
          title: example.title,
          artist: example.artist,
          metadataVersion: 1,
          durationSeconds: 150,
        );
        final fixture = await _Fixture.create(
          original: old,
          automatic: _source(example.candidateTitle, example.candidateArtist),
          validAudio: true,
        );
        final snapshot = await fixture.library.updateOriginalSongMetadata(
          old: old,
          updated: updated,
          current: fixture.current,
        );
        expect(
          _all(snapshot)
              .where((e) => e.song?.key == _songKey && !e.manualSource)
              .map((e) => e.onlineTrack?.candidate.id),
          everyElement('old-auto'),
        );
        expect(snapshot.favoriteTracks.single.filePath, fixture.audio.path);
      },
    );
  }
  test(
    'full title updates every reference, clears auto audio and persists without deleting files',
    () async {
      final fixture = await _Fixture.create();
      final before = fixture.current;
      final snapshot = await fixture.library.updateOriginalSongMetadata(
        old: _old,
        updated: _updated,
        current: before,
      );
      expect(fixture.store.writes, 1);
      expect(
        snapshot.playlistLibrary.favoriteTrackIds,
        before.playlistLibrary.favoriteTrackIds,
      );
      expect(
        snapshot.customPlaylists.map((p) => p.trackIds).toList(),
        before.customPlaylists.map((p) => p.trackIds).toList(),
      );
      final originalEntries = {
        for (final entry in _all(before)) entry.trackId: entry,
      };
      for (final entry in _all(
        snapshot,
      ).where((entry) => entry.song?.key == _songKey)) {
        expect(entry.song!.title, _updated.title);
        expect(entry.song!.durationSeconds, 225);
        expect(entry.song!.metadataVersion, 1);
        expect(entry.addedAt, originalEntries[entry.trackId]!.addedAt);
        if (entry.manualSource) {
          expect(entry.onlineTrack!.candidate.id, 'chosen-manually');
        } else {
          expect(entry.onlineTrack, isNull);
        }
      }
      final refreshedTrack = snapshot.onlineTracks.singleWhere(
        (t) => t.id == 'song-a',
      );
      expect(refreshedTrack.title, _updated.title);
      expect(refreshedTrack.duration, const Duration(seconds: 225));
      expect(refreshedTrack.filePath, isEmpty);
      expect(snapshot.cachedRecords.single.filePath, fixture.audio.path);
      expect(await fixture.audio.readAsBytes(), [1, 2, 3, 4]);
      expect(fixture.cache.deletions, 0);
      final reloaded = await fixture.newLibrary().loadCache();
      expect(
        reloaded.playlistLibrary.toJson(),
        snapshot.playlistLibrary.toJson(),
      );
      expect(reloaded.favoriteTracks.single.id, 'song-a');
      expect(reloaded.favoriteTracks.single.filePath, isEmpty);
      expect(
        reloaded.onlineTracks.singleWhere((t) => t.id == 'song-b').filePath,
        isEmpty,
      );
      expect(reloaded.cachedRecords, hasLength(1));
    },
  );

  test(
    'formatting and duration refresh preserve automatically chosen audio',
    () async {
      final fixture = await _Fixture.create();
      const formatted = PlaylistSong(
        key: _songKey,
        title: '不能說的秘密',
        artist: '周杰倫',
        durationSeconds: 210,
        metadataVersion: 1,
        coverUrl: 'https://img.test/new.jpg',
      );
      final snapshot = await fixture.library.updateOriginalSongMetadata(
        old: _old,
        updated: formatted,
        current: fixture.current,
      );
      final auto = _all(
        snapshot,
      ).where((e) => e.song?.key == _songKey && !e.manualSource);
      expect(
        auto.map((e) => e.onlineTrack?.candidate.id),
        everyElement('old-auto'),
      );
      expect(
        snapshot.onlineTracks.singleWhere((t) => t.id == 'song-a').filePath,
        fixture.audio.path,
      );
      expect(auto.map((e) => e.song!.durationSeconds), everyElement(210));
      expect(fixture.cache.deletions, 0);
    },
  );

  test(
    'queued stale metadata result cannot overwrite a newer saved result',
    () async {
      final fixture = await _Fixture.create();
      fixture.store.gate = Completer<void>();
      final first = fixture.library.updateOriginalSongMetadata(
        old: _old,
        updated: _updated,
        current: fixture.current,
      );
      await fixture.store.started.future;
      const stale = PlaylistSong(
        key: _songKey,
        title: '不能说的秘密（Live）',
        artist: '周杰伦',
        durationSeconds: 99,
        metadataVersion: 1,
      );
      final late = fixture.library.updateOriginalSongMetadata(
        old: _old,
        updated: stale,
        current: fixture.current,
      );
      fixture.store.gate!.complete();
      await first;
      final snapshot = await late;
      expect(fixture.store.writes, 1);
      expect(
        _all(
          snapshot,
        ).where((e) => e.song?.key == _songKey).map((e) => e.song!.title),
        everyElement(_updated.title),
      );
      expect(
        (await fixture.store.load()).toJson(),
        snapshot.playlistLibrary.toJson(),
      );
    },
  );

  test(
    'source selected manually while metadata was loading survives refresh',
    () async {
      final fixture = await _Fixture.create();
      final oldSnapshot = fixture.current;
      final track = oldSnapshot.onlineTracks.singleWhere(
        (t) => t.id == 'song-a',
      );
      await fixture.library.saveSongSource(
        track,
        _manual,
        current: oldSnapshot,
        manual: true,
      );
      final snapshot = await fixture.library.updateOriginalSongMetadata(
        old: _old,
        updated: _updated,
        current: oldSnapshot,
      );
      for (final entry in _all(snapshot).where((e) => e.trackId == 'song-a')) {
        expect(entry.song!.title, _updated.title);
        expect(entry.manualSource, isTrue);
        expect(entry.onlineTrack!.candidate.id, 'chosen-manually');
      }
      expect(
        _all(snapshot).singleWhere((e) => e.trackId == 'song-b').onlineTrack,
        isNull,
      );
    },
  );

  test(
    'failed atomic save keeps existing metadata and a later retry works',
    () async {
      final fixture = await _Fixture.create();
      fixture.store.fail = true;
      await expectLater(
        fixture.library.updateOriginalSongMetadata(
          old: _old,
          updated: _updated,
          current: fixture.current,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final persisted = await fixture.store.load();
      expect(persisted.toJson(), fixture.current.playlistLibrary.toJson());
      final retried = await fixture.library.updateOriginalSongMetadata(
        old: _old,
        updated: _updated,
        current: fixture.current,
      );
      expect(retried.favoriteTracks.single.title, _updated.title);
      expect(retried.favoriteTracks.single.filePath, isEmpty);
      expect(await fixture.audio.exists(), isTrue);
    },
  );

  test(
    'metadata guard checks title, artist and version even when the key is unchanged',
    () async {
      for (final replacement in const [
        PlaylistSong(
          key: _songKey,
          title: '用户修正的歌名',
          artist: _songArtist,
          metadataVersion: 0,
        ),
        PlaylistSong(
          key: _songKey,
          title: _songTitle,
          artist: '用户修正的歌手',
          metadataVersion: 0,
        ),
        PlaylistSong(
          key: _songKey,
          title: _songTitle,
          artist: _songArtist,
          metadataVersion: 2,
        ),
      ]) {
        final fixture = await _Fixture.create();
        final edited = await fixture.library.updateOriginalSongMetadata(
          old: _old,
          updated: replacement,
          current: fixture.current,
        );
        final stale = await fixture.library.updateOriginalSongMetadata(
          old: _old,
          updated: _updated,
          current: fixture.current,
        );
        expect(stale.playlistLibrary.toJson(), edited.playlistLibrary.toJson());
        expect(fixture.store.writes, 1);
      }
    },
  );
}

Iterable<PlaylistTrackEntry> _all(LibrarySnapshot snapshot) => [
  ...snapshot.playlistLibrary.favoriteEntries,
  for (final playlist in snapshot.customPlaylists) ...playlist.entries,
];

const _old = PlaylistSong(
  key: 'qq:123',
  title: '不能说的秘密',
  artist: '周杰伦',
  metadataVersion: 0,
);
const _updated = PlaylistSong(
  key: _songKey,
  title: '不能说的秘密（纯音乐）',
  artist: _songArtist,
  durationSeconds: 225,
  metadataVersion: 1,
);
const _auto = SavedOnlineTrack(
  candidate: MusicSearchCandidate(
    query: '不能说的秘密 周杰伦',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    keyword: '不能说的秘密',
    page: 1,
    id: 'old-auto',
    name: '不能说的秘密',
    artist: '周杰伦',
    album: '',
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: [MusicQuality(format: 'mp3')],
    score: 100,
    raw: {},
  ),
);
const _manual = SavedOnlineTrack(
  candidate: MusicSearchCandidate(
    query: '不能说的秘密 周杰伦',
    source: MusicDataSource.flac,
    platform: 'wyy',
    keyword: '不能说的秘密',
    page: 1,
    id: 'chosen-manually',
    name: '不能说的秘密（纯音乐）',
    artist: '周杰伦',
    album: '',
    duration: 225,
    link: '',
    coverUrl: '',
    qualities: [MusicQuality(format: 'mp3')],
    score: 100,
    raw: {},
  ),
);

SavedOnlineTrack _source(String title, String artist) => SavedOnlineTrack(
  candidate: MusicSearchCandidate(
    query: '$title $artist',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    keyword: title,
    page: 1,
    id: 'old-auto',
    name: title,
    artist: artist,
    album: '',
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3')],
    score: 100,
    raw: const {},
  ),
);

class _Fixture {
  _Fixture(this.audio, this.cache, this.store, this.library, this.current);
  final File audio;
  final _Cache cache;
  final _Store store;
  final LibraryUseCase library;
  final LibrarySnapshot current;

  static Future<_Fixture> create({
    PlaylistSong original = _old,
    SavedOnlineTrack automatic = _auto,
    bool validAudio = false,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'original_song_metadata_',
    );
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/old-audio.mp3');
    final bytes = validAudio
        ? [0x49, 0x44, 0x33, 0x04, 0, 0, ...List<int>.filled(16 * 1024, 0)]
        : [1, 2, 3, 4];
    await audio.writeAsBytes(bytes);
    final cache = _Cache(
      CachedTrack(
        cacheId: 'physical-old',
        music: ResolvedMusic(
          query: automatic.candidate.query,
          source: automatic.candidate.source,
          platform: automatic.candidate.platform,
          id: automatic.candidate.id,
          name: automatic.candidate.name,
          artist: automatic.candidate.artist,
          album: '',
          url: 'https://audio.test/old.mp3',
          quality: const MusicQuality(format: 'mp3'),
        ),
        filePath: audio.path,
        sizeBytes: bytes.length,
        fromCache: true,
      ),
    );
    final store = _Store(root);
    final now = DateTime(2026, 10, 8, 12);
    PlaylistTrackEntry entry(String id, {bool manual = false}) =>
        PlaylistTrackEntry(
          trackId: id,
          addedAt: now,
          song: original,
          onlineTrack: manual ? _manual : automatic,
          manualSource: manual,
        );
    PlaylistTrackEntry other(String id) => PlaylistTrackEntry(
      trackId: id,
      addedAt: now,
      song: PlaylistSong(key: 'wyy:$id', title: '其他歌曲', artist: '其他歌手'),
    );
    final playlists = PlaylistLibrary(
      favoriteEntries: [entry('song-a')],
      playlists: [
        MusicPlaylist(
          id: 'custom',
          name: '自建歌单',
          createdAt: now,
          updatedAt: now,
          entries: [
            other('unrelated-first'),
            entry('song-a'),
            other('unrelated-last'),
          ],
        ),
        MusicPlaylist(
          id: 'builtin-chart-qq',
          name: '榜单',
          createdAt: now,
          updatedAt: now,
          entries: [entry('manual-song', manual: true), entry('song-b')],
        ),
      ],
    );
    await store.write(playlists);
    store.writes = 0;
    final library = LibraryUseCase(
      cacheStore: cache,
      playlistStore: store,
      metadataRepository: TrackMetadataRepository(),
    );
    return _Fixture(
      audio,
      cache,
      store,
      library,
      library.applyCachedRecords([cache.record], playlists),
    );
  }

  LibraryUseCase newLibrary() => LibraryUseCase(
    cacheStore: cache,
    playlistStore: store,
    metadataRepository: TrackMetadataRepository(),
  );
}

class _Cache extends CachedTrackStore {
  _Cache(this.record);
  final CachedTrack record;
  int deletions = 0;
  @override
  Future<List<CachedTrack>> listCached() async => [record];
  @override
  Future<void> deleteCached(String cacheId) async {
    deletions++;
  }
}

class _Store extends PlaylistStore {
  _Store(Directory root) : super(rootProvider: () async => root);
  int writes = 0;
  bool fail = false;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {
    if (gate != null) {
      if (!started.isCompleted) started.complete();
      await gate!.future;
    }
    if (fail) {
      fail = false;
      throw const FileSystemException('controlled write failure');
    }
    writes++;
    await super.write(library, validTrackIds: validTrackIds);
  }
}
