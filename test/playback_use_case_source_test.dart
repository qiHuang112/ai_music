// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:ai_music/src/application/playback_use_case.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/playback/resumable_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'selected prepared stream is renewed after setting changes in same queue',
    () async {
      final handler = _Handler();
      var prepared = 0;
      final useCase = PlaybackUseCase(
        audioHandler: handler,
        prepareOnlineStream: (_) async {
          prepared++;
          return _BytesSource(2);
        },
      );
      const track = Track(
        id: 'song',
        title: 'Song',
        artist: 'Artist',
        album: '',
      );
      try {
        await useCase.playTrack(
          track,
          fallbackQueue: [track],
          selectedSource: _BytesSource(1),
          shouldPlay: () => false,
        );
        final source = handler.items.single.source as StreamAudioSource;
        expect(await _read(source), [1]);
        expect(prepared, 0);

        useCase.invalidateOnlineSources();
        expect(await _read(source), [2]);
        expect(prepared, 1);
        expect(await _read(source), [2]);
        expect(prepared, 1);
      } finally {
        await handler.dispose();
      }
    },
  );

  test(
    'settings changed during lazy preparation reject the late old source',
    () async {
      var revision = 0;
      final old = Completer<StreamAudioSource>();
      var prepared = 0;
      final source = DeferredStreamingAudioSource(
        tag: 'song',
        preparationRevision: () => revision,
        prepare: () {
          prepared++;
          return prepared == 1 ? old.future : Future.value(_BytesSource(2));
        },
      );
      final requested = _read(source);
      revision++;
      old.complete(_BytesSource(1));
      expect(await requested, [2]);
      expect(prepared, 2);
    },
  );

  test('failed lazy source can be retried without changing settings', () async {
    var prepared = 0;
    final source = DeferredStreamingAudioSource(
      tag: 'song',
      prepare: () async {
        if (++prepared == 1) throw StateError('temporarily unavailable');
        return _BytesSource(3);
      },
    );
    await expectLater(_read(source), throwsStateError);
    expect(await _read(source), [3]);
    expect(prepared, 2);
  });
}

Future<List<int>> _read(StreamAudioSource source) async =>
    (await source.request()).stream.expand((bytes) => bytes).toList();

class _BytesSource extends StreamAudioSource {
  _BytesSource(this.byte);
  final int byte;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async =>
      StreamAudioResponse(
        sourceLength: 1,
        contentLength: 1,
        offset: 0,
        contentType: 'audio/mpeg',
        stream: Stream.value([byte]),
      );
}

class _Handler extends MusicAudioHandler {
  List<PlayableAudio> items = [];

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    this.items = items;
    queue.add(items.map((item) => item.mediaItem).toList());
    mediaItem.add(items[initialIndex].mediaItem);
  }
}
