import 'package:ai_music/src/data/song_search_cache.dart';
import 'memory_download_history.dart';
import 'package:ai_music/src/data/playlist_usage_store.dart';
import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/music_mappers.dart';
import 'package:ai_music/src/application/music_ui_message.dart';
import 'package:ai_music/src/data/lan_library_client.dart';
import 'package:ai_music/src/data/lan_library_models.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/playlist_auto_download_store.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:ai_music/src/data/online_playlists.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/playback/resumable_audio_source.dart';
import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const origin = OnlinePlaylist(
    source: OnlinePlaylistSource.qq,
    id: 'new',
    name: '直接加入',
    creator: '',
    trackCount: 3,
  );
  const originSongs = [
    OnlinePlaylistSong(id: '1', title: '第一首', artist: '歌手'),
    OnlinePlaylistSong(id: '2', title: '第二首', artist: '歌手'),
    OnlinePlaylistSong(id: '3', title: '第三首', artist: '歌手'),
  ];
  test(
    'home and source picker share cached queries, with source-specific refresh',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _SearchCacheProbeResolver();
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        songSearchCache: SongSearchCache.memory(),
        cacheStore: _FakeCacheStore(cached: []),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
      );
      try {
        controller.source = MusicDataSource.auto;
        const track = Track(id: 'query', title: '歌曲', artist: '歌手', album: '');
        await controller.search('歌曲 歌手');
        final first = controller.candidates.single;
        expect((await controller.searchSongSources(track)).single, same(first));
        await controller.search('歌曲 歌手');
        expect(resolver.calls, 1);
        await controller.searchSongSources(
          track,
          searchSource: MusicDataSource.flac,
        );
        expect(resolver.calls, 2);
        await controller.searchSongSources(track, refresh: true);
        expect(resolver.calls, 3);
        expect(controller.songSourceLabel(track), '待匹配');
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'playlist audio prefetch caches five at low quality, rolls forward, and keeps manual count',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp(
        'rolling_audio_cache_',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final payload = List<int>.filled(20000, 0)..setRange(0, 3, [73, 68, 51]);
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.uri.path);
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      final handler = _SpyAudioHandler();
      final resolver = _PrefetchProbeResolver(server.port);
      final cache = CachedTrackStore(rootProvider: () async => root);
      final controller = MusicController(
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cache,
        playlistStore: _MemoryPlaylistStore(),
        songSearchCache: SongSearchCache.memory(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        checkConnectivity: () async => [ConnectivityResult.mobile],
      );
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 500 && !condition(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(condition(), isTrue);
      }

      try {
        await controller.initialize();
        final p = (await controller.createPlaylist('预缓存'))!;
        await controller.addCandidatesToPlaylist(p, [
          for (var i = 0; i < 7; i++) _candidate(id: '$i', name: '歌曲$i'),
        ]);
        final playlist = controller.customPlaylists.single;
        final tracks = controller.tracksForPlaylist(playlist);
        expect(requests, isEmpty); // Adding/opening does not download audio.
        await controller.playTrack(
          tracks.first,
          playlistId: playlist.id,
          queueTracks: tracks,
        );
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
          ),
        );
        await waitFor(() => controller.cachedTracks.length == 5);
        expect(requests, ['/1', '/2', '/3', '/4', '/5']);
        expect(
          resolver.levels.every((l) => l == MusicQualityLevel.low),
          isTrue,
        );
        expect(controller.downloadTasks, isEmpty);
        expect(controller.manuallyDownloadedSongCount, 0);
        expect(controller.cacheProgressFor(tracks[1]).value.offline, isTrue);
        expect(controller.songSourceLabel(tracks[1]), '布谷YY');
        final cachedIds = resolver.ids.length;
        await controller.playTrack(
          tracks[1],
          playlistId: playlist.id,
          index: 1,
          queueTracks: tracks,
        );
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
          ),
        );
        await waitFor(() => controller.cachedTracks.length == 6);
        expect(requests, ['/1', '/2', '/3', '/4', '/5', '/6']);
        expect(
          resolver.ids.length,
          cachedIds + 1,
        ); // Current song uses cached file.
        await controller.setPlaybackMode(PlaybackMode.repeatOne);
        await controller.clearPlaybackCache();
        expect(await cache.playbackCacheBytes(), 0);
        expect(controller.customPlaylists.single.entries, hasLength(7));
      } finally {
        await controller.stop();
        controller.dispose();
        await handler.dispose();
        await server.close(force: true);
        await root.delete(recursive: true);
        HttpOverrides.global = previous;
      }
    },
  );

  for (final action in ['play-next', 'clear']) {
    test(
      'precache cancellation $action stops writes and preserves correct resume/clear',
      () async {
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        final root = await Directory.systemTemp.createTemp('precache_cancel_');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final payload = List<int>.filled(20000, 0)
          ..setRange(0, 3, [73, 68, 51]);
        final release = Completer<void>();
        final ranges = <String>[];
        server.listen((request) async {
          final range = request.headers.value(HttpHeaders.rangeHeader)!;
          ranges.add(range);
          final offset = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
          );
          final response = request.response;
          response.bufferOutput = false;
          response.statusCode = HttpStatus.partialContent;
          response.contentLength = payload.length - offset;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $offset-${payload.length - 1}/${payload.length}',
          );
          response.headers.contentType = ContentType('audio', 'mpeg');
          try {
            if (ranges.length == 1) {
              response.add(payload.sublist(0, 4096));
              await response.flush();
              await release.future;
              response.add(payload.sublist(4096));
            } else {
              response.add(payload.sublist(offset));
            }
            await response.close();
          } catch (_) {}
        });
        final handler = _SpyAudioHandler();
        final cache = CachedTrackStore(rootProvider: () async => root);
        final controller = MusicController(
          audioHandler: handler,
          resolver: _PrefetchProbeResolver(server.port),
          cacheStore: cache,
          playlistStore: _MemoryPlaylistStore(),
          songSearchCache: SongSearchCache.memory(),
          settingsStore: _FakeSettingsStore(),
          metadataRepository: _StaticMetadataRepository(),
          downloadHistoryStore: MemoryDownloadHistory(),
          connectivityChanges: const Stream.empty(),
          checkConnectivity: () async => [ConnectivityResult.wifi],
        );
        Future<void> waitFor(bool Function() condition) async {
          for (var i = 0; i < 400 && !condition(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(condition(), isTrue);
        }

        try {
          await controller.initialize();
          final p = (await controller.createPlaylist('交接'))!;
          await controller.addCandidatesToPlaylist(p, [
            _candidate(id: '0', name: '当前'),
            _candidate(id: '1', name: '后面'),
          ]);
          final playlist = controller.customPlaylists.single;
          final tracks = controller.tracksForPlaylist(playlist);
          await controller.playTrack(
            tracks[0],
            playlistId: playlist.id,
            queueTracks: tracks,
          );
          handler.playbackState.add(
            PlaybackState(
              playing: true,
              processingState: AudioProcessingState.ready,
            ),
          );
          await waitFor(
            () =>
                (controller.cacheProgressFor(tracks[1]).value.fraction ?? 0) >
                0,
          );
          expect(controller.cacheProgressFor(tracks[1]).value.offline, isFalse);
          if (action == 'clear') {
            await controller.clearPlaybackCache().timeout(
              const Duration(seconds: 2),
            );
            release.complete();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            expect(await cache.playbackCacheBytes(), 0);
            expect(await cache.listCached(), isEmpty);
            expect(await cache.partialProgress(), isEmpty);
          } else {
            // Playing the prefetched song stops its writer first, then reuses prefix.
            await controller
                .playTrack(
                  tracks[1],
                  playlistId: playlist.id,
                  index: 1,
                  queueTracks: tracks,
                )
                .timeout(const Duration(seconds: 2));
            final source =
                handler.loadedItems[1].source as ResumableAudioSource;
            final response = await source.request();
            final bytes = await response.stream
                .expand((chunk) => chunk)
                .toList();
            await source.waitForCache();
            expect(bytes, payload);
            expect(ranges, ['bytes=0-', 'bytes=4096-']);
            expect(
              controller.cacheProgressFor(tracks[1]).value.offline,
              isTrue,
            );
            expect(controller.manuallyDownloadedSongCount, 0);
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await controller.stop();
          controller.dispose();
          await handler.dispose();
          await server.close(force: true);
          await root.delete(recursive: true);
          HttpOverrides.global = previous;
        }
      },
    );
  }

  test(
    'switching a legacy cached playlist song uses new-source metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'legacy_source_metadata_',
      );
      final cache = CachedTrackStore(rootProvider: () async => root);
      final old = _cachedTrack(id: 'legacy', name: '原资源');
      final file = await cache.playbackTargetFor(old.music);
      await file.writeAsBytes(
        List<int>.filled(20000, 0)..setRange(0, 3, [73, 68, 51]),
      );
      final record = await cache.finishPlaybackCache(old.music, file);
      final handler = _SpyAudioHandler();
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        audioHandler: handler,
        resolver: _PrefetchProbeResolver(9999),
        cacheStore: cache,
        playlistStore: _MemoryPlaylistStore(),
        songSearchCache: SongSearchCache.memory(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
      );
      try {
        await controller.initialize();
        final track = trackFromCached(record);
        await controller.toggleFavorite(track);
        await controller.playTrack(track, queueTracks: [track]);
        await Future<void>.delayed(Duration.zero);
        metadata.loadIds.clear();
        await controller.chooseSongSource(
          track,
          _candidate(id: 'replacement', name: '新资源'),
        );
        expect(controller.selectedSongSource(track)?.id, 'replacement');
        expect(metadata.loadIds, isNotEmpty);
        expect(metadata.loadIds.last, isNot(record.cacheId));
        expect(controller.favoriteTracks.single.id, track.id);
        expect(controller.favoriteTracks.single.title, '新资源');
      } finally {
        await controller.stop();
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'post-create matching ranks the best source and playback joins its query',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver()..gate = Completer();
      final store = _MemoryPlaylistStore();
      final root = await Directory.systemTemp.createTemp('ranked_playlist_');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: store,
        cacheStore: CachedTrackStore(rootProvider: () async => root),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs.take(1).toList(),
        ))!;
        final track = controller.tracksForPlaylist(playlist).single;
        expect(
          store.library.playlists.single.entries.single.song!.title,
          '第一首',
        );
        expect(
          controller.playlistSourceProgress.value[playlist.id]?.matching,
          true,
        );
        final playing = controller.playTrack(track);
        await Future<void>.delayed(Duration.zero);
        expect(resolver.searchCalls, 1);
        resolver.gate!.complete([
          _candidate(id: 'wrong', name: '另一首歌'),
          _candidate(id: 'right', name: '第一首'),
        ]);
        await playing;
        await controller.matchPlaylistSources(playlist.id);
        expect(resolver.searchCalls, 1);
        expect(resolver.resolveIds, ['right']);
        expect(controller.selectedSongSource(track)?.id, 'right');
        expect(
          controller.playlistSourceProgress.value[playlist.id]?.completed,
          1,
        );
        expect(controller.playlistSourceProgress.value[playlist.id]?.failed, 0);
        expect(store.library.playlists.single.entries.single.onlineTrack, null);
        expect(controller.cachedTracks, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'empty background results can retry and a deleted song ignores late matches',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver()..gate = Completer();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: _MemoryPlaylistStore(),
        cacheStore: _FakeCacheStore(cached: []),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs.take(1).toList(),
        ))!;
        final track = controller.tracksForPlaylist(playlist).single;
        resolver.gate!.complete([]);
        await controller.matchPlaylistSources(playlist.id);
        expect(controller.playlistSourceProgress.value[playlist.id]?.failed, 1);
        expect(controller.selectedSongSource(track), null);
        resolver.gate = Completer();
        final retry = controller.matchPlaylistSources(playlist.id);
        await Future<void>.delayed(Duration.zero);
        expect(resolver.searchCalls, 2);
        await controller.deletePlaylist(playlist);
        resolver.gate!.complete([_candidate(id: 'late', name: '第一首')]);
        await retry;
        expect(controller.customPlaylists, isEmpty);
        expect(controller.selectedSongSource(track), null);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'automatic source resolution falls back while a manual choice stays fixed on failure',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver()..failFirst = true;
      final root = await Directory.systemTemp.createTemp('source_fallback_');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: _MemoryPlaylistStore(),
        cacheStore: CachedTrackStore(rootProvider: () async => root),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs,
        ))!;
        final track = controller.tracksForPlaylist(playlist).first;
        await controller.playTrack(track);
        expect(resolver.resolveIds, ['first', 'second']);
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          controller
              .customPlaylists
              .single
              .entries
              .first
              .onlineTrack!
              .candidate
              .id,
          'second',
        );
        await controller.stop();
        await controller.chooseSongSource(
          track,
          _candidate(id: 'first', name: '固定来源'),
        );
        final searches = resolver.searchCalls;
        await expectLater(
          controller.playTrack(
            controller
                .tracksForPlaylist(controller.customPlaylists.single)
                .first,
          ),
          throwsStateError,
        );
        expect(resolver.searchCalls, searches);
        expect(
          controller
              .customPlaylists
              .single
              .entries
              .first
              .onlineTrack!
              .candidate
              .id,
          'first',
        );
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'manual download-all resolves unplayed songs and records successful sources',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver();
      final cache = _DownloadCacheStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: _MemoryPlaylistStore(),
        cacheStore: cache,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs.take(1).toList(),
        ))!;
        expect(cache.downloadIds, isEmpty);
        final result = await controller.downloadPlaylist(playlist);
        expect(result.downloaded, 1);
        expect(result.failed, 0);
        expect(cache.downloadIds, ['first']);
        expect(
          controller
              .customPlaylists
              .single
              .entries
              .single
              .onlineTrack!
              .candidate
              .id,
          'first',
        );
        expect(
          controller.customPlaylists.single.entries.single.song!.title,
          '第一首',
        );
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );
  test(
    'direct add saves original songs before background lookup without downloading',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver();
      final root = await Directory.systemTemp.createTemp('direct_playlist_');
      final store = PlaylistStore(rootProvider: () async => root);
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: store,
        cacheStore: _FakeCacheStore(cached: []),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs,
        ))!;
        expect(controller.tracksForPlaylist(playlist).map((t) => t.title), [
          '第一首',
          '第二首',
          '第三首',
        ]);
        await controller.matchPlaylistSources(playlist.id);
        expect(resolver.searchCalls, 3);
        expect(resolver.resolveIds, isEmpty);
        final duplicate = await controller.addPlaylistDirectly(
          origin,
          originSongs,
          target: playlist,
        );
        expect(duplicate!.entries.length, 3);
        await controller.toggleFavorite(
          controller.tracksForPlaylist(playlist).first,
        );
        await controller.loadCache(repairLegacy: false);
        expect(
          controller
              .tracksForPlaylist(controller.customPlaylists.single)
              .length,
          3,
        );
        expect(controller.favoriteTracks.single.title, '第一首');
        expect(
          (await store.load(
            validTrackIds: {},
          )).playlists.single.entries.every((e) => e.song != null),
          isTrue,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'background matching does not persist unplayed songs and manual choice stays fixed',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver();
      final store = _MemoryPlaylistStore();
      final root = await Directory.systemTemp.createTemp('song_source_');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: store,
        cacheStore: CachedTrackStore(rootProvider: () async => root),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs,
        ))!;
        final tracks = controller.tracksForPlaylist(playlist);
        await controller.matchPlaylistSources(playlist.id);
        await controller.playTrack(
          tracks.first,
          queueTracks: tracks,
          playlistId: playlist.id,
        );
        expect(resolver.searchCalls, 3);
        expect(
          store.library.playlists.single.entries.first.onlineTrack,
          isNull,
        ); // Ready/playing has not happened.
        expect(handler.loadedIds, tracks.map((t) => t.id));
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          store
              .library
              .playlists
              .single
              .entries
              .first
              .onlineTrack!
              .candidate
              .id,
          'first',
        );
        expect(store.library.playlists.single.entries[1].onlineTrack, isNull);
        await controller.stop();
        await controller.playTrack(
          controller.tracksForPlaylist(controller.customPlaylists.single).first,
        );
        expect(resolver.searchCalls, 3);
        await controller.chooseSongSource(
          tracks.first,
          _candidate(id: 'manual', name: '手选版本'),
        );
        expect(
          store.library.playlists.single.entries.first.trackId,
          tracks.first.id,
        );
        expect(
          store.library.playlists.single.entries.first.manualSource,
          isTrue,
        );
        expect(
          store
              .library
              .playlists
              .single
              .entries
              .first
              .onlineTrack!
              .candidate
              .id,
          'manual',
        );
        expect(handler.loadedInitialPosition, Duration.zero);
        expect(resolver.resolveIds.last, 'manual');
        await controller.loadCache(repairLegacy: false);
        expect(
          controller
              .customPlaylists
              .single
              .entries
              .first
              .onlineTrack!
              .candidate
              .id,
          'manual',
        );
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'manual source chosen while initial search is pending wins over late search',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver()
        ..gate = Completer<List<MusicSearchCandidate>>();
      final store = _MemoryPlaylistStore();
      final root = await Directory.systemTemp.createTemp('song_race_');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: store,
        cacheStore: CachedTrackStore(rootProvider: () async => root),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs,
        ))!;
        final track = controller.tracksForPlaylist(playlist).first;
        final playing = controller.playTrack(track);
        final failed = expectLater(
          playing,
          throwsA(isA<DownloadCancelledException>()),
        );
        await Future<void>.delayed(Duration.zero);
        await controller.chooseSongSource(
          track,
          _candidate(id: 'manual', name: '手选版本'),
        );
        resolver.gate!.complete([_candidate(id: 'late', name: '晚到结果')]);
        await failed;
        expect(
          store
              .library
              .playlists
              .single
              .entries
              .first
              .onlineTrack!
              .candidate
              .id,
          'manual',
        );
        expect(resolver.resolveIds, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'no source search results never persists a choice and playback reports failure',
    () async {
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        playlistStore: _MemoryPlaylistStore(),
        cacheStore: _FakeCacheStore(cached: []),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.addPlaylistDirectly(
          origin,
          originSongs,
        ))!;
        await expectLater(
          controller.playTrack(controller.tracksForPlaylist(playlist).first),
          throwsA(isA<StateError>()),
        );
        expect(
          controller.customPlaylists.single.entries.first.onlineTrack,
          isNull,
        );
        expect(handler.playCalls, 0);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'completion while history loads merges and persists both records',
    () async {
      final store = _DelayedDownloadHistory();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        downloadHistoryStore: store,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      addTearDown(() async {
        controller.dispose();
        await handler.dispose();
      });
      await controller.initialize();
      controller.downloadQueue.upsert(
        const DownloadTask(
          id: 'new',
          title: 'New',
          subtitle: '',
          status: DownloadTaskStatus.downloading,
        ),
      );
      controller.downloadQueue.update(
        'new',
        (task) => task.copyWith(status: DownloadTaskStatus.completed),
      );
      store.loaded.complete([
        const DownloadTask(
          id: 'old',
          title: 'Old',
          subtitle: '',
          status: DownloadTaskStatus.completed,
        ).toJson(),
      ]);
      await store.written.future;
      expect(store.records.map((r) => r['id']), containsAll(['old', 'new']));
      expect(controller.recentDownloadTasks, hasLength(2));
    },
  );

  test(
    're-importing chart candidates reports only new playlist entries',
    () async {
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.createPlaylist('榜单'))!;
        final first = _candidate(id: 'first', name: '第一首');
        final second = _candidate(id: 'second', name: '第二首');

        expect(await controller.addCandidatesToPlaylist(playlist, [first]), 1);
        expect(
          await controller.addCandidatesToPlaylist(playlist, [
            first,
            second,
            second,
          ]),
          1,
        );
        expect(
          await controller.addCandidatesToPlaylist(playlist, [first, second]),
          0,
        );
        expect(controller.customPlaylists.single.trackIds, hasLength(2));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'online playlist entry survives reload and uses cached metadata',
    () async {
      final handler = _SpyAudioHandler();
      final usage = _UsageSpy();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final playlists = _MemoryPlaylistStore();
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: playlists,
        playlistUsageStore: usage,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('截图歌单');
        expect(playlist, isNotNull);
        await controller.addCandidatesToPlaylist(playlist!, [
          _candidate(id: 'song-1', name: '第一首'),
        ]);
        await controller.loadCache(repairLegacy: false);
        final tracks = controller.tracksForPlaylist(
          controller.customPlaylists.single,
        );
        expect(tracks, hasLength(1));
        expect(tracks.single.id, startsWith('online-'));
        expect(tracks.single.filePath, cached.filePath);
        await controller.recordPlaylistUsage(playlist.id);
        await controller.playTrack(
          tracks.single,
          queueTracks: tracks,
          playlistId: playlist.id,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(handler.loadedIds, [tracks.single.id]);
        expect(usage.events, [(playlist.id, false), (playlist.id, true)]);
        expect(metadata.loadIds, contains(cached.cacheId));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'default LAN sync wires imported folders into controller playlists',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_controller_lan_folder_',
      );
      final audio = _controllerLanMp3Bytes();
      final gateway = _ControllerLanGateway(
        manifest: LanLibraryManifest.fromJson({
          'schemaVersion': 1,
          'libraryId': 'controller-library',
          'generatedAt': '2026-08-06T00:00:00Z',
          'tracks': [
            {
              'id': 'controller-lamaze',
              'title': '慢呼放松',
              'artist': 'AI Home',
              'album': '拉玛泽呼吸引导',
              'folderPath': 'Lamaze',
              'audio': {
                'url': '/api/v1/files/Lamaze/controller-lamaze.mp3',
                'sizeBytes': audio.length,
                'sha256': sha256.convert(audio).toString(),
                'format': 'mp3',
              },
            },
          ],
        }),
        audio: audio,
      );
      final playlistStore = _MemoryPlaylistStore();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: CachedTrackStore(rootProvider: () async => root),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        lanLibraryGateway: gateway,
      );

      try {
        await controller.initialize();
        final result = await controller.syncLanLibrary();

        expect(result?.playlistsCreated, 1);
        expect(controller.customPlaylists, hasLength(1));
        expect(controller.customPlaylists.single.name, 'Lamaze');
        expect(controller.customPlaylists.single.trackIds, [
          controller.cachedTracks.single.id,
        ]);
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('playTrack uses the explicit queue and applies shuffle mode', () async {
    final handler = _SpyAudioHandler();
    final tracks = [
      _cachedTrack(id: 'song-1', name: '第一首'),
      _cachedTrack(id: 'song-2', name: '第二首'),
    ];
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: tracks),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      await controller.setPlaybackMode(PlaybackMode.shuffle);
      final favoriteQueue = [trackFromCached(tracks.last)];

      await controller.playTrack(
        favoriteQueue.single,
        index: 0,
        queueTracks: favoriteQueue,
      );

      expect(handler.loadedIds, [tracks.last.cacheId]);
      expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'sequential mode repeats the queue and system action cycles three modes',
    () async {
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        await controller.setPlaybackMode(PlaybackMode.sequential);
        expect(handler.shuffleMode, AudioServiceShuffleMode.none);
        expect(handler.repeatMode, AudioServiceRepeatMode.all);

        await handler.customAction(MusicAudioHandler.togglePlaybackModeAction);
        expect(controller.playbackMode, PlaybackMode.repeatOne);
        expect(handler.repeatMode, AudioServiceRepeatMode.one);

        await handler.customAction(MusicAudioHandler.togglePlaybackModeAction);
        expect(controller.playbackMode, PlaybackMode.shuffle);
        expect(handler.shuffleMode, AudioServiceShuffleMode.all);

        await handler.customAction(MusicAudioHandler.togglePlaybackModeAction);
        expect(controller.playbackMode, PlaybackMode.sequential);
        expect(handler.repeatMode, AudioServiceRepeatMode.all);
        expect(handler.shuffleMode, AudioServiceShuffleMode.none);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'rapid mode taps keep the final player mode in sync with the UI',
    () async {
      final handler = _DelayedPlaybackModeHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        await controller.setPlaybackMode(PlaybackMode.sequential);
        handler.blockNextShuffleChange = true;

        final firstTap = controller.cyclePlaybackMode();
        await handler.shuffleChangeStarted.future;
        final secondTap = handler.customAction(
          MusicAudioHandler.togglePlaybackModeAction,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
        handler.releaseShuffleChange.complete();
        await Future.wait([firstTap, secondTap]);

        expect(controller.playbackMode, PlaybackMode.shuffle);
        expect(handler.repeatMode, AudioServiceRepeatMode.all);
        expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('default cached playback keeps the cache queue for next', () async {
    final handler = _SpyAudioHandler();
    final first = _cachedTrack(id: 'song-1', name: '第一首');
    final second = _cachedTrack(id: 'song-2', name: '第二首');
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [first, second]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      await controller.playTrack(trackFromCached(first));
      expect(handler.queue.value.map((item) => item.id), [
        first.cacheId,
        second.cacheId,
      ]);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'latest rapid track selection wins after an earlier queue load',
    () async {
      final handler = _DelayedFirstLoadHandler();
      final usage = _UsageSpy();
      final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
      final second = trackFromCached(_cachedTrack(id: 'second', name: '第二首'));
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        playlistUsageStore: usage,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.createPlaylist('usage'))!;
        final firstPlay = controller.playTrack(first, playlistId: playlist.id);
        await handler.firstLoadStarted.future;
        final secondPlay = controller.playTrack(
          second,
          playlistId: playlist.id,
        );
        handler.releaseFirstLoad.complete();
        await Future.wait([firstPlay, secondPlay]);
        await Future<void>.delayed(Duration.zero);
        expect(handler.mediaItem.value?.id, second.id);
        expect(usage.events, [(playlist.id, true)]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'new playlist matches extend only its active queue without reloading',
    () async {
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.createPlaylist('识别中'))!;
        final first = _cachedTrack(id: 'first', name: '第一首');
        final firstTrack = trackFromCached(first);
        await controller.addTrackToPlaylist(playlist, firstTrack);
        await controller.playTrack(
          firstTrack,
          playlistId: playlist.id,
          queueTracks: [firstTrack],
        );
        final playCalls = handler.playCalls;
        final position = const Duration(seconds: 37);
        handler.currentPositionOverride = position;
        final second = _candidate(id: 'second', name: '第二首');
        await controller.importPlaylistSelection('识别中', [
          second,
        ], target: playlist);
        expect(handler.loadedIds, [firstTrack.id]);
        expect(handler.queue.value.map((item) => item.id), [
          firstTrack.id,
          SavedOnlineTrack(candidate: second).trackId,
        ]);
        expect(handler.mediaItem.value?.id, firstTrack.id);
        expect(handler.currentPosition, position);
        expect(handler.playCalls, playCalls);

        await controller.importPlaylistSelection('识别中', [
          second,
        ], target: playlist);
        expect(handler.queue.value.length, 2);
        await controller.playTrack(firstTrack, queueTracks: [firstTrack]);
        await controller.importPlaylistSelection('识别中', [
          _candidate(id: 'third', name: '第三首'),
        ], target: playlist);
        expect(handler.queue.value.map((item) => item.id), [firstTrack.id]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'matches saved during a playlist queue load are added afterward',
    () async {
      final handler = _DelayedSecondLoadHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.createPlaylist('识别中'))!;
        final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
        final second = trackFromCached(_cachedTrack(id: 'second', name: '第二首'));
        await controller.addTracksToPlaylist(playlist, [first, second]);
        await controller.playTrack(
          first,
          playlistId: playlist.id,
          queueTracks: [first, second],
        );
        final next = controller.playTrack(
          second,
          playlistId: playlist.id,
          queueTracks: [first, second],
        );
        await handler.secondLoadStarted.future;
        final third = _candidate(id: 'third', name: '第三首');
        await controller.importPlaylistSelection('识别中', [
          third,
        ], target: playlist);
        handler.releaseSecondLoad.complete();
        await next;
        expect(handler.queue.value.map((item) => item.id), [
          first.id,
          second.id,
          SavedOnlineTrack(candidate: third).trackId,
        ]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('reviewing a saved match replaces the upcoming queue item', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      final old = _candidate(id: 'old', name: '旧匹配');
      final replacement = _candidate(id: 'new', name: '新匹配');
      final playlist = (await controller.importPlaylistCandidates('识别中', [
        old,
      ]))!;
      final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
      await controller.addTrackToPlaylist(playlist, first);
      final oldTrack = controller.tracksForPlaylist(playlist).single;
      await controller.playTrack(
        first,
        playlistId: playlist.id,
        queueTracks: [first, oldTrack],
      );
      final playCalls = handler.playCalls;
      await controller.replaceImportedCandidate(
        playlist,
        oldTrack.id,
        replacement,
        removePrevious: true,
      );
      expect(handler.queue.value.map((item) => item.id), [
        first.id,
        SavedOnlineTrack(candidate: replacement).trackId,
      ]);
      expect(handler.mediaItem.value?.id, first.id);
      expect(handler.playCalls, playCalls);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('reviewing the playing match keeps it until the next song', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      final old = _candidate(id: 'old', name: '旧匹配');
      final replacement = _candidate(id: 'new', name: '新匹配');
      final playlist = (await controller.importPlaylistCandidates('识别中', [
        old,
      ]))!;
      final oldTrack = controller
          .tracksForPlaylist(playlist)
          .single
          .copyWith(filePath: '/tmp/old-match.mp3');
      await controller.playTrack(
        oldTrack,
        playlistId: playlist.id,
        queueTracks: [oldTrack],
      );
      final playCalls = handler.playCalls;
      await controller.replaceImportedCandidate(
        playlist,
        oldTrack.id,
        replacement,
        removePrevious: true,
      );
      final newId = SavedOnlineTrack(candidate: replacement).trackId;
      expect(handler.mediaItem.value?.id, oldTrack.id);
      expect(handler.queue.value.map((item) => item.id), [oldTrack.id, newId]);
      expect(handler.playCalls, playCalls);
      handler.emit(handler.queue.value.last);
      await Future<void>.delayed(Duration.zero);
      expect(handler.queue.value.map((item) => item.id), [newId]);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('stop waits for an in-flight queue load and stays stopped', () async {
    final handler = _DelayedFirstLoadHandler();
    final track = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      final playing = controller.playTrack(track);
      await handler.firstLoadStarted.future;
      final stopping = controller.stop();
      handler.releaseFirstLoad.complete();
      await Future.wait([playing, stopping]);
      expect(handler.playbackState.value.playing, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('queue load does not wait for a song-length play Future', () async {
    final handler = _LongPlayingHandler();
    final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
    final second = trackFromCached(_cachedTrack(id: 'second', name: '第二首'));
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      await controller.playTrack(first).timeout(const Duration(seconds: 1));
      await controller.playTrack(second).timeout(const Duration(seconds: 1));
      expect(handler.mediaItem.value?.id, second.id);
      await controller.stop().timeout(const Duration(seconds: 1));
    } finally {
      handler.finishPlayback();
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'dispose prevents a delayed queue load from starting playback',
    () async {
      final handler = _DelayedFirstLoadHandler();
      final track = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      await controller.initialize();
      final playing = controller.playTrack(track);
      await handler.firstLoadStarted.future;
      controller.dispose();
      handler.releaseFirstLoad.complete();
      await playing;
      expect(handler.playCalls, 0);
      await handler.dispose();
    },
  );

  test('media item changes trigger metadata reload', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final metadata = _StaticMetadataRepository(
      metadata: const TrackMetadata(
        lyrics: [LyricLine(time: Duration(seconds: 1), text: '第一句')],
      ),
    );
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      handler.emit(mediaItemFromTrack(trackFromCached(cached)));
      for (var i = 0; i < 10 && controller.currentLyrics.isEmpty; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(metadata.loadIds, contains(cached.cacheId));
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('metadata load keeps existing artwork media item unchanged', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(
      id: 'song-1',
      name: '第一首',
      coverUrl: 'https://cdn.example.test/song-1.jpg',
    );
    final metadata = _StaticMetadataRepository(
      metadata: TrackMetadata(
        artworkUri: Uri.parse('https://cdn.example.test/song-1.jpg'),
      ),
    );
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      handler.emit(mediaItemFromTrack(trackFromCached(cached)));
      for (var i = 0; i < 10 && metadata.loadIds.isEmpty; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(metadata.loadIds, contains(cached.cacheId));
      expect(handler.mediaItemUpdateCount, 0);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'downloaded candidate is cached before metadata priming completes',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final metadata = _CompletingMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final candidate = _candidate(id: 'song-1', name: '第一首');

      try {
        await controller.initialize();
        final loadingStates = <bool>[];
        controller.addListener(() {
          loadingStates.add(controller.isLoadingCache);
        });

        await controller.downloadCandidate(candidate);

        expect(metadata.loadIds, [cacheStore.cached.single.cacheId]);
        expect(controller.isCandidateCached(candidate), isTrue);
        expect(controller.cachedTracks.single.title, '第一首');

        metadata.complete(const TrackMetadata());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Metadata lives in its own store; completing it must not reload and
        // rewrite the entire music/playlist library for every downloaded song.
        expect(cacheStore.listCachedCalls, 1);
        expect(loadingStates, isNot(contains(true)));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'byte progress updates download listeners without rebuilding the library',
    () async {
      final handler = _SpyAudioHandler();
      final cache = _ProgressCacheStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _DelayedMusicResolver(),
        cacheStore: cache,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        var libraryNotifications = 0;
        var progressNotifications = 0;
        controller.addListener(() => libraryNotifications++);
        controller.downloadProgressChanges.addListener(
          () => progressNotifications++,
        );
        final candidate = _candidate(id: 'progress', name: 'Progress');
        final row = controller.songCacheProgress.listenable(
          controller.downloadQueue.taskIdForCandidate(candidate),
        );
        final other = controller.cacheProgressForId('unrelated');
        var otherNotifications = 0;
        other.addListener(() => otherNotifications++);
        final download = controller.downloadCandidate(
          candidate,
          background: false,
        );
        await cache.started.future;
        final before = libraryNotifications;
        for (var i = 1; i <= 100; i++) {
          cache.report!(CachedDownloadProgress(bytes: i, totalBytes: 200));
        }
        expect(libraryNotifications, before);
        expect(progressNotifications, 100);
        expect(controller.activeDownloadTasks.single.progress, .5);
        expect(row.value.fraction, .5);
        expect(row.value.offline, false);
        expect(otherNotifications, 0);
        cache.finish.complete();
        await download;
        expect(libraryNotifications, greaterThan(before));
        expect(
          controller.recentDownloadTasks.single.status,
          DownloadTaskStatus.completed,
        );
        expect(controller.isCandidateCached(candidate), true);
        expect(row.value.fraction, 1);
        expect(row.value.offline, true);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'system favorite action toggles the active track favorite state',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final playlistStore = _MemoryPlaylistStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        handler.emit(mediaItemFromTrack(track));
        handler
          ..currentPositionOverride = const Duration(seconds: 37)
          ..currentBufferedPositionOverride = const Duration(seconds: 60)
          ..currentQueueIndexOverride = 0
          ..loadedIds = const [];
        handler.playbackState.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: true,
            updatePosition: const Duration(seconds: 5),
            bufferedPosition: const Duration(seconds: 10),
            queueIndex: 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.isFavorite(track), isFalse);

        await handler.customAction(MusicAudioHandler.toggleFavoriteAction);

        expect(controller.isFavorite(track), isTrue);
        expect(playlistStore.library.favoriteTrackIds, [track.id]);
        expect(handler.loadedIds, isEmpty);
        expect(handler.restoredMediaId, isNull);
        expect(handler.restoredPosition, isNull);
        expect(
          handler.playbackState.value.updatePosition,
          const Duration(seconds: 37),
        );
        expect(
          handler.playbackState.value.bufferedPosition,
          const Duration(seconds: 60),
        );
        expect(handler.playbackState.value.queueIndex, 0);

        await handler.customAction(MusicAudioHandler.toggleFavoriteAction, {
          'mediaId': 'other-song',
        });

        expect(controller.isFavorite(track), isTrue);
        expect(playlistStore.library.favoriteTrackIds, [track.id]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('changing playback mode keeps current song and position', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final item = mediaItemFromTrack(trackFromCached(cached));
      handler
        ..emit(item)
        ..currentPositionOverride = const Duration(seconds: 42);

      await controller.setPlaybackMode(PlaybackMode.shuffle);

      expect(handler.restoredMediaId, isNull);
      expect(handler.restoredPosition, isNull);
      expect(handler.shuffleMode, AudioServiceShuffleMode.all);
      expect(handler.repeatMode, AudioServiceRepeatMode.all);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'repeating current track does not reload queue and resumes if paused',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        await controller.playTrack(track);

        handler
          ..loadedIds = const []
          ..playCalls = 0;
        handler.playbackState.add(PlaybackState(playing: true));

        await controller.playTrack(track);

        expect(handler.loadedIds, isEmpty);
        expect(handler.playCalls, 0);

        handler.playbackState.add(PlaybackState(playing: false));
        await controller.playTrack(track);

        expect(handler.loadedIds, isEmpty);
        expect(handler.playCalls, 1);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('repeating current track does not download the next song', () async {
    final handler = _SpyAudioHandler()..nextQueueIndexOverride = 1;
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final current = trackFromCached(cached);
    const upcoming = Track(
      id: 'online-next',
      title: '下一首',
      artist: '歌手',
      album: '',
    );
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      await controller.playTrack(current, queueTracks: [current, upcoming]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      handler.emit(mediaItemFromTrack(current));
      handler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handler.loadedIds, [current.id, upcoming.id]);
      expect(handler.stopCalls, 0);
      expect(handler.mediaItem.value?.id, current.id);
      expect(handler.nextQueueIndex, 1);
      expect(controller.playbackMode, PlaybackMode.sequential);
      expect(controller.pendingPrefetchTrackId, isNull);

      await controller.playTrack(current, queueTracks: [current, upcoming]);
      expect(controller.pendingPrefetchTrackId, isNull);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'playing on mobile data prefetches lyrics for the next three songs',
    () async {
      final handler = _SpyAudioHandler()..nextQueueIndexOverride = 1;
      final records = [
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          _cachedTrack(id: id, name: id),
      ];
      final cacheStore = _DownloadCacheStore()..cached.addAll(records);
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.mobile],
      );
      try {
        await controller.initialize();
        final queue = records.map(trackFromCached).toList();
        await controller.playTrack(queue.first, queueTracks: queue);
        handler.emit(mediaItemFromTrack(queue.first));
        handler.playbackState.add(
          handler.playbackState.value.copyWith(playing: true),
        );
        await Future<void>.delayed(const Duration(milliseconds: 850));

        expect(controller.isOnWifi, isFalse);
        expect(metadata.prefetchedIds, ['b', 'c', 'd']);
        expect(cacheStore.downloadIds, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'untimed lyrics upgrade retries when the song is played again',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'retry-lyrics', name: '待补时间轴');
      final metadata = _RetryingTimedMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _DownloadCacheStore()..cached.add(cached),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      try {
        await controller.initialize();
        final track = trackFromCached(cached);
        await controller.playTrack(track);
        handler.emit(mediaItemFromTrack(track));
        await Future<void>.delayed(Duration.zero);
        expect(metadata.upgradeCalls, 1);

        metadata.finishFirstAttemptWithoutTiming();
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentLyrics.last.time, Duration.zero);

        await controller.stop();
        await controller.playTrack(track);
        handler.emit(mediaItemFromTrack(track));
        await Future<void>.delayed(Duration.zero);

        expect(metadata.upgradeCalls, 2);
        expect(controller.currentLyrics.last.time, const Duration(seconds: 20));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'queueing an online next song does not resolve or download it',
    () async {
      final handler = _SpyAudioHandler()..nextQueueIndexOverride = 1;
      final first = _cachedTrack(id: 'first', name: '第一首');
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore()..cached.add(first);
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('在线歌曲');
        await controller.addCandidatesToPlaylist(playlist!, [
          _candidate(id: 'upcoming', name: '下一首'),
        ]);
        final upcoming = controller
            .tracksForPlaylist(controller.customPlaylists.single)
            .single;
        final current = trackFromCached(first);
        await controller.playTrack(current, queueTracks: [current, upcoming]);
        handler.emit(mediaItemFromTrack(current));
        handler.playbackState.add(PlaybackState(playing: true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(resolver.resolveIds, isEmpty);
        expect(cacheStore.downloadIds, isEmpty);
        expect(controller.pendingPrefetchTrackId, isNull);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'same track in a different visible queue rebuilds queue at current position',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final firstTrack = trackFromCached(first);
        final secondTrack = trackFromCached(second);
        await controller.playTrack(
          firstTrack,
          index: 0,
          queueTracks: [firstTrack, secondTrack],
        );

        handler
          ..loadedIds = const []
          ..loadedInitialPosition = null
          ..currentPositionOverride = const Duration(seconds: 38);
        handler.playbackState.add(PlaybackState(playing: true));

        await controller.playTrack(
          firstTrack,
          index: 0,
          queueTracks: [firstTrack],
        );

        expect(handler.loadedIds, [first.cacheId]);
        expect(handler.loadedInitialPosition, const Duration(seconds: 38));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('clearSearch ignores delayed stale search results', () async {
    final handler = _SpyAudioHandler();
    final resolver = _CompletingSearchResolver();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final search = controller.search('周杰伦');
      await Future<void>.delayed(Duration.zero);

      expect(controller.isSearching, isTrue);

      controller.clearSearch();
      resolver.complete([_candidate(id: 'song-1', name: '稻香')]);
      await search;

      expect(controller.isSearching, isFalse);
      expect(controller.candidates, isEmpty);
      expect(controller.errorDetail, isNull);
      expect(controller.statusMessage, isNull);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('new search supersedes an in-flight search', () async {
    final handler = _SpyAudioHandler();
    final resolver = _SequencedSearchResolver();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final firstSearch = controller.search('A');
      await Future<void>.delayed(Duration.zero);
      final secondSearch = controller.search('B');
      await Future<void>.delayed(Duration.zero);

      resolver.complete(0, [_candidate(id: 'song-a', name: '旧结果')]);
      await firstSearch;
      expect(controller.candidates, isEmpty);
      expect(controller.isSearching, isTrue);

      resolver.complete(1, [_candidate(id: 'song-b', name: '新结果')]);
      await secondSearch;

      expect(controller.candidates.single.name, '新结果');
      expect(controller.isSearching, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('favorite and playlist entries keep added time metadata', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      final track = trackFromCached(cached);

      await controller.toggleFavorite(track);
      final playlist = await controller.createPlaylist('Road');
      await controller.addTrackToPlaylist(playlist!, track);

      expect(controller.favoriteAddedAt(track), isNotNull);
      expect(
        controller.playlistTrackAddedAt(
          controller.customPlaylists.single,
          track,
        ),
        isNotNull,
      );
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'batch adding tracks appends in selection order and skips duplicates',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('Road');
        await controller.addTrackToPlaylist(playlist!, trackFromCached(first));
        await controller.addTracksToPlaylist(
          controller.customPlaylists.single,
          [trackFromCached(second), trackFromCached(first)],
        );

        expect(controller.customPlaylists.single.trackIds, [
          first.cacheId,
          second.cacheId,
        ]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'batch deleting cached tracks removes metadata and playlist references',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final cacheStore = _FakeCacheStore(cached: [first, second]);
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(
          favoriteEntries: [
            PlaylistTrackEntry(trackId: first.cacheId, addedAt: DateTime(2026)),
            PlaylistTrackEntry(
              trackId: second.cacheId,
              addedAt: DateTime(2026),
            ),
          ],
          playlists: [
            MusicPlaylist(
              id: 'road',
              name: 'Road',
              entries: [
                PlaylistTrackEntry(
                  trackId: first.cacheId,
                  addedAt: DateTime(2026),
                ),
                PlaylistTrackEntry(
                  trackId: second.cacheId,
                  addedAt: DateTime(2026),
                ),
              ],
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: cacheStore,
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );

      try {
        await controller.initialize();
        await controller.deleteCachedTracks([
          trackFromCached(first),
          trackFromCached(second),
        ]);

        expect(cacheStore.cached, isEmpty);
        expect(
          metadata.deletedIds,
          unorderedEquals([first.cacheId, second.cacheId]),
        );
        expect(controller.favoriteTracks, isEmpty);
        expect(controller.customPlaylists.single.trackIds, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'deleting a queued non-current cached track rebuilds queue around current track',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final firstTrack = trackFromCached(first);
        final secondTrack = trackFromCached(second);
        await controller.playTrack(
          firstTrack,
          index: 0,
          queueTracks: [firstTrack, secondTrack],
        );
        handler
          ..loadedIds = const []
          ..loadedInitialPosition = null
          ..currentPositionOverride = const Duration(seconds: 21);
        handler.playbackState.add(PlaybackState(playing: true));

        await controller.deleteCachedTrack(secondTrack);

        expect(handler.loadedIds, [first.cacheId]);
        expect(handler.loadedInitialPosition, const Duration(seconds: 21));
        expect(handler.mediaItem.value?.id, first.cacheId);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'deleting cached queue member retains an online current track',
    () async {
      final handler = _SpyAudioHandler();
      final cached = _cachedTrack(id: 'cached', name: '下载歌曲');
      const online = Track(
        id: 'online-current',
        title: '在线歌曲',
        artist: '歌手',
        album: '',
        source: 'https://example.test/song.mp3',
      );
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [cached]),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        await controller.playTrack(
          online,
          index: 0,
          queueTracks: [online, trackFromCached(cached)],
        );
        handler.currentPositionOverride = const Duration(seconds: 12);
        await controller.deleteCachedTrack(trackFromCached(cached));
        expect(handler.stopCalls, 0);
        expect(handler.mediaItem.value?.id, online.id);
        expect(handler.queue.value.map((item) => item.id), [online.id]);
        expect(handler.loadedInitialPosition, const Duration(seconds: 12));
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'reordering favorites and playlists preserves added time metadata',
    () async {
      final handler = _SpyAudioHandler();
      final first = _cachedTrack(id: 'song-1', name: '第一首');
      final second = _cachedTrack(id: 'song-2', name: '第二首');
      final firstAddedAt = DateTime(2026, 1, 1);
      final secondAddedAt = DateTime(2026, 1, 2);
      final playlistStore = _MemoryPlaylistStore()
        ..library = PlaylistLibrary(
          favoriteEntries: [
            PlaylistTrackEntry(trackId: first.cacheId, addedAt: firstAddedAt),
            PlaylistTrackEntry(trackId: second.cacheId, addedAt: secondAddedAt),
          ],
          playlists: [
            MusicPlaylist(
              id: 'road',
              name: 'Road',
              entries: [
                PlaylistTrackEntry(
                  trackId: first.cacheId,
                  addedAt: firstAddedAt,
                ),
                PlaylistTrackEntry(
                  trackId: second.cacheId,
                  addedAt: secondAddedAt,
                ),
              ],
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [first, second]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );

      try {
        await controller.initialize();
        final reversedTracks = [
          trackFromCached(second),
          trackFromCached(first),
        ];
        await controller.reorderFavoriteTracks(reversedTracks);
        await controller.reorderPlaylistTracks(
          controller.customPlaylists.single,
          reversedTracks,
        );

        expect(playlistStore.library.favoriteTrackIds, [
          second.cacheId,
          first.cacheId,
        ]);
        expect(
          playlistStore.library.favoriteEntries.first.addedAt,
          secondAddedAt,
        );
        expect(playlistStore.library.playlists.single.trackIds, [
          second.cacheId,
          first.cacheId,
        ]);
        expect(
          playlistStore.library.playlists.single.entries.first.addedAt,
          secondAddedAt,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('clearing media item invalidates pending metadata load', () async {
    final handler = _SpyAudioHandler();
    final cached = _cachedTrack(id: 'song-1', name: '第一首');
    final metadata = _CompletingMetadataRepository();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: [cached]),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );

    try {
      await controller.initialize();
      handler.emit(mediaItemFromTrack(trackFromCached(cached)));
      for (var i = 0; i < 10 && metadata.loadIds.isEmpty; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      handler.emit(null);
      metadata.complete(
        const TrackMetadata(
          lyrics: [LyricLine(time: Duration(seconds: 1), text: '旧歌词')],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.currentLyrics, isEmpty);
      expect(controller.currentArtworkUri, isNull);
      expect(controller.isLoadingMetadata, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('playlist mutations are serialized', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();

      final first = controller.createPlaylist('A');
      final second = controller.createPlaylist('B');
      await Future.wait([first, second]);

      expect(controller.customPlaylists.map((playlist) => playlist.name), [
        'A',
        'B',
      ]);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'downloadCandidate caches without auto-playing and allows concurrency',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final firstCandidate = _candidate(id: 'song-1', name: '第一首');
      final secondCandidate = _candidate(id: 'song-2', name: '第二首');

      try {
        await controller.initialize();

        final first = controller.downloadCandidate(firstCandidate);
        await Future<void>.delayed(Duration.zero);
        final second = controller.downloadCandidate(secondCandidate);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(resolver.resolveIds, ['song-1', 'song-2']);
        expect(controller.isCandidateDownloading(firstCandidate), isTrue);
        expect(controller.isCandidateDownloading(secondCandidate), isTrue);

        await Future.wait([first, second]);

        expect(cacheStore.downloadIds, unorderedEquals(['song-1', 'song-2']));
        expect(handler.loadedIds, isEmpty);
        expect(controller.isCandidateDownloading(firstCandidate), isFalse);
        expect(controller.isCandidateDownloading(secondCandidate), isFalse);
        expect(controller.activeDownloadTasks, isEmpty);
        expect(
          controller.cachedTracks.map((track) => track.title),
          unorderedEquals(['第一首', '第二首']),
        );
        expect(metadata.loadIds, hasLength(2));
        expect(metadata.loadIds.toSet(), {
          cacheStore.cached[0].cacheId,
          cacheStore.cached[1].cacheId,
        });
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('same media id with changed labels shares one download task', () async {
    final handler = _SpyAudioHandler();
    final resolver = _DelayedMusicResolver();
    final cacheStore = _DownloadCacheStore();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cacheStore,
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      final first = _candidate(id: 'same-id', name: '晴天');
      final renamed = _candidate(id: 'same-id', name: '晴天 Live');
      await Future.wait([
        controller.downloadCandidate(first),
        controller.downloadCandidate(renamed),
      ]);
      expect(
        controller.downloadQueue.taskIdForCandidate(first),
        controller.downloadQueue.taskIdForCandidate(renamed),
      );
      expect(resolver.resolveIds, ['same-id']);
      expect(cacheStore.downloadIds, ['same-id']);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'repeated download tap keeps task status and does not resolve twice',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _DelayedMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      final candidate = _candidate(id: 'song-1', name: '第一首');

      try {
        await controller.initialize();

        final first = controller.downloadCandidate(candidate);
        await Future<void>.delayed(Duration.zero);
        await controller.downloadCandidate(candidate);

        expect(resolver.resolveIds, ['song-1']);
        expect(
          controller.statusMessage?.code,
          MusicUiMessageCode.downloadAlreadyRunning,
        );

        await first;

        expect(controller.activeDownloadTasks, isEmpty);
        expect(
          controller.recentDownloadTasks.single.status,
          DownloadTaskStatus.completed,
        );
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('batch download joins an existing singleflight task', () async {
    final handler = _SpyAudioHandler();
    final resolver = _DelayedMusicResolver();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: _DownloadCacheStore(),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    final candidate = _candidate(id: 'song-1', name: '第一首');
    try {
      await controller.initialize();
      final first = controller.downloadCandidate(candidate);
      await Future<void>.delayed(Duration.zero);
      final joined = controller.downloadCandidateAndWait(candidate);

      await first;
      expect((await joined)?.status, DownloadTaskStatus.completed);
      expect(resolver.resolveIds, ['song-1']);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'direct screenshot download rejects a resolved different song',
    () async {
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _WrongIdentityResolver(),
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final task = await controller.downloadCandidateAndWait(
          _candidate(id: 'song-1', name: '第一首'),
          requireExactIdentity: true,
        );

        expect(task?.status, DownloadTaskStatus.failed);
        expect(cacheStore.cached, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'screenshot download can use a selected result without exact identity gate',
    () async {
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _WrongIdentityResolver(),
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final task = await controller.downloadCandidateAndWait(
          _candidate(id: 'song-1', name: '第一首'),
          requireExactIdentity: false,
        );

        expect(task?.status, DownloadTaskStatus.completed);
        expect(cacheStore.cached, hasLength(1));
        expect(cacheStore.cached.single.music.name, '另一首歌');
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'playlist selection keeps the same relaxed identity policy on download',
    () async {
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: _WrongIdentityResolver(),
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('截图歌单');
        final candidate = _candidate(id: 'song-1', name: '第一首');
        await controller.addCandidatesToPlaylist(playlist!, [candidate]);

        final task = await controller.downloadCandidateAndWait(candidate);
        expect(task?.status, DownloadTaskStatus.completed);
        expect(cacheStore.cached.single.music.name, '另一首歌');
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'Wi-Fi playlist batch skips cache and continues after one failure',
    () async {
      final connectivity =
          StreamController<List<ConnectivityResult>>.broadcast();
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore()
        ..cached.add(_cachedTrack(id: 'cached', name: '已缓存'));
      final resolver = _SelectivePlaylistResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: connectivity.stream,
        checkConnectivity: () async => [ConnectivityResult.mobile],
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('批量下载');
        await controller.addCandidatesToPlaylist(playlist!, [
          _candidate(id: 'cached', name: '已缓存'),
          _candidate(id: 'bad', name: '失败'),
          _candidate(id: 'good', name: '成功'),
        ]);

        final offline = await controller.downloadPlaylist(
          playlist,
          wifiOnly: true,
        );
        expect(offline.stoppedForWifi, isTrue);
        expect(resolver.resolveIds, isEmpty);

        connectivity.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(controller.isOnWifi, isTrue);
        final result = await controller.downloadPlaylist(
          playlist,
          wifiOnly: true,
        );
        expect(result.downloaded, 1);
        expect(result.skipped, 1);
        expect(result.failed, 1);
        expect(resolver.resolveIds, ['bad', 'good']);
        expect(cacheStore.downloadIds, ['good']);
        expect(controller.isPlaylistDownloading(playlist), isFalse);
      } finally {
        controller.dispose();
        await handler.dispose();
        await connectivity.close();
      }
    },
  );

  test(
    'Wi-Fi loss cancels the active auto download and stops the batch',
    () async {
      final connectivity =
          StreamController<List<ConnectivityResult>>.broadcast();
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final resolver = _GatedPlaylistResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: connectivity.stream,
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('WiFi断开');
        controller.playlistDownloadConcurrency = 1;
        await controller.addCandidatesToPlaylist(playlist!, [
          _candidate(id: 'first', name: '第一首'),
          _candidate(id: 'second', name: '第二首'),
        ]);

        final batch = controller.downloadPlaylist(playlist, wifiOnly: true);
        await resolver.started.future;
        connectivity.add([ConnectivityResult.mobile]);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        resolver.release.complete();
        final result = await batch;

        expect(result.stoppedForWifi, isTrue);
        expect(resolver.resolveIds, ['first']);
        expect(cacheStore.downloadIds, isEmpty);
      } finally {
        controller.dispose();
        await handler.dispose();
        await connectivity.close();
      }
    },
  );

  test(
    'brief Wi-Fi loss remains resumable when canceled work settles after recovery',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_wifi_flicker_',
      );
      final connectivity =
          StreamController<List<ConnectivityResult>>.broadcast();
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final resolver = _GatedPlaylistResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        playlistAutoDownloadStore: PlaylistAutoDownloadStore(
          rootProvider: () async => root,
        ),
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: connectivity.stream,
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('WiFi 闪断');
        controller.playlistDownloadConcurrency = 1;
        await controller.addCandidatesToPlaylist(playlist!, [
          _candidate(id: 'first', name: '第一首'),
          _candidate(id: 'second', name: '第二首'),
        ]);

        final firstBatch = controller.startWifiPlaylistDownloadOnce(playlist)!;
        await resolver.started.future;
        connectivity.add([ConnectivityResult.mobile]);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        connectivity.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        resolver.release.complete();
        final interrupted = await firstBatch;

        expect(interrupted.stoppedForWifi, isTrue);
        expect(resolver.resolveIds, ['first']);
        expect(cacheStore.downloadIds, isEmpty);

        final resumed = controller.startWifiPlaylistDownloadOnce(playlist);
        expect(resumed, isNotNull);
        final finished = await resumed!;
        expect(finished.downloaded, 2);
        expect(cacheStore.downloadIds, ['first', 'second']);
        expect(controller.startWifiPlaylistDownloadOnce(playlist), isNull);
      } finally {
        controller.dispose();
        await handler.dispose();
        await connectivity.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'unchanged Wi-Fi playlist waits 24 hours across controller restarts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_auto_playlist_',
      );
      final playlists = _MemoryPlaylistStore();
      final cache = _DownloadCacheStore();
      final resolver = _SelectivePlaylistResolver();
      final store = PlaylistAutoDownloadStore(rootProvider: () async => root);

      Future<MusicController> makeController(
        PlaylistAutoDownloadStore attempts,
      ) async {
        final controller = MusicController(
          songSearchCache: SongSearchCache.memory(),
          downloadHistoryStore: MemoryDownloadHistory(),
          audioHandler: _SpyAudioHandler(),
          resolver: resolver,
          cacheStore: cache,
          playlistStore: playlists,
          settingsStore: _FakeSettingsStore(),
          playlistAutoDownloadStore: attempts,
          metadataRepository: _StaticMetadataRepository(),
          connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
          checkConnectivity: () async => [ConnectivityResult.wifi],
        );
        await controller.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(controller.isOnWifi, isTrue);
        return controller;
      }

      MusicController? controller;
      try {
        controller = await makeController(store);
        final playlist = (await controller.createPlaylist('自动下载'))!;
        await controller.addCandidatesToPlaylist(playlist, [
          _candidate(id: 'bad', name: '一直失败'),
        ]);
        expect(
          (await controller.startWifiPlaylistDownloadOnce(playlist)!).failed,
          1,
        );
        expect(resolver.resolveIds, ['bad']);
        controller.dispose();

        final restartedStore = PlaylistAutoDownloadStore(
          rootProvider: () async => root,
        );
        controller = await makeController(restartedStore);
        final samePlaylist = controller.customPlaylists.single;
        final suppressed = await controller.startWifiPlaylistDownloadOnce(
          samePlaylist,
        )!;
        expect(suppressed.failed, 0);
        expect(resolver.resolveIds, ['bad']);

        await controller.addCandidatesToPlaylist(samePlaylist, [
          _candidate(id: 'good', name: '新加入'),
        ]);
        final changed = await controller.startWifiPlaylistDownloadOnce(
          samePlaylist,
        )!;
        expect(changed.failed, 1);
        expect(changed.downloaded, 1);
        expect(resolver.resolveIds, ['bad', 'bad', 'good']);
        final recorded = (await restartedStore.get(playlist.id))!;
        await restartedStore.record(
          playlist.id,
          PlaylistAutoDownloadAttempt(
            revision: recorded.revision,
            startedAt: DateTime.now().subtract(const Duration(hours: 25)),
          ),
        );
        controller.dispose();

        controller = await makeController(
          PlaylistAutoDownloadStore(rootProvider: () async => root),
        );
        final expired = await controller.startWifiPlaylistDownloadOnce(
          controller.customPlaylists.single,
        )!;
        expect(expired.failed, 1);
        expect(resolver.resolveIds, ['bad', 'bad', 'good', 'bad']);
      } finally {
        controller?.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'unfinished persisted auto batch retries after a process restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_unfinished_auto_',
      );
      final playlists = _MemoryPlaylistStore();
      final cache = _DownloadCacheStore();
      final firstResolver = _GatedPlaylistResolver();
      final firstHandler = _SpyAudioHandler();
      final firstStore = PlaylistAutoDownloadStore(
        rootProvider: () async => root,
      );
      final first = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: firstHandler,
        resolver: firstResolver,
        cacheStore: cache,
        playlistStore: playlists,
        settingsStore: _FakeSettingsStore(),
        playlistAutoDownloadStore: firstStore,
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      MusicController? restarted;
      _SpyAudioHandler? restartedHandler;
      try {
        await first.initialize();
        final playlist = (await first.createPlaylist('未完成'))!;
        await first.addCandidatesToPlaylist(playlist, [
          _candidate(id: 'bad', name: '待重试'),
        ]);
        unawaited(first.startWifiPlaylistDownloadOnce(playlist)!);
        await firstResolver.started.future;
        expect((await firstStore.get(playlist.id))?.completed, isFalse);
        first.dispose(); // Model process death before the batch can settle.

        final resolver = _SelectivePlaylistResolver();
        final secondStore = PlaylistAutoDownloadStore(
          rootProvider: () async => root,
        );
        restartedHandler = _SpyAudioHandler();
        restarted = MusicController(
          songSearchCache: SongSearchCache.memory(),
          downloadHistoryStore: MemoryDownloadHistory(),
          audioHandler: restartedHandler,
          resolver: resolver,
          cacheStore: cache,
          playlistStore: playlists,
          settingsStore: _FakeSettingsStore(),
          playlistAutoDownloadStore: secondStore,
          metadataRepository: _StaticMetadataRepository(),
          connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
          checkConnectivity: () async => [ConnectivityResult.wifi],
        );
        await restarted.initialize();
        final result = await restarted.startWifiPlaylistDownloadOnce(
          restarted.customPlaylists.single,
        )!;
        expect(result.failed, 1);
        expect(resolver.resolveIds, ['bad']);
        expect((await secondStore.get(playlist.id))?.completed, isTrue);
      } finally {
        restarted?.dispose();
        await firstHandler.dispose();
        await restartedHandler?.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'playlist change during attempt persistence uses the new revision once',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_auto_revision_',
      );
      final store = _DelayedPlaylistAutoDownloadStore(root);
      final resolver = _SelectivePlaylistResolver();
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: _DownloadCacheStore(),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        playlistAutoDownloadStore: store,
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      try {
        await controller.initialize();
        final playlist = (await controller.createPlaylist('改动中'))!;
        await controller.addCandidatesToPlaylist(playlist, [
          _candidate(id: 'bad', name: '原歌曲'),
        ]);
        final staleBatch = controller.startWifiPlaylistDownloadOnce(playlist)!;
        await store.pendingRecordStarted.future;
        await controller.addCandidatesToPlaylist(playlist, [
          _candidate(id: 'good', name: '新增歌曲'),
        ]);
        store.releasePendingRecord.complete();
        expect((await staleBatch).stoppedForWifi, isTrue);
        expect(resolver.resolveIds, isEmpty);

        final freshBatch = await controller.startWifiPlaylistDownloadOnce(
          playlist,
        )!;
        expect(freshBatch.failed, 1);
        expect(freshBatch.downloaded, 1);
        expect(resolver.resolveIds, ['bad', 'good']);
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('auto-download store failure does not escape into the page', () async {
    final handler = _SpyAudioHandler();
    final resolver = _SelectivePlaylistResolver();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: _DownloadCacheStore(),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      playlistAutoDownloadStore: _FailingPlaylistAutoDownloadStore(),
      metadataRepository: _StaticMetadataRepository(),
      connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
      checkConnectivity: () async => [ConnectivityResult.wifi],
    );
    try {
      await controller.initialize();
      final playlist = (await controller.createPlaylist('存储失败'))!;
      await controller.addCandidatesToPlaylist(playlist, [
        _candidate(id: 'bad', name: '待下载'),
      ]);
      final result = await controller.startWifiPlaylistDownloadOnce(playlist)!;
      expect(result.failed, 1);
      expect(controller.errorDetail, isNotNull);
      expect(controller.startWifiPlaylistDownloadOnce(playlist), isNull);
      expect(resolver.resolveIds, isEmpty);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('only the first automatic playlist batch exposes progress', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_first_playlist_progress_',
    );
    final playlists = _MemoryPlaylistStore();
    final cache = _DownloadCacheStore();
    final firstResolver = _GatedPlaylistResolver();
    final firstHandler = _SpyAudioHandler();
    final firstStore = PlaylistAutoDownloadStore(
      rootProvider: () async => root,
    );
    final first = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: firstHandler,
      resolver: firstResolver,
      cacheStore: cache,
      playlistStore: playlists,
      settingsStore: _FakeSettingsStore(),
      playlistAutoDownloadStore: firstStore,
      metadataRepository: _StaticMetadataRepository(),
      connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
      checkConnectivity: () async => [ConnectivityResult.wifi],
    );
    MusicController? second;
    _SpyAudioHandler? secondHandler;
    try {
      await first.initialize();
      final playlist = (await first.createPlaylist('首进进度'))!;
      await first.addCandidatesToPlaylist(playlist, [
        _candidate(id: 'first', name: '第一首'),
      ]);
      final beforeOpening = first.customPlaylists.single.updatedAt;
      expect(await first.claimFirstPlaylistOpening(playlist), isTrue);
      expect(first.customPlaylists.single.updatedAt, beforeOpening);
      final firstBatch = first.startWifiPlaylistDownloadOnce(
        playlist,
        showProgress: true,
      )!;
      await firstResolver.started.future;
      expect(first.playlistDownloadProgress(playlist), isNotNull);
      firstResolver.release.complete();
      await firstBatch;
      expect(first.playlistDownloadProgress(playlist), isNull);

      final nextResolver = _GatedPlaylistResolver();
      secondHandler = _SpyAudioHandler();
      second = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: secondHandler,
        resolver: nextResolver,
        cacheStore: cache,
        playlistStore: playlists,
        settingsStore: _FakeSettingsStore(),
        playlistAutoDownloadStore: PlaylistAutoDownloadStore(
          rootProvider: () async => root,
        ),
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      await second.initialize();
      final samePlaylist = second.customPlaylists.single;
      expect(await second.claimFirstPlaylistOpening(samePlaylist), isFalse);
      await second.addCandidatesToPlaylist(samePlaylist, [
        _candidate(id: 'second', name: '第二首'),
      ]);
      final laterBatch = second.startWifiPlaylistDownloadOnce(
        samePlaylist,
        showProgress: false,
      )!;
      await nextResolver.started.future;
      expect(second.isPlaylistDownloading(samePlaylist), isTrue);
      expect(second.playlistDownloadProgress(samePlaylist), isNull);
      nextResolver.release.complete();
      await laterBatch;
    } finally {
      first.dispose();
      second?.dispose();
      await firstHandler.dispose();
      await secondHandler?.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'playlist batch runs three downloads in parallel and reports progress',
    () async {
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final resolver = _ConcurrentPlaylistResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.mobile],
      );
      try {
        await controller.initialize();
        expect(controller.playlistDownloadConcurrency, 3);
        final playlist = await controller.createPlaylist('并行');
        await controller.addCandidatesToPlaylist(playlist!, [
          for (final id in ['a', 'b', 'c', 'd', 'e'])
            _candidate(id: id, name: id),
        ]);

        final batch = controller.downloadPlaylist(playlist);
        await resolver.waitForStarts(3);
        expect(resolver.started, ['a', 'b', 'c']);
        expect(controller.isPlaylistDownloading(playlist), isTrue);
        expect(controller.hasActiveDownloads, isTrue);
        expect(controller.playlistDownloadProgress(playlist)?.processed, 0);

        resolver.release('b');
        await resolver.waitForStarts(4);
        expect(resolver.started, ['a', 'b', 'c', 'd']);
        expect(controller.playlistDownloadProgress(playlist)?.processed, 1);

        resolver.release('c');
        await resolver.waitForStarts(5);
        resolver.release('a');
        resolver.release('d');
        resolver.release('e');
        final result = await batch;

        expect(result.downloaded, 5);
        expect(resolver.maxActive, 3);
        expect(controller.cachedCountForPlaylist(playlist), 5);
        expect(controller.playlistDownloadProgress(playlist), isNull);
        expect(controller.isPlaylistDownloading(playlist), isFalse);
        expect(controller.hasActiveDownloads, isFalse);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'playlist batch is registered before progress listeners can reenter',
    () async {
      final handler = _SpyAudioHandler();
      final cacheStore = _DownloadCacheStore();
      final resolver = _GatedPlaylistResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      try {
        await controller.initialize();
        final playlist = await controller.createPlaylist('重入');
        await controller.addCandidatesToPlaylist(playlist!, [
          _candidate(id: 'first', name: '第一首'),
        ]);

        PlaylistDownloadProgress? firstProgress;
        Future<PlaylistDownloadSummary>? reentrantBatch;
        var reentered = false;
        var progressWasReplaced = false;
        var progressWithoutBatch = false;
        controller.addListener(() {
          final progress = controller.playlistDownloadProgress(playlist);
          if (progress == null || progress.processed != 0) return;
          if (!controller.isPlaylistDownloading(playlist)) {
            progressWithoutBatch = true;
          }
          if (firstProgress != null && !identical(firstProgress, progress)) {
            progressWasReplaced = true;
          }
          firstProgress ??= progress;
          if (!reentered) {
            reentered = true;
            reentrantBatch = controller.downloadPlaylist(
              playlist,
              wifiOnly: true,
            );
          }
        });

        final manualBatch = controller.downloadPlaylist(playlist);
        await resolver.started.future;
        expect(reentrantBatch, isNotNull);
        expect(progressWithoutBatch, isFalse);
        expect(progressWasReplaced, isFalse);
        resolver.release.complete();
        final results = await Future.wait([manualBatch, reentrantBatch!]);
        expect(results.map((result) => result.downloaded), [1, 1]);
        expect(cacheStore.downloadIds, ['first']);
        expect(controller.isPlaylistDownloading(playlist), isFalse);
        expect(controller.playlistDownloadProgress(playlist), isNull);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('manual playlist download works on mobile data', () async {
    final handler = _SpyAudioHandler();
    final cacheStore = _DownloadCacheStore();
    final resolver = _DelayedMusicResolver();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cacheStore,
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
      connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
      checkConnectivity: () async => [ConnectivityResult.mobile],
    );
    try {
      await controller.initialize();
      final playlist = await controller.createPlaylist('手动');
      await controller.addCandidatesToPlaylist(playlist!, [
        _candidate(id: 'mobile', name: '移动网络下载'),
      ]);

      final result = await controller.downloadPlaylist(playlist);
      expect(result.downloaded, 1);
      expect(result.stoppedForWifi, isFalse);
      expect(cacheStore.downloadIds, ['mobile']);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('failed downloads remain visible as recent tasks', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FailingMusicResolver(),
      cacheStore: _DownloadCacheStore(),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      await controller.downloadCandidate(_candidate(id: 'song-1', name: '第一首'));

      expect(controller.activeDownloadTasks, isEmpty);
      expect(
        controller.recentDownloadTasks.single.status,
        DownloadTaskStatus.failed,
      );
      expect(
        controller.recentDownloadTasks.single.error,
        contains('resolve failed'),
      );

      controller.clearDownloadTask(controller.recentDownloadTasks.single.id);
      expect(controller.recentDownloadTasks, isEmpty);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('playCandidate prepares streaming without a full download', () async {
    final handler = _SpyAudioHandler();
    final resolver = _DelayedMusicResolver();
    final cacheStore = _DownloadCacheStore();
    final metadata = _StaticMetadataRepository(
      metadata: const TrackMetadata(
        lyrics: [LyricLine(time: Duration(seconds: 1), text: '哎呀歌词')],
      ),
    );
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cacheStore,
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: metadata,
    );
    final candidate = _candidate(id: 'song-1', name: '第一首');

    try {
      await controller.initialize();

      expect(controller.isCandidateCached(candidate), isFalse);

      await controller.playCandidate(candidate);

      expect(resolver.resolveIds, ['song-1']);
      expect(cacheStore.downloadIds, isEmpty);
      expect(controller.isCandidateCached(candidate), isFalse);
      expect(handler.loadedIds, [
        SavedOnlineTrack(candidate: candidate).trackId,
      ]);
      expect(handler.playCalls, 1);
      expect(controller.currentTrack?.title, '第一首');
      expect(metadata.loadIds, hasLength(1));
      expect(controller.currentLyrics.single.text, '哎呀歌词');
      expect(
        controller.statusMessage?.code,
        MusicUiMessageCode.playingOnlineStream,
      );
      expect(controller.hasSearchState, isFalse);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test('next resumes playback when player is paused', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _FakeMusicResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );

    try {
      await controller.initialize();
      handler.playbackState.add(PlaybackState(playing: false));

      await controller.next();

      expect(handler.skipNextCalls, 1);
      expect(handler.playCalls, 1);
      expect(handler.playbackState.value.playing, isTrue);
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  test(
    'playCandidate refreshes cached candidate cover without redownloading',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _CoverResolvingMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final cached = _cachedTrack(id: 'song-1', name: '第一首');
      cacheStore.cached.add(cached);
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final candidate = _candidate(
        id: 'song-1',
        name: '第一首',
        coverUrl: 'https://img.example.test/song-1.jpg',
      );

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(resolver.resolveIds, ['song-1']);
        expect(cacheStore.downloadIds, isEmpty);
        expect(
          cacheStore.cached.single.music.coverUrl,
          'https://img.example.test/song-1.jpg',
        );
        expect(metadata.loadIds, contains(cached.cacheId));
        expect(handler.loadedIds, [cached.cacheId]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test(
    'playCandidate refreshes cached candidate lyrics even when cover exists',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LyricsResolvingMusicResolver();
      final cacheStore = _DownloadCacheStore();
      final cached = _cachedTrack(
        id: 'song-1',
        name: '第一首',
        coverUrl: 'https://img.example.test/existing.jpg',
      );
      cacheStore.cached.add(cached);
      final metadata = _StaticMetadataRepository();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: cacheStore,
        playlistStore: _FakePlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: metadata,
      );
      final candidate = _candidate(id: 'song-1', name: '第一首');

      try {
        await controller.initialize();

        await controller.playCandidate(candidate);

        expect(resolver.resolveIds, ['song-1']);
        expect(cacheStore.downloadIds, isEmpty);
        expect(cacheStore.cached.single.music.coverUrl, cached.music.coverUrl);
        expect(cacheStore.cached.single.music.lyrics?.text, contains('补齐歌词'));
        expect(metadata.loadIds, contains(cached.cacheId));
        expect(handler.loadedIds, [cached.cacheId]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('overlapping stream reads keep the active part protected', () async {
    final originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final root = await Directory.systemTemp.createTemp('active_stream_part_');
    final payload = List<int>.generate(20000, (i) => i % 251);
    final release = Completer<void>();
    final firstChunk = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      final response = request.response;
      response.bufferOutput = false;
      response.headers.contentType = ContentType('audio', 'mpeg');
      if (range == 'bytes=0-') {
        response
          ..statusCode = HttpStatus.partialContent
          ..contentLength = payload.length
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-${payload.length - 1}/${payload.length}',
          )
          ..add(payload.sublist(0, 4096));
        await response.flush();
        await release.future;
        try {
          response.add(payload.sublist(4096));
          await response.close();
        } catch (_) {}
      } else {
        expect(range, 'bytes=4096-8191');
        response
          ..statusCode = HttpStatus.partialContent
          ..contentLength = 4096
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 4096-8191/${payload.length}',
          )
          ..add(payload.sublist(4096, 8192));
        await response.close();
      }
    });
    final store = _TrimmingProbeCacheStore(root);
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      audioHandler: handler,
      resolver: _LocalStreamResolver(server.port),
      cacheStore: store,
      playlistStore: _FakePlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      await controller.playCandidate(_candidate(id: 'song-1', name: '第一首'));
      final source = handler.loadedItems.single.source as ResumableAudioSource;
      final first = await source.request();
      final firstDone = first.stream.listen((_) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      }).asFuture<void>();
      await firstChunk.future.timeout(const Duration(seconds: 2));
      final part = File('${store.target.path}.part');
      expect(await part.length(), 4096);

      final second = await source.request(0, 8192);
      expect(
        await second.stream.expand((chunk) => chunk).toList(),
        payload.sublist(0, 8192),
      );
      await store.firstTrim.future.timeout(const Duration(seconds: 2));
      expect(store.protectedAtFirstTrim, true);
      expect(await part.exists(), true);

      release.complete();
      await firstDone;
    } finally {
      if (!release.isCompleted) release.complete();
      controller.dispose();
      await handler.dispose();
      await server.close(force: true);
      await root.delete(recursive: true);
      HttpOverrides.global = originalHttpOverrides;
    }
  });
}

class _SpyAudioHandler extends MusicAudioHandler {
  List<String> loadedIds = const [];
  List<PlayableAudio> loadedItems = const [];
  AudioServiceShuffleMode? shuffleMode;
  AudioServiceRepeatMode? repeatMode;
  Duration currentPositionOverride = Duration.zero;
  Duration currentBufferedPositionOverride = Duration.zero;
  int? currentQueueIndexOverride;
  int? nextQueueIndexOverride;
  Duration? loadedInitialPosition;
  String? restoredMediaId;
  Duration? restoredPosition;
  int playCalls = 0;
  int skipNextCalls = 0;
  int mediaItemUpdateCount = 0;
  int stopCalls = 0;

  @override
  Duration get currentPosition => currentPositionOverride;

  @override
  Duration get currentBufferedPosition => currentBufferedPositionOverride;

  @override
  int? get currentQueueIndex => currentQueueIndexOverride;

  @override
  int? get nextQueueIndex => nextQueueIndexOverride;

  @override
  int? followingQueueIndex(String mediaId) {
    final index = loadedIds.indexOf(mediaId);
    return index >= 0 && index + 1 < loadedIds.length ? index + 1 : null;
  }

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    loadedItems = items;
    loadedIds = [for (final item in items) item.mediaItem.id];
    loadedInitialPosition = initialPosition;
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex].mediaItem);
    }
    if (playWhenReady) {
      await play();
    }
  }

  @override
  Future<void> appendQueue(List<PlayableAudio> additions) async {
    queue.add([...queue.value, ...additions.map((item) => item.mediaItem)]);
  }

  @override
  Future<void> replaceQueueItemAt(int index, PlayableAudio replacement) async {
    queue.add([...queue.value]..[index] = replacement.mediaItem);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    queue.add([...queue.value]..removeAt(index));
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    mediaItem.add(null);
    queue.add(const []);
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> skipToNext() async {
    skipNextCalls += 1;
    await play();
  }

  @override
  Future<void> updateCurrentMediaItem(MediaItem updated) async {
    mediaItemUpdateCount += 1;
    mediaItem.add(updated);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    this.shuffleMode = shuffleMode;
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    this.repeatMode = repeatMode;
  }

  @override
  Future<void> restoreCurrentItemPosition(
    String mediaId,
    Duration position,
  ) async {
    restoredMediaId = mediaId;
    restoredPosition = position;
  }

  void emit(MediaItem? item) {
    mediaItem.add(item);
  }
}

class _DelayedPlaybackModeHandler extends _SpyAudioHandler {
  final shuffleChangeStarted = Completer<void>();
  final releaseShuffleChange = Completer<void>();
  bool blockNextShuffleChange = false;

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (blockNextShuffleChange) {
      blockNextShuffleChange = false;
      shuffleChangeStarted.complete();
      await releaseShuffleChange.future;
    }
    await super.setShuffleMode(shuffleMode);
  }
}

class _DelayedFirstLoadHandler extends _SpyAudioHandler {
  final firstLoadStarted = Completer<void>();
  final releaseFirstLoad = Completer<void>();
  var _loads = 0;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    _loads += 1;
    if (_loads == 1) {
      firstLoadStarted.complete();
      await releaseFirstLoad.future;
    }
    await super.loadQueue(
      items,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      playWhenReady: playWhenReady,
    );
  }
}

class _DelayedSecondLoadHandler extends _SpyAudioHandler {
  final secondLoadStarted = Completer<void>();
  final releaseSecondLoad = Completer<void>();
  var _loads = 0;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    _loads += 1;
    if (_loads == 2) {
      secondLoadStarted.complete();
      await releaseSecondLoad.future;
    }
    await super.loadQueue(
      items,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      playWhenReady: playWhenReady,
    );
  }
}

class _LongPlayingHandler extends _SpyAudioHandler {
  final _playFinished = Completer<void>();

  @override
  Future<void> play() {
    playCalls += 1;
    playbackState.add(playbackState.value.copyWith(playing: true));
    return _playFinished.future;
  }

  void finishPlayback() {
    if (!_playFinished.isCompleted) _playFinished.complete();
  }
}

class _StaticMetadataRepository extends TrackMetadataRepository {
  _StaticMetadataRepository({this.metadata = const TrackMetadata()});

  final TrackMetadata metadata;
  final loadIds = <String>[];
  final prefetchedIds = <String>[];
  final deletedIds = <String>[];

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return metadata;
  }

  @override
  Future<TrackMetadata> loadBypassingLyricsMiss(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return metadata;
  }

  @override
  Future<TrackMetadata> prefetchLyrics(CachedTrack track) async {
    prefetchedIds.add(track.music.id);
    return metadata;
  }

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) async => metadata;

  @override
  Future<void> delete(String cacheId) async {
    deletedIds.add(cacheId);
  }
}

class _RetryingTimedMetadataRepository extends _StaticMetadataRepository {
  _RetryingTimedMetadataRepository()
    : super(
        metadata: const TrackMetadata(
          lyrics: [
            LyricLine(time: Duration.zero, text: '第一句'),
            LyricLine(time: Duration.zero, text: '第二句'),
          ],
        ),
      );

  final Completer<TrackMetadata> _firstAttempt = Completer<TrackMetadata>();
  int upgradeCalls = 0;

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) {
    upgradeCalls += 1;
    if (upgradeCalls == 1) return _firstAttempt.future;
    return Future.value(
      const TrackMetadata(
        lyrics: [
          LyricLine(time: Duration(seconds: 1), text: '第一句'),
          LyricLine(time: Duration(seconds: 20), text: '第二句'),
        ],
      ),
    );
  }

  void finishFirstAttemptWithoutTiming() => _firstAttempt.complete(metadata);
}

class _CompletingMetadataRepository extends TrackMetadataRepository {
  final loadIds = <String>[];
  final _completer = Completer<TrackMetadata>();

  @override
  Future<TrackMetadata> load(CachedTrack track) async {
    loadIds.add(track.cacheId);
    return _completer.future;
  }

  void complete(TrackMetadata metadata) {
    _completer.complete(metadata);
  }
}

class _FakeCacheStore extends CachedTrackStore {
  @override
  Future<Map<String, ({int bytes, int? total})>> partialProgress() async => {};

  _FakeCacheStore({required this.cached});

  final List<CachedTrack> cached;

  @override
  Future<List<CachedTrack>> listCached() async {
    return cached;
  }

  @override
  Future<void> cleanupTemporaryFiles() async {}

  @override
  Future<void> deleteCached(String cacheId) async {
    cached.removeWhere((track) => track.cacheId == cacheId);
  }
}

class _FakePlaylistStore extends PlaylistStore {
  _FakePlaylistStore() : super(rootProvider: _unusedRootProvider);

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async {
    return const PlaylistLibrary.empty();
  }

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {}
}

class _MemoryPlaylistStore extends PlaylistStore {
  _MemoryPlaylistStore() : super(rootProvider: _unusedRootProvider);

  PlaylistLibrary library = const PlaylistLibrary.empty();

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    library = _sanitize(library, validTrackIds);
    return library;
  }

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    this.library = _sanitize(library, validTrackIds);
  }

  PlaylistLibrary _sanitize(PlaylistLibrary library, Set<String>? validIds) {
    List<PlaylistTrackEntry> filter(List<PlaylistTrackEntry> entries) {
      final unique = <PlaylistTrackEntry>[];
      final seen = <String>{};
      for (final entry in entries) {
        if (seen.add(entry.trackId) &&
            (validIds == null ||
                validIds.contains(entry.trackId) ||
                entry.onlineTrack != null ||
                entry.song != null)) {
          unique.add(entry);
        }
      }
      return unique;
    }

    return PlaylistLibrary(
      favoriteEntries: filter(library.favoriteEntries),
      playlists: [
        for (final playlist in library.playlists)
          playlist.copyWith(entries: filter(playlist.entries)),
      ],
    );
  }
}

class _ControllerLanGateway implements LanLibraryGateway {
  _ControllerLanGateway({required this.manifest, required this.audio});

  final LanLibraryManifest manifest;
  final List<int> audio;

  @override
  Future<LanLibraryManifest> fetchLibrary(String baseUrl) async => manifest;

  @override
  Uri resolveAssetUri(String baseUrl, LanAsset asset) {
    return Uri.parse(baseUrl).resolveUri(asset.url);
  }

  @override
  Future<LanLibraryHealth> testConnection(String baseUrl) async {
    return LanLibraryHealth(
      schemaVersion: manifest.schemaVersion,
      trackCount: manifest.tracks.length,
    );
  }

  @override
  Future<int> downloadAsset(String baseUrl, LanAsset asset, File target) async {
    await target.writeAsBytes(audio);
    return audio.length;
  }
}

List<int> _controllerLanMp3Bytes() {
  return [
    0x49,
    0x44,
    0x33,
    0x04,
    0x00,
    0x00,
    ...List<int>.filled(16 * 1024, 0x42),
  ];
}

class _FakeSettingsStore implements MusicSettingsStore {
  @override
  Future<MusicAppSettings> loadSettings() async {
    return const MusicAppSettings();
  }

  @override
  Future<void> saveSettings(MusicAppSettings settings) async {}

  @override
  Future<MusicDataSource> loadSource() async {
    return MusicDataSource.buguyy;
  }

  @override
  Future<void> saveSource(MusicDataSource source) async {}
}

class _FakeMusicResolver implements MusicResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    return const [];
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    throw UnimplementedError();
  }
}

class _LocalStreamResolver extends _FakeMusicResolver {
  _LocalStreamResolver(this.port);

  final int port;

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'http://127.0.0.1:$port/song',
      quality: const MusicQuality(format: 'mp3', bitrate: '128'),
    );
  }
}

class _TrimmingProbeCacheStore extends CachedTrackStore {
  _TrimmingProbeCacheStore(Directory root)
    : target = File('${root.path}/song.mp3'),
      super(rootProvider: (() async => root));

  final File target;
  final Completer<void> firstTrim = Completer<void>();
  bool? protectedAtFirstTrim;

  @override
  Future<File> playbackTargetFor(ResolvedMusic music) async => target;

  @override
  Future<void> trimPlaybackParts({
    Set<String> protectedPaths = const {},
  }) async {
    final part = File('${target.path}.part');
    if (!firstTrim.isCompleted) {
      protectedAtFirstTrim = protectedPaths.contains(part.path);
      firstTrim.complete();
    }
    if (await part.exists() && !protectedPaths.contains(part.path)) {
      await part.delete();
    }
  }
}

class _DelayedMusicResolver implements MusicResolver {
  final resolveIds = <String>[];

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    return const [];
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
    );
  }
}

class _LazySongResolver extends _DelayedMusicResolver {
  int searchCalls = 0;
  bool failFirst = false;
  Completer<List<MusicSearchCandidate>>? gate;
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    searchCalls++;
    return gate?.future ??
        Future.value([
          _candidate(id: 'first', name: '默认第一首'),
          _candidate(id: 'second', name: '候选第二首'),
        ]);
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) {
    if (failFirst && candidate.id == 'first') {
      resolveIds.add(candidate.id);
      throw StateError('Source unavailable');
    }
    return super.resolve(candidate);
  }
}

class _SelectivePlaylistResolver extends _DelayedMusicResolver {
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) {
    if (candidate.id == 'bad') {
      resolveIds.add(candidate.id);
      throw StateError('one song failed');
    }
    return super.resolve(candidate);
  }
}

class _DelayedPlaylistAutoDownloadStore extends PlaylistAutoDownloadStore {
  _DelayedPlaylistAutoDownloadStore(Directory root)
    : super(rootProvider: () async => root);

  final pendingRecordStarted = Completer<void>();
  final releasePendingRecord = Completer<void>();
  bool _delayFirstPendingRecord = true;

  @override
  Future<void> record(
    String playlistId,
    PlaylistAutoDownloadAttempt attempt,
  ) async {
    if (!attempt.completed && _delayFirstPendingRecord) {
      _delayFirstPendingRecord = false;
      pendingRecordStarted.complete();
      await releasePendingRecord.future;
    }
    await super.record(playlistId, attempt);
  }
}

class _FailingPlaylistAutoDownloadStore extends PlaylistAutoDownloadStore {
  @override
  Future<PlaylistAutoDownloadAttempt?> get(String playlistId) async {
    throw const FileSystemException('attempt file unavailable');
  }
}

class _GatedPlaylistResolver extends _DelayedMusicResolver {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    if (!started.isCompleted) started.complete();
    await release.future;
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
    );
  }
}

class _ConcurrentPlaylistResolver extends _DelayedMusicResolver {
  final started = <String>[];
  final _gates = <String, Completer<void>>{};
  final _startWaiters = <int, Completer<void>>{};
  int active = 0;
  int maxActive = 0;

  Future<void> waitForStarts(int count) {
    if (started.length >= count) return Future<void>.value();
    return (_startWaiters[count] ??= Completer<void>()).future;
  }

  void release(String id) => _gates[id]!.complete();

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    started.add(candidate.id);
    active += 1;
    if (active > maxActive) maxActive = active;
    final gate = Completer<void>();
    _gates[candidate.id] = gate;
    for (final entry in _startWaiters.entries) {
      if (started.length >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    await gate.future;
    active -= 1;
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
    );
  }
}

class _WrongIdentityResolver extends _DelayedMusicResolver {
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async =>
      ResolvedMusic(
        query: candidate.query,
        source: candidate.source,
        platform: candidate.platform,
        id: candidate.id,
        name: '另一首歌',
        artist: candidate.artist,
        album: candidate.album,
        url: 'https://cdn.example.test/${candidate.id}.mp3',
        quality: const MusicQuality(format: 'mp3'),
      );
}

class _FailingMusicResolver extends _FakeMusicResolver {
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    throw StateError('resolve failed');
  }
}

class _CoverResolvingMusicResolver extends _FakeMusicResolver {
  final resolveIds = <String>[];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
      coverUrl: candidate.coverUrl,
    );
  }
}

class _LyricsResolvingMusicResolver extends _FakeMusicResolver {
  final resolveIds = <String>[];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveIds.add(candidate.id);
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}.mp3',
      quality: const MusicQuality(format: 'mp3'),
      lyrics: const ResolvedLyrics(
        source: 'test',
        text: '[00:01.00]补齐歌词',
        lines: 1,
        timed: true,
      ),
    );
  }
}

class _CompletingSearchResolver extends _FakeMusicResolver {
  final _searchCompleter = Completer<List<MusicSearchCandidate>>();

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    return _searchCompleter.future;
  }

  void complete(List<MusicSearchCandidate> candidates) {
    _searchCompleter.complete(candidates);
  }
}

class _SequencedSearchResolver extends _FakeMusicResolver {
  final _searchCompleters = <Completer<List<MusicSearchCandidate>>>[];

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    final completer = Completer<List<MusicSearchCandidate>>();
    _searchCompleters.add(completer);
    return completer.future;
  }

  void complete(int index, List<MusicSearchCandidate> candidates) {
    _searchCompleters[index].complete(candidates);
  }
}

class _DownloadCacheStore extends CachedTrackStore {
  final cached = <CachedTrack>[];
  final downloadIds = <String>[];
  int listCachedCalls = 0;

  @override
  Future<CachedTrack> downloadOrReuse(
    ResolvedMusic result, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCanceled();
    downloadIds.add(result.id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final track = CachedTrack(
      cacheId: cacheIdForResolved(result),
      music: result,
      filePath: '/tmp/${result.id}.mp3',
      sizeBytes: 4,
      fromCache: false,
    );
    cached.add(track);
    return track;
  }

  @override
  Future<List<CachedTrack>> listCached() async {
    listCachedCalls += 1;
    return List<CachedTrack>.unmodifiable(cached);
  }

  @override
  Future<CachedTrack> updateCachedMusic(
    CachedTrack cachedTrack,
    ResolvedMusic music,
  ) async {
    final index = cached.indexWhere(
      (track) => track.cacheId == cachedTrack.cacheId,
    );
    final updated = cachedTrack.copyWith(music: music, fromCache: true);
    if (index == -1) {
      cached.add(updated);
    } else {
      cached[index] = updated;
    }
    return updated;
  }

  @override
  Future<void> cleanupTemporaryFiles() async {}
}

MusicSearchCandidate _candidate({
  required String id,
  required String name,
  String coverUrl = '',
}) {
  return MusicSearchCandidate(
    query: name,
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    keyword: name,
    page: 1,
    id: id,
    name: name,
    artist: 'artist',
    album: '',
    duration: 200,
    link: '',
    coverUrl: coverUrl,
    qualities: const [MusicQuality(format: 'mp3')],
    score: 100,
    raw: const {},
  );
}

CachedTrack _cachedTrack({
  required String id,
  required String name,
  String coverUrl = '',
}) {
  final music = ResolvedMusic(
    query: name,
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: id,
    name: name,
    artist: 'artist',
    album: '',
    url: 'https://cdn.example.test/$id.mp3',
    quality: const MusicQuality(format: 'mp3'),
    coverUrl: coverUrl,
  );
  return CachedTrack(
    cacheId: cacheIdForResolved(music),
    music: music,
    filePath: '/tmp/$id.mp3',
    sizeBytes: 4,
    fromCache: true,
  );
}

Future<Directory> _unusedRootProvider() async {
  return Directory.systemTemp.createTemp('ai_music_unused_');
}

class _ProgressCacheStore extends _DownloadCacheStore {
  final started = Completer<void>();
  final finish = Completer<void>();
  void Function(CachedDownloadProgress)? report;
  @override
  Future<CachedTrack> downloadOrReuse(
    ResolvedMusic result, {
    void Function(CachedDownloadProgress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    report = onProgress;
    started.complete();
    await finish.future;
    return super.downloadOrReuse(
      result,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}

class _UsageSpy extends PlaylistUsageStore {
  final events = <(String, bool)>[];
  @override
  Future<void> load() async {}
  @override
  Future<void> record(String id, {required bool played}) async {
    events.add((id, played));
  }
}

class _DelayedDownloadHistory extends MemoryDownloadHistory {
  final loaded = Completer<List<Map<String, dynamic>>>();
  final written = Completer<void>();
  @override
  Future<List<Map<String, dynamic>>> read() => loaded.future;
  @override
  Future<void> write(List<Map<String, Object?>> tasks) async {
    await super.write(tasks);
    if (!written.isCompleted) written.complete();
  }
}

class _SearchCacheProbeResolver extends _FakeMusicResolver {
  int calls = 0;
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    calls++;
    return [_candidate(id: '$calls', name: '歌曲')];
  }
}

class _PrefetchProbeResolver extends _LocalStreamResolver
    implements QualitySelectableMusicResolver {
  _PrefetchProbeResolver(super.port);
  final ids = <String>[];
  final levels = <MusicQualityLevel>[];
  @override
  Future<ResolvedMusic> resolveAtQuality(
    MusicSearchCandidate candidate,
    MusicQualityLevel level,
  ) async {
    ids.add(candidate.id);
    levels.add(level);
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'http://127.0.0.1:$port/${candidate.id}',
      quality: const MusicQuality(format: 'mp3', bitrate: '128'),
    );
  }
}
