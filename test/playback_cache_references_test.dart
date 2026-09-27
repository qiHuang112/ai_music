import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/application/library_use_case.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reloaded online favorites and playlists prefer a manual download',
    () async {
      final root = await Directory.systemTemp.createTemp('cache_preference_');
      const saved = SavedOnlineTrack(
        candidate: MusicSearchCandidate(
          query: 'artist song',
          source: MusicDataSource.buguyy,
          platform: 'buguyy',
          keyword: 'song',
          page: 1,
          id: 'song-1',
          name: 'song',
          artist: 'artist',
          album: '',
          duration: 0,
          link: '',
          coverUrl: '',
          qualities: [MusicQuality(format: 'mp3')],
          score: 1,
          raw: {},
        ),
      );
      const lowMusic = ResolvedMusic(
        query: 'artist song',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        id: 'song-1',
        name: 'song',
        artist: 'artist',
        album: '',
        url: 'https://cdn.example.test/low.mp3',
        quality: MusicQuality(format: 'mp3', bitrate: '128'),
      );
      const highMusic = ResolvedMusic(
        query: 'artist song',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        id: 'song-1',
        name: 'song',
        artist: 'artist',
        album: '',
        url: 'https://cdn.example.test/high.mp3',
        quality: MusicQuality(format: 'mp3', bitrate: '320'),
      );
      final lowFile = File('${root.path}/low.mp3');
      final highFile = File('${root.path}/high.mp3');
      final low = CachedTrack(
        cacheId: cacheIdForResolved(lowMusic),
        music: lowMusic,
        filePath: lowFile.path,
        sizeBytes: 4,
        fromCache: true,
        playbackCache: true,
      );
      final high = CachedTrack(
        cacheId: cacheIdForResolved(highMusic),
        music: highMusic,
        filePath: highFile.path,
        sizeBytes: 4,
        fromCache: true,
      );
      final now = DateTime(2026, 9, 27);
      final entry = PlaylistTrackEntry(
        trackId: saved.trackId,
        onlineTrack: saved,
        addedAt: now,
      );
      try {
        await lowFile.writeAsBytes([1, 2, 3, 4]);
        await highFile.writeAsBytes([5, 6, 7, 8]);
        await File(
          '${root.path}/_cache_index.json',
        ).writeAsString(jsonEncode([low.toJson(), high.toJson()]));
        await PlaylistStore(rootProvider: () async => root).write(
          PlaylistLibrary(
            favoriteEntries: [entry],
            playlists: [
              MusicPlaylist(
                id: 'custom',
                name: '我的歌单',
                entries: [entry],
                createdAt: now,
                updatedAt: now,
              ),
            ],
          ),
        );

        final reloaded = await LibraryUseCase(
          cacheStore: CachedTrackStore(rootProvider: () async => root),
          playlistStore: PlaylistStore(rootProvider: () async => root),
          metadataRepository: TrackMetadataRepository(),
        ).loadCache();
        expect(reloaded.cachedRecords, hasLength(2));
        expect(reloaded.onlineTracks.single.filePath, highFile.path);
        expect(reloaded.favoriteTracks.single.filePath, highFile.path);
        expect(reloaded.customPlaylists.single.trackIds, [saved.trackId]);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('favorite added during uncached playback survives restart', () async {
    final root = await Directory.systemTemp.createTemp('stream_favorite_');
    final library = LibraryUseCase(
      cacheStore: CachedTrackStore(rootProvider: () async => root),
      playlistStore: PlaylistStore(rootProvider: () async => root),
      metadataRepository: TrackMetadataRepository(),
    );
    const saved = SavedOnlineTrack(
      candidate: MusicSearchCandidate(
        query: 'artist song',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        keyword: 'song',
        page: 1,
        id: 'song-1',
        name: 'song',
        artist: 'artist',
        album: '',
        duration: 0,
        link: '',
        coverUrl: '',
        qualities: [MusicQuality(format: 'mp3')],
        score: 1,
        raw: {},
      ),
    );
    try {
      final empty = await library.loadCache();
      await library.toggleFavorite(
        Track(id: saved.trackId, title: 'song', artist: 'artist', album: ''),
        current: empty,
        onlineTrack: saved,
      );
      final restored = await library.loadCache();
      expect(restored.favoriteTracks, hasLength(1));
      expect(
        restored.playlistLibrary.favoriteEntries.single.onlineTrack,
        isNotNull,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('clearing streamed audio keeps favorite and playlist entries', () async {
    final root = await Directory.systemTemp.createTemp('playback_references_');
    final cache = CachedTrackStore(rootProvider: () async => root);
    final playlists = PlaylistStore(rootProvider: () async => root);
    final library = LibraryUseCase(
      cacheStore: cache,
      playlistStore: playlists,
      metadataRepository: TrackMetadataRepository(),
    );
    const music = ResolvedMusic(
      query: 'artist song',
      source: MusicDataSource.buguyy,
      platform: 'buguyy',
      id: 'song-1',
      name: 'song',
      artist: 'artist',
      album: '',
      url: 'https://cdn.example.test/song.mp3',
      quality: MusicQuality(format: 'mp3'),
    );
    try {
      final file = await cache.playbackTargetFor(music);
      await file.writeAsBytes([
        0x49,
        0x44,
        0x33,
        0x04,
        0x00,
        0x00,
        ...List<int>.filled(16 * 1024, 0),
      ]);
      final record = await cache.finishPlaybackCache(music, file);
      final now = DateTime(2026, 9, 27);
      final entry = PlaylistTrackEntry(trackId: record.cacheId, addedAt: now);
      await playlists.write(
        PlaylistLibrary(
          favoriteEntries: [entry],
          playlists: [
            MusicPlaylist(
              id: 'custom',
              name: '我的歌单',
              entries: [entry],
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );

      final before = await library.loadCache();
      expect(before.favoriteTracks, hasLength(1));
      await library.preservePlaybackReferences(current: before);
      await cache.clearPlaybackCache();
      final after = await library.loadCache();
      expect(after.cachedTracks, isEmpty);
      expect(after.favoriteTracks, hasLength(1));
      expect(after.favoriteTracks.single.title, 'song');
      expect(after.customPlaylists.single.entries, hasLength(1));
      final favorite = after.playlistLibrary.favoriteEntries.single;
      expect(favorite.onlineTrack?.candidate.source, MusicDataSource.buguyy);
      expect(
        after.customPlaylists.single.entries.single.trackId,
        favorite.trackId,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
