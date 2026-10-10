import 'package:ai_music/src/data/music_charts.dart';
import 'package:ai_music/src/data/auto_source_health.dart';
import 'package:ai_music/src/data/playlist_song.dart';
import 'package:ai_music/src/data/listening_stats_store.dart';
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

  for (final stage in ['search', 'resolve', 'load']) {
    for (final command in [
      'pause',
      'next',
      'system pause',
      'system next',
      'stop',
    ]) {
      test('Auto recovery respects $command during $stage', () async {
        final resolver = _DelayedRecoveryResolver(stage);
        final handler = _MediaHealthHandler();
        final f = await _SourcePreferenceFixture.create(
          initialSource: MusicDataSource.auto,
          resolverOverride: resolver,
          handlerOverride: handler,
        );
        try {
          final track = f.track;
          await f.controller.playTrack(track, queueTracks: [track]);
          if (stage == 'load') handler.recoveryLoadGate = resolver.release;
          final prepared =
              (handler.loadedItems.single.source
                          as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          for (var i = 0; i < 3; i++) {
            prepared.onFailure!(const HttpException('Audio HTTP 503'));
          }
          if (stage == 'load') {
            await handler.recoveryLoadStarted.future;
          } else {
            await resolver.started.future;
          }
          Future<void>? stopping;
          switch (command) {
            case 'pause':
              await f.controller.togglePlayPause();
            case 'next':
              await f.controller.next();
            case 'system pause':
              await handler.pause();
            case 'system next':
              await handler.skipToNext();
            case 'stop':
              stopping = f.controller.stop();
          }
          final playsAfterCommand = handler.playCalls;
          resolver.release.complete();
          await stopping;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            handler.playCalls,
            playsAfterCommand,
            reason: 'Stale recovery must not play after a newer command',
          );
          if (command.contains('pause') || command == 'stop') {
            expect(handler.playbackState.value.playing, false);
          }
          if (stage != 'load') expect(handler.loadCalls, 1);
        } finally {
          if (!resolver.release.isCompleted) resolver.release.complete();
          await f.close();
        }
      });
    }
  }

  group('legacy QQ playlist metadata repair', () {
    for (final action in ['play', 'favorite']) {
      test(
        '$action does not revive vocal cache when the logical song ID is its old cache ID',
        () async {
          final f = await _QqMetadataFixture.create(useCacheId: true);
          try {
            final stale = f.track;
            expect(stale.id, f.cache.cached.single.cacheId);
            if (action == 'play') {
              await f.controller.playTrack(stale, queueTracks: [stale]);
              expect(
                f.handler.loadedItems.single.source,
                isA<DeferredStreamingAudioSource>(),
              );
              final prepared =
                  (f.handler.loadedItems.single.source
                              as DeferredStreamingAudioSource)
                          .initialSource
                      as ResumableAudioSource;
              expect(prepared.url.path, '/instrumental');
            } else {
              await f.controller.toggleFavorite(stale);
              await f.controller.waitForFavoriteDownloads();
              expect(f.cache.downloadIds, ['instrumental']);
            }
            expect(f.repository.calls, ['42']);
            expect(f.resolver.ids, ['instrumental']);
            expect(f.controller.selectedSongSource(stale)?.id, 'instrumental');
            expect(f.controller.customPlaylists.single.trackIds, [stale.id]);
            expect(await f.vocalFile.exists(), true);
          } finally {
            await f.close();
          }
        },
      );
    }

    test(
      'a stale repaired song later in a new queue cannot keep its old vocal URI',
      () async {
        final f = await _QqMetadataFixture.create();
        try {
          final stale = f.track;
          await f.controller.matchPlaylistSources(f.playlist.id);
          final current = stale.copyWith(id: 'current-local', title: '本地歌曲');
          await f.controller.playTrack(current, queueTracks: [current, stale]);
          expect(f.repository.calls, ['42']);
          expect(f.handler.loadedItems, hasLength(2));
          expect(
            f.handler.loadedItems.last.source,
            isA<DeferredStreamingAudioSource>(),
          );
          expect(f.handler.loadedItems.last.mediaItem.title, '回忆观影券 (伴奏)');
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'a reused pre-repair Track snapshot cannot replay the old vocal file later',
      () async {
        final f = await _QqMetadataFixture.create();
        try {
          final stale = f.track;
          await f.controller.playTrack(stale, queueTracks: [stale]);
          await f.controller.stop();
          await f.controller.playTrack(stale, queueTracks: [stale]);
          expect(f.repository.calls, ['42']);
          expect(
            f.handler.loadedItems.single.source,
            isA<DeferredStreamingAudioSource>(),
          );
          final prepared =
              (f.handler.loadedItems.single.source
                          as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          expect(prepared.url.path, '/instrumental');
          expect(f.resolver.ids, ['instrumental', 'instrumental']);
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'favorite download repairs legacy QQ identity before reusing old audio',
      () async {
        final f = await _QqMetadataFixture.create();
        try {
          final stale = f.track;
          await f.controller.toggleFavorite(stale);
          await f.controller.waitForFavoriteDownloads();
          expect(f.repository.calls, ['42']);
          expect(f.cache.downloadIds, ['instrumental']);
          expect(f.controller.favoriteTracks.single.id, stale.id);
          expect(
            f.store.library.favoriteEntries.single.song?.title,
            '回忆观影券 (伴奏)',
          );
          expect(
            f.store.library.favoriteEntries.single.onlineTrack?.candidate.id,
            'instrumental',
          );
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'version repair stops playing a valid vocal cache and preserves its file and logical order',
      () async {
        final f = await _QqMetadataFixture.create(favorite: true);
        try {
          final oldTrack = f.track;
          expect(oldTrack.filePath, f.vocalFile.path);
          expect(f.repository.calls, isEmpty);
          final ids = f.playlist.trackIds;
          await f.controller.playTrack(
            oldTrack,
            queueTracks: [oldTrack],
            playlistId: f.playlist.id,
          );
          expect(f.repository.calls, ['42']);
          expect(f.resolver.ids, ['instrumental']);
          expect(
            f.controller.originalSongForTrack(oldTrack)?.title,
            '回忆观影券 (伴奏)',
          );
          expect(
            f.controller.originalSongForTrack(oldTrack)?.metadataVersion,
            1,
          );
          expect(f.controller.selectedSongSource(oldTrack)?.id, 'instrumental');
          expect(f.controller.customPlaylists.single.trackIds, ids);
          expect(f.store.library.favoriteEntries.single.trackId, oldTrack.id);
          expect(
            f.store.library.favoriteEntries.single.song?.title,
            '回忆观影券 (伴奏)',
          );
          expect(
            f.store.library.playlists.single.entries.single.addedAt,
            DateTime(2026, 10, 1),
          );
          final prepared =
              (f.handler.loadedItems.single.source
                          as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          expect(prepared.url.path, '/instrumental');
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'download all repairs original metadata before treating vocal cache as already downloaded',
      () async {
        final f = await _QqMetadataFixture.create();
        try {
          final result = await f.controller.downloadPlaylist(f.playlist);
          expect(result.downloaded, 1);
          expect(result.skipped, 0);
          expect(result.failed, 0);
          expect(f.repository.calls, ['42']);
          expect(f.cache.downloadIds, ['instrumental']);
          expect(f.resolver.ids, ['instrumental']);
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'explicit manual vocal choice remains cached while original QQ metadata is repaired',
      () async {
        final f = await _QqMetadataFixture.create(manual: true);
        try {
          final oldTrack = f.track;
          await f.controller.playTrack(oldTrack, queueTracks: [oldTrack]);
          expect(f.repository.calls, ['42']);
          expect(
            f.controller.originalSongForTrack(oldTrack)?.title,
            '回忆观影券 (伴奏)',
          );
          expect(f.controller.selectedSongSource(oldTrack)?.id, 'vocal');
          expect(
            f.store.library.playlists.single.entries.single.manualSource,
            true,
          );
          expect(f.resolver.ids, isEmpty);
          expect(f.track.filePath, f.vocalFile.path);
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'metadata lookup failure leaves local playback usable and is not repeated in the process',
      () async {
        final f = await _QqMetadataFixture.create();
        f.repository.failure = const SocketException('metadata unavailable');
        try {
          final oldTrack = f.track;
          await f.controller.playTrack(oldTrack, queueTracks: [oldTrack]);
          await f.controller.playTrack(oldTrack, queueTracks: [oldTrack]);
          await f.controller.matchPlaylistSources(f.playlist.id);
          expect(f.repository.calls, ['42']);
          expect(f.resolver.ids, isEmpty);
          expect(f.controller.selectedSongSource(oldTrack)?.id, 'vocal');
          expect(
            f.controller.originalSongForTrack(oldTrack)?.metadataVersion,
            0,
          );
          expect(f.handler.mediaItem.value?.id, oldTrack.id);
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'playback and download share one pending original metadata request',
      () async {
        final f = await _QqMetadataFixture.create();
        f.repository.gate = Completer<OnlinePlaylistSong>();
        try {
          final oldTrack = f.track;
          final playing = f.controller.playTrack(
            oldTrack,
            queueTracks: [oldTrack],
          );
          await f.repository.started.future.timeout(const Duration(seconds: 2));
          final downloading = f.controller.downloadPlaylist(f.playlist);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(f.repository.calls, ['42']);
          f.repository.gate!.complete(_repairedQqSong);
          await playing;
          final result = await downloading;
          expect(result.failed, 0);
          expect(f.repository.calls, ['42']);
          expect(f.resolver.ids, everyElement('instrumental'));
          expect(
            f.controller.originalSongForTrack(oldTrack)?.metadataVersion,
            1,
          );
        } finally {
          await f.close();
        }
      },
    );

    test(
      'manual source chosen during QQ refresh survives its late response',
      () async {
        final f = await _QqMetadataFixture.create();
        f.repository.gate = Completer<OnlinePlaylistSong>();
        try {
          final oldTrack = f.track;
          final matching = f.controller.matchPlaylistSources(f.playlist.id);
          await f.repository.started.future.timeout(const Duration(seconds: 2));
          await f.controller.chooseSongSource(
            oldTrack,
            _qqRepairCandidate('manual', '回忆观影券 (现场手选)'),
          );
          f.repository.gate!.complete(_repairedQqSong);
          await matching;
          expect(
            f.store.library.playlists.single.entries.single.manualSource,
            true,
          );
          expect(f.controller.selectedSongSource(oldTrack)?.id, 'manual');
          expect(f.controller.customPlaylists.single.trackIds, [oldTrack.id]);
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'deleted playlist entry is not resurrected by late QQ metadata',
      () async {
        final f = await _QqMetadataFixture.create();
        f.repository.gate = Completer<OnlinePlaylistSong>();
        try {
          final oldTrack = f.track;
          final matching = f.controller.matchPlaylistSources(f.playlist.id);
          await f.repository.started.future.timeout(const Duration(seconds: 2));
          await f.controller.removeTrackFromPlaylist(f.playlist, oldTrack);
          f.repository.gate!.complete(_repairedQqSong);
          await matching;
          expect(f.controller.customPlaylists.single.trackIds, isEmpty);
          expect(f.store.library.playlists.single.entries, isEmpty);
          expect(f.controller.canSwitchSongSource(oldTrack), false);
          expect(await f.vocalFile.exists(), true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'already current metadata does not require a QQ network lookup',
      () async {
        final f = await _QqMetadataFixture.create(metadataVersion: 1);
        try {
          final track = f.track;
          await f.controller.playTrack(track, queueTracks: [track]);
          expect(f.repository.calls, isEmpty);
          expect(f.resolver.ids, isEmpty);
        } finally {
          await f.close();
        }
      },
    );
  });

  group('auto source media failure recovery', () {
    for (final action in ['pause', 'next']) {
      test(
        '$action during failed native load cancels the queued automatic recovery',
        () async {
          final resolver = _MediaHealthResolver();
          final handler = _MediaHealthHandler()..failFirstLoad = true;
          final release = Completer<void>();
          handler.firstFailureGate = release;
          resolver.reportSourceFailure(
            MusicDataSource.buguyy,
            const HttpException('Audio HTTP 503'),
          );
          resolver.reportSourceFailure(
            MusicDataSource.buguyy,
            const HttpException('Audio HTTP 503'),
          );
          final f = await _SourcePreferenceFixture.create(
            initialSource: MusicDataSource.auto,
            resolverOverride: resolver,
            handlerOverride: handler,
          );
          try {
            final track = f.track;
            final loading = expectLater(
              f.controller.playTrack(track, queueTracks: [track]),
              throwsA(isA<HttpException>()),
            );
            await handler.firstFailureStarted.future.timeout(
              const Duration(seconds: 2),
            );
            if (action == 'pause') {
              handler.playbackState.add(
                PlaybackState(
                  playing: true,
                  processingState: AudioProcessingState.loading,
                ),
              );
              await f.controller.togglePlayPause();
              expect(handler.playbackState.value.playing, false);
            } else {
              await f.controller.next();
            }
            release.complete();
            await loading;
            await Future<void>.delayed(const Duration(milliseconds: 30));
            expect(handler.loadCalls, 1);
            expect(resolver.ids, ['old-song']);
            expect(resolver.searchProviders, isEmpty);
          } finally {
            if (!release.isCompleted) release.complete();
            await f.close();
          }
        },
      );
    }

    test(
      'switching to the next song cancels stale recovery of the previous song',
      () async {
        final resolver = _MediaHealthResolver();
        final handler = _MediaHealthHandler();
        final f = await _SourcePreferenceFixture.create(
          initialSource: MusicDataSource.auto,
          resolverOverride: resolver,
          handlerOverride: handler,
        );
        try {
          final first = f.track;
          final playlist = f.controller.customPlaylists.single;
          await f.controller.importPlaylistSelection(playlist.name, [
            _sourcePreferenceCandidate(
              MusicDataSource.buguyy,
              id: 'old-next',
              name: '第二首',
            ),
          ], target: playlist);
          final tracks = f.controller.tracksForPlaylist(
            f.controller.customPlaylists.single,
          );
          final next = tracks.last;
          await f.controller.playTrack(
            first,
            queueTracks: tracks,
            playlistId: playlist.id,
          );
          final prepared =
              (handler.loadedItems.first.source as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          for (var i = 0; i < 3; i++) {
            prepared.onFailure!(const HttpException('Audio HTTP 503'));
          }
          await f.controller.playQueueItem(next.id);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(handler.mediaItem.value?.id, next.id);
          expect(resolver.ids, ['old-song', 'flac-next']);
          expect(resolver.searchProviders, everyElement(MusicDataSource.flac));
        } finally {
          await f.close();
        }
      },
    );

    test(
      'rolling prefetch uses healthy provider after current media failure opens circuit',
      () async {
        final overrides = HttpOverrides.current;
        HttpOverrides.global = null;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <String>[];
        final payload = _controllerLanMp3Bytes();
        server.listen((request) async {
          requests.add(request.uri.path);
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = payload.length;
          request.response.add(payload);
          await request.response.close();
        });
        final resolver = _MediaHealthResolver(port: server.port);
        final handler = _MediaHealthHandler()..readyOnPlay = true;
        final f = await _SourcePreferenceFixture.create(
          initialSource: MusicDataSource.auto,
          resolverOverride: resolver,
          handlerOverride: handler,
          onlineConnectivity: true,
        );
        try {
          final first = f.track;
          final playlist = f.controller.customPlaylists.single;
          await f.controller.importPlaylistSelection(playlist.name, [
            _sourcePreferenceCandidate(
              MusicDataSource.buguyy,
              id: 'old-next',
              name: '第二首',
            ),
          ], target: playlist);
          final tracks = f.controller.tracksForPlaylist(
            f.controller.customPlaylists.single,
          );
          await f.controller.playTrack(
            first,
            queueTracks: tracks,
            playlistId: playlist.id,
          );
          final prepared =
              (handler.loadedItems.first.source as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          for (var i = 0; i < 3; i++) {
            prepared.onFailure!(const HttpException('Audio HTTP 503'));
          }
          await _waitForMediaCondition(() => handler.loadCalls >= 2);
          await _waitForMediaCondition(
            () => f.controller.cacheProgressFor(tracks.last).value.offline,
            timeout: const Duration(seconds: 4),
          );
          expect(resolver.ids, ['old-song', 'flac-song', 'flac-next']);
          expect(requests, ['/flac-next']);
          expect(resolver.searchProviders, everyElement(MusicDataSource.flac));
          await f.controller.playQueueItem(tracks.last.id);
          expect(resolver.ids.where((id) => id.startsWith('old-')), [
            'old-song',
          ]);
        } finally {
          await f.controller.stop();
          await f.close();
          await server.close(force: true);
          HttpOverrides.global = overrides;
        }
      },
    );

    test(
      'third media failure recovers current song and future searches omit disabled provider',
      () async {
        final resolver = _MediaHealthResolver();
        final handler = _MediaHealthHandler();
        final f = await _SourcePreferenceFixture.create(
          initialSource: MusicDataSource.auto,
          resolverOverride: resolver,
          handlerOverride: handler,
        );
        try {
          final track = f.track;
          await f.controller.playTrack(track, queueTracks: [track]);
          final prepared =
              (handler.loadedItems.single.source
                          as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          prepared.onFailure!(const HttpException('Audio HTTP 503'));
          prepared.onFailure!(const HttpException('Audio HTTP 503'));
          expect(
            resolver.isSourceAvailableForAuto(MusicDataSource.buguyy),
            true,
          );
          prepared.onFailure!(const HttpException('Audio HTTP 503'));
          await _waitForMediaCondition(() => handler.loadCalls >= 2);
          expect(
            resolver.isSourceAvailableForAuto(MusicDataSource.buguyy),
            false,
          );
          expect(resolver.ids, ['old-song', 'flac-song']);
          expect(
            f.controller.selectedSongSource(track)?.source,
            MusicDataSource.flac,
          );
          final results = await f.controller.searchSongSources(
            track,
            refresh: true,
          );
          expect(
            results.map((c) => c.source),
            everyElement(MusicDataSource.flac),
          );
          expect(resolver.searchProviders, everyElement(MusicDataSource.flac));
          expect(handler.mediaItem.value?.id, track.id);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'third media failure during native load recovers even before metadata was published',
      () async {
        final resolver = _MediaHealthResolver();
        final handler = _MediaHealthHandler()..failFirstLoad = true;
        resolver.reportSourceFailure(
          MusicDataSource.buguyy,
          const HttpException('Audio HTTP 503'),
        );
        resolver.reportSourceFailure(
          MusicDataSource.buguyy,
          const HttpException('Audio HTTP 503'),
        );
        final f = await _SourcePreferenceFixture.create(
          initialSource: MusicDataSource.auto,
          resolverOverride: resolver,
          handlerOverride: handler,
        );
        try {
          final track = f.track;
          await expectLater(
            f.controller.playTrack(track, queueTracks: [track]),
            throwsA(isA<HttpException>()),
          );
          await _waitForMediaCondition(() => handler.loadCalls >= 2);
          expect(resolver.ids, ['old-song', 'flac-song']);
          expect(handler.mediaItem.value?.id, track.id);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'manual choice does not auto-switch after media circuit opens',
      () async {
        final resolver = _MediaHealthResolver();
        final handler = _MediaHealthHandler();
        final f = await _SourcePreferenceFixture.create(
          initialSource: MusicDataSource.auto,
          manual: true,
          resolverOverride: resolver,
          handlerOverride: handler,
        );
        try {
          final track = f.track;
          await f.controller.playTrack(track, queueTracks: [track]);
          final prepared =
              (handler.loadedItems.single.source
                          as DeferredStreamingAudioSource)
                      .initialSource
                  as ResumableAudioSource;
          for (var i = 0; i < 3; i++) {
            prepared.onFailure!(const HttpException('Audio HTTP 503'));
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            resolver.isSourceAvailableForAuto(MusicDataSource.buguyy),
            false,
          );
          expect(handler.loadCalls, 1);
          expect(resolver.ids, ['old-song']);
          expect(resolver.searchProviders, isEmpty);
          expect(
            f.controller.selectedSongSource(track)?.source,
            MusicDataSource.buguyy,
          );
        } finally {
          await f.close();
        }
      },
    );
  });

  group('source preference applies to saved playlist audio', () {
    for (final manual in [false, true]) {
      test(
        'same-source saved wrong singer ${manual ? 'stays as manual choice' : 'is rematched automatically'}',
        () async {
          final f = await _SourcePreferenceFixture.create(
            wrongArtist: true,
            manual: manual,
          );
          try {
            final track = f.track;
            await f.controller.playTrack(track, queueTracks: [track]);
            if (manual) {
              expect(f.resolver.searchSources, isEmpty);
              expect(f.resolver.ids, ['old-song']);
            } else {
              expect(f.resolver.searchSources, [MusicDataSource.buguyy]);
              expect(f.resolver.ids, ['buguyy-song']);
              expect(f.controller.selectedSongSource(track)?.artist, 'artist');
            }
          } finally {
            await f.close();
          }
        },
      );
    }

    for (final legacy in [false, true]) {
      test(
        'uncached ${legacy ? 'legacy' : 'metadata'} song re-matches after BuguYY to FLAC switch',
        () async {
          final f = await _SourcePreferenceFixture.create(legacy: legacy);
          try {
            expect(
              f.controller.selectedSongSource(f.track)?.source,
              MusicDataSource.buguyy,
            );
            await f.controller.saveSource(MusicDataSource.flac);
            await f.controller.playTrack(f.track, queueTracks: [f.track]);
            expect(f.resolver.searchSources, [MusicDataSource.flac]);
            expect(f.resolver.ids, ['flac-song']);
            expect(
              f.controller.selectedSongSource(f.track)?.source,
              MusicDataSource.flac,
            );
          } finally {
            await f.close();
          }
        },
      );

      for (final action in ['playlist', 'favorite']) {
        test(
          '${legacy ? 'legacy' : 'metadata'} $action download respects saved FLAC preference',
          () async {
            final f = await _SourcePreferenceFixture.create(
              legacy: legacy,
              initialSource: MusicDataSource.flac,
            );
            try {
              if (action == 'playlist') {
                final summary = await f.controller.downloadPlaylist(
                  f.controller.customPlaylists.single,
                );
                expect(summary.failed, 0);
                expect(summary.downloaded, 1);
              } else {
                await f.controller.toggleFavorite(f.track);
                await f.controller.waitForFavoriteDownloads();
                expect(
                  f.controller.downloadTasks.every(
                    (task) => task.status == DownloadTaskStatus.completed,
                  ),
                  true,
                );
              }
              expect(f.resolver.searchSources, [MusicDataSource.flac]);
              expect(f.resolver.ids, ['flac-song']);
              expect(f.cache.downloadIds, ['flac-song']);
            } finally {
              await f.close();
            }
          },
        );
      }
    }

    test(
      'manual per-song choice remains fixed when the global source changes',
      () async {
        final f = await _SourcePreferenceFixture.create(
          manual: true,
          initialSource: MusicDataSource.flac,
        );
        try {
          await f.controller.playTrack(f.track, queueTracks: [f.track]);
          expect(f.resolver.searchSources, isEmpty);
          expect(f.resolver.ids, ['old-song']);
          expect(
            f.controller.selectedSongSource(f.track)?.source,
            MusicDataSource.buguyy,
          );
        } finally {
          await f.close();
        }
      },
    );

    test(
      'complete local audio is reused after changing source with no online request',
      () async {
        final f = await _SourcePreferenceFixture.create(
          cached: true,
          initialSource: MusicDataSource.flac,
        );
        try {
          await f.controller.playTrack(f.track, queueTracks: [f.track]);
          expect(f.resolver.searchSources, isEmpty);
          expect(f.resolver.ids, isEmpty);
          expect(f.handler.loadedIds, [f.track.id]);
          expect(f.controller.cacheProgressFor(f.track).value.offline, true);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'old in-flight matching cannot overwrite the result after source change',
      () async {
        final f = await _SourcePreferenceFixture.create(savedCandidate: false);
        final gate = Completer<List<MusicSearchCandidate>>();
        f.resolver.searchGates[MusicDataSource.buguyy] = gate;
        try {
          final first = f.controller.playTrack(f.track, queueTracks: [f.track]);
          final rejected = expectLater(
            first,
            throwsA(isA<DownloadCancelledException>()),
          );
          await f.resolver.searchStarted.future.timeout(
            const Duration(seconds: 2),
          );
          await f.controller.saveSource(MusicDataSource.flac);
          await f.controller.playTrack(f.track, queueTracks: [f.track]);
          gate.complete([_sourcePreferenceCandidate(MusicDataSource.buguyy)]);
          await rejected;
          expect(f.resolver.searchSources, [
            MusicDataSource.buguyy,
            MusicDataSource.flac,
          ]);
          expect(f.resolver.ids, ['flac-song']);
          expect(
            f.controller.selectedSongSource(f.track)?.source,
            MusicDataSource.flac,
          );
        } finally {
          if (!gate.isCompleted) gate.complete([]);
          await f.close();
        }
      },
    );
  });

  group('来听 charts and favorite downloads', () {
    const rows = MusicChartResult(
      entries: [
        MusicChartEntry(
          rank: 1,
          title: 'First',
          artist: 'artist',
          sourceId: 'a',
        ),
        MusicChartEntry(
          rank: 2,
          title: 'Second',
          artist: 'artist',
          sourceId: 'b',
        ),
      ],
    );

    test(
      'opening charts saves metadata only and other library writes preserve charts',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final chart = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          expect(chart.isBuiltIn, isTrue);
          expect(f.controller.customPlaylists, isEmpty);
          expect(f.controller.tracksForPlaylist(chart).map((t) => t.title), [
            'First',
            'Second',
          ]);
          expect(f.resolver.searchCalls, 0);
          expect(f.resolver.ids, isEmpty);
          expect(f.controller.downloadTasks, isEmpty);
          final custom = (await f.controller.createPlaylist('Mine'))!;
          await f.controller.renamePlaylist(custom, 'Renamed');
          expect(f.store.library.playlists.length, 2);
          expect(f.controller.builtInPlaylists.single.trackIds, chart.trackIds);
          expect(f.controller.customPlaylists.single.name, 'Renamed');
          await f.controller.deletePlaylist(custom);
          await f.controller.loadCache(repairLegacy: false);
          expect(f.controller.builtInPlaylists.single.trackIds, chart.trackIds);
          await expectLater(
            f.controller.renamePlaylist(chart, 'Not allowed'),
            throwsStateError,
          );
          await expectLater(
            f.controller.deletePlaylist(chart),
            throwsStateError,
          );
          expect(f.controller.builtInPlaylists.single.name, chart.name);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'refresh reorders by rank, deduplicates rows and retains manual sources and favorites',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final first = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          final track = f.controller.tracksForPlaylist(first).first;
          await f.controller.chooseSongSource(
            track,
            _candidate(id: 'chosen', name: 'First'),
          );
          // A saved/manual source remains stable across a changed chart position.
          final next = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            const MusicChartResult(
              entries: [
                MusicChartEntry(
                  rank: 1,
                  title: 'Second',
                  artist: 'artist',
                  sourceId: 'b',
                ),
                MusicChartEntry(
                  rank: 2,
                  title: 'First',
                  artist: 'artist',
                  sourceId: 'a',
                ),
                MusicChartEntry(
                  rank: 3,
                  title: 'First',
                  artist: 'artist',
                  sourceId: 'a',
                ),
              ],
            ),
          );
          expect(next.trackIds, first.trackIds.reversed.toList());
          expect(next.entries.last.manualSource, isTrue);
          expect(next.entries.last.onlineTrack?.candidate.id, 'chosen');
          expect(next.createdAt, first.createdAt);
          expect(f.resolver.searchCalls, 0);
          final persisted = MusicPlaylist.fromJson(next.toJson())!;
          expect(persisted.isBuiltIn, isTrue);
          expect(persisted.trackIds, next.trackIds);
        } finally {
          await f.close();
        }
      },
    );

    for (final quality in MusicQualityLevel.values) {
      test(
        'new favorite downloads in background at captured ${quality.name} quality',
        () async {
          final f = await _LaitingFixture.create();
          f.resolver.gates['fav'] = Completer<void>();
          try {
            f.controller.defaultDownloadQuality = quality;
            final playlist = (await f.controller.importPlaylistCandidates(
              'Mine',
              [_candidate(id: 'fav', name: 'Favorite')],
            ))!;
            final track = f.controller.tracksForPlaylist(playlist).single;
            await f.controller.toggleFavorite(track);
            expect(f.controller.isFavorite(track), isTrue);
            expect(f.controller.cachedTracks, isEmpty);
            while (f.resolver.ids.isEmpty) {
              await Future<void>.delayed(Duration.zero);
            }
            expect(f.resolver.levels, [quality]);
            f.controller.defaultDownloadQuality = MusicQualityLevel.low;
            f.resolver.gates['fav']!.complete();
            await f.controller.waitForFavoriteDownloads();
            expect(f.controller.isFavorite(track), isTrue);
            expect(f.cache.downloadIds, ['fav']);
            expect(
              f.controller.downloadTasks.single.status,
              DownloadTaskStatus.completed,
            );
            expect(f.controller.manuallyDownloadedSongCount, 1);
            await f.controller.toggleFavorite(track);
            await f.controller.waitForFavoriteDownloads();
            expect(f.resolver.ids.length, 1);
            expect(f.controller.cachedTracks.length, 1);
          } finally {
            await f.close();
          }
        },
      );
    }

    test(
      'favorite source lookup failure leaves favorite and a visible failed task',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final chart = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          final track = f.controller.tracksForPlaylist(chart).first;
          f.resolver.searchResults = const [];
          await f.controller.toggleFavorite(track);
          await f.controller.waitForFavoriteDownloads();
          expect(f.controller.isFavorite(track), isTrue);
          expect(
            f.controller.downloadTasks.single.status,
            DownloadTaskStatus.failed,
          );
          expect(f.controller.downloadTasks.single.error, isNotEmpty);
          expect(f.cache.downloadIds, isEmpty);
          expect(f.controller.activeDownloadTasks, isEmpty);
          expect(f.controller.customPlaylists, isEmpty);
          expect(f.controller.builtInPlaylists.single.trackIds.length, 2);
        } finally {
          await f.close();
        }
      },
    );

    test('favorite resolve failure does not remove the favorite', () async {
      final f = await _LaitingFixture.create();
      try {
        f.resolver.fail = true;
        final playlist = (await f.controller.importPlaylistCandidates('Mine', [
          _candidate(id: 'bad', name: 'Bad'),
        ]))!;
        final track = f.controller.tracksForPlaylist(playlist).single;
        await f.controller.toggleFavorite(track);
        await f.controller.waitForFavoriteDownloads();
        expect(f.controller.isFavorite(track), isTrue);
        expect(
          f.controller.downloadTasks.single.status,
          DownloadTaskStatus.failed,
        );
        expect(f.controller.downloadTasks.single.error, contains('offline'));
      } finally {
        await f.close();
      }
    });

    test(
      'favorite jobs obey concurrency, removal cancels queued work, and re-add is not lost',
      () async {
        final f = await _LaitingFixture.create();
        try {
          f.controller.playlistDownloadConcurrency = 1;
          f.controller.defaultDownloadQuality = MusicQualityLevel.medium;
          f.resolver.gates['one'] = Completer<void>();
          final playlist = (await f.controller
              .importPlaylistCandidates('Mine', [
                _candidate(id: 'one', name: 'One'),
                _candidate(id: 'two', name: 'Two'),
                _candidate(id: 'three', name: 'Three'),
              ]))!;
          final tracks = f.controller.tracksForPlaylist(playlist);
          for (final t in tracks) {
            await f.controller.toggleFavorite(t);
          }
          expect(f.resolver.ids, ['one']);
          await f.controller.toggleFavorite(tracks[1]); // queued remove
          await f.controller.toggleFavorite(tracks[2]); // queued remove
          await f.controller.toggleFavorite(tracks[2]); // queued re-add
          f.controller.defaultDownloadQuality = MusicQualityLevel.low;
          f.resolver.gates['one']!.complete();
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.ids, ['one', 'three']);
          expect(f.resolver.levels, [
            MusicQualityLevel.medium,
            MusicQualityLevel.medium,
          ]);
          expect(f.controller.isFavorite(tracks[1]), isFalse);
          expect(f.controller.isFavorite(tracks[2]), isTrue);
          expect(
            f.controller.downloadTasks
                .where((t) => t.status == DownloadTaskStatus.canceled)
                .length,
            2,
          );
        } finally {
          await f.close();
        }
      },
    );

    test(
      'bulk removal cancels unresolved favorites even if search returns later',
      () async {
        final f = await _LaitingFixture.create();
        try {
          f.resolver.searchGate = Completer<List<MusicSearchCandidate>>();
          final chart = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          final track = f.controller.tracksForPlaylist(chart).first;
          await f.controller.toggleFavorite(track);
          while (f.resolver.searchCalls == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          await f.controller.removeTracksFromFavorites([track]);
          await f.controller.waitForFavoriteDownloads();
          expect(f.controller.isFavorite(track), isFalse);
          expect(
            f.controller.downloadTasks.single.status,
            DownloadTaskStatus.canceled,
          );
          f.resolver.searchGate!.complete([
            _candidate(id: 'late', name: 'First'),
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(f.resolver.ids, isEmpty);
          expect(f.cache.downloadIds, isEmpty);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'manual download and favorite share a task then upgrade only if the shared quality is lower',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(id: 'shared-fav', name: 'Shared');
          f.resolver.gates[candidate.id] = Completer<void>();
          final playlist = (await f.controller.importPlaylistCandidates(
            'Mine',
            [candidate],
          ))!;
          final track = f.controller.tracksForPlaylist(playlist).single;
          final downloading = f.controller.downloadCandidate(
            candidate,
            quality: MusicQualityLevel.low,
          );
          await Future<void>.delayed(Duration.zero);
          f.controller.defaultDownloadQuality = MusicQualityLevel.high;
          await f.controller.toggleFavorite(track);
          f.resolver.gates[candidate.id]!.complete();
          await downloading;
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.levels, [
            MusicQualityLevel.low,
            MusicQualityLevel.high,
          ]);
          expect(f.controller.downloadTasks.length, 1);
          expect(f.controller.manuallyDownloadedSongCount, 1);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'readding a favorite upgrades an already running lower-quality download',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(id: 'readd-active', name: 'Readd');
          f.resolver.gates[candidate.id] = Completer<void>();
          final playlist = (await f.controller.importPlaylistCandidates(
            'Mine',
            [candidate],
          ))!;
          final track = f.controller.tracksForPlaylist(playlist).single;
          f.controller.defaultDownloadQuality = MusicQualityLevel.low;
          await f.controller.toggleFavorite(track);
          while (f.resolver.ids.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          await f.controller.toggleFavorite(track);
          f.controller.defaultDownloadQuality = MusicQualityLevel.high;
          await f.controller.toggleFavorite(track);
          f.controller.defaultDownloadQuality = MusicQualityLevel.low;
          f.resolver.gates[candidate.id]!.complete();
          await f.controller.waitForFavoriteDownloads();
          expect(f.controller.isFavorite(track), isTrue);
          expect(f.resolver.levels, [
            MusicQualityLevel.low,
            MusicQualityLevel.high,
          ]);
          expect(f.cache.downloadIds, [candidate.id, candidate.id]);
          expect(
            f.controller.downloadTasks.single.status,
            DownloadTaskStatus.completed,
          );
        } finally {
          await f.close();
        }
      },
    );

    for (final damage in ['empty', 'truncated', 'text']) {
      test(
        'favorite repairs a $damage manual cache instead of reporting reuse',
        () async {
          final f = await _LaitingFixture.create();
          final root = await Directory.systemTemp.createTemp('fav_bad_cache_');
          try {
            final candidate = _candidate(id: 'bad-cache', name: 'Bad cache');
            final music = await f.resolver.resolveAtQuality(
              candidate,
              MusicQualityLevel.high,
            );
            f.resolver.ids.clear();
            f.resolver.levels.clear();
            final bytes = switch (damage) {
              'empty' => <int>[],
              'truncated' => [
                0x66,
                0x4c,
                0x61,
                0x43,
                ...List<int>.filled(17000, 0),
              ],
              _ => '<html>${List.filled(20000, 'x').join()}</html>'.codeUnits,
            };
            final file = File('${root.path}/song.flac');
            await file.writeAsBytes(bytes);
            f.cache.cached.add(
              CachedTrack(
                cacheId: cacheIdForResolved(music),
                music: music,
                filePath: file.path,
                sizeBytes: damage == 'text' ? bytes.length : 20000,
                fromCache: true,
              ),
            );
            await f.controller.loadCache(repairLegacy: false);
            await f.controller.toggleFavorite(f.controller.cachedTracks.single);
            await f.controller.waitForFavoriteDownloads();
            expect(f.resolver.ids, [candidate.id]);
            expect(f.cache.downloadIds, [candidate.id]);
            expect(f.controller.downloadTasks.single.reusedCache, isFalse);
          } finally {
            await f.close();
            await root.delete(recursive: true);
          }
        },
      );
    }

    test(
      'chart refresh retains unresolved songs in the playing queue until stop',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'chart_queue_snapshot_',
        );
        final f = await _LaitingFixture.create(root: root);
        try {
          final chart = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          final tracks = f.controller.tracksForPlaylist(chart);
          tracks[0] = await f.cacheChartTrack(
            tracks[0],
            File('${root.path}/current.mp3'),
          );
          await f.controller.playTrack(
            tracks[0],
            playlistId: chart.id,
            queueTracks: tracks,
          );
          final deferred =
              f.handler.loadedItems[1].source as DeferredStreamingAudioSource;
          final refreshed = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            const MusicChartResult(
              entries: [
                MusicChartEntry(
                  rank: 1,
                  title: 'First',
                  artist: 'artist',
                  sourceId: 'a',
                ),
              ],
            ),
          );
          expect(refreshed.trackIds, [tracks[0].id]);
          f.resolver.searchResults = [
            _candidate(id: 'second-source', name: 'Second'),
          ];
          // This is the same lazy preparation used by native automatic advance.
          await deferred.prepare();
          await f.controller.playQueueItem(tracks[1].id);
          expect(f.resolver.searchCalls, greaterThan(0));
          expect(f.resolver.ids, ['second-source', 'second-source']);
          expect(
            f.handler.queue.value.map((i) => i.id),
            tracks.map((t) => t.id),
          );
          f.handler.playbackState.add(
            f.handler.playbackState.value.copyWith(
              playing: true,
              processingState: AudioProcessingState.ready,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(f.store.library.playlists.single.trackIds, refreshed.trackIds);
          expect(
            f.controller.selectedSongSource(tracks[1])?.id,
            'second-source',
          );
          await f.controller.stop();
          expect(f.controller.canSwitchSongSource(tracks[1]), isFalse);
          expect(f.controller.selectedSongSource(tracks[1]), isNull);
        } finally {
          await f.close();
          await root.delete(recursive: true);
        }
      },
    );

    test(
      'a missing high file cannot suppress upgrading a shared low download',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(
            id: 'missing-high',
            name: 'Missing high',
          );
          final music = await f.resolver.resolveAtQuality(
            candidate,
            MusicQualityLevel.high,
          );
          f.resolver.ids.clear();
          f.resolver.levels.clear();
          f.cache.cached.add(
            CachedTrack(
              cacheId: cacheIdForResolved(music),
              music: music,
              filePath: '/nonexistent/laiting-high.flac',
              sizeBytes: 20000,
              fromCache: true,
            ),
          );
          await f.controller.loadCache(repairLegacy: false);
          final track = f.controller.cachedTracks.single;
          f.resolver.gates[candidate.id] = Completer<void>();
          final manual = f.controller.downloadCandidate(
            candidate,
            quality: MusicQualityLevel.low,
          );
          while (f.resolver.ids.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          await f.controller.toggleFavorite(track);
          f.resolver.gates[candidate.id]!.complete();
          await manual;
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.levels, [
            MusicQualityLevel.low,
            MusicQualityLevel.high,
          ]);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'a low file cannot borrow the quality of another broken high record',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'fav_exact_quality_',
        );
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(id: 'same-source', name: 'Same source');
          final high = await f.resolver.resolveAtQuality(
            candidate,
            MusicQualityLevel.high,
          );
          final low = await f.resolver.resolveAtQuality(
            candidate,
            MusicQualityLevel.low,
          );
          f.resolver.ids.clear();
          f.resolver.levels.clear();
          final file = File('${root.path}/low.mp3');
          final bytes = [0x49, 0x44, 0x33, ...List<int>.filled(20000, 0)];
          await file.writeAsBytes(bytes);
          f.cache.cached.addAll([
            CachedTrack(
              cacheId: cacheIdForResolved(high),
              music: high,
              filePath: '${root.path}/missing.flac',
              sizeBytes: 20000,
              fromCache: true,
            ),
            CachedTrack(
              cacheId: cacheIdForResolved(low),
              music: low,
              filePath: file.path,
              sizeBytes: bytes.length,
              fromCache: true,
            ),
          ]);
          await f.controller.loadCache(repairLegacy: false);
          await f.controller.toggleFavorite(
            f.controller.cachedTracks.firstWhere(
              (t) => t.id == cacheIdForResolved(low),
            ),
          );
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.levels, [MusicQualityLevel.high]);
          expect(f.controller.downloadTasks.single.reusedCache, isFalse);
        } finally {
          await f.close();
          await root.delete(recursive: true);
        }
      },
    );

    test(
      'cancel and readd during file validation uses the new captured quality',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'fav_validation_gate_',
        );
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(id: 'validate-gate', name: 'Validate');
          final low = await f.resolver.resolveAtQuality(
            candidate,
            MusicQualityLevel.low,
          );
          f.resolver.ids.clear();
          f.resolver.levels.clear();
          final file = File('${root.path}/low.mp3');
          final bytes = [0x49, 0x44, 0x33, ...List<int>.filled(20000, 0)];
          await file.writeAsBytes(bytes);
          f.cache.cached.add(
            CachedTrack(
              cacheId: cacheIdForResolved(low),
              music: low,
              filePath: file.path,
              sizeBytes: bytes.length,
              fromCache: true,
            ),
          );
          await f.controller.loadCache(repairLegacy: false);
          final track = f.controller.cachedTracks.single;
          f.cache.validationGate = Completer<void>();
          f.controller.defaultDownloadQuality = MusicQualityLevel.low;
          await f.controller.toggleFavorite(track);
          await f.cache.validationStarted.future;
          await f.controller.toggleFavorite(track);
          f.controller.defaultDownloadQuality = MusicQualityLevel.high;
          await f.controller.toggleFavorite(track);
          f.cache.validationGate!.complete();
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.levels, [MusicQualityLevel.high]);
          expect(
            f.controller.downloadTasks.where((t) => t.reusedCache),
            isEmpty,
          );
          expect(f.controller.isFavorite(track), isTrue);
        } finally {
          if (f.cache.validationGate?.isCompleted == false) {
            f.cache.validationGate!.complete();
          }
          await f.close();
          await root.delete(recursive: true);
        }
      },
    );

    test(
      'removed chart queue row keeps manual source against a late old match',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'chart_manual_queue_',
        );
        final f = await _LaitingFixture.create(root: root);
        try {
          final chart = await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          final tracks = f.controller.tracksForPlaylist(chart);
          tracks[0] = await f.cacheChartTrack(
            tracks[0],
            File('${root.path}/first.mp3'),
          );
          await f.controller.playTrack(
            tracks[0],
            playlistId: chart.id,
            queueTracks: tracks,
          );
          final deferred =
              f.handler.loadedItems[1].source as DeferredStreamingAudioSource;
          await f.controller.updateChartPlaylist(
            qqMusicCharts[1],
            const MusicChartResult(
              entries: [
                MusicChartEntry(
                  rank: 1,
                  title: 'First',
                  artist: 'artist',
                  sourceId: 'a',
                ),
              ],
            ),
          );
          f.resolver.searchGate = Completer<List<MusicSearchCandidate>>();
          final preparing = deferred.prepare();
          final canceled = expectLater(
            preparing,
            throwsA(isA<DownloadCancelledException>()),
          );
          while (f.resolver.searchCalls == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          await f.controller.chooseSongSource(
            tracks[1],
            _candidate(id: 'manual-new', name: 'Second'),
          );
          f.resolver.searchGate!.complete([
            _candidate(id: 'old-match', name: 'Second'),
          ]);
          await canceled;
          await f.controller.playQueueItem(tracks[1].id);
          expect(f.controller.selectedSongSource(tracks[1])?.id, 'manual-new');
          expect(f.resolver.ids, ['manual-new']);
          expect(f.store.library.playlists.single.trackIds, [tracks[0].id]);
          // Starting the refreshed chart creates a new queue and drops its old row.
          final current = f.controller.tracksForPlaylist(
            f.controller.builtInPlaylists.single,
          );
          await f.controller.playTrack(
            current[0],
            playlistId: chart.id,
            queueTracks: current,
          );
          expect(f.controller.canSwitchSongSource(tracks[1]), isFalse);
          expect(f.controller.selectedSongSource(tracks[1]), isNull);
        } finally {
          if (f.resolver.searchGate?.isCompleted == false) {
            f.resolver.searchGate!.complete([]);
          }
          await f.close();
          await root.delete(recursive: true);
        }
      },
    );

    for (final saveAsFavorite in [true, false]) {
      test(
        'removed unresolved chart row persists its song when ${saveAsFavorite ? 'favorited' : 'added to a playlist'}',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'chart_queue_save_',
          );
          final f = await _LaitingFixture.create(root: root);
          try {
            final chart = await f.controller.updateChartPlaylist(
              qqMusicCharts[1],
              rows,
            );
            final tracks = f.controller.tracksForPlaylist(chart);
            tracks[0] = await f.cacheChartTrack(
              tracks[0],
              File('${root.path}/first.mp3'),
            );
            await f.controller.playTrack(
              tracks[0],
              playlistId: chart.id,
              queueTracks: tracks,
            );
            await f.controller.updateChartPlaylist(
              qqMusicCharts[1],
              const MusicChartResult(
                entries: [
                  MusicChartEntry(
                    rank: 1,
                    title: 'First',
                    artist: 'artist',
                    sourceId: 'a',
                  ),
                ],
              ),
            );
            f.resolver.searchResults = [
              _candidate(id: 'second-source', name: 'Second'),
            ];
            if (saveAsFavorite) {
              await f.controller.toggleFavorite(tracks[1]);
              await f.controller.waitForFavoriteDownloads();
              expect(f.controller.favoriteTracks.single.id, tracks[1].id);
              expect(f.controller.favoriteTracks.single.title, 'Second');
              expect(
                f.store.library.favoriteEntries.single.song?.title,
                'Second',
              );
              expect(f.resolver.levels, [MusicQualityLevel.high]);
            } else {
              // Persist a hand-picked source with metadata and its manual flag.
              await f.controller.chooseSongSource(
                tracks[1],
                _candidate(id: 'manual-new', name: 'Second'),
              );
              final target = (await f.controller.createPlaylist('Mine'))!;
              await f.controller.addTracksToPlaylist(target, [tracks[1]]);
              final entry = f.store.library.playlists
                  .firstWhere((p) => p.id == target.id)
                  .entries
                  .single;
              expect(entry.song?.title, 'Second');
              expect(entry.onlineTrack?.candidate.id, 'manual-new');
              expect(entry.manualSource, isTrue);
              expect(
                f.controller
                    .tracksForPlaylist(f.controller.customPlaylists.single)
                    .single
                    .title,
                'Second',
              );
            }
            expect(f.controller.builtInPlaylists.single.trackIds, [
              tracks[0].id,
            ]);
            await f.controller.stop();
            // The explicit save survives releasing the temporary playing queue.
            expect(f.controller.canSwitchSongSource(tracks[1]), isTrue);
          } finally {
            await f.close();
            await root.delete(recursive: true);
          }
        },
      );
    }

    test(
      'first chart playback matches similarity, queues all rows and remembers a successful source',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'laiting_chart_play_',
        );
        final handler = _StatsAudioHandler();
        final resolver = _LaitingResolver()
          ..searchResults = [
            _candidate(id: 'wrong', name: 'Different song'),
            _candidate(id: 'right', name: 'First'),
          ];
        final store = _MemoryPlaylistStore();
        final controller = MusicController(
          audioHandler: handler,
          resolver: resolver,
          cacheStore: CachedTrackStore(rootProvider: () async => root),
          playlistStore: store,
          settingsStore: _FakeSettingsStore(),
          metadataRepository: _StaticMetadataRepository(),
          listeningStatsStore: ListeningStatsStore.memory(),
          songSearchCache: SongSearchCache.memory(),
          downloadHistoryStore: MemoryDownloadHistory(),
          connectivityChanges: const Stream.empty(),
          checkConnectivity: () async => [],
        );
        try {
          await controller.initialize();
          final chart = await controller.updateChartPlaylist(
            qqMusicCharts[1],
            rows,
          );
          final tracks = controller.tracksForPlaylist(chart);
          await controller.playTrack(
            tracks.first,
            queueTracks: tracks,
            playlistId: chart.id,
          );
          expect(resolver.ids, ['right']);
          expect(resolver.levels, [MusicQualityLevel.low]);
          expect(handler.queue.value.map((i) => i.id), chart.trackIds);
          expect(handler.playbackState.value.playing, isTrue);
          for (
            var i = 0;
            i < 20 &&
                store.library.playlists.single.entries.first.onlineTrack ==
                    null;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            store
                .library
                .playlists
                .single
                .entries
                .first
                .onlineTrack
                ?.candidate
                .id,
            'right',
          );
          expect(
            store.library.playlists.single.entries.last.onlineTrack,
            isNull,
          );
          expect(controller.downloadTasks, isEmpty);
        } finally {
          await controller.stop();
          controller.dispose();
          await handler.dispose();
          await root.delete(recursive: true);
        }
      },
    );

    test(
      'a complete manual file of sufficient quality is reused without network',
      () async {
        final f = await _LaitingFixture.create();
        final root = await Directory.systemTemp.createTemp(
          'laiting_fav_reuse_',
        );
        try {
          final candidate = _candidate(id: 'existing', name: 'Existing');
          final music = await f.resolver.resolveAtQuality(
            candidate,
            MusicQualityLevel.high,
          );
          f.resolver.ids.clear();
          f.resolver.levels.clear();
          final file = File('${root.path}/existing.flac');
          final bytes = [0x66, 0x4c, 0x61, 0x43, ...List<int>.filled(20000, 0)];
          await file.writeAsBytes(bytes);
          final record = CachedTrack(
            cacheId: cacheIdForResolved(music),
            music: music,
            filePath: file.path,
            sizeBytes: bytes.length,
            fromCache: true,
          );
          f.cache.cached.add(record);
          await f.controller.loadCache(repairLegacy: false);
          final track = f.controller.cachedTracks.single;
          await f.controller.toggleFavorite(track);
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.ids, isEmpty);
          expect(f.cache.downloadIds, isEmpty);
          expect(f.controller.downloadTasks.single.reusedCache, isTrue);
          expect(f.controller.busyCandidate, isNull);
          expect(f.controller.busyCandidateKeys, isEmpty);
          expect(f.controller.manuallyDownloadedSongCount, 1);
          expect(f.controller.isFavorite(track), isTrue);
        } finally {
          await f.close();
          await root.delete(recursive: true);
        }
      },
    );

    test(
      'a low-quality playback cache is upgraded when newly favorited',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(id: 'cached-low', name: 'Low cache');
          final music = await f.resolver.resolveAtQuality(
            candidate,
            MusicQualityLevel.low,
          );
          f.resolver.ids.clear();
          f.resolver.levels.clear();
          final record = CachedTrack(
            cacheId: cacheIdForResolved(music),
            music: music,
            filePath: '/tmp/low-cache.mp3',
            sizeBytes: 4,
            fromCache: true,
            playbackCache: true,
          );
          f.cache.cached.add(record);
          await f.controller.loadCache(repairLegacy: false);
          final track = f.controller.cachedTracks.single;
          await f.controller.toggleFavorite(track);
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.levels, [MusicQualityLevel.high]);
          expect(f.controller.manuallyDownloadedSongCount, 1);
          expect(f.controller.isFavorite(track), isTrue);
          expect(
            f.controller.favoriteTracks.single.filePath,
            '/tmp/cached-low.mp3',
          );
        } finally {
          await f.close();
        }
      },
    );

    test(
      'loading existing favorites does not redownload the collection',
      () async {
        final f = await _LaitingFixture.create();
        try {
          final candidate = _candidate(
            id: 'old-favorite',
            name: 'Old favorite',
          );
          final saved = SavedOnlineTrack(candidate: candidate);
          f.store.library = PlaylistLibrary(
            favoriteEntries: [
              PlaylistTrackEntry(
                trackId: saved.trackId,
                addedAt: DateTime.now(),
                onlineTrack: saved,
              ),
            ],
            playlists: const [],
          );
          await f.controller.loadCache(repairLegacy: false);
          await f.controller.waitForFavoriteDownloads();
          expect(f.controller.favoriteTracks.length, 1);
          expect(f.resolver.ids, isEmpty);
          expect(f.controller.downloadTasks, isEmpty);
        } finally {
          await f.close();
        }
      },
    );

    test(
      'disposal cancels queued favorites and leaves no late audio downloads',
      () async {
        final f = await _LaitingFixture.create();
        try {
          f.controller.playlistDownloadConcurrency = 1;
          f.resolver.gates['one'] = Completer<void>();
          final playlist = (await f.controller.importPlaylistCandidates(
            'Mine',
            [
              _candidate(id: 'one', name: 'One'),
              _candidate(id: 'two', name: 'Two'),
            ],
          ))!;
          for (final track in f.controller.tracksForPlaylist(playlist)) {
            await f.controller.toggleFavorite(track);
          }
          f.controller.dispose();
          f.disposed = true;
          f.resolver.gates['one']!.complete();
          await f.controller.waitForFavoriteDownloads();
          expect(f.resolver.ids, ['one']);
          expect(f.cache.downloadIds, isEmpty);
          expect(f.controller.activeDownloadTasks, isEmpty);
        } finally {
          await f.close();
        }
      },
    );
  });

  test(
    'statistics retain the actual playlist origin and known quality identity',
    () async {
      final handler = _StatsAudioHandler();
      await handler.dispose();
      final stats = ListeningStatsStore.memory();
      final original = _cachedTrack(id: 'shared', name: 'Shared song');
      final otherQuality = original.copyWith(
        cacheId: '${original.cacheId}-high',
        filePath: '/tmp/shared-high.mp3',
      );
      final candidate = _candidate(id: 'shared', name: 'Shared song');
      final canonical = SavedOnlineTrack(candidate: candidate).trackId;
      final playlistStore = _MemoryPlaylistStore();
      final controller = MusicController(
        audioHandler: handler,
        listeningStatsStore: stats,
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: [original, otherQuality]),
        playlistStore: playlistStore,
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      Future<void> hear(Track track, String? playlist) async {
        handler.currentPositionOverride = Duration.zero;
        await controller.playTrack(
          track,
          queueTracks: [track],
          playlistId: playlist,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        controller.refreshListeningStats();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        handler.currentPositionOverride = const Duration(seconds: 1);
        controller.refreshListeningStats();
      }

      try {
        await controller.initialize();
        final p = (await controller.createPlaylist('Original'))!;
        final q = (await controller.createPlaylist('Also contains this song'))!;
        final tracks = controller.cachedTracks;
        await controller.addTrackToPlaylist(p, tracks[0]);
        await controller.addTrackToPlaylist(q, tracks[0]);
        await hear(tracks[0], p.id);
        final first = stats.report();
        expect(first.songCount, 1);
        expect(first.playlistRanks.single.id, p.id);
        final identity = first.songRanks.single.id;
        // Being favorited does not change the identity; another quality is the same song.
        await controller.toggleFavorite(tracks[0]);
        await hear(tracks[1], null);
        expect(stats.report().songCount, 1);
        expect(stats.report().songRanks.single.id, identity);
        expect(stats.report().playlistRanks.map((r) => r.id), [p.id]);
        expect(
          controller
              .trackForListeningSong(
                ListeningSong(
                  id: identity,
                  trackId: 'removed-quality',
                  title: 'Shared song',
                  artist: 'artist',
                ),
              )
              ?.id,
          isNotNull,
        );
        // An unavailable logical ID cannot silently play an unrelated same-named song.
        expect(
          controller.trackForListeningSong(
            ListeningSong(
              id: '$canonical-different',
              trackId: 'missing',
              title: 'Shared song',
              artist: 'artist',
            ),
          ),
          isNull,
        );
      } finally {
        controller.dispose();
        await Future<void>.delayed(Duration.zero);
      }
    },
  );

  test(
    'queue selection removes the retired current match after switching',
    () async {
      final handler = _SpyAudioHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final old = _candidate(id: 'old', name: 'Old match');
        final second = _candidate(id: 'second', name: 'Second');
        final replacement = _candidate(id: 'new', name: 'New match');
        final playlist = (await controller.importPlaylistCandidates(
          'Review queue',
          [old, second],
        ))!;
        final queue = controller
            .tracksForPlaylist(playlist)
            .map((t) => t.copyWith(filePath: '/tmp/${t.id}.mp3'))
            .toList();
        await controller.playTrack(
          queue.first,
          playlistId: playlist.id,
          queueTracks: queue,
        );
        await controller.replaceImportedCandidate(
          playlist,
          queue.first.id,
          replacement,
          removePrevious: true,
        );
        expect(handler.queue.value.map((t) => t.id), contains(queue.first.id));
        await controller.playQueueItem(queue[1].id);
        await Future<void>.delayed(Duration.zero);
        expect(
          handler.queue.value.map((t) => t.id),
          isNot(contains(queue.first.id)),
        );
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

  test('failed queue source selection retains playlist additions', () async {
    final handler = _SpyAudioHandler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      audioHandler: handler,
      resolver: _SelectivePlaylistResolver(),
      cacheStore: _FakeCacheStore(cached: const []),
      playlistStore: _MemoryPlaylistStore(),
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
    );
    try {
      await controller.initialize();
      final first = _candidate(id: 'first', name: 'First');
      final bad = _candidate(id: 'bad', name: 'Unavailable');
      final playlist = (await controller.importPlaylistCandidates(
        'Review queue',
        [first, bad],
      ))!;
      final queue = controller.tracksForPlaylist(playlist);
      queue[0] = queue[0].copyWith(filePath: '/tmp/review-first.mp3');
      await controller.playTrack(
        queue.first,
        playlistId: playlist.id,
        queueTracks: queue,
      );
      await expectLater(
        controller.playQueueItem(queue[1].id),
        throwsStateError,
      );
      expect(handler.mediaItem.value?.id, queue.first.id);
      final third = _candidate(id: 'third', name: 'Added');
      await controller.importPlaylistSelection('Review queue', [
        third,
      ], target: playlist);
      expect(
        handler.queue.value.map((t) => t.id),
        contains(SavedOnlineTrack(candidate: third).trackId),
      );
    } finally {
      controller.dispose();
      await handler.dispose();
    }
  });

  for (final stopDuringLoad in [false, true]) {
    test(
      stopDuringLoad
          ? 'stopped failed queue load cannot restore playlist synchronization'
          : 'failed queue load catches up saved matches and keeps synchronization',
      () async {
        final handler = _DelayedSecondLoadHandler()..failSecondLoad = true;
        final controller = MusicController(
          songSearchCache: SongSearchCache.memory(),
          downloadHistoryStore: MemoryDownloadHistory(),
          connectivityChanges: const Stream.empty(),
          audioHandler: handler,
          resolver: _FakeMusicResolver(),
          cacheStore: _FakeCacheStore(cached: const []),
          playlistStore: _MemoryPlaylistStore(),
          settingsStore: _FakeSettingsStore(),
          metadataRepository: _StaticMetadataRepository(),
        );
        try {
          await controller.initialize();
          final playlist = (await controller.createPlaylist('同步失败'))!;
          final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
          final second = trackFromCached(
            _cachedTrack(id: 'second', name: '第二首'),
          );
          await controller.addTracksToPlaylist(playlist, [first, second]);
          await controller.playTrack(
            first,
            playlistId: playlist.id,
            queueTracks: [first, second],
          );
          final pending = controller.playQueueItem(second.id);
          await handler.secondLoadStarted.future;
          final third = _candidate(id: 'third', name: '第三首');
          await controller.importPlaylistSelection('同步失败', [
            third,
          ], target: playlist);
          final stopped = stopDuringLoad ? controller.stop() : null;
          final failure = expectLater(pending, throwsStateError);
          handler.releaseSecondLoad.complete();
          await failure;
          if (stopped != null) await stopped;
          if (stopDuringLoad) {
            expect(handler.queue.value, isEmpty);
            expect(handler.mediaItem.value, isNull);
          } else {
            expect(handler.mediaItem.value?.id, first.id);
            expect(handler.queue.value.map((item) => item.id), [
              first.id,
              second.id,
              SavedOnlineTrack(candidate: third).trackId,
            ]);
          }
          final fourth = _candidate(id: 'fourth', name: '第四首');
          await controller.importPlaylistSelection('同步失败', [
            fourth,
          ], target: playlist);
          expect(
            handler.queue.value.map((item) => item.id),
            stopDuringLoad
                ? isEmpty
                : contains(SavedOnlineTrack(candidate: fourth).trackId),
          );
        } finally {
          controller.dispose();
          await handler.dispose();
        }
      },
    );
  }

  test(
    'queue source preparation retains matches added before loading',
    () async {
      final root = await Directory.systemTemp.createTemp('queue_prepare_');
      final handler = _SpyAudioHandler();
      final resolver = _QueuePrepareGateResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: resolver,
        cacheStore: CachedTrackStore(rootProvider: () async => root),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.importPlaylistCandidates('准备中', [
          _candidate(id: 'pending', name: '第二首'),
        ]))!;
        final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
        final second = controller.tracksForPlaylist(playlist).single;
        await controller.addTrackToPlaylist(playlist, first);
        await controller.playTrack(
          first,
          playlistId: playlist.id,
          queueTracks: [first, second],
        );
        final pending = controller.playQueueItem(second.id);
        await resolver.started.future;
        final third = _candidate(id: 'third', name: '第三首');
        await controller.importPlaylistSelection('准备中', [
          third,
        ], target: playlist);
        final thirdId = SavedOnlineTrack(candidate: third).trackId;
        expect(handler.queue.value.map((item) => item.id), contains(thirdId));
        resolver.release.complete();
        await pending;
        expect(handler.mediaItem.value?.id, second.id);
        expect(handler.queue.value.map((item) => item.id), [
          first.id,
          second.id,
          thirdId,
        ]);
      } finally {
        controller.dispose();
        await handler.dispose();
        await root.delete(recursive: true);
      }
    },
  );

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
    'rapid queue selections retain playlist ownership and later additions',
    () async {
      final handler = _DelayedSecondLoadHandler();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
        audioHandler: handler,
        resolver: _FakeMusicResolver(),
        cacheStore: _FakeCacheStore(cached: const []),
        playlistStore: _MemoryPlaylistStore(),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
      );
      try {
        await controller.initialize();
        final playlist = (await controller.createPlaylist('同步队列'))!;
        final first = trackFromCached(_cachedTrack(id: 'first', name: '第一首'));
        final second = trackFromCached(_cachedTrack(id: 'second', name: '第二首'));
        await controller.addTracksToPlaylist(playlist, [first, second]);
        await controller.playTrack(
          first,
          playlistId: playlist.id,
          queueTracks: [first, second],
        );
        final pending = controller.playQueueItem(second.id);
        await handler.secondLoadStarted.future;
        final latest = controller.playQueueItem(first.id);
        handler.releaseSecondLoad.complete();
        await Future.wait([pending, latest]);
        expect(handler.mediaItem.value?.id, first.id);
        expect(handler.queue.value.map((item) => item.id), [
          first.id,
          second.id,
        ]);
        final added = _candidate(id: 'third', name: '第三首');
        await controller.importPlaylistSelection('同步队列', [
          added,
        ], target: playlist);
        expect(handler.queue.value.map((item) => item.id), [
          first.id,
          second.id,
          SavedOnlineTrack(candidate: added).trackId,
        ]);
        final before = handler.playCalls;
        await controller.playQueueItem(first.id);
        expect(handler.playCalls, before);
        expect(() => controller.playQueueItem('removed'), throwsStateError);
        await controller.stop();
        expect(() => controller.playQueueItem(first.id), throwsStateError);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    },
  );

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
                (handler.loadedItems[1].source as DeferredStreamingAudioSource)
                        .initialSource
                    as ResumableAudioSource;
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
  for (final failure in ['search', 'resolve', 'load']) {
    test('failed preview $failure retains current source controls', () async {
      const origin = OnlinePlaylist(
        source: OnlinePlaylistSource.qq,
        id: 'review',
        name: 'Review',
        creator: '',
        trackCount: 2,
      );
      const first = OnlinePlaylistSong(
        id: '1',
        title: 'First',
        artist: 'Artist',
      );
      const second = OnlinePlaylistSong(
        id: '2',
        title: 'Second',
        artist: 'Artist',
      );
      final handler = _DelayedSecondLoadHandler()..releaseSecondLoad.complete();
      final resolver = _FailingPreviewResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: _MemoryPlaylistStore(),
        cacheStore: _FakeCacheStore(cached: []),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
      );
      try {
        await controller.initialize();
        await controller.playOnlinePlaylistSong(origin, first);
        final playing = controller.currentTrack!;
        if (failure == 'search') {
          resolver.gate = Completer<List<MusicSearchCandidate>>()..complete([]);
        } else if (failure == 'resolve') {
          resolver.failResolve = true;
          resolver.gate = Completer<List<MusicSearchCandidate>>()
            ..complete([_candidate(id: 'unresolved', name: 'Second')]);
        } else {
          handler.failSecondLoad = true;
        }
        await expectLater(
          controller.playOnlinePlaylistSong(origin, second),
          throwsA(anything),
        );
        expect(controller.currentTrack!.id, playing.id);
        expect(controller.canSwitchSongSource(playing), true);
        expect(controller.originalSongForTrack(playing)?.title, first.title);
        expect(handler.loadedIds, [playing.id]);
        // A real source change must still reload A rather than the failed B.
        resolver.gate = null;
        resolver.failResolve = false;
        await controller.chooseSongSource(
          playing,
          _candidate(id: 'replacement', name: 'First'),
        );
        expect(controller.currentTrack!.id, playing.id);
        expect(handler.loadedIds, [playing.id]);
      } finally {
        controller.dispose();
        await handler.dispose();
      }
    });
  }

  for (final failures in [(true, true), (false, true), (true, false)]) {
    test('overlapping preview load/search failures $failures', () async {
      const origin = OnlinePlaylist(
        source: OnlinePlaylistSource.qq,
        id: 'overlap',
        name: 'Overlap',
        creator: '',
        trackCount: 3,
      );
      const songs = [
        OnlinePlaylistSong(id: 'a', title: 'Alpha', artist: 'Artist'),
        OnlinePlaylistSong(id: 'b', title: 'Beta', artist: 'Artist'),
        OnlinePlaylistSong(id: 'c', title: 'Gamma', artist: 'Artist'),
      ];
      final handler = _DelayedSecondLoadHandler()..failSecondLoad = failures.$1;
      final resolver = _LazySongResolver();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: _MemoryPlaylistStore(),
        cacheStore: _FakeCacheStore(cached: []),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
      );
      try {
        await controller.initialize();
        await controller.playOnlinePlaylistSong(origin, songs[0]);
        final second = controller.playOnlinePlaylistSong(origin, songs[1]);
        final secondResult = failures.$1
            ? expectLater(second, throwsStateError)
            : second;
        await handler.secondLoadStarted.future;
        if (failures.$2) {
          resolver.gate = Completer<List<MusicSearchCandidate>>()..complete([]);
        }
        final third = controller.playOnlinePlaylistSong(origin, songs[2]);
        final thirdResult = failures.$2
            ? expectLater(third, throwsStateError)
            : third;
        if (failures.$2) await thirdResult;
        handler.releaseSecondLoad.complete();
        await Future.wait([secondResult, thirdResult]);
        final expected = songs[!failures.$2 ? 2 : (!failures.$1 ? 1 : 0)];
        final playing = controller.currentTrack!;
        expect(playing.id, handler.mediaItem.value!.id);
        expect(playing.title, expected.title);
        expect(controller.canSwitchSongSource(playing), true);
        expect(controller.originalSongForTrack(playing)?.title, expected.title);
        resolver.gate = null;
        await controller.chooseSongSource(
          playing,
          _candidate(id: 'replacement', name: expected.title),
        );
        expect(controller.currentTrack?.id, playing.id);
        expect(handler.loadedIds, [playing.id]);
      } finally {
        if (!handler.releaseSecondLoad.isCompleted) {
          handler.releaseSecondLoad.complete();
        }
        controller.dispose();
        await handler.dispose();
      }
    });
  }

  test(
    'online playlist preview plays only clicked song without saving a playlist',
    () async {
      final handler = _SpyAudioHandler();
      final resolver = _LazySongResolver();
      final store = _MemoryPlaylistStore();
      final controller = MusicController(
        songSearchCache: SongSearchCache.memory(),
        audioHandler: handler,
        resolver: resolver,
        playlistStore: store,
        cacheStore: _FakeCacheStore(cached: []),
        settingsStore: _FakeSettingsStore(),
        metadataRepository: _StaticMetadataRepository(),
        downloadHistoryStore: MemoryDownloadHistory(),
        connectivityChanges: const Stream.empty(),
      );
      try {
        await controller.initialize();
        await controller.playOnlinePlaylistSong(origin, originSongs[1]);
        expect(handler.loadedItems, hasLength(1));
        expect(handler.loadedItems.single.mediaItem.title, '第二首');
        expect(resolver.searchCalls, 1);
        expect(resolver.resolveIds, hasLength(1));
        expect(controller.customPlaylists, isEmpty);
        expect(store.library.playlists, isEmpty);
        expect(
          controller.originalSongForTrack(controller.currentTrack!)?.title,
          '第二首',
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(resolver.searchCalls, 1);
        expect(resolver.resolveIds, hasLength(1));
        expect(controller.downloadQueue.tasks, isEmpty);
        expect(controller.canSwitchSongSource(controller.currentTrack!), true);
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
        );
        expect(duplicate!.entries.length, 3);
        expect(duplicate.id, playlist.id);
        expect(controller.customPlaylists, hasLength(1));
        final persisted = MusicPlaylist.fromJson(duplicate.toJson())!;
        expect(persisted.onlineOriginKey, '${origin.source.name}:${origin.id}');
        expect(
          persisted.copyWith(name: 'renamed').onlineOriginKey,
          persisted.onlineOriginKey,
        );
        final concurrent = await Future.wait([
          controller.addPlaylistDirectly(origin, originSongs),
          controller.addPlaylistDirectly(origin, originSongs),
        ]);
        expect(concurrent.map((p) => p!.id).toSet(), {playlist.id});
        expect(controller.customPlaylists, hasLength(1));
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
        final next = controller.playQueueItem(second.id);
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
      final source =
          (handler.loadedItems.single.source as DeferredStreamingAudioSource)
                  .initialSource
              as ResumableAudioSource;
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
    recordPlaybackIntent();
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
  bool failSecondLoad = false;
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
      if (failSecondLoad) throw StateError('device load failed');
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
    return const MusicAppSettings(source: MusicDataSource.auto);
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

class _FailingPreviewResolver extends _LazySongResolver {
  bool failResolve = false;
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) {
    if (failResolve) throw StateError('Preview source unavailable');
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
  _DownloadCacheStore({super.rootProvider});
  Completer<void>? validationGate;
  final validationStarted = Completer<void>();
  @override
  Future<bool> isValidCachedAudio(CachedTrack track) async {
    if (validationGate != null) {
      if (!validationStarted.isCompleted) validationStarted.complete();
      await validationGate!.future;
    }
    return super.isValidCachedAudio(track);
  }

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

class _QueuePrepareGateResolver extends _LocalStreamResolver {
  _QueuePrepareGateResolver() : super(1);
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    if (candidate.id == 'pending') {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    return super.resolve(candidate);
  }
}

class _StatsAudioHandler extends _SpyAudioHandler {
  @override
  bool get hasConsistentPlaybackItem => true;
  @override
  Future<void> play() async {
    await super.play();
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.ready),
    );
  }
}

class _LaitingFixture {
  _LaitingFixture(
    this.controller,
    this.handler,
    this.resolver,
    this.cache,
    this.store,
  );
  final MusicController controller;
  final _SpyAudioHandler handler;
  final _LaitingResolver resolver;
  final _DownloadCacheStore cache;
  final _MemoryPlaylistStore store;
  bool disposed = false;

  Future<Track> cacheChartTrack(Track track, File file) async {
    final candidate = _candidate(id: 'cached-${track.id}', name: track.title);
    final bytes = _controllerLanMp3Bytes();
    await file.writeAsBytes(bytes);
    cache.cached.add(
      _cachedTrack(
        id: candidate.id,
        name: track.title,
      ).copyWith(filePath: file.path, sizeBytes: bytes.length),
    );
    await controller.chooseSongSource(track, candidate);
    await controller.loadCache(repairLegacy: false);
    return controller
        .tracksForPlaylist(controller.builtInPlaylists.single)
        .firstWhere((item) => item.id == track.id);
  }

  static Future<_LaitingFixture> create({Directory? root}) async {
    final handler = _SpyAudioHandler();
    final resolver = _LaitingResolver();
    final cache = _DownloadCacheStore(
      rootProvider: root == null ? null : () async => root,
    );
    final store = _MemoryPlaylistStore();
    final controller = MusicController(
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cache,
      playlistStore: store,
      settingsStore: _FakeSettingsStore(),
      metadataRepository: _StaticMetadataRepository(),
      listeningStatsStore: ListeningStatsStore.memory(),
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      checkConnectivity: () async => [],
    );
    await controller.initialize();
    return _LaitingFixture(controller, handler, resolver, cache, store);
  }

  Future<void> close() async {
    if (!disposed) controller.dispose();
    for (final gate in resolver.gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await controller.waitForFavoriteDownloads();
    await handler.dispose();
  }
}

class _LaitingResolver extends _FakeMusicResolver
    implements QualitySelectableMusicResolver {
  final ids = <String>[];
  final levels = <MusicQualityLevel>[];
  final gates = <String, Completer<void>>{};
  int searchCalls = 0;
  bool fail = false;
  List<MusicSearchCandidate> searchResults = [];
  Completer<List<MusicSearchCandidate>>? searchGate;
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searchCalls++;
    return searchGate?.future ?? Future.value(searchResults);
  }

  @override
  Future<ResolvedMusic> resolveAtQuality(
    MusicSearchCandidate candidate,
    MusicQualityLevel quality,
  ) async {
    ids.add(candidate.id);
    levels.add(quality);
    if (gates[candidate.id] case final gate?) await gate.future;
    if (fail) throw StateError('offline');
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: 'https://cdn.example.test/${candidate.id}',
      quality: quality == MusicQualityLevel.high
          ? const MusicQuality(format: 'flac')
          : MusicQuality(
              format: 'mp3',
              bitrate: quality == MusicQualityLevel.medium ? '320' : '128',
            ),
    );
  }
}

class _SourcePreferenceFixture {
  _SourcePreferenceFixture(
    this.controller,
    this.handler,
    this.resolver,
    this.cache,
    this.root,
  );
  final MusicController controller;
  final _SpyAudioHandler handler;
  final _SourcePreferenceResolver resolver;
  final _DownloadCacheStore cache;
  final Directory root;
  Track get track =>
      controller.tracksForPlaylist(controller.customPlaylists.single).single;
  static Future<_SourcePreferenceFixture> create({
    bool legacy = false,
    bool manual = false,
    bool cached = false,
    bool savedCandidate = true,
    bool wrongArtist = false,
    bool onlineConnectivity = false,
    MusicDataSource initialSource = MusicDataSource.buguyy,
    _SourcePreferenceResolver? resolverOverride,
    _SpyAudioHandler? handlerOverride,
  }) async {
    final root = await Directory.systemTemp.createTemp('source-preference-');
    final handler = handlerOverride ?? _SpyAudioHandler();
    final resolver = resolverOverride ?? _SourcePreferenceResolver();
    final cache = _DownloadCacheStore(rootProvider: () async => root);
    final old = SavedOnlineTrack(
      candidate: _sourcePreferenceCandidate(
        MusicDataSource.buguyy,
        id: 'old-song',
        artist: wrongArtist ? '翻唱歌手' : 'artist',
      ),
    );
    if (cached) {
      final resolved = await resolver.resolveAtQuality(
        old.candidate,
        MusicQualityLevel.low,
      );
      final music = ResolvedMusic.fromJson({
        ...resolved.toJson(),
        'coverUrl': 'https://example.test/cover.jpg',
        'lyrics': {
          'source': 'fixture',
          'text': '完整歌词',
          'lines': [],
          'timed': false,
        },
      });
      resolver.ids.clear();
      final file = File('${root.path}/complete.mp3');
      final bytes = _controllerLanMp3Bytes();
      await file.writeAsBytes(bytes);
      cache.cached.add(
        CachedTrack(
          cacheId: cacheIdForResolved(music),
          music: music,
          filePath: file.path,
          sizeBytes: bytes.length,
          fromCache: true,
        ),
      );
    }
    final at = DateTime(2026, 10, 8);
    final store = _MemoryPlaylistStore()
      ..library = PlaylistLibrary(
        favoriteEntries: [],
        playlists: [
          MusicPlaylist(
            id: 'source-pref',
            name: '测试歌单',
            createdAt: at,
            updatedAt: at,
            entries: [
              PlaylistTrackEntry(
                trackId: old.trackId,
                addedAt: at,
                onlineTrack: savedCandidate ? old : null,
                manualSource: manual,
                song: legacy
                    ? null
                    : const PlaylistSong(
                        key: 'netease:42',
                        title: '测试歌曲',
                        artist: 'artist',
                      ),
              ),
            ],
          ),
        ],
      );
    final controller = MusicController(
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cache,
      playlistStore: store,
      settingsStore: _SourcePreferenceSettings(initialSource),
      metadataRepository: _StaticMetadataRepository(),
      listeningStatsStore: ListeningStatsStore.memory(),
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      checkConnectivity: () async =>
          onlineConnectivity ? [ConnectivityResult.wifi] : [],
    );
    await controller.initialize();
    return _SourcePreferenceFixture(controller, handler, resolver, cache, root);
  }

  Future<void> close() async {
    controller.dispose();
    for (final gate in resolver.searchGates.values) {
      if (!gate.isCompleted) gate.complete([]);
    }
    await controller.waitForFavoriteDownloads();
    await handler.dispose();
    await root.delete(recursive: true);
  }
}

class _SourcePreferenceSettings extends _FakeSettingsStore {
  _SourcePreferenceSettings(this.source);
  final MusicDataSource source;
  @override
  Future<MusicAppSettings> loadSettings() async =>
      MusicAppSettings(source: source, downloadPlaylistsOnWifi: false);
}

class _SourcePreferenceResolver extends _LaitingResolver {
  final searchSources = <MusicDataSource>[];
  final searchGates =
      <MusicDataSource, Completer<List<MusicSearchCandidate>>>{};
  final searchStarted = Completer<void>();
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    searchSources.add(source);
    if (!searchStarted.isCompleted) searchStarted.complete();
    return searchGates[source]?.future ??
        Future.value([_sourcePreferenceCandidate(source)]);
  }
}

MusicSearchCandidate _sourcePreferenceCandidate(
  MusicDataSource source, {
  String? id,
  String name = '测试歌曲',
  String artist = 'artist',
}) => MusicSearchCandidate(
  query: '测试歌曲 artist',
  source: source,
  platform: source == MusicDataSource.flac ? 'wyy' : 'buguyy',
  keyword: '测试歌曲',
  page: 1,
  id: id ?? '${source.storageValue}-song',
  name: name,
  artist: artist,
  album: '',
  duration: 200,
  link: '',
  coverUrl: '',
  qualities: const [MusicQuality(format: 'mp3')],
  score: 100,
  raw: const {},
);

Future<void> _waitForMediaCondition(
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  for (var i = 0; i < timeout.inMilliseconds ~/ 10 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    ready(),
    true,
    reason: 'Expected media recovery state before deadline',
  );
  await Future<void>.delayed(Duration.zero);
}

class _MediaHealthHandler extends _SpyAudioHandler {
  int loadCalls = 0;
  bool failFirstLoad = false;
  final firstFailureStarted = Completer<void>();
  Completer<void>? firstFailureGate;
  bool readyOnPlay = false;
  Completer<void>? recoveryLoadGate;
  final recoveryLoadStarted = Completer<void>();
  @override
  Future<void> pause() async {
    recordPlaybackIntent();
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> play() async {
    await super.play();
    if (readyOnPlay) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.ready,
        ),
      );
    }
  }

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    loadCalls++;
    if (loadCalls == 1 && failFirstLoad) {
      loadedItems = items;
      queue.add(items.map((item) => item.mediaItem).toList());
      final prepared =
          (items[initialIndex].source as DeferredStreamingAudioSource)
                  .initialSource
              as ResumableAudioSource;
      prepared.onFailure!(const HttpException('Audio HTTP 503'));
      if (!firstFailureStarted.isCompleted) firstFailureStarted.complete();
      await firstFailureGate?.future;
      throw const HttpException('Audio HTTP 503');
    }
    if (loadCalls > 1 && recoveryLoadGate != null) {
      if (!recoveryLoadStarted.isCompleted) recoveryLoadStarted.complete();
      await recoveryLoadGate!.future;
    }
    await super.loadQueue(
      items,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      playWhenReady: playWhenReady,
    );
  }
}

class _MediaHealthResolver extends _SourcePreferenceResolver
    implements AutoSourceHealthResolver {
  _MediaHealthResolver({this.port});
  final int? port;
  final health = AutoSourceHealth();
  final searchProviders = <MusicDataSource>[];
  @override
  List<MusicDataSource> get availableAutoSources => health.availableSources;
  @override
  bool isSourceAvailableForAuto(MusicDataSource source) =>
      health.isAvailable(source);
  @override
  String? sourceDegradationReason(MusicDataSource source) =>
      health.degradationReason(source);
  @override
  void reportSourceFailure(MusicDataSource source, Object error) =>
      health.recordFailure(source, error, operation: AutoSourceOperation.media);
  @override
  void reportSourceSuccess(MusicDataSource source) =>
      health.recordSuccess(source, operation: AutoSourceOperation.media);
  @override
  Future<ResolvedMusic> resolveForSourceMode(
    MusicSearchCandidate candidate,
    MusicDataSource mode, {
    MusicQualityLevel? quality,
  }) => health.run(
    candidate.source,
    () async {
      final result = await super.resolveAtQuality(
        candidate,
        quality ?? MusicQualityLevel.low,
      );
      return port == null
          ? result
          : ResolvedMusic.fromJson({
              ...result.toJson(),
              'url': 'http://127.0.0.1:$port/${candidate.id}',
            });
    },
    automatic: mode == MusicDataSource.auto,
    operation: AutoSourceOperation.resolve,
  );
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searchSources.add(source);
    final provider = source == MusicDataSource.auto
        ? health.availableSources.first
        : source;
    return health.run(
      provider,
      () async {
        searchProviders.add(provider);
        return [
          _sourcePreferenceCandidate(
            provider,
            id: '${provider.storageValue}-${query.contains('第二首') ? 'next' : 'song'}',
            name: query.contains('第二首') ? '第二首' : '测试歌曲',
          ),
        ];
      },
      automatic: source == MusicDataSource.auto,
      operation: AutoSourceOperation.search,
    );
  }
}

const _repairedQqSong = OnlinePlaylistSong(
  id: '42',
  title: '回忆观影券 (伴奏)',
  artist: '版本歌手',
  durationSeconds: 200,
);

class _QqMetadataRepository extends OnlinePlaylistRepository {
  final calls = <String>[];
  final started = Completer<void>();
  Completer<OnlinePlaylistSong>? gate;
  Object? failure;
  @override
  Future<OnlinePlaylistSong> loadQqSong(String id) async {
    calls.add(id);
    if (!started.isCompleted) started.complete();
    if (failure case final error?) throw error;
    return gate?.future ?? _repairedQqSong;
  }
}

class _QqMetadataResolver extends _LaitingResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searchCalls++;
    return [_qqRepairCandidate('instrumental', '回忆观影券 (伴奏)')];
  }
}

MusicSearchCandidate _qqRepairCandidate(String id, String name) =>
    MusicSearchCandidate(
      query: '$name 版本歌手',
      source: MusicDataSource.flac,
      platform: 'wyy',
      keyword: name,
      page: 1,
      id: id,
      name: name,
      artist: '版本歌手',
      album: '',
      duration: 200,
      link: '',
      coverUrl: 'https://example.test/cover.jpg',
      qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
      score: 100,
      raw: const {},
    );

class _QqMetadataFixture {
  _QqMetadataFixture(
    this.controller,
    this.handler,
    this.repository,
    this.resolver,
    this.store,
    this.cache,
    this.root,
    this.vocalFile,
  );
  final MusicController controller;
  final _SpyAudioHandler handler;
  final _QqMetadataRepository repository;
  final _QqMetadataResolver resolver;
  final _MemoryPlaylistStore store;
  final _DownloadCacheStore cache;
  final Directory root;
  final File vocalFile;
  MusicPlaylist get playlist => controller.customPlaylists.single;
  Track get track => controller.tracksForPlaylist(playlist).single;
  static Future<_QqMetadataFixture> create({
    bool manual = false,
    bool favorite = false,
    bool useCacheId = false,
    int metadataVersion = 0,
  }) async {
    final root = await Directory.systemTemp.createTemp('qq-legacy-metadata-');
    final file = File('${root.path}/vocal.mp3');
    final bytes = _controllerLanMp3Bytes();
    await file.writeAsBytes(bytes);
    final candidate = _qqRepairCandidate('vocal', '回忆观影券');
    final saved = SavedOnlineTrack(candidate: candidate);
    final resolver = _QqMetadataResolver();
    final resolved = await resolver.resolveAtQuality(
      candidate,
      MusicQualityLevel.high,
    );
    resolver.ids.clear();
    final music = ResolvedMusic.fromJson({
      ...resolved.toJson(),
      'quality': {'format': 'mp3', 'bitrate': '320'},
      'coverUrl': 'https://example.test/cover.jpg',
      'lyrics': {
        'source': 'fixture',
        'text': '完整歌词',
        'lines': 1,
        'timed': false,
      },
    });
    final cache = _DownloadCacheStore(rootProvider: () async => root)
      ..cached.add(
        CachedTrack(
          cacheId: cacheIdForResolved(music),
          music: music,
          filePath: file.path,
          sizeBytes: bytes.length,
          fromCache: true,
        ),
      );
    final original = PlaylistSong.fromJson({
      'key': 'qq:42',
      'title': '回忆观影券',
      'artist': '版本歌手',
      if (metadataVersion > 0) 'metadataVersion': metadataVersion,
    })!;
    final entry = PlaylistTrackEntry(
      trackId: useCacheId ? cacheIdForResolved(music) : 'legacy-qq-logical',
      addedAt: DateTime(2026, 10, 1),
      onlineTrack: saved,
      song: original,
      manualSource: manual,
    );
    final store = _MemoryPlaylistStore()
      ..library = PlaylistLibrary(
        favoriteEntries: favorite ? [entry] : [],
        playlists: [
          MusicPlaylist(
            id: 'legacy-qq',
            name: '凡人百世书-BGM',
            entries: [entry],
            createdAt: DateTime(2026, 10, 1),
            updatedAt: DateTime(2026, 10, 1),
          ),
        ],
      );
    final handler = _SpyAudioHandler();
    final repository = _QqMetadataRepository();
    final controller = MusicController(
      audioHandler: handler,
      resolver: resolver,
      cacheStore: cache,
      playlistStore: store,
      playlistMetadataRepository: repository,
      settingsStore: _SourcePreferenceSettings(MusicDataSource.flac),
      metadataRepository: _StaticMetadataRepository(),
      listeningStatsStore: ListeningStatsStore.memory(),
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      checkConnectivity: () async => [],
    );
    await controller.initialize();
    return _QqMetadataFixture(
      controller,
      handler,
      repository,
      resolver,
      store,
      cache,
      root,
      file,
    );
  }

  Future<void> close() async {
    if (repository.gate case final gate? when !gate.isCompleted) {
      gate.complete(_repairedQqSong);
    }
    controller.dispose();
    await controller.waitForFavoriteDownloads();
    await handler.dispose();
    await root.delete(recursive: true);
  }
}

class _DelayedRecoveryResolver extends _MediaHealthResolver {
  _DelayedRecoveryResolver(this.stage);
  final String stage;
  final started = Completer<void>();
  final release = Completer<void>();
  Future<void> gate(String current) async {
    if (stage == current && health.availableSources.length == 1) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
  }

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    await gate('search');
    return super.search(query, source);
  }

  @override
  Future<ResolvedMusic> resolveForSourceMode(
    MusicSearchCandidate candidate,
    MusicDataSource mode, {
    MusicQualityLevel? quality,
  }) async {
    await gate('resolve');
    return super.resolveForSourceMode(candidate, mode, quality: quality);
  }
}
