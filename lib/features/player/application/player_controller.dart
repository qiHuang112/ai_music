import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_providers.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/track.dart';
import '../data/music_audio_handler.dart';

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(musicAudioHandlerProvider).playbackState;
});

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(musicAudioHandlerProvider).mediaItem;
});

final playbackPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(musicAudioHandlerProvider).positionStream;
});

final playbackDurationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(musicAudioHandlerProvider).durationStream;
});

final currentIndexProvider = StreamProvider<int?>((ref) {
  return ref.watch(musicAudioHandlerProvider).currentIndexStream;
});

final playerControllerProvider = Provider<PlayerController>((ref) {
  return PlayerController(ref, ref.watch(musicAudioHandlerProvider));
});

class PlayerController {
  const PlayerController(this._ref, this._audioHandler);

  final Ref _ref;
  final MusicAudioHandler _audioHandler;

  Future<void> playTrack(Track track) async {
    final library = _ref.read(libraryControllerProvider).value;
    if (library == null) {
      return;
    }

    final queue = library.tracks.isEmpty ? [track] : library.tracks;
    final index = queue.indexWhere((item) => item.id == track.id);
    await _audioHandler.loadAndPlay(queue, index < 0 ? 0 : index);

    if (!track.isCached) {
      unawaited(
        _ref
            .read(libraryControllerProvider.notifier)
            .cacheTrack(track, surfaceError: false)
            .catchError((_) => track),
      );
    }
  }

  Future<void> togglePlayPause() async {
    final state = _ref.read(playbackStateProvider).value;
    if (state?.playing ?? false) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> seek(Duration position) => _audioHandler.seek(position);

  Future<void> next() => _audioHandler.skipToNext();

  Future<void> previous() => _audioHandler.skipToPrevious();

  Future<void> toggleRepeatOne() async {
    final state = _ref.read(playbackStateProvider).value;
    final isRepeatOne = state?.repeatMode == AudioServiceRepeatMode.one;
    await _audioHandler.setRepeatOne(!isRepeatOne);
  }
}
