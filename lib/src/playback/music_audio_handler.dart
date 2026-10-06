import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../platform/platform_detection.dart';
import 'playback_index_tracker.dart';
import 'shuffle_skip_planner.dart';

class PlayableAudio {
  const PlayableAudio({required this.mediaItem, required this.source});

  final MediaItem mediaItem;
  final AudioSource source;
}

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler({ShuffleSkipPlanner? shuffleSkipPlanner})
    : _shuffleSkipPlanner = shuffleSkipPlanner ?? ShuffleSkipPlanner() {
    if (isOpenHarmonyPlatform) {
      _ohosMediaControlsChannel.setMethodCallHandler(
        _handleOhosMediaControlCall,
      );
    }
    _playbackEventSubscription = _player.playbackEventStream.listen((event) {
      // Use the same native event for metadata and queueIndex. The derived
      // currentIndex stream can lag, especially with fast release callbacks.
      _handleCurrentIndexChanged(event.currentIndex);
      playbackState.add(_transformEvent(event));
    });
    _durationSubscription = _player.durationStream.listen(_publishDuration);
    _processingStateSubscription = _player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        stop();
      }
    });
  }

  final AudioPlayer _player = AudioPlayer(maxSkipsOnError: 20);
  static const MethodChannel _ohosMediaControlsChannel = MethodChannel(
    'com.qi.ai_music.ohos_media_controls',
  );
  static const String toggleFavoriteAction = 'toggleFavorite';
  static const String togglePlaybackModeAction = 'togglePlaybackMode';
  Future<void> Function(String loopMode)? onOhosLoopModeRequested;
  Future<void> Function(String mediaId)? onOhosToggleFavoriteRequested;
  Future<void> Function(String mediaId)? onToggleFavoriteRequested;
  Future<void> Function()? onTogglePlaybackModeRequested;
  late final StreamSubscription<PlaybackEvent> _playbackEventSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final StreamSubscription<ProcessingState> _processingStateSubscription;
  List<PlayableAudio> _items = const [];
  final ShuffleSkipPlanner _shuffleSkipPlanner;
  final PlaybackIndexTracker _indexTracker = PlaybackIndexTracker();
  bool _editingQueue = false;
  bool _loadingQueue = false;
  int _queueRevision = 0;
  bool _shuffleModeEnabled = false;
  bool _isCurrentFavorite = false;

  Duration get currentPosition => _player.position;
  Duration get currentBufferedPosition => _player.bufferedPosition;
  double get currentSpeed => _player.speed;
  int? get currentQueueIndex => _player.playbackEvent.currentIndex;
  int? get nextQueueIndex {
    final current = mediaItem.value;
    if (_shuffleModeEnabled && current != null) {
      final next = _shuffleSkipPlanner.peekNextAfter(current.id);
      final index = _items.indexWhere((item) => item.mediaItem.id == next);
      return index < 0 ? null : index;
    }
    return _nextSequentialIndex();
  }

  int? followingQueueIndex(String mediaId) {
    if (_shuffleModeEnabled) {
      final nextId = _shuffleSkipPlanner.peekNextAfter(mediaId);
      final index = _items.indexWhere((item) => item.mediaItem.id == nextId);
      return index < 0 ? null : index;
    }
    final index = _items.indexWhere((item) => item.mediaItem.id == mediaId);
    if (index < 0) return null;
    if (index + 1 < _items.length) return index + 1;
    return _player.loopMode == LoopMode.all && _items.length > 1 ? 0 : null;
  }

  Stream<Duration> get positionStream => _player.positionStream;
  bool get hasConsistentPlaybackItem =>
      !_loadingQueue &&
      _player.currentIndex != null &&
      _player.currentIndex! >= 0 &&
      _player.currentIndex! < _items.length &&
      _items[_player.currentIndex!].mediaItem.id == mediaItem.value?.id;
  Stream<bool> get listeningDiscontinuities =>
      _player.positionDiscontinuityStream.map(
        (event) =>
            event.reason == PositionDiscontinuityReason.autoAdvance &&
            !_loadingQueue &&
            !_editingQueue,
      );

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
    _loadingQueue = true;
    _queueRevision += 1;
    var safeIndex = 0;
    try {
      _items = List<PlayableAudio>.unmodifiable(items);
      _indexTracker.reset();
      _shuffleSkipPlanner.reset(
        _items.map((item) => item.mediaItem.id).toList(),
      );
      queue.add(_items.map((item) => item.mediaItem).toList(growable: false));

      if (_items.isEmpty) {
        mediaItem.add(null);
        unawaited(_syncOhosMediaItem(null));
        await _player.stop();
        return;
      }

      safeIndex = initialIndex.clamp(0, _items.length - 1);
      if (!playWhenReady && _player.playing) {
        await _player.pause();
      }
      await _player.setAudioSources(
        [for (final item in _items) item.source],
        initialIndex: safeIndex,
        initialPosition: initialPosition,
      );
    } finally {
      _loadingQueue = false;
    }
    final actualIndex = _player.playbackEvent.currentIndex ?? safeIndex;
    _publishCurrentItem(actualIndex.clamp(0, _items.length - 1));
    playbackState.add(_transformEvent(_player.playbackEvent));
    if (playWhenReady) {
      await play();
    }
  }

  /// Adds newly recognized playlist songs without resetting the current
  /// source, position, or playback state.
  Future<void> appendQueue(List<PlayableAudio> additions) async {
    if (additions.isEmpty) return;
    _beginQueueEdit();
    try {
      await _player.addAudioSources([
        for (final item in additions) item.source,
      ]);
      _items = List<PlayableAudio>.unmodifiable([..._items, ...additions]);
      _publishQueue();
    } finally {
      await _finishQueueEdit();
    }
  }

  /// Replaces an upcoming or previous item without seeking or restarting the
  /// current source. The currently playing item is handled by the controller
  /// after playback advances.
  Future<void> replaceQueueItemAt(int index, PlayableAudio replacement) async {
    if (index < 0 || index >= _items.length || index == _player.currentIndex) {
      throw RangeError.index(index, _items);
    }
    _beginQueueEdit();
    try {
      await _player.insertAudioSource(index, replacement.source);
      await _player.removeAudioSourceAt(index + 1);
      _items = List<PlayableAudio>.unmodifiable([
        for (var i = 0; i < _items.length; i++)
          i == index ? replacement : _items[i],
      ]);
      _publishQueue();
    } finally {
      await _finishQueueEdit();
    }
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _items.length || index == _player.currentIndex) {
      throw RangeError.index(index, _items);
    }
    _beginQueueEdit();
    try {
      await _player.removeAudioSourceAt(index);
      _items = List<PlayableAudio>.unmodifiable([
        for (var i = 0; i < _items.length; i++)
          if (i != index) _items[i],
      ]);
      _publishQueue();
    } finally {
      await _finishQueueEdit();
    }
  }

  void _beginQueueEdit() {
    _editingQueue = true;
    _queueRevision += 1;
    // Pending numeric seek targets belong to the old source list. Cancel them
    // before native insert/remove callbacks can move those indices.
    _indexTracker.reset();
  }

  Future<void> _finishQueueEdit() async {
    // just_audio may complete the mutation before its queued index callback.
    // Keep that structural index shift out of automatic shuffle detection.
    await Future<void>.delayed(Duration.zero);
    _editingQueue = false;
    _publishCurrentIfChanged();
  }

  void _publishQueue() {
    _shuffleSkipPlanner.updateQueue(
      _items.map((item) => item.mediaItem.id).toList(growable: false),
    );
    queue.add(_items.map((item) => item.mediaItem).toList(growable: false));
  }

  void _publishCurrentIfChanged() {
    final index = _player.playbackEvent.currentIndex;
    if (index == null || index < 0 || index >= _items.length) return;
    if (mediaItem.value?.id != _items[index].mediaItem.id) {
      _publishCurrentItem(index);
    } else {
      _indexTracker.markPublished(index);
    }
    playbackState.add(_transformEvent(_player.playbackEvent));
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
            ? PlayableAudio(mediaItem: updated, source: _items[i].source)
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
    _indexTracker.markManualTarget(
      currentIndex: _player.currentIndex,
      targetIndex: index,
    );
    await _player.seek(position, index: index);
    _publishCurrentItem(index);
  }

  @override
  Future<void> play() {
    unawaited(
      _player.play().catchError((Object error, StackTrace stack) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
            errorMessage: error.toString(),
          ),
        );
      }),
    );
    return Future<void>.value();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
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
    if (_shuffleModeEnabled && _items.length > 1) {
      final index = _player.playbackEvent.currentIndex;
      final current = index == null || index < 0 || index >= _items.length
          ? null
          : _items[index].mediaItem;
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
        await play();
        return;
      }
    }
    final nextIndex = _manualAdjacentIndex(1);
    if (nextIndex == null) return;
    _indexTracker.markManualTarget(
      currentIndex: _player.currentIndex,
      targetIndex: nextIndex,
    );
    await _player.seek(Duration.zero, index: nextIndex);
    await play();
  }

  @override
  Future<void> skipToPrevious() async {
    final previousIndex = _manualAdjacentIndex(-1);
    if (previousIndex == null) return;
    _indexTracker.markManualTarget(
      currentIndex: _player.currentIndex,
      targetIndex: previousIndex,
    );
    await _player.seek(Duration.zero, index: previousIndex);
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
    playbackState.add(
      playbackState.value.copyWith(
        repeatMode: repeatMode,
        controls: _mediaControls(repeatMode: repeatMode),
      ),
    );
    unawaited(_syncOhosControlState(repeatMode: repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled =
        shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    _shuffleModeEnabled = enabled;
    if (!enabled) _indexTracker.pendingShuffleRedirectIndex = null;
    if (enabled) {
      _shuffleSkipPlanner.updateQueue(
        _items.map((item) => item.mediaItem.id).toList(),
      );
    }
    // 手动下一首需要走 Dart 层的稳定随机顺序和短听排除策略；
    // 不启用 just_audio 内建 shuffle，避免真机下一首被播放器内部顺序接管。
    await _player.setShuffleModeEnabled(false);
    playbackState.add(
      playbackState.value.copyWith(
        shuffleMode: shuffleMode,
        controls: _mediaControls(shuffleMode: shuffleMode),
      ),
    );
    unawaited(_syncOhosControlState(shuffleMode: shuffleMode));
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
    if (name == togglePlaybackModeAction) {
      await onTogglePlaybackModeRequested?.call();
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> stop() async {
    _indexTracker.pendingShuffleRedirectIndex = null;
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
    _indexTracker.pendingShuffleRedirectIndex = null;
    await _playbackEventSubscription.cancel();
    await _durationSubscription.cancel();
    await _processingStateSubscription.cancel();
    if (isOpenHarmonyPlatform) {
      _ohosMediaControlsChannel.setMethodCallHandler(null);
    }
    await _player.dispose();
  }

  void _handleCurrentIndexChanged(int? index) {
    if (_editingQueue || _loadingQueue) return;
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
        if (_indexTracker.lastIndex != index) {
          _publishCurrentItem(index);
        }
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
    // The fallback is already the native current source. Publish it now,
    // then publish the random target only when native confirms that transition.
    _publishCurrentItem(fallbackIndex);
    if (shuffleIndex == -1 || shuffleIndex == fallbackIndex) return;
    _indexTracker.markPendingShuffleRedirect(shuffleIndex);
    unawaited(_seekToShuffleRedirect(shuffleIndex, _queueRevision));
  }

  Future<void> _seekToShuffleRedirect(
    int shuffleIndex,
    int queueRevision,
  ) async {
    try {
      // Native events reach playbackEvent before just_audio's derived state.
      // Seeking inside that callback can otherwise be discarded as "loading".
      await Future<void>.delayed(Duration.zero);
      if (_loadingQueue ||
          _editingQueue ||
          _queueRevision != queueRevision ||
          _indexTracker.pendingShuffleRedirectIndex != shuffleIndex) {
        return;
      }
      await _player.seek(Duration.zero, index: shuffleIndex);
    } catch (_) {
      if (_queueRevision == queueRevision &&
          _indexTracker.pendingShuffleRedirectIndex == shuffleIndex) {
        _indexTracker.pendingShuffleRedirectIndex = null;
        final actual = _player.playbackEvent.currentIndex;
        if (!_loadingQueue &&
            !_editingQueue &&
            actual != null &&
            actual >= 0 &&
            actual < _items.length) {
          _publishCurrentItem(actual);
        }
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
      queueIndex: _loadingQueue || _editingQueue
          ? null
          : _indexTracker.lastIndex,
      repeatMode: playbackState.value.repeatMode,
      shuffleMode: playbackState.value.shuffleMode,
    );
  }

  static const List<int> _androidCompactActionIndices = [0, 2, 3];

  List<MediaControl> _mediaControls({
    AudioServiceRepeatMode? repeatMode,
    AudioServiceShuffleMode? shuffleMode,
  }) {
    final shuffled =
        (shuffleMode ?? playbackState.value.shuffleMode) !=
        AudioServiceShuffleMode.none;
    final repeatsOne =
        (repeatMode ?? playbackState.value.repeatMode) ==
        AudioServiceRepeatMode.one;
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
      MediaControl.custom(
        androidIcon: shuffled
            ? 'drawable/ic_notification_shuffle'
            : repeatsOne
            ? 'drawable/ic_notification_repeat_one'
            : 'drawable/ic_notification_repeat_all',
        label: shuffled
            ? '随机播放'
            : repeatsOne
            ? '单曲循环'
            : '顺序播放',
        name: togglePlaybackModeAction,
      ),
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

  int? _manualAdjacentIndex(int offset) {
    final index = _player.currentIndex;
    if (index == null || _items.isEmpty) {
      return null;
    }
    return (index + offset + _items.length) % _items.length;
  }
}
