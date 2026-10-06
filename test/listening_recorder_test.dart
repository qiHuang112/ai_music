import 'dart:async';

import 'package:ai_music/src/application/listening_recorder.dart';
import 'package:ai_music/src/data/listening_stats_store.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'recorder follows native playback, buffering, seek, background and clear',
    () async {
      final handler = _Handler();
      // Stop the real native player's initialization; drive the service streams below.
      await handler.dispose();
      final store = ListeningStatsStore.memory();
      var elapsed = Duration.zero;
      final start = DateTime(2026, 10, 6, 12);
      final recorder = ListeningRecorder(
        handler: handler,
        store: store,
        elapsed: () => elapsed,
        now: () => start.add(elapsed),
        contextFor: (item) => ListeningContext(
          ListeningSong(
            id: item.id,
            trackId: item.id,
            title: item.title,
            artist: '',
            durationMs: item.duration?.inMilliseconds,
          ),
          playlistId: 'origin',
          playlistName: 'Original playlist',
        ),
      );
      void advance(int seconds, int position) {
        elapsed = Duration(seconds: seconds);
        handler.position = Duration(seconds: position);
      }

      Future<void> state(
        AudioProcessingState state, {
        bool playing = true,
      }) async {
        handler.playbackState.add(
          PlaybackState(processingState: state, playing: playing),
        );
        await Future<void>.delayed(Duration.zero);
      }

      try {
        handler.mediaItem.add(
          const MediaItem(
            id: 'a',
            title: 'Song',
            duration: Duration(minutes: 4),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await state(AudioProcessingState.ready);
        advance(30, 30);
        // Native positions alone are not proof that the requested item loaded.
        recorder.capture();
        expect(store.records, isEmpty);
        handler.consistent = true;
        recorder.capture();
        advance(40, 40);
        recorder.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(Duration.zero);
        expect(store.report().milliseconds, 10000);
        advance(60, 60);
        await state(AudioProcessingState.ready, playing: false);
        expect(store.report().milliseconds, 30000);
        expect(store.report().plays, 1);
        advance(360, 60);
        await state(AudioProcessingState.ready, playing: false);
        expect(store.report().milliseconds, 30000);
        await state(AudioProcessingState.ready);
        advance(365, 65);
        await state(AudioProcessingState.buffering);
        advance(500, 65);
        await state(AudioProcessingState.ready);
        expect(store.report().milliseconds, 35000);
        advance(501, 180);
        handler.discontinuities.add(false);
        await Future<void>.delayed(Duration.zero);
        advance(506, 185);
        recorder.capture();
        expect(store.report().milliseconds, 40000);
        advance(507, 0);
        handler.discontinuities.add(true);
        await Future<void>.delayed(Duration.zero);
        advance(537, 30);
        recorder.capture();
        expect(store.report().plays, 2);
        expect(store.report().playlistRanks.single.id, 'origin');
        final cleared = recorder.clear();
        await Future<void>.delayed(Duration.zero);
        await cleared;
        expect(store.records, isEmpty);
        expect(handler.playbackState.value.playing, isTrue);
        expect(handler.mediaItem.value!.id, 'a');
        advance(567, 60);
        recorder.capture();
        expect(store.report().milliseconds, 30000);
        expect(store.report().plays, 1);
        // Terminal state captures the final partial interval and ends the visit.
        advance(568, 61);
        await state(AudioProcessingState.completed, playing: false);
        expect(store.report().milliseconds, 31000);
      } finally {
        final closed = recorder.close();
        await Future<void>.delayed(Duration.zero);
        await closed;
        final done = handler.discontinuities.close();
        await Future<void>.delayed(Duration.zero);
        await done;
      }
    },
  );
}

class _Handler extends MusicAudioHandler {
  bool consistent = false;
  Duration position = Duration.zero;
  final discontinuities = StreamController<bool>.broadcast(sync: true);
  @override
  bool get hasConsistentPlaybackItem => consistent;
  @override
  Duration get currentPosition => position;
  @override
  Stream<bool> get listeningDiscontinuities => discontinuities.stream;
}
