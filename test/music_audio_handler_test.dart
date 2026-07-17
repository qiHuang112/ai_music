import 'dart:async';

import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'android controls use favorite, previous, play pause, and next',
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

  test('player errors reload once on the next user play or seek', () async {
    final player = _RecoveryAudioPlayer();
    final handler = MusicAudioHandler(player: player);
    const item = MediaItem(id: 'song-1', title: 'Song 1');
    try {
      await handler.loadQueue([
        PlayableAudio(mediaItem: item, uri: Uri.parse('http://127.0.0.1/a')),
      ], playWhenReady: false);
      player.positionValue = const Duration(seconds: 12);
      player.emitError();
      await Future<void>.delayed(Duration.zero);

      await handler.play();

      expect(player.setAudioSourcesCount, 2);
      expect(player.initialPositions.last, const Duration(seconds: 12));
      expect(player.playCount, 1);

      player.positionValue = const Duration(seconds: 20);
      player.emitError();
      await Future<void>.delayed(Duration.zero);
      await handler.seek(const Duration(seconds: 45));

      expect(player.setAudioSourcesCount, 3);
      expect(player.initialPositions.last, const Duration(seconds: 45));
      expect(player.playCount, 2);

      await handler.seek(const Duration(seconds: 50));
      expect(player.setAudioSourcesCount, 3);
      expect(player.seekPositions, [const Duration(seconds: 50)]);

      player.emitError();
      await Future<void>.delayed(Duration.zero);
      player.failNextSetAudioSources = true;
      await expectLater(handler.play(), throwsStateError);
      expect(player.setAudioSourcesCount, 4);

      await handler.play();
      expect(player.setAudioSourcesCount, 4);
    } finally {
      await handler.dispose();
    }
  });

  test(
    'loadQueue returns after play starts instead of waiting for completion',
    () async {
      final player = _RecoveryAudioPlayer()..playCompleter = Completer<void>();
      final handler = MusicAudioHandler(player: player);
      try {
        await handler
            .loadQueue([
              PlayableAudio(
                mediaItem: const MediaItem(id: 'song-1', title: 'Song 1'),
                uri: Uri.parse('http://127.0.0.1/song-1'),
              ),
            ])
            .timeout(const Duration(milliseconds: 100));

        expect(player.playCount, 1);
      } finally {
        player.playCompleter?.complete();
        await handler.dispose();
      }
    },
  );

  test(
    'managed search queue delegates navigation and publishes all rows',
    () async {
      final player = _RecoveryAudioPlayer();
      final handler = MusicAudioHandler(player: player);
      var requestedIndex = -1;
      var nextRequests = 0;
      handler.onSkipToQueueItemRequested = (index) async {
        requestedIndex = index;
        return true;
      };
      handler.onSkipToNextRequested = () async {
        nextRequests += 1;
        return true;
      };
      try {
        await handler.loadQueue([
          PlayableAudio(
            mediaItem: const MediaItem(id: 'song-1', title: 'Song 1'),
            uri: Uri.parse('http://127.0.0.1/song-1'),
          ),
        ], playWhenReady: false);
        await handler.publishDisplayQueue(const [
          MediaItem(id: 'song-1', title: 'Song 1'),
          MediaItem(id: 'song-2', title: 'Song 2'),
        ], currentIndex: 0);

        await handler.skipToQueueItem(1);
        await handler.skipToNext();

        expect(handler.queue.value.map((item) => item.id), [
          'song-1',
          'song-2',
        ]);
        expect(handler.currentQueueIndex, 0);
        expect(requestedIndex, 1);
        expect(nextRequests, 1);
        expect(player.seekPositions, isEmpty);
      } finally {
        await handler.dispose();
      }
    },
  );

  test(
    'managed search queue advances when the current source completes',
    () async {
      final player = _RecoveryAudioPlayer();
      final handler = MusicAudioHandler(player: player);
      var completions = 0;
      handler.onPlaybackCompleted = () async {
        completions += 1;
        return true;
      };
      try {
        player.emitCompleted();
        await Future<void>.delayed(Duration.zero);

        expect(completions, 1);
        expect(player.stopCount, 0);
      } finally {
        await handler.dispose();
      }
    },
  );
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

class _RecoveryAudioPlayer implements AudioPlayer {
  final _playbackEvents = StreamController<PlaybackEvent>.broadcast();
  final _currentIndexes = StreamController<int?>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _processingStates = StreamController<ProcessingState>.broadcast();

  int setAudioSourcesCount = 0;
  int playCount = 0;
  int stopCount = 0;
  bool failNextSetAudioSources = false;
  Completer<void>? playCompleter;
  final List<Duration> initialPositions = [];
  final List<Duration> seekPositions = [];
  Duration positionValue = Duration.zero;
  Duration bufferedPositionValue = Duration.zero;
  int? currentIndexValue = 0;
  ProcessingState processingStateValue = ProcessingState.idle;
  bool playingValue = false;

  void emitError() {
    processingStateValue = ProcessingState.idle;
    _playbackEvents.add(
      PlaybackEvent(
        processingState: ProcessingState.idle,
        updatePosition: positionValue,
        bufferedPosition: bufferedPositionValue,
        currentIndex: currentIndexValue,
        errorCode: 500,
        errorMessage: 'source failed',
      ),
    );
  }

  void emitCompleted() {
    processingStateValue = ProcessingState.completed;
    _processingStates.add(ProcessingState.completed);
  }

  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEvents.stream;

  @override
  Stream<int?> get currentIndexStream => _currentIndexes.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Stream<ProcessingState> get processingStateStream => _processingStates.stream;

  @override
  Duration get position => positionValue;

  @override
  Duration get bufferedPosition => bufferedPositionValue;

  @override
  Duration? get duration => null;

  @override
  int? get currentIndex => currentIndexValue;

  @override
  ProcessingState get processingState => processingStateValue;

  @override
  bool get playing => playingValue;

  @override
  double get speed => 1;

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    setAudioSourcesCount += 1;
    currentIndexValue = initialIndex ?? 0;
    positionValue = initialPosition ?? Duration.zero;
    initialPositions.add(positionValue);
    if (failNextSetAudioSources) {
      failNextSetAudioSources = false;
      throw StateError('reload failed');
    }
    processingStateValue = ProcessingState.ready;
    return null;
  }

  @override
  Future<void> play() async {
    playCount += 1;
    playingValue = true;
    await playCompleter?.future;
  }

  @override
  Future<void> pause() async {
    playingValue = false;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      positionValue = position;
      seekPositions.add(position);
    }
    currentIndexValue = index ?? currentIndexValue;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    playingValue = false;
  }

  @override
  Future<void> dispose() async {
    await _playbackEvents.close();
    await _currentIndexes.close();
    await _durations.close();
    await _processingStates.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
