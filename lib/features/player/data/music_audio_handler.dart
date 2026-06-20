import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../library/domain/track.dart';

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    _subscriptions.add(
      _player.playbackEventStream.listen(_broadcastPlaybackState),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        if (index == null || index < 0 || index >= queue.value.length) {
          return;
        }
        mediaItem.add(queue.value[index]);
      }),
    );
    _subscriptions.add(
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          skipToNext();
        }
      }),
    );
  }

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  List<Track> _tracks = const [];

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  Future<void> loadAndPlay(List<Track> tracks, int index) async {
    if (tracks.isEmpty) {
      return;
    }

    final boundedIndex = index.clamp(0, tracks.length - 1).toInt();
    _tracks = tracks;
    final items = tracks.map(_toMediaItem).toList(growable: false);
    queue.add(items);
    mediaItem.add(items[boundedIndex]);

    final sources = tracks
        .map(
          (track) =>
              AudioSource.uri(_playableUri(track), tag: _toMediaItem(track)),
        )
        .toList(growable: false);

    await _player.setAudioSources(sources, initialIndex: boundedIndex);
    await _player.play();
  }

  Future<void> setRepeatOne(bool enabled) async {
    await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
    playbackState.add(
      playbackState.value.copyWith(
        repeatMode: enabled
            ? AudioServiceRepeatMode.one
            : AudioServiceRepeatMode.none,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) {
      return;
    }
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> skipToNext() async {
    if (_tracks.isEmpty) {
      return;
    }
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      await _player.seek(Duration.zero, index: 0);
    }
    await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_tracks.isEmpty) {
      return;
    }
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero, index: _tracks.length - 1);
    }
    await _player.play();
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }

  MediaItem _toMediaItem(Track track) {
    return MediaItem(
      id: track.localPath ?? track.sourceUrl,
      title: track.title,
      artist: track.artist,
      album: track.album,
      extras: {'trackId': track.id},
    );
  }

  Uri _playableUri(Track track) {
    final path = track.localPath;
    if (path != null && File(path).existsSync()) {
      return Uri.file(path);
    }
    return Uri.parse(track.sourceUrl);
  }

  void _broadcastPlaybackState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapProcessingState(_player.processingState),
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
        repeatMode: _player.loopMode == LoopMode.one
            ? AudioServiceRepeatMode.one
            : AudioServiceRepeatMode.none,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }
}
