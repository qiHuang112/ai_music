import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../platform/platform_detection.dart';

class PlayableAudio {
  const PlayableAudio({required this.mediaItem, required this.uri});

  final MediaItem mediaItem;
  final Uri uri;
}

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    if (isOpenHarmonyPlatform) {
      _ohosMediaControlsChannel.setMethodCallHandler(
        _handleOhosMediaControlCall,
      );
    }
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
  static const MethodChannel _ohosMediaControlsChannel = MethodChannel(
    'com.qi.ai_music.ohos_media_controls',
  );
  Future<void> Function(String loopMode)? onOhosLoopModeRequested;
  Future<void> Function(String mediaId)? onOhosToggleFavoriteRequested;
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
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    // App 内播放器、通知栏、锁屏和耳机按键都消费 audio_service 队列，不能绕过这里直接播。
    _items = List<PlayableAudio>.unmodifiable(items);
    queue.add(_items.map((item) => item.mediaItem).toList(growable: false));

    if (_items.isEmpty) {
      mediaItem.add(null);
      unawaited(_syncOhosMediaItem(null));
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
      initialPosition: initialPosition,
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
    final item = _withKnownDuration(updated);
    mediaItem.add(item);
    await _syncOhosMediaItem(item);
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
    unawaited(_syncOhosControlState(repeatMode: repeatMode));
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
    unawaited(_syncOhosControlState(shuffleMode: shuffleMode));
  }

  Future<void> syncOhosControlState({bool? isFavorite}) {
    return _syncOhosControlState(
      repeatMode: playbackState.value.repeatMode,
      shuffleMode: playbackState.value.shuffleMode,
      isFavorite: isFavorite,
    );
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
    if (isOpenHarmonyPlatform) {
      _ohosMediaControlsChannel.setMethodCallHandler(null);
    }
    await _player.dispose();
  }

  void _publishCurrentItem(int? index) {
    if (index == null || index < 0 || index >= _items.length) {
      mediaItem.add(null);
      unawaited(_syncOhosMediaItem(null));
      return;
    }
    final item = _withKnownDuration(_items[index].mediaItem);
    mediaItem.add(item);
    unawaited(_syncOhosMediaItem(item));
  }

  void _publishDuration(Duration? duration) {
    if (duration == null) {
      return;
    }
    final current = mediaItem.value;
    if (current == null || current.duration == duration) {
      return;
    }
    // just_audio 常在 setAudioSources 之后才拿到时长；这里补发给系统播控和进度条。
    final item = current.copyWith(duration: duration);
    mediaItem.add(item);
    unawaited(_syncOhosMediaItem(item));
  }

  MediaItem _withKnownDuration(MediaItem item) {
    final duration = _player.duration;
    if (duration == null || item.duration == duration) {
      return item;
    }
    return item.copyWith(duration: duration);
  }

  Future<void> _syncOhosMediaItem(MediaItem? item) async {
    if (!isOpenHarmonyPlatform) {
      return;
    }
    try {
      if (item == null) {
        await _ohosMediaControlsChannel.invokeMethod<void>('clearMediaItem');
        return;
      }
      await _ohosMediaControlsChannel.invokeMethod<void>('updateMediaItem', {
        'id': item.id,
        'title': item.title,
        'artist': item.artist,
        'artUri': item.artUri?.toString(),
        'duration': item.duration?.inMilliseconds,
      });
    } on MissingPluginException {
      // 热重启早期插件可能尚未挂载；播放器主链路不应因此失败。
    } catch (_) {
      // 播控中心元数据是展示增强，不能影响播放。
    }
  }

  Future<void> _syncOhosControlState({
    AudioServiceRepeatMode? repeatMode,
    AudioServiceShuffleMode? shuffleMode,
    bool? isFavorite,
  }) async {
    if (!isOpenHarmonyPlatform) {
      return;
    }
    try {
      final args = <String, Object>{};
      if (repeatMode != null) {
        args['repeatMode'] = repeatMode.name;
      }
      if (shuffleMode != null) {
        args['shuffleMode'] = shuffleMode.name;
      }
      if (isFavorite != null) {
        args['isFavorite'] = isFavorite;
      }
      await _ohosMediaControlsChannel.invokeMethod<void>(
        'updateControlState',
        args,
      );
    } on MissingPluginException {
      // 热重启早期插件可能尚未挂载；播放器主链路不应因此失败。
    } catch (_) {
      // 播控中心按钮状态是展示增强，不能影响播放。
    }
  }

  Future<Object?> _handleOhosMediaControlCall(MethodCall call) async {
    switch (call.method) {
      case 'setLoopMode':
        final loopMode = _stringArg(call.arguments, 'loopMode');
        final loopCallback = onOhosLoopModeRequested;
        if (loopMode != null && loopCallback != null) {
          await loopCallback(loopMode);
          return null;
        }
        final repeatMode = _repeatModeFromOhosCall(call.arguments);
        if (repeatMode != null) {
          await setRepeatMode(repeatMode);
        }
        return null;
      case 'toggleFavorite':
        final mediaId = _stringArg(call.arguments, 'assetId');
        final callback = onOhosToggleFavoriteRequested;
        if (callback != null) {
          await callback(mediaId ?? mediaItem.value?.id ?? '');
        }
        return null;
      default:
        throw MissingPluginException(
          'No HarmonyOS media control handler for ${call.method}',
        );
    }
  }

  AudioServiceRepeatMode? _repeatModeFromOhosCall(Object? arguments) {
    final mode = _stringArg(arguments, 'loopMode');
    return switch (mode) {
      'single' => AudioServiceRepeatMode.one,
      'list' || 'shuffle' => AudioServiceRepeatMode.all,
      'sequence' => AudioServiceRepeatMode.none,
      _ => null,
    };
  }

  String? _stringArg(Object? arguments, String key) {
    if (arguments is Map) {
      final value = arguments[key];
      return value?.toString();
    }
    return null;
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
