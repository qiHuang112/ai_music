import 'package:audio_service/audio_service.dart';

import '../domain/music_models.dart';
import '../playback/music_audio_handler.dart';
import 'music_mappers.dart';

class PlaybackUseCase {
  const PlaybackUseCase({required this.audioHandler});

  final MusicAudioHandler audioHandler;

  Future<void> playTrack(
    Track track, {
    int? index,
    required List<Track> fallbackQueue,
    List<Track>? queueTracks,
  }) async {
    final queue = (queueTracks ?? fallbackQueue).isEmpty
        ? <Track>[track]
        : queueTracks ?? fallbackQueue;
    final queueIndex = index ?? queue.indexWhere((item) => item.id == track.id);
    final safeIndex = queueIndex == -1 ? 0 : queueIndex;
    await audioHandler.loadQueue([
      for (final item in queue)
        PlayableAudio(
          mediaItem: mediaItemFromTrack(item),
          uri: _uriForTrack(item),
        ),
    ], initialIndex: safeIndex);
  }

  Future<void> togglePlayPause() async {
    final playing = audioHandler.playbackState.value.playing;
    if (playing) {
      await audioHandler.pause();
    } else {
      await audioHandler.play();
    }
  }

  Future<void> seek(Duration position) => audioHandler.seek(position);

  Future<void> next() => audioHandler.skipToNext();

  Future<void> previous() => audioHandler.skipToPrevious();

  Future<void> stop() => audioHandler.stop();

  Future<void> applyPlaybackMode(PlaybackMode mode) async {
    final currentItemId = audioHandler.mediaItem.value?.id;
    final currentPosition = audioHandler.currentPosition;
    switch (mode) {
      case PlaybackMode.sequential:
        await audioHandler.setShuffleMode(AudioServiceShuffleMode.none);
        await audioHandler.setRepeatMode(AudioServiceRepeatMode.none);
        break;
      case PlaybackMode.loopAll:
        await audioHandler.setShuffleMode(AudioServiceShuffleMode.none);
        await audioHandler.setRepeatMode(AudioServiceRepeatMode.all);
        break;
      case PlaybackMode.repeatOne:
        await audioHandler.setShuffleMode(AudioServiceShuffleMode.none);
        await audioHandler.setRepeatMode(AudioServiceRepeatMode.one);
        break;
      case PlaybackMode.shuffle:
        await audioHandler.setRepeatMode(AudioServiceRepeatMode.all);
        await audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
        break;
    }
    if (currentItemId != null) {
      await audioHandler.restoreCurrentItemPosition(
        currentItemId,
        currentPosition,
      );
    }
  }
}

Uri _uriForTrack(Track track) {
  final source = track.playbackSource;
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Uri.parse(source);
  }
  return Uri.file(source);
}
