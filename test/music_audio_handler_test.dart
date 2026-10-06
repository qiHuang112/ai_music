import 'dart:async';

import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/playback/shuffle_skip_planner.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'android controls include favorite and a fifth playback mode action',
    () async {
      final handler = MusicAudioHandler();
      try {
        await handler.syncControlState(isFavorite: false);

        var state = handler.playbackState.value;
        expect(state.androidCompactActionIndices, const [0, 2, 3]);
        expect(state.controls[0].action, MediaAction.custom);
        expect(
          state.controls[0].customAction?.name,
          MusicAudioHandler.toggleFavoriteAction,
        );
        expect(
          state.controls[0].androidIcon,
          'drawable/ic_notification_favorite_border',
        );
        expect(state.controls[1], MediaControl.skipToPrevious);
        expect(state.controls[2], MediaControl.play);
        expect(state.controls[3], MediaControl.skipToNext);
        expect(state.controls, hasLength(5));
        expect(state.controls[4].action, MediaAction.custom);
        expect(
          state.controls[4].customAction?.name,
          MusicAudioHandler.togglePlaybackModeAction,
        );
        expect(
          state.controls[4].androidIcon,
          'drawable/ic_notification_repeat_all',
        );

        await handler.setRepeatMode(AudioServiceRepeatMode.one);
        expect(
          handler.playbackState.value.controls[4].androidIcon,
          'drawable/ic_notification_repeat_one',
        );
        await handler.setShuffleMode(AudioServiceShuffleMode.all);
        expect(
          handler.playbackState.value.controls[4].androidIcon,
          'drawable/ic_notification_shuffle',
        );

        await handler.syncControlState(isFavorite: true);
        state = handler.playbackState.value;
        expect(
          state.controls[0].androidIcon,
          'drawable/ic_notification_favorite',
        );
      } finally {
        await handler.dispose();
      }
    },
  );

  test('favorite custom action reports the active media id', () async {
    final handler = MusicAudioHandler();
    var toggledId = '';
    handler.onToggleFavoriteRequested = (mediaId) async {
      toggledId = mediaId;
    };
    try {
      handler.mediaItem.add(const MediaItem(id: 'song-1', title: 'Song 1'));

      await handler.customAction(MusicAudioHandler.toggleFavoriteAction);

      expect(toggledId, 'song-1');
    } finally {
      handler.onToggleFavoriteRequested = null;
      await handler.dispose();
    }
  });

  test('playback mode custom action calls the controller callback', () async {
    final handler = MusicAudioHandler();
    var calls = 0;
    handler.onTogglePlaybackModeRequested = () async {
      calls += 1;
    };
    try {
      await handler.customAction(MusicAudioHandler.togglePlaybackModeAction);
      expect(calls, 1);
    } finally {
      handler.onTogglePlaybackModeRequested = null;
      await handler.dispose();
    }
  });

  test('favorite control sync keeps the current playback position', () async {
    final handler = _PositionedAudioHandler(
      position: const Duration(seconds: 42),
      bufferedPosition: const Duration(seconds: 60),
      speed: 1.25,
      queueIndex: 2,
    );
    try {
      await Future<void>.delayed(Duration.zero);
      handler.playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: true,
          updatePosition: const Duration(seconds: 5),
          bufferedPosition: const Duration(seconds: 10),
          speed: 1,
          queueIndex: 0,
        ),
      );

      await handler.syncControlState(isFavorite: true);

      final state = handler.playbackState.value;
      expect(state.updatePosition, const Duration(seconds: 42));
      expect(state.bufferedPosition, const Duration(seconds: 60));
      expect(state.speed, 1.25);
      expect(state.queueIndex, 2);
      expect(
        state.controls[0].androidIcon,
        'drawable/ic_notification_favorite',
      );
    } finally {
      await handler.dispose();
    }
  });

  test('manual next and previous publish each selected song once', () async {
    final originalPlatform = JustAudioPlatform.instance;
    JustAudioPlatform.instance = _TestJustAudioPlatform();
    final handler = MusicAudioHandler();
    final publishedIds = <String>[];
    final subscription = handler.mediaItem.stream.listen((item) {
      if (item != null) publishedIds.add(item.id);
    });
    try {
      await handler.loadQueue([
        PlayableAudio(
          mediaItem: const MediaItem(id: 'a', title: 'A'),
          source: AudioSource.uri(Uri.parse('https://example.com/a.mp3')),
        ),
        PlayableAudio(
          mediaItem: const MediaItem(id: 'b', title: 'B'),
          source: AudioSource.uri(Uri.parse('https://example.com/b.mp3')),
        ),
      ], playWhenReady: false);
      await Future<void>.delayed(Duration.zero);
      publishedIds.clear();

      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      await Future<void>.delayed(Duration.zero);
      publishedIds.clear();
      await handler.skipToNext();
      await Future<void>.delayed(Duration.zero);
      expect(publishedIds, ['b']);

      publishedIds.clear();
      await handler.skipToPrevious();
      await Future<void>.delayed(Duration.zero);
      expect(publishedIds, ['a']);
    } finally {
      await subscription.cancel();
      await handler.dispose();
      JustAudioPlatform.instance = originalPlatform;
    }
  });

  test(
    'shuffle next uses native current song even when displayed metadata is stale',
    () async {
      final original = JustAudioPlatform.instance;
      final platform = _TestJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final planner = ShuffleSkipPlanner(seed: 7);
      final handler = MusicAudioHandler(shuffleSkipPlanner: planner);
      try {
        final ids = ['a', 'b', 'c', 'd'];
        await handler.loadQueue([
          for (final id in ids)
            PlayableAudio(
              mediaItem: MediaItem(id: id, title: id),
              source: AudioSource.uri(Uri.parse('https://example.com/$id.mp3')),
            ),
        ], playWhenReady: false);
        await handler.setShuffleMode(AudioServiceShuffleMode.all);
        await handler.skipToQueueItem(2);
        await Future<void>.delayed(Duration.zero);
        final expected = ids.indexOf(planner.peekNextAfter('c')!);
        final stale = ids.firstWhere(
          (id) => planner.peekNextAfter(id) != ids[expected],
        );
        handler.mediaItem.add(MediaItem(id: stale, title: stale));
        await handler.skipToNext();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(platform._players.values.single._index, expected);
        expect(handler.mediaItem.value?.id, ids[expected]);
        expect(handler.playbackState.value.queueIndex, expected);
      } finally {
        await handler.dispose();
        JustAudioPlatform.instance = original;
      }
    },
  );

  test(
    'shuffle redirect keeps displayed item aligned with native audio while seeking',
    () async {
      final original = JustAudioPlatform.instance;
      final platform = _TestJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final planner = ShuffleSkipPlanner(seed: 7);
      final handler = MusicAudioHandler(shuffleSkipPlanner: planner);
      try {
        final ids = ['a', 'b', 'c', 'd'];
        await handler.loadQueue([
          for (final id in ids)
            PlayableAudio(
              mediaItem: MediaItem(id: id, title: id),
              source: AudioSource.uri(Uri.parse('https://example.com/$id.mp3')),
            ),
        ], playWhenReady: false);
        await handler.setShuffleMode(AudioServiceShuffleMode.all);
        await Future<void>.delayed(Duration.zero);
        final native = platform._players.values.single;
        final target = ids.indexOf(planner.peekNextAfter('a')!);
        final fallback = [1, 2, 3].firstWhere((i) => i != target);
        native.seekGate = Completer<void>();
        native.advanceTo(fallback);
        await native.seekStarted.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(Duration.zero);
        expect(handler.currentQueueIndex, fallback);
        expect(
          handler.mediaItem.value?.id,
          ids[fallback],
          reason:
              'The source currently producing audio must supply system metadata.',
        );
        native.seekGate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(handler.mediaItem.value?.id, ids[native._index!]);
        expect(handler.playbackState.value.queueIndex, native._index);
      } finally {
        for (final player in platform._players.values) {
          if (player.seekGate?.isCompleted == false) {
            player.seekGate!.complete();
          }
        }
        await handler.dispose();
        JustAudioPlatform.instance = original;
      }
    },
  );

  test(
    'shuffle publishes actual error fallback rather than waiting forever for its target',
    () async {
      final original = JustAudioPlatform.instance;
      final platform = _TestJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final planner = ShuffleSkipPlanner(seed: 7);
      final handler = MusicAudioHandler(shuffleSkipPlanner: planner);
      try {
        final ids = ['a', 'b', 'c', 'd'];
        await handler.loadQueue([
          for (final id in ids)
            PlayableAudio(
              mediaItem: MediaItem(id: id, title: id),
              source: AudioSource.uri(Uri.parse('https://example.com/$id.mp3')),
            ),
        ], playWhenReady: false);
        await handler.setShuffleMode(AudioServiceShuffleMode.all);
        await Future<void>.delayed(Duration.zero);
        final native = platform._players.values.single;
        final target = ids.indexOf(planner.peekNextAfter('a')!);
        final fallback = [1, 2, 3].firstWhere((i) => i != target);
        final recovered = [
          1,
          2,
          3,
        ].firstWhere((i) => i != target && i != fallback);
        native.seekGate = Completer<void>();
        native.advanceTo(fallback);
        await native.seekStarted.future.timeout(const Duration(seconds: 2));
        native.advanceTo(recovered);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(handler.mediaItem.value?.id, ids[recovered]);
        expect(handler.playbackState.value.queueIndex, recovered);
      } finally {
        for (final player in platform._players.values) {
          if (player.seekGate?.isCompleted == false) {
            player.seekGate!.complete();
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await handler.dispose();
        JustAudioPlatform.instance = original;
      }
    },
  );

  test(
    'removing an earlier queue item synchronizes the system index without another native event',
    () async {
      final original = JustAudioPlatform.instance;
      final platform = _TestJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final handler = MusicAudioHandler();
      try {
        await handler.loadQueue(
          [
            for (final id in ['a', 'b', 'c', 'd'])
              PlayableAudio(
                mediaItem: MediaItem(id: id, title: id),
                source: AudioSource.uri(
                  Uri.parse('https://example.com/$id.mp3'),
                ),
              ),
          ],
          initialIndex: 2,
          playWhenReady: false,
        );
        await handler.removeQueueItemAt(0);
        await Future<void>.delayed(Duration.zero);
        expect(platform._players.values.single._index, 1);
        expect(handler.mediaItem.value?.id, 'c');
        expect(handler.playbackState.value.queueIndex, 1);
      } finally {
        await handler.dispose();
        JustAudioPlatform.instance = original;
      }
    },
  );

  test(
    'editing the queue cancels a deferred shuffle seek whose index would move',
    () async {
      final original = JustAudioPlatform.instance;
      final platform = _TestJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final planner = ShuffleSkipPlanner(seed: 7);
      final handler = MusicAudioHandler(shuffleSkipPlanner: planner);
      Future<void>? editing;
      try {
        final ids = ['a', 'b', 'c', 'd'];
        await handler.loadQueue([
          for (final id in ids)
            PlayableAudio(
              mediaItem: MediaItem(id: id, title: id),
              source: AudioSource.uri(Uri.parse('https://example.com/$id.mp3')),
            ),
        ], playWhenReady: false);
        await handler.setShuffleMode(AudioServiceShuffleMode.all);
        await Future<void>.delayed(Duration.zero);
        final native = platform._players.values.single;
        final target = ids.indexOf(planner.peekNextAfter('a')!);
        final fallback = [1, 2, 3].firstWhere((index) => index != target);
        final advanced = handler.mediaItem.firstWhere(
          (item) => item?.id == ids[fallback],
        );
        native.advanceTo(fallback);
        await advanced.timeout(const Duration(seconds: 2));
        native.removeGate = Completer<void>();
        editing = handler.removeQueueItemAt(0);
        await native.removeStarted.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(native.seekStarted.isCompleted, isFalse);
        native.removeGate!.complete();
        await editing;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(native.seekStarted.isCompleted, isFalse);
        expect(native._index, fallback - 1);
        expect(handler.mediaItem.value?.id, ids[fallback]);
        expect(handler.playbackState.value.queueIndex, fallback - 1);
      } finally {
        for (final player in platform._players.values) {
          if (player.removeGate?.isCompleted == false) {
            player.removeGate!.complete();
          }
        }
        await editing;
        await handler.dispose();
        JustAudioPlatform.instance = original;
      }
    },
  );

  test(
    'appending recognized songs keeps the current item and queue index',
    () async {
      final originalPlatform = JustAudioPlatform.instance;
      JustAudioPlatform.instance = _TestJustAudioPlatform();
      final handler = MusicAudioHandler();
      try {
        await handler.loadQueue([
          PlayableAudio(
            mediaItem: const MediaItem(id: 'a', title: 'A'),
            source: AudioSource.uri(Uri.parse('https://example.com/a.mp3')),
          ),
        ], playWhenReady: false);
        await handler.appendQueue([
          PlayableAudio(
            mediaItem: const MediaItem(id: 'b', title: 'B'),
            source: AudioSource.uri(Uri.parse('https://example.com/b.mp3')),
          ),
        ]);
        expect(handler.mediaItem.value?.id, 'a');
        expect(handler.currentQueueIndex, 0);
        expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
        expect(handler.nextQueueIndex, 1);
      } finally {
        await handler.dispose();
        JustAudioPlatform.instance = originalPlatform;
      }
    },
  );

  test(
    'replacing an upcoming match keeps the current source selected',
    () async {
      final originalPlatform = JustAudioPlatform.instance;
      JustAudioPlatform.instance = _TestJustAudioPlatform();
      final handler = MusicAudioHandler();
      try {
        PlayableAudio item(String id) => PlayableAudio(
          mediaItem: MediaItem(id: id, title: id),
          source: AudioSource.uri(Uri.parse('https://example.com/$id.mp3')),
        );
        await handler.loadQueue([
          item('a'),
          item('b'),
          item('c'),
        ], playWhenReady: false);
        await handler.replaceQueueItemAt(1, item('d'));
        expect(handler.queue.value.map((item) => item.id), ['a', 'd', 'c']);
        expect(handler.mediaItem.value?.id, 'a');
        expect(handler.currentQueueIndex, 0);
        await handler.removeQueueItemAt(2);
        expect(handler.queue.value.map((item) => item.id), ['a', 'd']);
        expect(handler.mediaItem.value?.id, 'a');
      } finally {
        await handler.dispose();
        JustAudioPlatform.instance = originalPlatform;
      }
    },
  );
}

class _TestJustAudioPlatform extends JustAudioPlatform {
  final _players = <String, _TestAudioPlayerPlatform>{};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _TestAudioPlayerPlatform(request.id);
    _players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await _players.remove(request.id)?.close();
    return DisposePlayerResponse();
  }
}

class _TestAudioPlayerPlatform extends AudioPlayerPlatform {
  _TestAudioPlayerPlatform(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  int? _index;
  Completer<void>? seekGate;
  Completer<void>? removeGate;
  final removeStarted = Completer<void>();
  final seekStarted = Completer<void>();
  void advanceTo(int index) {
    _index = index;
    _emit();
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _index = request.initialIndex ?? 0;
    _emit();
    return LoadResponse(duration: null);
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (!seekStarted.isCompleted) seekStarted.complete();
    if (seekGate != null) await seekGate!.future;
    _index = request.index ?? _index;
    _emit();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async {
    if (_index != null && _index! >= request.index) {
      _index = _index! + request.children.length;
    }
    _emit();
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async {
    if (!removeStarted.isCompleted) removeStarted.complete();
    if (removeGate != null) await removeGate!.future;
    if (_index != null && _index! >= request.endIndex) {
      _index = _index! - (request.endIndex - request.startIndex);
    }
    _emit();
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  Future<void> close() => _events.close();

  void _emit() {
    _events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updatePosition: Duration.zero,
        updateTime: DateTime.now(),
        bufferedPosition: Duration.zero,
        duration: null,
        icyMetadata: null,
        currentIndex: _index,
        androidAudioSessionId: null,
      ),
    );
  }
}

class _PositionedAudioHandler extends MusicAudioHandler {
  _PositionedAudioHandler({
    required this.position,
    required this.bufferedPosition,
    required this.speed,
    required this.queueIndex,
  });

  final Duration position;
  final Duration bufferedPosition;
  final double speed;
  final int? queueIndex;

  @override
  Duration get currentPosition => position;

  @override
  Duration get currentBufferedPosition => bufferedPosition;

  @override
  double get currentSpeed => speed;

  @override
  int? get currentQueueIndex => queueIndex;
}
