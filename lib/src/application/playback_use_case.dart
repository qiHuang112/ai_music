import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/music_models.dart';
import '../playback/music_audio_handler.dart';
import '../playback/on_demand_audio_source.dart';
import 'music_mappers.dart';

class PlaybackUseCase {
  PlaybackUseCase({required this.audioHandler, this.prepareOnlineTrack});

  final MusicAudioHandler audioHandler;
  final Future<File> Function(Track track)? prepareOnlineTrack;
  String? _lastRequestedTrackId;
  String? _lastQueueSignature;

  Future<bool> playTrack(
    Track track, {
    int? index,
    required List<Track> fallbackQueue,
    List<Track>? queueTracks,
    bool Function()? shouldPlay,
  }) async {
    final queue = (queueTracks ?? fallbackQueue).isEmpty
        ? <Track>[track]
        : queueTracks ?? fallbackQueue;
    final queueSignature = _queueSignature(queue);
    final currentTrackId = audioHandler.mediaItem.value?.id;
    final sameTrack =
        currentTrackId == track.id ||
        (currentTrackId == null && _lastRequestedTrackId == track.id);
    // 去重必须同时看歌曲和队列；同一首在收藏/缓存/歌单里点击，下一首应按当前列表走。
    final sameQueue = _lastQueueSignature == queueSignature;
    if (sameTrack && sameQueue) {
      if (!audioHandler.playbackState.value.playing &&
          (shouldPlay?.call() ?? true)) {
        _startPlayback();
      }
      return false;
    }
    final queueIndex = index ?? queue.indexWhere((item) => item.id == track.id);
    final safeIndex = queueIndex == -1 ? 0 : queueIndex;
    final initialPosition = sameTrack
        ? audioHandler.currentPosition
        : Duration.zero;
    await audioHandler.loadQueue(
      [
        for (final item in queue)
          PlayableAudio(
            mediaItem: mediaItemFromTrack(item),
            source: item.playbackSource.isEmpty
                ? OnDemandAudioSource(
                    tag: mediaItemFromTrack(item),
                    prepare: () {
                      final prepare = prepareOnlineTrack;
                      if (prepare == null) {
                        throw StateError(
                          'Online track preparation is unavailable',
                        );
                      }
                      return prepare(item);
                    },
                  )
                : AudioSource.uri(
                    _uriForTrack(item),
                    tag: mediaItemFromTrack(item),
                  ),
          ),
      ],
      initialIndex: safeIndex,
      initialPosition: initialPosition,
      playWhenReady: shouldPlay == null,
    );
    if (shouldPlay?.call() ?? false) {
      _startPlayback();
    }
    _lastRequestedTrackId = track.id;
    _lastQueueSignature = queueSignature;
    return true;
  }

  void _startPlayback() {
    unawaited(
      audioHandler.play().catchError((Object error, StackTrace stack) {
        audioHandler.playbackState.add(
          audioHandler.playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
            errorMessage: error.toString(),
          ),
        );
      }),
    );
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

  Future<void> stop() async {
    _lastRequestedTrackId = null;
    _lastQueueSignature = null;
    await audioHandler.stop();
  }

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
    final nextItemId = audioHandler.mediaItem.value?.id;
    if (currentItemId != null &&
        nextItemId != null &&
        nextItemId != currentItemId) {
      // just_audio 开启随机时可能切换当前 index；这里把用户正在听的位置拉回去。
      await audioHandler.restoreCurrentItemPosition(
        currentItemId,
        currentPosition,
      );
    }
  }
}

String _queueSignature(List<Track> queue) {
  return queue.map((track) => track.id).join('\u001f');
}

Uri _uriForTrack(Track track) {
  final source = track.playbackSource;
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Uri.parse(source);
  }
  return Uri.file(source);
}
