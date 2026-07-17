import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../platform/platform_detection.dart';
import 'playback_index_tracker.dart';
import 'shuffle_skip_planner.dart';

class PlayableAudio {
  const PlayableAudio({required this.mediaItem, required this.uri});

  final MediaItem mediaItem;
  final Uri uri;
}

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler({
    ShuffleSkipPlanner? shuffleSkipPlanner,
    AudioPlayer? player,
  }) : _player = player ?? AudioPlayer(),
       _shuffleSkipPlanner = shuffleSkipPlanner ?? ShuffleSkipPlanner() {
    if (isOpenHarmonyPlatform) {
      _ohosMediaControlsChannel.setMethodCallHandler(
        _handleOhosMediaControlCall,
      );
    }
    _playbackEventSubscription = _player.playbackEventStream.listen(
      (event) {
        final failed = event.errorCode != null || event.errorMessage != null;
        if (failed) {
          _markSourceError();
        }
        final state = _transformEvent(event);
        playbackState.add(
          failed
              ? state.copyWith(
                  processingState: AudioProcessingState.error,
                  playing: false,
                )
              : state,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _markSourceError();
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );
      },
    );
    _currentIndexSubscription = _player.currentIndexStream.listen(
      _handleCurrentIndexChanged,
    );
    _durationSubscription = _player.durationStream.listen(_publishDuration);
    _processingStateSubscription = _player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        unawaited(_handlePlaybackCompleted());
      }
    });
  }

  final AudioPlayer _player;
  static const MethodChannel _ohosMediaControlsChannel = MethodChannel(
    'com.qi.ai_music.ohos_media_controls',
  );
  static const String toggleFavoriteAction = 'toggleFavorite';
  Future<void> Function(String loopMode)? onOhosLoopModeRequested;
  Future<void> Function(String mediaId)? onOhosToggleFavoriteRequested;
  Future<void> Function(String mediaId)? onToggleFavoriteRequested;
  Future<bool> Function()? onSkipToNextRequested;
  Future<bool> Function()? onSkipToPreviousRequested;
  Future<bool> Function(int index)? onSkipToQueueItemRequested;
  Future<bool> Function()? onPlaybackCompleted;
  late final StreamSubscription<PlaybackEvent> _playbackEventSubscription;
  late final StreamSubscription<int?> _currentIndexSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final StreamSubscription<ProcessingState> _processingStateSubscription;
  List<PlayableAudio> _items = const [];
  List<MediaItem>? _displayQueueItems;
  int? _displayQueueIndex;
  final ShuffleSkipPlanner _shuffleSkipPlanner;
  final PlaybackIndexTracker _indexTracker = PlaybackIndexTracker();
  bool _shuffleModeEnabled = false;
  bool _isCurrentFavorite = false;
  bool _sourceErrorPending = false;
  bool _isRecoveringSource = false;
  bool _playRequested = false;
  bool _isHandlingCompletion = false;

  Duration get currentPosition => _player.position;
  Duration get currentBufferedPosition => _player.bufferedPosition;
  double get currentSpeed => _player.speed;
  int? get currentQueueIndex => _displayQueueIndex ?? _player.currentIndex;
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
    _displayQueueItems = null;
    _displayQueueIndex = null;
    _sourceErrorPending = false;
    _isRecoveringSource = false;
    _playRequested = false;
    _indexTracker.reset();
    _shuffleSkipPlanner.reset(_items.map((item) => item.mediaItem.id).toList());
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
    final displayItems = _displayQueueItems;
    if (displayItems == null) {
      queue.add(_items.map((item) => item.mediaItem).toList(growable: false));
    } else {
      final displayIndex = displayItems.indexWhere(
        (item) => item.id == updated.id,
      );
      if (displayIndex != -1) {
        _displayQueueItems = List<MediaItem>.unmodifiable([
          for (var i = 0; i < displayItems.length; i += 1)
            if (i == displayIndex) updated else displayItems[i],
        ]);
      }
      queue.add(_displayQueueItems!);
    }
    final item = _withKnownDuration(updated);
    mediaItem.add(item);
    await _syncOhosMediaItem(item);
  }

  Future<void> publishDisplayQueue(
    List<MediaItem> items, {
    required int currentIndex,
  }) async {
    if (items.isEmpty) {
      _displayQueueItems = null;
      _displayQueueIndex = null;
      queue.add(_items.map((item) => item.mediaItem).toList(growable: false));
      return;
    }
    _displayQueueItems = List<MediaItem>.unmodifiable(items);
    _displayQueueIndex = currentIndex.clamp(0, items.length - 1);
    // ignore: avoid_print
    print(
      '[AI Music][playback] display queue count=${items.length} '
      'currentIndex=$_displayQueueIndex',
    );
    queue.add(_displayQueueItems!);
    playbackState.add(
      playbackState.value.copyWith(queueIndex: _displayQueueIndex),
    );
  }

  Future<void> restoreCurrentItemPosition(
    String mediaId,
    Duration position,
  ) async {
    final index = _items.indexWhere((item) => item.mediaItem.id == mediaId);
    if (index == -1) {
      return;
    }
    _indexTracker.markManualTarget(
      currentIndex: _player.currentIndex,
      targetIndex: index,
    );
    await _player.seek(position, index: index);
    _publishCurrentItem(index);
  }

  @override
  Future<void> play() async {
    _playRequested = true;
    await _reloadSourceAfterError(_player.position);
    _startPlayer();
  }

  @override
  Future<void> pause() async {
    _playRequested = false;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final reloaded = await _reloadSourceAfterError(position);
    if (!reloaded) {
      await _player.seek(position);
      return;
    }
    if (_playRequested) {
      _startPlayer();
    }
  }

  void _startPlayer() {
    unawaited(
      _player.play().onError((Object error, StackTrace stackTrace) {
        _markSourceError();
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );
      }),
    );
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final callback = onSkipToQueueItemRequested;
    if (callback != null && await callback(index)) {
      return;
    }
    if (index < 0 || index >= _items.length) {
      return;
    }
    _indexTracker.markManualTarget(
      currentIndex: _player.currentIndex,
      targetIndex: index,
    );
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  @override
  Future<void> skipToNext() async {
    final callback = onSkipToNextRequested;
    if (callback != null && await callback()) {
      return;
    }
    if (_shuffleModeEnabled && _items.length > 1) {
      final current = mediaItem.value;
      final nextId = current == null
          ? null
          : _shuffleSkipPlanner.nextAfter(
              current.id,
              position: _player.position,
            );
      final nextIndex = nextId == null
          ? -1
          : _items.indexWhere((item) => item.mediaItem.id == nextId);
      if (nextIndex != -1) {
        _indexTracker.markManualTarget(
          currentIndex: _player.currentIndex,
          targetIndex: nextIndex,
        );
        await _player.seek(Duration.zero, index: nextIndex);
        _publishCurrentItem(nextIndex);
        await play();
        return;
      }
    }
    final nextIndex = _nextSequentialIndex();
    if (nextIndex != null) {
      _indexTracker.markManualTarget(
        currentIndex: _player.currentIndex,
        targetIndex: nextIndex,
      );
    }
    await _player.seekToNext();
    await play();
  }

  @override
  Future<void> skipToPrevious() async {
    final callback = onSkipToPreviousRequested;
    if (callback != null && await callback()) {
      return;
    }
    final previousIndex = _previousSequentialIndex();
    if (previousIndex != null) {
      _indexTracker.markManualTarget(
        currentIndex: _player.currentIndex,
        targetIndex: previousIndex,
      );
    }
    await _player.seekToPrevious();
    await play();
  }

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
    _shuffleModeEnabled = enabled;
    if (enabled) {
      _shuffleSkipPlanner.updateQueue(
        _items.map((item) => item.mediaItem.id).toList(),
      );
    }
    // 手动下一首需要走 Dart 层的稳定随机顺序和短听排除策略；
    // 不启用 just_audio 内建 shuffle，避免真机下一首被播放器内部顺序接管。
    await _player.setShuffleModeEnabled(false);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    unawaited(_syncOhosControlState(shuffleMode: shuffleMode));
  }

  Future<void> setManagedQueueMode({
    required AudioServiceRepeatMode repeatMode,
    required AudioServiceShuffleMode shuffleMode,
  }) async {
    _shuffleModeEnabled = false;
    await _player.setLoopMode(LoopMode.off);
    await _player.setShuffleModeEnabled(false);
    playbackState.add(
      playbackState.value.copyWith(
        repeatMode: repeatMode,
        shuffleMode: shuffleMode,
      ),
    );
    unawaited(
      _syncOhosControlState(repeatMode: repeatMode, shuffleMode: shuffleMode),
    );
  }

  Future<void> syncControlState({bool? isFavorite}) {
    if (isFavorite != null) {
      _isCurrentFavorite = isFavorite;
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: _mediaControls(),
        androidCompactActionIndices: _androidCompactActionIndices,
        updatePosition: currentPosition,
        bufferedPosition: currentBufferedPosition,
        speed: currentSpeed,
        queueIndex: currentQueueIndex,
      ),
    );
    return _syncOhosControlState(
      repeatMode: playbackState.value.repeatMode,
      shuffleMode: playbackState.value.shuffleMode,
      isFavorite: isFavorite,
    );
  }

  Future<void> syncOhosControlState({bool? isFavorite}) {
    return syncControlState(isFavorite: isFavorite);
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == toggleFavoriteAction) {
      final callback = onToggleFavoriteRequested;
      if (callback != null) {
        await callback(_mediaIdFromExtras(extras) ?? mediaItem.value?.id ?? '');
      }
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> stop() async {
    _playRequested = false;
    _sourceErrorPending = false;
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

  Future<void> _handlePlaybackCompleted() async {
    if (_isHandlingCompletion) {
      return;
    }
    _isHandlingCompletion = true;
    try {
      final callback = onPlaybackCompleted;
      if (callback != null && await callback()) {
        return;
      }
      await stop();
    } finally {
      _isHandlingCompletion = false;
    }
  }

  void _markSourceError() {
    if (!_isRecoveringSource && _items.isNotEmpty) {
      _sourceErrorPending = true;
    }
  }

  Future<bool> _reloadSourceAfterError(Duration position) async {
    if (!_sourceErrorPending || _isRecoveringSource || _items.isEmpty) {
      return false;
    }
    _sourceErrorPending = false;
    _isRecoveringSource = true;
    final index = (_player.currentIndex ?? _indexTracker.lastIndex ?? 0).clamp(
      0,
      _items.length - 1,
    );
    try {
      await _player.setAudioSources(
        [
          for (final item in _items)
            AudioSource.uri(item.uri, tag: item.mediaItem),
        ],
        initialIndex: index,
        initialPosition: position,
      );
      _publishCurrentItem(index);
      return true;
    } finally {
      _isRecoveringSource = false;
    }
  }

  void _handleCurrentIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _items.length) {
      _indexTracker.markPublished(null);
      mediaItem.add(null);
      unawaited(_syncOhosMediaItem(null));
      return;
    }
    final action = _indexTracker.handleIndexChanged(
      index,
      shuffleModeEnabled: _shuffleModeEnabled,
      itemCount: _items.length,
    );
    switch (action) {
      case PlaybackIndexChangeAction.ignore:
        return;
      case PlaybackIndexChangeAction.redirectAutomaticShuffle:
        _redirectAutomaticShuffleAdvance(index);
        return;
      case PlaybackIndexChangeAction.publish:
        _publishCurrentItem(index);
    }
  }

  void _redirectAutomaticShuffleAdvance(int fallbackIndex) {
    final previousIndex = _indexTracker.lastIndex;
    if (previousIndex == null ||
        previousIndex < 0 ||
        previousIndex >= _items.length) {
      _publishCurrentItem(fallbackIndex);
      return;
    }
    final nextId = _shuffleSkipPlanner.nextAfterCompleted(
      _items[previousIndex].mediaItem.id,
    );
    final shuffleIndex = nextId == null
        ? -1
        : _items.indexWhere((item) => item.mediaItem.id == nextId);
    if (shuffleIndex == -1 || shuffleIndex == fallbackIndex) {
      _publishCurrentItem(fallbackIndex);
      return;
    }
    _indexTracker.markPendingShuffleRedirect(shuffleIndex);
    unawaited(_seekToShuffleRedirect(shuffleIndex, fallbackIndex));
  }

  Future<void> _seekToShuffleRedirect(
    int shuffleIndex,
    int fallbackIndex,
  ) async {
    try {
      await _player.seek(Duration.zero, index: shuffleIndex);
    } catch (_) {
      if (_indexTracker.pendingShuffleRedirectIndex == shuffleIndex) {
        _indexTracker.pendingShuffleRedirectIndex = null;
        _publishCurrentItem(fallbackIndex);
      }
    }
  }

  void _publishCurrentItem(int index) {
    _indexTracker.markPublished(index);
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
      case 'play':
        await play();
        return null;
      case 'pause':
        await pause();
        return null;
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
        final callback =
            onOhosToggleFavoriteRequested ?? onToggleFavoriteRequested;
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

  String? _mediaIdFromExtras(Map<String, dynamic>? extras) {
    final value = extras?['mediaId'];
    return value?.toString();
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: _mediaControls(),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: _androidCompactActionIndices,
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
      queueIndex: _displayQueueIndex ?? event.currentIndex,
      repeatMode: playbackState.value.repeatMode,
      shuffleMode: playbackState.value.shuffleMode,
    );
  }

  static const List<int> _androidCompactActionIndices = [0, 2, 3];

  List<MediaControl> _mediaControls() {
    return [
      MediaControl.custom(
        androidIcon: _isCurrentFavorite
            ? 'drawable/ic_notification_favorite'
            : 'drawable/ic_notification_favorite_border',
        label: _isCurrentFavorite ? '取消收藏' : '收藏',
        name: toggleFavoriteAction,
        extras: {'mediaId': mediaItem.value?.id ?? ''},
      ),
      MediaControl.skipToPrevious,
      if (_player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];
  }

  int? _nextSequentialIndex() {
    final index = _player.currentIndex;
    if (index == null || _items.isEmpty) {
      return null;
    }
    if (index + 1 < _items.length) {
      return index + 1;
    }
    return _player.loopMode == LoopMode.all ? 0 : null;
  }

  int? _previousSequentialIndex() {
    final index = _player.currentIndex;
    if (index == null || _items.isEmpty) {
      return null;
    }
    if (index > 0) {
      return index - 1;
    }
    return _player.loopMode == LoopMode.all ? _items.length - 1 : index;
  }
}
