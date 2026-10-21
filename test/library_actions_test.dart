import 'dart:io';

import 'package:ai_music/src/application/library_use_case.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/presentation/music_home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new cached favorite keeps its source after clearing playback audio',
    () async {
      final f = await _Fixture.create();
      f.cache.record = f.cache.record.copyWith(playbackCache: true);
      final before = await f.useCase.loadCache();
      final music = f.cache.record.music;
      final saved = SavedOnlineTrack(
        candidate: MusicSearchCandidate(
          query: music.query,
          source: music.source,
          platform: music.platform,
          keyword: music.name,
          page: 1,
          id: music.id,
          name: music.name,
          artist: music.artist,
          album: music.album,
          duration: 0,
          link: '',
          coverUrl: music.coverUrl,
          qualities: [music.quality],
          score: 0,
          raw: const {},
        ),
      );
      final added = await f.useCase.toggleFavorite(
        before.cachedTracks.single,
        current: before,
        onlineTrack: saved,
      );
      expect(added.playlistLibrary.favoriteTrackIds, contains('physical'));
      await f.useCase.preservePlaybackReferences(current: added);
      f.cache.present = false;
      final restored = await f.newUseCase().loadCache();
      final favorite = restored.playlistLibrary.favoriteEntries.singleWhere(
        (e) => e.trackId == 'physical',
      );
      expect(favorite.onlineTrack?.candidate.id, music.id);
      expect(favorite.song?.title, music.name);
      expect(restored.favoriteTracks.any((t) => t.id == 'physical'), isTrue);
      expect(
        restored.playlistLibrary.favoriteTrackIds,
        containsAll(['a', 'b', 'c']),
      );
    },
  );

  test(
    'cached song favorite survives the real playlist disk round trip',
    () async {
      final f = await _Fixture.create();
      const music = ResolvedMusic(
        query: '寻常岁月诗 蓝安Lane',
        source: MusicDataSource.flac,
        platform: 'kuwo',
        id: '659943118',
        name: '寻常岁月诗',
        artist: '蓝安Lane',
        album: '',
        url: 'https://audio.test/song.mp3',
        quality: MusicQuality(format: 'mp3', bitrate: '320'),
      );
      f.cache.record = f.cache.record.copyWith(
        music: music,
        cacheId: cacheIdForResolved(music),
      );
      final before = await f.useCase.loadCache();
      final saved = SavedOnlineTrack(
        candidate: MusicSearchCandidate(
          query: music.query,
          source: music.source,
          platform: music.platform,
          keyword: music.name,
          page: 1,
          id: music.id,
          name: music.name,
          artist: music.artist,
          album: music.album,
          duration: 0,
          link: '',
          coverUrl: music.coverUrl,
          qualities: [music.quality],
          score: 0,
          raw: const {},
        ),
      );
      final track = before.cachedTracks.single;
      expect(track.id, isNot(saved.trackId));
      final added = await f.useCase.toggleFavorite(
        track,
        current: before,
        onlineTrack: saved,
      );
      expect(added.playlistLibrary.favoriteTrackIds, contains(track.id));
      expect(
        (await f.newUseCase().loadCache()).favoriteTracks.map((t) => t.id),
        contains(track.id),
      );
      final removed = await f.useCase.toggleFavorite(
        track,
        current: added,
        onlineTrack: saved,
      );
      expect(
        removed.playlistLibrary.favoriteTrackIds,
        isNot(contains(track.id)),
      );
      expect(
        removed.playlistLibrary.favoriteTrackIds,
        containsAll(['a', 'b', 'c']),
      );
    },
  );

  test(
    'pins survive disk restart independently without changing entry order or dates',
    () async {
      final f = await _Fixture.create();
      final before = await f.useCase.loadCache();
      // Both calls deliberately carry the same stale snapshot.
      await Future.wait([
        f.useCase.setTrackPinned(
          favoritePlaylistId,
          'b',
          pinned: true,
          current: before,
        ),
        f.useCase.setTrackPinned('custom', 'a', pinned: true, current: before),
      ]);
      final restored = await f.newUseCase().loadCache();
      expect(restored.playlistLibrary.favoritePinnedTrackIds, ['b']);
      expect(restored.customPlaylists.single.pinnedTrackIds, ['a']);
      expect(restored.playlistLibrary.favoriteTrackIds, ['a', 'b', 'c']);
      expect(restored.customPlaylists.single.trackIds, ['a', 'b', 'c']);
      expect(
        restored.playlistLibrary.favoriteEntries.map((e) => e.addedAt),
        before.playlistLibrary.favoriteEntries.map((e) => e.addedAt),
      );
      final unpinned = await f.useCase.setTrackPinned(
        favoritePlaylistId,
        'b',
        pinned: false,
        current: before,
      );
      expect(unpinned.playlistLibrary.favoritePinnedTrackIds, isEmpty);
      expect(unpinned.customPlaylists.single.pinnedTrackIds, ['a']);
      expect(unpinned.playlistLibrary.favoriteTrackIds, ['a', 'b', 'c']);
    },
  );

  test(
    'newest pin comes first and removing a song prunes only its list pin',
    () async {
      final f = await _Fixture.create();
      var snapshot = await f.useCase.loadCache();
      for (final id in ['a', 'b', 'a']) {
        snapshot = await f.useCase.setTrackPinned(
          'custom',
          id,
          pinned: true,
          current: snapshot,
        );
      }
      expect(snapshot.customPlaylists.single.pinnedTrackIds, ['a', 'b']);
      snapshot = await f.useCase.removeTracksFromPlaylist(
        snapshot.customPlaylists.single,
        [snapshot.onlineTracks.singleWhere((t) => t.id == 'a')],
        current: snapshot,
      );
      expect(snapshot.customPlaylists.single.pinnedTrackIds, ['b']);
      expect(snapshot.playlistLibrary.favoriteTrackIds, ['a', 'b', 'c']);
      expect(
        (await f.newUseCase().loadCache())
            .customPlaylists
            .single
            .pinnedTrackIds,
        ['b'],
      );
    },
  );

  test(
    'pin persistence failure leaves the live snapshot unchanged and retry works',
    () async {
      final f = await _Fixture.create();
      final before = await f.useCase.loadCache();
      f.store.fail = true;
      await expectLater(
        f.useCase.setTrackPinned('custom', 'b', pinned: true, current: before),
        throwsStateError,
      );
      f.store.fail = false;
      final after = await f.useCase.setTrackPinned(
        'custom',
        'c',
        pinned: true,
        current: before,
      );
      expect(after.customPlaylists.single.pinnedTrackIds, ['c']);
      expect(before.customPlaylists.single.pinnedTrackIds, isEmpty);
      await expectLater(
        f.useCase.setTrackPinned(
          'custom',
          'missing',
          pinned: true,
          current: after,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'evicting playback audio migrates legacy pins while preserving manual per-list ids',
    () async {
      final f = await _Fixture.create();
      f.cache.record = f.cache.record.copyWith(playbackCache: true);
      final entries = (await f.store.load()).playlists.single.entries;
      final at = DateTime(2026, 4, 2);
      final old = PlaylistLibrary(
        favoriteEntries: [PlaylistTrackEntry(trackId: 'physical', addedAt: at)],
        favoritePinnedTrackIds: ['physical'],
        playlists: [
          MusicPlaylist(
            id: 'custom',
            name: 'Manual',
            entries: [
              PlaylistTrackEntry(
                trackId: 'physical',
                addedAt: at,
                song: entries[1].song,
                onlineTrack: entries[1].onlineTrack,
                manualSource: true,
              ),
            ],
            pinnedTrackIds: ['physical'],
            createdAt: at,
            updatedAt: at,
          ),
        ],
      );
      final before = f.useCase.applyCachedRecords([f.cache.record], old);
      final converted = await f.useCase.preservePlaybackReferences(
        current: before,
      );
      final next = converted.playlistLibrary.favoriteEntries.single.trackId;
      expect(next, isNot('physical'));
      expect(converted.playlistLibrary.favoritePinnedTrackIds, [next]);
      expect(converted.customPlaylists.single.pinnedTrackIds, ['physical']);
      expect(converted.playlistLibrary.favoriteEntries.single.addedAt, at);
      f.cache.present = false;
      final restarted = await f.newUseCase().loadCache();
      expect(restarted.playlistLibrary.favoritePinnedTrackIds, [next]);
      expect(restarted.customPlaylists.single.pinnedTrackIds, ['physical']);
      expect(restarted.favoriteTracks, hasLength(1));
    },
  );

  test(
    'saved online songs retain original playlist artwork when the audio source has none',
    () async {
      final f = await _Fixture.create();
      f.cache.record = f.cache.record.copyWith(
        music: ResolvedMusic.fromJson({
          ...f.cache.record.music.toJson(),
          'coverUrl': '',
        }),
      );
      final initial = await f.useCase.loadCache();
      final song = initial.playlistLibrary.favoriteEntries[1];
      final library = initial.playlistLibrary.copyWith(
        playlists: const [],
        favoriteEntries: [
          PlaylistTrackEntry(
            trackId: song.trackId,
            addedAt: song.addedAt,
            onlineTrack: song.onlineTrack,
            song: const PlaylistSong(
              key: 'qq:b',
              title: 'Song',
              artist: 'Artist',
              coverUrl: 'https://original.test/album.jpg',
            ),
          ),
        ],
      );
      final restored = f.useCase.applyCachedRecords([f.cache.record], library);
      expect(
        restored.favoriteTracks.single.artworkUri.toString(),
        'https://original.test/album.jpg',
      );
      expect(f.provider.calls, 0);
    },
  );

  test(
    'legacy and malformed pin data remain readable and invalid ids are removed',
    () {
      final f = MusicPlaylist(
        id: 'p',
        name: 'P',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        trackIds: ['a', 'b'],
      );
      expect(
        MusicPlaylist.fromJson(
          f.toJson().cast<String, dynamic>(),
        )!.pinnedTrackIds,
        isEmpty,
      );
      final json = {
        ...f.toJson(),
        'pinnedTrackIds': ['b', 3, 'b', 'missing', 'a'],
      };
      final restored = MusicPlaylist.fromJson(json)!;
      expect(restored.pinnedTrackIds, ['b', 'a']);
      expect(restored.copyWith(trackIds: ['a']).pinnedTrackIds, ['a']);
      expect(
        MusicPlaylist.fromJson({
          ...json,
          'pinnedTrackIds': 'bad',
        })!.pinnedTrackIds,
        isEmpty,
      );
    },
  );

  test('manual drag keeps the pinned block and permits its internal order', () {
    expect(
      reorderIdsForReorderableListView(
        ['a', 'b', 'c', 'd'],
        3,
        0,
        pinnedIds: {'a', 'b'},
      ),
      ['a', 'b', 'd', 'c'],
    );
    expect(
      reorderIdsForReorderableListView(
        ['a', 'b', 'c', 'd'],
        0,
        3,
        pinnedIds: {'a', 'b'},
      ),
      ['b', 'a', 'c', 'd'],
    );
  });

  test(
    'cached metadata and local artwork hydrate rows after restart without provider work',
    () async {
      final f = await _Fixture.create();
      final cover = File('${f.root.path}/cover.png');
      await cover.writeAsBytes([1, 2, 3]);
      final metadata = MetadataCacheStore(rootProvider: () async => f.root);
      await metadata.write('physical', TrackMetadata(artworkUri: cover.uri));
      final before = await f.newUseCase().loadCache();
      expect(before.cachedTracks.single.artworkUri, cover.uri);
      expect(before.favoriteTracks.first.artworkUri, cover.uri);
      expect(before.customPlaylists.single.entries.first.trackId, 'a');
      expect(
        before.onlineTracks.singleWhere((t) => t.id == 'b').artworkUri,
        cover.uri,
      );
      expect(
        before.onlineTracks.singleWhere((t) => t.id == 'c').artworkUri,
        isNull,
        reason: 'Live recording cannot borrow studio artwork by loose title',
      );
      expect(f.provider.calls, 0);
      await cover.delete();
      final after = await f.newUseCase().loadCache();
      expect(
        after.cachedTracks.single.artworkUri.toString(),
        'https://example.test/original.jpg',
      );
      expect(
        after.favoriteTracks.first.artworkUri.toString(),
        'https://example.test/song.jpg',
      );
      expect(f.provider.calls, 0);
    },
  );

  test('LAN sidecar artwork takes precedence over stale metadata', () async {
    final f = await _Fixture.create();
    final cover = File('${f.root.path}/local.jpg');
    await cover.writeAsBytes([1]);
    await MetadataCacheStore(rootProvider: () async => f.root).write(
      'physical',
      TrackMetadata(artworkUri: Uri.https('stale.test', '/image')),
    );
    f.cache.record = f.cache.record.copyWith(artworkPath: cover.path);
    final loaded = await f.newUseCase().loadCache();
    expect(loaded.cachedTracks.single.artworkUri, cover.uri);
    expect(loaded.favoriteTracks.first.artworkUri, cover.uri);
    expect(f.provider.calls, 0);
  });
}

class _Fixture {
  _Fixture(this.root, this.cache, this.store, this.provider);
  final Directory root;
  final _Cache cache;
  final _Store store;
  final _Provider provider;
  late final useCase = newUseCase();
  LibraryUseCase newUseCase() => LibraryUseCase(
    cacheStore: cache,
    playlistStore: store,
    metadataRepository: TrackMetadataRepository(
      cacheStore: MetadataCacheStore(rootProvider: () async => root),
      providers: [provider],
    ),
  );
  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('library_actions_');
    addTearDown(() => root.delete(recursive: true));
    final music = ResolvedMusic(
      query: 'Song Artist',
      source: MusicDataSource.buguyy,
      platform: 'buguyy',
      id: 'song',
      name: 'Song',
      artist: 'Artist',
      album: '',
      url: 'https://audio.test/song.mp3',
      coverUrl: 'https://example.test/original.jpg',
      quality: const MusicQuality(format: 'mp3'),
    );
    final cache = _Cache(
      CachedTrack(
        cacheId: 'physical',
        music: music,
        filePath: '${root.path}/song.mp3',
        sizeBytes: 4,
        fromCache: true,
      ),
    );
    final store = _Store(root);
    final entries = [
      PlaylistTrackEntry(
        trackId: 'a',
        addedAt: DateTime(2026),
        song: const PlaylistSong(
          key: 'qq:a',
          title: 'Song',
          artist: 'Artist',
          coverUrl: 'https://example.test/song.jpg',
        ),
      ),
      PlaylistTrackEntry(
        trackId: 'b',
        addedAt: DateTime(2026, 2),
        onlineTrack: SavedOnlineTrack(
          candidate: MusicSearchCandidate(
            query: 'Song Artist',
            source: MusicDataSource.buguyy,
            platform: 'buguyy',
            id: 'song',
            name: 'Song',
            artist: 'Artist',
            album: '',
            keyword: 'Song',
            page: 1,
            duration: 200,
            link: '',
            coverUrl: '',
            qualities: const [],
            score: 100,
            raw: const {},
          ),
        ),
        song: const PlaylistSong(key: 'qq:b', title: 'Song', artist: 'Artist'),
      ),
      PlaylistTrackEntry(
        trackId: 'c',
        addedAt: DateTime(2026, 3),
        song: const PlaylistSong(
          key: 'qq:c',
          title: 'Song (Live)',
          artist: 'Artist',
        ),
      ),
    ];
    await store.write(
      PlaylistLibrary(
        favoriteEntries: entries,
        playlists: [
          MusicPlaylist(
            id: 'custom',
            name: 'Custom',
            entries: entries,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      ),
    );
    return _Fixture(root, cache, store, _Provider());
  }
}

class _Cache extends CachedTrackStore {
  _Cache(this.record);
  CachedTrack record;
  bool present = true;
  @override
  Future<List<CachedTrack>> listCached() async => present ? [record] : [];
}

class _Store extends PlaylistStore {
  _Store(Directory root) : super(rootProvider: () async => root);
  bool fail = false;
  @override
  Future<void> write(PlaylistLibrary library, {Set<String>? validTrackIds}) {
    if (fail) throw StateError('disk full');
    return super.write(library, validTrackIds: validTrackIds);
  }
}

class _Provider implements TrackMetadataProvider {
  int calls = 0;
  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    calls++;
    return const TrackMetadata();
  }
}
