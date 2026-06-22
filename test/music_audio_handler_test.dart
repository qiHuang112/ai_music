import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
