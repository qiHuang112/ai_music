import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class PlayableAudio {
  const PlayableAudio({required this.mediaItem, required this.uri});

  final MediaItem mediaItem;
  final Uri uri;
}

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    _playbackEventSubscription = _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });
    _currentIndexSubscription = _player.currentIndexStream.listen(
      _publishCurrentItem,
    );
    _durationSubscription = _player.durationStream.listen(_publishDuration);
    _processingStateSubscription = _player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        stop();
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<PlaybackEvent> _playbackEventSubscription;
  late final StreamSubscription<int?> _currentIndexSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final StreamSubscription<ProcessingState> _processingStateSubscription;
  List<PlayableAudio> _items = const [];

  Duration get currentPosition => _player.position;
  Stream<Duration> get positionStream => _player.positionStream;

  Future<void> configure() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    bool playWhenReady = true,
  }) async {
    _items = List<PlayableAudio>.unmodifiable(items);
    queue.add(_items.map((item) => item.mediaItem).toList(growable: false));

    if (_items.isEmpty) {
      mediaItem.add(null);
      await _player.stop();
      return;
    }

    final safeIndex = initialIndex.clamp(0, _items.length - 1);
    await _player.setAudioSources(
      [
        for (final item in _items)
          AudioSource.uri(item.uri, tag: item.mediaItem),
      ],
      initialIndex: safeIndex,
      initialPosition: Duration.zero,
    );
    _publishCurrentItem(safeIndex);
    if (playWhenReady) {
      await play();
    }
  }

  Future<void> updateCurrentMediaItem(MediaItem updated) async {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _items.length) {
      return;
    }
    if (_items[index].mediaItem.id != updated.id) {
      return;
    }
    _items = List<PlayableAudio>.unmodifiable([
      for (var i = 0; i < _items.length; i += 1)
        i == index
            ? PlayableAudio(mediaItem: updated, uri: _items[i].uri)
            : _items[i],
    ]);
    queue.add(_items.map((item) => item.mediaItem).toList(growable: false));
    mediaItem.add(_withKnownDuration(updated));
  }

  Future<void> restoreCurrentItemPosition(
    String mediaId,
    Duration position,
  ) async {
    final index = _items.indexWhere((item) => item.mediaItem.id == mediaId);
    if (index == -1) {
      return;
    }
    await _player.seek(position, index: index);
    _publishCurrentItem(index);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled =
        shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    if (enabled) {
      await _player.shuffle();
    }
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }

  Future<void> dispose() async {
    await _playbackEventSubscription.cancel();
    await _currentIndexSubscription.cancel();
    await _durationSubscription.cancel();
    await _processingStateSubscription.cancel();
    await _player.dispose();
  }

  void _publishCurrentItem(int? index) {
    if (index == null || index < 0 || index >= _items.length) {
      mediaItem.add(null);
      return;
    }
    final item = _withKnownDuration(_items[index].mediaItem);
    mediaItem.add(item);
  }

  void _publishDuration(Duration? duration) {
    if (duration == null) {
      return;
    }
    final current = mediaItem.value;
    if (current == null || current.duration == duration) {
      return;
    }
    mediaItem.add(current.copyWith(duration: duration));
  }

  MediaItem _withKnownDuration(MediaItem item) {
    final duration = _player.duration;
    if (duration == null || item.duration == duration) {
      return item;
    }
    return item.copyWith(duration: duration);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: playbackState.value.repeatMode,
      shuffleMode: playbackState.value.shuffleMode,
    );
  }
}
