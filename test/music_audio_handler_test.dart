import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('android compact controls use favorite, play pause, and next', () async {
    final handler = MusicAudioHandler();
    try {
      await handler.syncControlState(isFavorite: false);

      var state = handler.playbackState.value;
      expect(state.androidCompactActionIndices, const [0, 1, 3]);
      expect(state.controls[0].action, MediaAction.custom);
      expect(
        state.controls[0].customAction?.name,
        MusicAudioHandler.toggleFavoriteAction,
      );
      expect(
        state.controls[0].androidIcon,
        'drawable/ic_notification_favorite_border',
      );
      expect(state.controls[1], MediaControl.play);
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
  });

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
}
