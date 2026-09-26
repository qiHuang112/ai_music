import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/lyrics_artwork.dart';
import '../data/legacy_cache_repairer.dart';
import '../data/lan_library_client.dart';
import '../data/lan_library_models.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
import '../data/saved_online_track.dart';
import '../domain/music_models.dart';
import '../playback/music_audio_handler.dart';
import 'download_queue_controller.dart';
import 'download_use_case.dart';
import 'lan_folder_playlist_merger.dart';
import 'library_controller.dart';
import 'library_use_case.dart';
import 'lan_sync_use_case.dart';
import 'metadata_use_case.dart';
import 'music_mappers.dart';
import 'music_ui_message.dart';
import 'playback_use_case.dart';
import 'prefetch_retry.dart';
import 'settings_controller.dart';
import 'screenshot_matcher.dart';

/// UI 层的组合门面。
///
/// 搜索、下载、播放、歌单和元数据的核心流程分别下沉到 use case。
/// 这里保留 ChangeNotifier 状态，是为了让页面只依赖一个稳定入口。
class MusicController extends ChangeNotifier {
  MusicController({
    required this.audioHandler,
    MusicResolver? resolver,
    CachedTrackStore? cacheStore,
    PlaylistStore? playlistStore,
    MusicSettingsStore? settingsStore,
    TrackMetadataRepository? metadataRepository,
    LegacyCacheRepairer? legacyRepairer,
    LanLibraryGateway? lanLibraryGateway,
    LanSyncUseCase? lanSyncUseCase,
  }) : _resolver = resolver ?? RemoteMusicResolver(),
       _cacheStore = cacheStore ?? CachedTrackStore(),
       _playlistStore = playlistStore ?? PlaylistStore(),
       _settingsStore = settingsStore ?? MusicSettingsStore(),
       _metadataRepository = metadataRepository ?? TrackMetadataRepository(),
       _legacyRepairerOverride = legacyRepairer {
    _lanLibraryGateway = lanLibraryGateway ?? LanLibraryClient();
    _ownsLanLibraryGateway = lanLibraryGateway == null;
    settingsController = SettingsController(settingsStore: _settingsStore);
    libraryUseCase = LibraryUseCase(
      cacheStore: _cacheStore,
      playlistStore: _playlistStore,
      metadataRepository: _metadataRepository,
      libraryController: libraryController,
    );
    downloadUseCase = DownloadUseCase(
      resolver: _resolver,
      cacheStore: _cacheStore,
      queue: downloadQueue,
    );
    this.lanSyncUseCase =
        lanSyncUseCase ??
        LanSyncUseCase(
          gateway: _lanLibraryGateway,
          cacheStore: _cacheStore,
          playlistMerger: LanFolderPlaylistMerger(store: _playlistStore),
        );
    playbackUseCase = PlaybackUseCase(
      audioHandler: audioHandler,
      prepareOnlineTrack: _prepareOnlineTrack,
    );
    _nextPrefetch = NextTrackPrefetch(
      prepare: (trackId) async {
        final request = _prefetchRequest;
        final track = _activeQueueTracks
            .where((item) => item.id == trackId)
            .firstOrNull;
        if (track == null) return;
        await _prepareOnlineTrack(track, prefetchRequest: request);
      },
      classify: classifyAudioPrefetchFailure,
      nextAfterDefinitive: _nextAfterDefinitivePrefetchFailure,
      onCancel: (_) {
        _prefetchRequest += 1;
        final taskId = _prefetchTaskId;
        if (taskId != null) downloadQueue.cancel(taskId);
      },
    );
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (results) => _nextPrefetch.setOnline(
          results.any((result) => result != ConnectivityResult.none),
        ),
        onError: (Object _) {},
      );
      unawaited(
        Connectivity()
            .checkConnectivity()
            .then((results) {
              if (!_isDisposed) {
                _nextPrefetch.setOnline(
                  results.any((result) => result != ConnectivityResult.none),
                );
              }
            })
            .catchError((Object _) {}),
      );
    } catch (_) {
      // Platforms without a connectivity plugin still use bounded retry.
    }
    metadataUseCase = MetadataUseCase(repository: _metadataRepository);
    audioHandler.onOhosLoopModeRequested = _handleOhosLoopModeRequested;
    audioHandler.onOhosToggleFavoriteRequested =
        _handleOhosToggleFavoriteRequested;
    audioHandler.onToggleFavoriteRequested = _handleToggleFavoriteRequested;
    _mediaItemSubscription = audioHandler.mediaItem.listen(
      _handleMediaItemChanged,
    );
    _playbackSubscription = audioHandler.playbackState.listen((state) {
      if (state.playing) _maybePrefetchNext();
    });
  }

  final MusicAudioHandler audioHandler;
  final MusicResolver _resolver;
  final CachedTrackStore _cacheStore;
  final PlaylistStore _playlistStore;
  final MusicSettingsStore _settingsStore;
  final TrackMetadataRepository _metadataRepository;
  final LegacyCacheRepairer? _legacyRepairerOverride;
  late final LanLibraryGateway _lanLibraryGateway;
  late final bool _ownsLanLibraryGateway;
  final LibraryController libraryController = const LibraryController();
  final DownloadQueueController downloadQueue = DownloadQueueController();
  late final SettingsController settingsController;
  late final LibraryUseCase libraryUseCase;
  late final DownloadUseCase downloadUseCase;
  late final LanSyncUseCase lanSyncUseCase;
  late final PlaybackUseCase playbackUseCase;
  late final MetadataUseCase metadataUseCase;
  late final StreamSubscription<MediaItem?> _mediaItemSubscription;
  late final StreamSubscription<PlaybackState> _playbackSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  late final NextTrackPrefetch _nextPrefetch;
  int _prefetchRequest = 0;
  String? _prefetchTaskId;
  final Map<String, Future<void>> _downloadsInFlight = {};
  final Map<String, Object> _downloadFailures = {};
  List<Track> _activeQueueTracks = const [];
  int _playRequest = 0;
  Future<void> _playLoadTail = Future<void>.value();
  String? _prefetchForCurrentId;
  final Set<String> _prefetchRejectedForCurrent = {};
  @visibleForTesting
  String? get pendingPrefetchTrackId => _nextPrefetch.trackId;
  List<CachedTrack> _cachedRecords = const [];
  PlaylistLibrary _playlistLibrary = const PlaylistLibrary.empty();
  int _metadataRequest = 0;
  // 搜索框允许“非空换非空”快速输入；request id 用来丢弃晚返回的旧结果。
  int _searchRequest = 0;
  String? _metadataTrackId;
  final Set<String> _autoMetadataRecoveryAttempted = {};
  bool _legacyRepairRunning = false;
  bool _isDisposed = false;

  MusicDataSource source = MusicDataSource.buguyy;
  List<MusicSearchCandidate> candidates = const [];
  List<Track> cachedTracks = const [];
  List<Track> onlineTracks = const [];
  List<Track> favoriteTracks = const [];
  List<MusicPlaylist> customPlaylists = const [];
  List<DownloadTask> get downloadTasks => downloadQueue.tasks;
  MusicSearchCandidate? get busyCandidate => downloadQueue.busyCandidate;
  Set<String> get busyCandidateKeys => downloadQueue.busyCandidateKeys;
  PlaybackMode playbackMode = PlaybackMode.sequential;
  AppLanguage language = AppLanguage.zh;
  AppThemePreference themePreference = AppThemePreference.dark;
  String lanLibraryUrl = defaultLanLibraryUrl;
  bool isTestingLanConnection = false;
  bool isLanSyncing = false;
  int lanSyncCompleted = 0;
  int lanSyncTotal = 0;
  String lanSyncCurrentTitle = '';
  String? lanConnectionStatus;
  String? lanSyncError;
  LanSyncResult? lastLanSyncResult;
  TrackMetadata currentMetadata = const TrackMetadata();
  bool isSearching = false;
  bool isLoadingCache = false;
  bool isLoadingMetadata = false;
  bool isRepairingLegacyCache = false;
  String? errorDetail;
  MusicUiMessage? errorMessage;
  MusicUiMessage? statusMessage;
  String? metadataError;

  Stream<PlaybackState> get playbackStateStream => audioHandler.playbackState;
  Stream<MediaItem?> get mediaItemStream => audioHandler.mediaItem;
  Stream<Duration> get positionStream => audioHandler.positionStream;
  List<LyricLine> get currentLyrics => currentMetadata.lyrics;
  Uri? get currentArtworkUri => currentMetadata.artworkUri;
  List<DownloadTask> get activeDownloadTasks {
    return downloadQueue.activeTasks;
  }

  List<DownloadTask> get recentDownloadTasks {
    return downloadQueue.recentTasks;
  }

  bool get hasSearchState {
    return isSearching ||
        candidates.isNotEmpty ||
        errorMessage != null ||
        errorDetail != null;
  }

  Track? get currentTrack {
    final item = audioHandler.mediaItem.value;
    if (item == null) {
      return null;
    }
    return [
      ...cachedTracks,
      ...onlineTracks,
    ].where((track) => track.id == item.id).firstOrNull;
  }

  Future<void> initialize() async {
    final settings = await settingsController.load();
    source = settings.source;
    language = settings.language;
    themePreference = settings.theme;
    lanLibraryUrl = settings.lanLibraryUrl;
    await _cacheStore.cleanupTemporaryFiles();
    await loadCache();
    notifyListeners();
  }

  Future<void> loadCache({bool repairLegacy = true}) async {
    if (_isDisposed) {
      return;
    }
    isLoadingCache = true;
    notifyListeners();
    try {
      _applyLibrarySnapshot(await libraryUseCase.loadCache());
      if (_isDisposed) {
        return;
      }
      if (repairLegacy && !_legacyRepairRunning) {
        unawaited(repairLegacyCache());
      }
    } catch (exception) {
      if (_isDisposed) {
        return;
      }
      errorDetail = friendlyError(exception);
    } finally {
      if (!_isDisposed) {
        isLoadingCache = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveSource(MusicDataSource nextSource) async {
    source = nextSource;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> saveLanguage(AppLanguage nextLanguage) async {
    language = nextLanguage;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> saveTheme(AppThemePreference nextTheme) async {
    themePreference = nextTheme;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> saveLanLibraryUrl(String value) async {
    lanLibraryUrl = normalizeLanLibraryBaseUri(value).toString();
    lanConnectionStatus = null;
    notifyListeners();
    await _saveSettings();
  }

  Future<LanLibraryHealth?> testLanConnection([String? value]) async {
    if (isTestingLanConnection) {
      return null;
    }
    isTestingLanConnection = true;
    lanConnectionStatus = null;
    notifyListeners();
    try {
      final candidate = normalizeLanLibraryBaseUri(
        value ?? lanLibraryUrl,
      ).toString();
      final health = await _lanLibraryGateway.testConnection(candidate);
      lanConnectionStatus = '连接成功，共 ${health.trackCount} 首';
      return health;
    } on Object catch (error) {
      lanConnectionStatus = friendlyError(error);
      return null;
    } finally {
      isTestingLanConnection = false;
      notifyListeners();
    }
  }

  Future<LanSyncResult?> syncLanLibrary() async {
    if (isLanSyncing) {
      return null;
    }
    isLanSyncing = true;
    lanSyncCompleted = 0;
    lanSyncTotal = 0;
    lanSyncCurrentTitle = '';
    lanSyncError = null;
    lastLanSyncResult = null;
    notifyListeners();
    try {
      final result = await lanSyncUseCase.sync(
        lanLibraryUrl,
        onProgress: (progress) {
          lanSyncCompleted = progress.completed;
          lanSyncTotal = progress.total;
          lanSyncCurrentTitle = progress.currentTitle;
          notifyListeners();
        },
      );
      lastLanSyncResult = result;
      await loadCache(repairLegacy: false);
      return result;
    } on Object catch (error) {
      lanSyncError = friendlyError(error);
      return null;
    } finally {
      isLanSyncing = false;
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }
    final request = ++_searchRequest;
    isSearching = true;
    errorDetail = null;
    errorMessage = null;
    statusMessage = null;
    candidates = const [];
    notifyListeners();
    try {
      final progressiveResolver = _resolver is ProgressiveMusicResolver
          ? _resolver as ProgressiveMusicResolver
          : null;
      if (progressiveResolver != null) {
        await for (final progress in progressiveResolver.searchProgressively(
          trimmed,
          source,
        )) {
          if (request != _searchRequest) {
            return;
          }
          candidates = progress.candidates;
          if (progress.isComplete) {
            if (progress.error != null) {
              errorDetail = friendlyError(progress.error!);
            } else if (progress.candidates.isEmpty) {
              errorMessage = const MusicUiMessage(
                MusicUiMessageCode.noOnlineMatchesFound,
              );
            }
          }
          notifyListeners();
        }
      } else {
        final result = await _resolver.search(trimmed, source);
        if (request != _searchRequest) {
          return;
        }
        candidates = result;
        if (result.isEmpty) {
          errorMessage = const MusicUiMessage(
            MusicUiMessageCode.noOnlineMatchesFound,
          );
        }
      }
    } catch (exception) {
      if (request != _searchRequest) {
        return;
      }
      errorDetail = friendlyError(exception);
      errorMessage = null;
    } finally {
      if (request == _searchRequest) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchRequest += 1;
    isSearching = false;
    candidates = const [];
    errorDetail = null;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();
  }

  Future<void> downloadCandidate(
    MusicSearchCandidate candidate, {
    bool? requireExactIdentity,
    bool background = false,
  }) async {
    final key = downloadQueue.taskIdForCandidate(candidate);
    final inFlight = _downloadsInFlight[key];
    if (inFlight != null) {
      if (!background) {
        statusMessage = const MusicUiMessage(
          MusicUiMessageCode.downloadAlreadyRunning,
        );
        notifyListeners();
      }
      return;
    }
    final work = _downloadCandidateNow(
      candidate,
      requireExactIdentity: requireExactIdentity,
      background: background,
    );
    _downloadsInFlight[key] = work;
    try {
      await work;
    } finally {
      _downloadsInFlight.remove(key);
    }
  }

  Future<DownloadTask?> downloadCandidateAndWait(
    MusicSearchCandidate candidate, {
    bool? requireExactIdentity,
  }) async {
    final key = downloadQueue.taskIdForCandidate(candidate);
    final inFlight = _downloadsInFlight[key];
    if (inFlight != null) {
      await inFlight;
    } else {
      await downloadCandidate(
        candidate,
        requireExactIdentity: requireExactIdentity,
      );
    }
    return downloadQueue.taskById(key);
  }

  Future<void> _downloadCandidateNow(
    MusicSearchCandidate candidate, {
    bool? requireExactIdentity,
    bool background = false,
  }) async {
    final taskId = downloadQueue.taskIdForCandidate(candidate);
    _downloadFailures.remove(taskId);
    // 重复点击同一候选时只提示已有任务，避免清掉当前下载进度和状态。
    if (downloadQueue.hasActiveToken(
      downloadQueue.taskIdForCandidate(candidate),
    )) {
      if (!background) {
        statusMessage = const MusicUiMessage(
          MusicUiMessageCode.downloadAlreadyRunning,
        );
        notifyListeners();
      }
      return;
    }
    if (!background) {
      errorDetail = null;
      errorMessage = null;
      statusMessage = null;
      notifyListeners();
    }
    final result = await downloadUseCase.downloadCandidate(
      candidate,
      requireExactIdentity: requireExactIdentity ?? false,
      onStatus: (message) {
        if (!background) {
          statusMessage = message;
          if (!_isDisposed) notifyListeners();
        }
      },
      onChanged: () {
        if (!_isDisposed) notifyListeners();
      },
    );
    if (result.failure != null) _downloadFailures[taskId] = result.failure!;
    if (result.cached != null) {
      _upsertCachedRecord(result.cached!);
      if (!background) {
        statusMessage = result.statusMessage ?? statusMessage;
        errorDetail = result.errorDetail;
      }
      if (!_isDisposed) notifyListeners();
      unawaited(_primeMetadataAndReloadCache(result.cached!));
      return;
    }
    if (!background) {
      statusMessage = result.statusMessage ?? statusMessage;
      errorDetail = result.errorDetail;
    }
    if (!_isDisposed) notifyListeners();
  }

  void cancelDownload(String taskId) {
    downloadUseCase.cancelDownload(taskId);
    notifyListeners();
  }

  void clearDownloadTask(String taskId) {
    downloadQueue.clearTask(taskId);
    notifyListeners();
  }

  bool isCandidateDownloading(MusicSearchCandidate candidate) {
    return downloadQueue.isCandidateDownloading(candidate);
  }

  bool isCandidateCached(MusicSearchCandidate candidate) {
    return _cachedRecordForCandidate(candidate) != null;
  }

  Future<void> playCandidate(MusicSearchCandidate candidate) async {
    final request = ++_playRequest;
    var record = _cachedRecordForCandidate(candidate);
    if (record == null) {
      await downloadCandidate(candidate);
      record = _cachedRecordForCandidate(candidate);
    } else {
      record = await _refreshCachedCandidateMetadata(candidate, record);
    }
    if (record == null || request != _playRequest) {
      return;
    }
    final track = trackFromCached(record);
    final index = cachedTracks.indexWhere((item) => item.id == track.id);
    await _playTrack(
      track,
      request: request,
      index: index == -1 ? null : index,
    );
    if (request != _playRequest) return;
    statusMessage = const MusicUiMessage(MusicUiMessageCode.playingCachedFile);
    notifyListeners();
  }

  Future<void> playTrack(Track track, {int? index, List<Track>? queueTracks}) =>
      _playTrack(
        track,
        request: ++_playRequest,
        index: index,
        queueTracks: queueTracks,
      );

  Future<void> _playTrack(
    Track track, {
    required int request,
    int? index,
    List<Track>? queueTracks,
  }) async {
    var prepared = track;
    if (track.playbackSource.isEmpty) {
      final file = await _prepareOnlineTrack(track);
      if (request != _playRequest) return;
      prepared = track.copyWith(filePath: file.path);
    }
    final selectedQueue =
        queueTracks ??
        (cachedTracks.any((item) => item.id == prepared.id)
            ? cachedTracks
            : <Track>[prepared]);
    final queue = [
      for (final item in selectedQueue)
        item.id == prepared.id ? prepared : item,
    ];
    final prior = _playLoadTail;
    final done = Completer<void>();
    _playLoadTail = done.future;
    await prior;
    try {
      if (request != _playRequest) return;
      final sameQueue =
          audioHandler.mediaItem.value?.id == prepared.id &&
          _activeQueueTracks.length == queue.length &&
          queue.asMap().entries.every(
            (entry) => _activeQueueTracks[entry.key].id == entry.value.id,
          );
      if (!sameQueue) {
        _nextPrefetch.cancel();
        _prefetchForCurrentId = null;
        _prefetchRejectedForCurrent.clear();
      }
      _activeQueueTracks = queue;
      final loaded = await playbackUseCase.playTrack(
        prepared,
        index: index,
        fallbackQueue: cachedTracks,
        queueTracks: queue,
        shouldPlay: () => request == _playRequest && !_isDisposed,
      );
      if (loaded && request == _playRequest) {
        await setPlaybackMode(playbackMode);
      }
    } finally {
      done.complete();
    }
  }

  Future<void> togglePlayPause() => playbackUseCase.togglePlayPause();

  Future<void> seek(Duration position) => playbackUseCase.seek(position);

  Future<void> seekToLyricLine(LyricLine line) => seek(line.time);

  Future<void> next() => playbackUseCase.next();

  Future<void> previous() => playbackUseCase.previous();

  Future<void> stop() async {
    _playRequest += 1;
    _nextPrefetch.cancel();
    _activeQueueTracks = const [];
    _prefetchForCurrentId = null;
    _prefetchRejectedForCurrent.clear();
    await _playLoadTail;
    await playbackUseCase.stop();
  }

  Future<File> _prepareOnlineTrack(Track track, {int? prefetchRequest}) async {
    void checkPrefetch() {
      if (prefetchRequest != null && prefetchRequest != _prefetchRequest) {
        throw const DownloadCancelledException();
      }
    }

    checkPrefetch();
    final saved = _onlineTrackForId(track.id);
    if (saved == null) {
      throw StateError('No validated online source for ${track.title}');
    }
    var cached = _cachedRecordForCandidate(saved.candidate);
    if (cached != null && await File(cached.filePath).exists()) {
      checkPrefetch();
      return File(cached.filePath);
    }
    checkPrefetch();
    final taskId = downloadQueue.taskIdForCandidate(saved.candidate);
    final inFlight = _downloadsInFlight[taskId];
    if (inFlight != null) {
      if (prefetchRequest == null && _prefetchTaskId == taskId) {
        _prefetchTaskId = null;
      }
      await inFlight;
    } else {
      if (prefetchRequest != null) _prefetchTaskId = taskId;
      try {
        await downloadCandidate(
          saved.candidate,
          background: prefetchRequest != null,
        );
      } finally {
        if (_prefetchTaskId == taskId) _prefetchTaskId = null;
      }
    }
    checkPrefetch();
    cached = _cachedRecordForCandidate(saved.candidate);
    if (cached == null || !await File(cached.filePath).exists()) {
      throw _downloadFailures[taskId] ??
          StateError('Audio is unavailable for ${track.title}');
    }
    return File(cached.filePath);
  }

  SavedOnlineTrack? _onlineTrackForId(String id) {
    for (final entry in [
      ..._playlistLibrary.favoriteEntries,
      for (final playlist in _playlistLibrary.playlists) ...playlist.entries,
    ]) {
      if (entry.trackId == id && entry.onlineTrack != null) {
        return entry.onlineTrack;
      }
    }
    return null;
  }

  void _maybePrefetchNext() {
    if (playbackMode == PlaybackMode.repeatOne) return;
    final currentId = audioHandler.mediaItem.value?.id;
    if (currentId == null || _prefetchForCurrentId == currentId) return;
    _prefetchRejectedForCurrent.clear();
    final index = audioHandler.nextQueueIndex;
    if (index == null || index < 0 || index >= _activeQueueTracks.length) {
      return;
    }
    final next = _activeQueueTracks[index];
    if (next.playbackSource.isNotEmpty) return;
    _prefetchForCurrentId = currentId;
    _nextPrefetch.activate(next.id);
  }

  String? _nextAfterDefinitivePrefetchFailure(String failedId) {
    _prefetchRejectedForCurrent.add(failedId);
    var cursor = failedId;
    for (var visited = 0; visited < _activeQueueTracks.length; visited += 1) {
      final index = audioHandler.followingQueueIndex(cursor);
      if (index == null || index < 0 || index >= _activeQueueTracks.length) {
        return null;
      }
      final track = _activeQueueTracks[index];
      if (track.id == audioHandler.mediaItem.value?.id) return null;
      cursor = track.id;
      if (_prefetchRejectedForCurrent.contains(track.id) ||
          track.playbackSource.isNotEmpty) {
        continue;
      }
      return track.id;
    }
    return null;
  }

  Future<void> deleteCachedTrack(Track track) async {
    await _handleDeletedTracksPlaybackImpact({track.id});
    _applyLibrarySnapshot(
      await libraryUseCase.deleteCachedTrack(track, current: _librarySnapshot),
    );
    notifyListeners();
  }

  Future<void> deleteCachedTracks(List<Track> tracks) async {
    final ids = {for (final track in tracks) track.id};
    if (ids.isEmpty) {
      return;
    }
    await _handleDeletedTracksPlaybackImpact(ids);
    _applyLibrarySnapshot(
      await libraryUseCase.deleteCachedTracks(
        tracks,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> repairLegacyCache() async {
    if (_legacyRepairRunning) {
      return;
    }
    _legacyRepairRunning = true;
    isRepairingLegacyCache = true;
    notifyListeners();
    try {
      final repairer =
          _legacyRepairerOverride ??
          LegacyCacheRepairer(resolver: _resolver, cacheStore: _cacheStore);
      final count = await repairer.repair(List<CachedTrack>.of(_cachedRecords));
      if (count > 0) {
        await loadCache(repairLegacy: false);
      }
    } finally {
      _legacyRepairRunning = false;
      isRepairingLegacyCache = false;
      notifyListeners();
    }
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    final changed = playbackMode != mode;
    playbackMode = mode;
    notifyListeners();
    await playbackUseCase.applyPlaybackMode(mode);
    if (changed) {
      _nextPrefetch.cancel();
      _prefetchForCurrentId = null;
      _prefetchRejectedForCurrent.clear();
      if (audioHandler.playbackState.value.playing) {
        _maybePrefetchNext();
      }
    }
    await _syncOhosControlState();
  }

  Future<void> cyclePlaybackMode() {
    final nextMode = switch (playbackMode) {
      PlaybackMode.sequential => PlaybackMode.loopAll,
      PlaybackMode.loopAll => PlaybackMode.repeatOne,
      PlaybackMode.repeatOne => PlaybackMode.shuffle,
      PlaybackMode.shuffle => PlaybackMode.sequential,
    };
    return setPlaybackMode(nextMode);
  }

  Future<void> loadMetadataForCurrentTrack() async {
    final track = currentTrack;
    if (track == null) {
      return;
    }
    await _loadMetadataForTrack(track);
  }

  List<Track> tracksForPlaylist(MusicPlaylist playlist) {
    return libraryController.tracksForIds(playlist.trackIds, [
      ...cachedTracks,
      ...onlineTracks,
    ]);
  }

  ScreenshotMatcher createScreenshotMatcher() =>
      ScreenshotMatcher(resolver: _resolver);

  Future<void> addCandidatesToPlaylist(
    MusicPlaylist playlist,
    List<MusicSearchCandidate> selected,
  ) async {
    _applyLibrarySnapshot(
      await libraryUseCase.addOnlineTracksToPlaylist(playlist, [
        for (final candidate in selected)
          SavedOnlineTrack(candidate: candidate),
      ], current: _librarySnapshot),
    );
    notifyListeners();
  }

  DateTime? favoriteAddedAt(Track track) {
    return _playlistLibrary.favoriteEntries
        .where((entry) => entry.trackId == track.id)
        .firstOrNull
        ?.addedAt;
  }

  DateTime? playlistTrackAddedAt(MusicPlaylist playlist, Track track) {
    return playlist.entries
        .where((entry) => entry.trackId == track.id)
        .firstOrNull
        ?.addedAt;
  }

  bool isFavorite(Track track) {
    return _playlistLibrary.favoriteTrackIds.contains(track.id);
  }

  bool isInPlaylist(MusicPlaylist playlist, Track track) {
    return playlist.trackIds.contains(track.id);
  }

  Future<void> toggleFavorite(Track track) async {
    _applyLibrarySnapshot(
      await libraryUseCase.toggleFavorite(track, current: _librarySnapshot),
    );
    notifyListeners();
    await _syncOhosControlState();
  }

  Future<MusicPlaylist?> createPlaylist(String name) async {
    final result = await libraryUseCase.createPlaylist(
      name,
      current: _librarySnapshot,
    );
    _applyLibrarySnapshot(result.snapshot);
    notifyListeners();
    return result.playlist;
  }

  Future<void> renamePlaylist(MusicPlaylist playlist, String name) async {
    _applyLibrarySnapshot(
      await libraryUseCase.renamePlaylist(
        playlist,
        name,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> deletePlaylist(MusicPlaylist playlist) async {
    _applyLibrarySnapshot(
      await libraryUseCase.deletePlaylist(playlist, current: _librarySnapshot),
    );
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(MusicPlaylist playlist, Track track) async {
    _applyLibrarySnapshot(
      await libraryUseCase.addTrackToPlaylist(
        playlist,
        track,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> addTracksToPlaylist(
    MusicPlaylist playlist,
    List<Track> tracks,
  ) async {
    _applyLibrarySnapshot(
      await libraryUseCase.addTracksToPlaylist(
        playlist,
        tracks,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(
    MusicPlaylist playlist,
    Track track,
  ) async {
    _applyLibrarySnapshot(
      await libraryUseCase.removeTrackFromPlaylist(
        playlist,
        track,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> removeTracksFromPlaylist(
    MusicPlaylist playlist,
    List<Track> tracks,
  ) async {
    _applyLibrarySnapshot(
      await libraryUseCase.removeTracksFromPlaylist(
        playlist,
        tracks,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> removeTracksFromFavorites(List<Track> tracks) async {
    _applyLibrarySnapshot(
      await libraryUseCase.removeTracksFromFavorites(
        tracks,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> reorderFavoriteTracks(List<Track> tracks) async {
    _applyLibrarySnapshot(
      await libraryUseCase.reorderFavoriteTracks(
        tracks,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> reorderPlaylistTracks(
    MusicPlaylist playlist,
    List<Track> tracks,
  ) async {
    _applyLibrarySnapshot(
      await libraryUseCase.reorderPlaylistTracks(
        playlist,
        tracks,
        current: _librarySnapshot,
      ),
    );
    notifyListeners();
  }

  Future<void> _saveSettings() {
    return settingsController.save(
      source: source,
      language: language,
      theme: themePreference,
      lanLibraryUrl: lanLibraryUrl,
    );
  }

  LibrarySnapshot get _librarySnapshot {
    return LibrarySnapshot(
      cachedRecords: _cachedRecords,
      cachedTracks: cachedTracks,
      onlineTracks: onlineTracks,
      playlistLibrary: _playlistLibrary,
      favoriteTracks: favoriteTracks,
      customPlaylists: customPlaylists,
    );
  }

  void _applyLibrarySnapshot(LibrarySnapshot snapshot) {
    _cachedRecords = snapshot.cachedRecords;
    _playlistLibrary = snapshot.playlistLibrary;
    cachedTracks = snapshot.cachedTracks;
    onlineTracks = snapshot.onlineTracks;
    favoriteTracks = snapshot.favoriteTracks;
    customPlaylists = snapshot.customPlaylists;
  }

  void _upsertCachedRecord(CachedTrack record) {
    final records = List<CachedTrack>.of(_cachedRecords);
    final index = records.indexWhere((item) => item.cacheId == record.cacheId);
    if (index == -1) {
      records.add(record);
    } else {
      records[index] = record;
    }
    _applyLibrarySnapshot(
      libraryUseCase.applyCachedRecords(records, _playlistLibrary),
    );
  }

  CachedTrack? _cachedRecordForCandidate(MusicSearchCandidate candidate) {
    for (final record in _cachedRecords) {
      final music = record.music;
      if (music.source != candidate.source ||
          music.platform != candidate.platform) {
        continue;
      }
      if (candidate.id.isNotEmpty && music.id == candidate.id) {
        return record;
      }
      if (candidate.id.isEmpty &&
          music.name == candidate.name &&
          music.artist == candidate.artist) {
        return record;
      }
    }
    return null;
  }

  Future<void> _handleDeletedTracksPlaybackImpact(
    Set<String> deletedIds,
  ) async {
    final currentItem = audioHandler.mediaItem.value;
    final currentId = currentItem?.id;
    if (currentId != null && deletedIds.contains(currentId)) {
      await stop();
      return;
    }
    final queuedIds = [for (final item in audioHandler.queue.value) item.id];
    if (!queuedIds.any(deletedIds.contains)) {
      return;
    }
    if (currentId == null) {
      await stop();
      return;
    }
    final byId = {
      for (final track in cachedTracks) track.id: track,
      for (final track in _activeQueueTracks) track.id: track,
    };
    final remainingQueue = [
      for (final id in queuedIds)
        if (!deletedIds.contains(id) && byId[id] != null) byId[id]!,
    ];
    final currentIndex = remainingQueue.indexWhere(
      (track) => track.id == currentId,
    );
    if (currentIndex == -1) {
      await stop();
      return;
    }
    final wasPlaying = audioHandler.playbackState.value.playing;
    final loaded = await playbackUseCase.playTrack(
      remainingQueue[currentIndex],
      index: currentIndex,
      fallbackQueue: remainingQueue,
      queueTracks: remainingQueue,
    );
    _activeQueueTracks = remainingQueue;
    if (loaded) {
      await playbackUseCase.applyPlaybackMode(playbackMode);
    }
    if (!wasPlaying) {
      await audioHandler.pause();
    }
  }

  void _handleMediaItemChanged(MediaItem? item) {
    if (item != null && audioHandler.playbackState.value.playing) {
      _maybePrefetchNext();
    }
    if (item == null) {
      _metadataRequest += 1;
      _metadataTrackId = null;
      currentMetadata = const TrackMetadata();
      metadataError = null;
      isLoadingMetadata = false;
      notifyListeners();
      unawaited(_syncOhosControlState());
      return;
    }
    if (_metadataTrackId == item.id) {
      return;
    }
    final track = [
      ...cachedTracks,
      ...onlineTracks,
    ].where((track) => track.id == item.id).firstOrNull;
    if (track == null) {
      _metadataRequest += 1;
      _metadataTrackId = null;
      currentMetadata = const TrackMetadata();
      metadataError = null;
      isLoadingMetadata = false;
      notifyListeners();
      unawaited(_syncOhosControlState());
      return;
    }
    unawaited(_loadMetadataForTrack(track));
    unawaited(_syncOhosControlState());
  }

  Future<void> _loadMetadataForTrack(Track track) async {
    _metadataTrackId = track.id;
    // 切歌时歌词/封面请求可能晚返回；request id 保证只写入当前歌曲的结果。
    final request = ++_metadataRequest;
    final cached = _cachedRecordForTrack(track);
    if (cached == null) {
      if (!_isActiveMetadataRequest(request, track)) {
        return;
      }
      currentMetadata = TrackMetadata(artworkUri: track.artworkUri);
      metadataError = null;
      isLoadingMetadata = false;
      notifyListeners();
      return;
    }
    currentMetadata = TrackMetadata(artworkUri: track.artworkUri);
    metadataError = null;
    isLoadingMetadata = true;
    notifyListeners();
    try {
      final metadata = await metadataUseCase.load(cached);
      if (!_isActiveMetadataRequest(request, track)) {
        return;
      }
      currentMetadata = metadata;
      final active = audioHandler.mediaItem.value;
      if (active?.id == track.id &&
          metadata.artworkUri != null &&
          active?.artUri != metadata.artworkUri) {
        await audioHandler.updateCurrentMediaItem(
          active!.copyWith(artUri: metadata.artworkUri),
        );
        await _syncOhosControlState();
      }
    } catch (exception) {
      if (_isActiveMetadataRequest(request, track)) {
        metadataError = friendlyError(exception);
      }
    } finally {
      if (_isActiveMetadataRequest(request, track)) {
        isLoadingMetadata = false;
        notifyListeners();
      }
    }
  }

  Future<void> _primeMetadataForCached(CachedTrack cached) async {
    try {
      await metadataUseCase.load(cached);
    } catch (_) {
      // 下载主流程不能因为封面/歌词兜底失败而失败；播放页仍会展示可读 metadataError。
    }
  }

  CachedTrack? _cachedRecordForTrack(Track track) {
    final direct = _cachedRecords
        .where((record) => record.cacheId == track.id)
        .firstOrNull;
    if (direct != null) return direct;
    final online = _onlineTrackForId(track.id);
    return online == null ? null : _cachedRecordForCandidate(online.candidate);
  }

  Future<void> _primeMetadataAndReloadCache(CachedTrack cached) async {
    await _primeMetadataForCached(cached);
    if (_isDisposed) {
      return;
    }
    await loadCache(repairLegacy: false);
  }

  Future<void> autoRecoverMetadataForCurrentTrack() async {
    final track = currentTrack;
    if (track == null || currentLyrics.isNotEmpty || isLoadingMetadata) {
      return;
    }
    if (!_autoMetadataRecoveryAttempted.add(track.id)) {
      return;
    }
    await recoverMetadataForCurrentTrack();
  }

  Future<void> recoverMetadataForCurrentTrack({
    bool bypassLyricsMiss = false,
  }) async {
    final track = currentTrack;
    if (track == null) {
      return;
    }
    final request = ++_metadataRequest;
    _metadataTrackId = track.id;
    metadataError = null;
    isLoadingMetadata = true;
    notifyListeners();
    try {
      final cached = _cachedRecordForTrack(track);
      if (cached == null) {
        return;
      }
      final refreshed = await _resolveAndUpdateCachedMetadata(cached);
      final metadata = bypassLyricsMiss
          ? await metadataUseCase.loadBypassingLyricsMiss(refreshed)
          : await metadataUseCase.load(refreshed);
      if (!_isActiveMetadataRequest(request, track)) {
        return;
      }
      currentMetadata = metadata;
      if (metadata.hasLyrics) {
        _autoMetadataRecoveryAttempted.remove(track.id);
      }
      final active = audioHandler.mediaItem.value;
      if (active?.id == track.id &&
          metadata.artworkUri != null &&
          active?.artUri != metadata.artworkUri) {
        await audioHandler.updateCurrentMediaItem(
          active!.copyWith(artUri: metadata.artworkUri),
        );
        await _syncOhosControlState();
      }
    } catch (exception) {
      if (_isActiveMetadataRequest(request, track)) {
        metadataError = friendlyError(exception);
      }
    } finally {
      if (_isActiveMetadataRequest(request, track)) {
        isLoadingMetadata = false;
        notifyListeners();
      }
    }
  }

  Future<CachedTrack> _refreshCachedCandidateMetadata(
    MusicSearchCandidate candidate,
    CachedTrack record,
  ) async {
    final hasCandidateCover = candidate.coverUrl.trim().isNotEmpty;
    final missingCover = record.music.coverUrl.trim().isEmpty;
    final missingLyrics =
        record.music.lyrics == null && record.lyricsPath.trim().isEmpty;
    if ((!missingCover || !hasCandidateCover) && !missingLyrics) {
      await _primeMetadataForCached(record);
      return record;
    }
    try {
      final resolved = await _resolver.resolve(candidate);
      final updated = await _cacheStore.updateCachedMusic(
        record,
        _mergeResolvedMetadata(record.music, resolved),
      );
      await _primeMetadataForCached(updated);
      await loadCache(repairLegacy: false);
      return _cachedRecords.firstWhere(
        (cached) => cached.cacheId == updated.cacheId,
        orElse: () => updated,
      );
    } catch (_) {
      await _primeMetadataForCached(record);
      return record;
    }
  }

  Future<CachedTrack> _resolveAndUpdateCachedMetadata(
    CachedTrack record,
  ) async {
    final resolved = await _resolver.resolve(_candidateFromCached(record));
    final updated = await _cacheStore.updateCachedMusic(
      record,
      _mergeResolvedMetadata(record.music, resolved),
    );
    await loadCache(repairLegacy: false);
    return _cachedRecords.firstWhere(
      (cached) => cached.cacheId == updated.cacheId,
      orElse: () => updated,
    );
  }

  MusicSearchCandidate _candidateFromCached(CachedTrack record) {
    final music = record.music;
    return MusicSearchCandidate(
      query: music.query.trim().isNotEmpty ? music.query : music.name,
      source: music.source,
      platform: music.platform,
      keyword: music.query.trim().isNotEmpty ? music.query : music.name,
      page: 1,
      id: music.id,
      name: music.name,
      artist: music.artist,
      album: music.album,
      duration: 0,
      link: '',
      coverUrl: music.coverUrl,
      qualities: [music.quality],
      score: 100,
      raw: const {},
    );
  }

  ResolvedMusic _mergeResolvedMetadata(
    ResolvedMusic current,
    ResolvedMusic resolved,
  ) {
    return ResolvedMusic(
      query: resolved.query.trim().isNotEmpty ? resolved.query : current.query,
      source: resolved.source,
      platform: resolved.platform.trim().isNotEmpty
          ? resolved.platform
          : current.platform,
      id: resolved.id.trim().isNotEmpty ? resolved.id : current.id,
      name: resolved.name.trim().isNotEmpty ? resolved.name : current.name,
      artist: resolved.artist.trim().isNotEmpty
          ? resolved.artist
          : current.artist,
      album: resolved.album.trim().isNotEmpty ? resolved.album : current.album,
      url: current.url.trim().isNotEmpty ? current.url : resolved.url,
      quality: resolved.quality.format.trim().isNotEmpty
          ? resolved.quality
          : current.quality,
      coverUrl: resolved.coverUrl.trim().isNotEmpty
          ? resolved.coverUrl
          : current.coverUrl,
      lyrics: resolved.lyrics ?? current.lyrics,
      panLink: current.panLink || resolved.panLink,
    );
  }

  bool _isActiveMetadataRequest(int request, Track track) {
    return request == _metadataRequest &&
        audioHandler.mediaItem.value?.id == track.id;
  }

  Future<void> _handleOhosLoopModeRequested(String loopMode) {
    final mode = switch (loopMode) {
      'single' => PlaybackMode.repeatOne,
      'list' => PlaybackMode.loopAll,
      'shuffle' => PlaybackMode.shuffle,
      'sequence' => PlaybackMode.sequential,
      _ => playbackMode,
    };
    return setPlaybackMode(mode);
  }

  Future<void> _handleOhosToggleFavoriteRequested(String mediaId) async {
    return _handleToggleFavoriteRequested(mediaId);
  }

  Future<void> _handleToggleFavoriteRequested(String mediaId) async {
    final track = currentTrack;
    if (track == null) {
      return;
    }
    if (mediaId.isNotEmpty && mediaId != track.id) {
      return;
    }
    await toggleFavorite(track);
  }

  Future<void> _syncOhosControlState() async {
    final track = currentTrack;
    await audioHandler.syncControlState(
      isFavorite: track != null && isFavorite(track),
    );
  }

  @override
  void dispose() {
    _playRequest += 1;
    _isDisposed = true;
    audioHandler.onOhosLoopModeRequested = null;
    audioHandler.onOhosToggleFavoriteRequested = null;
    audioHandler.onToggleFavoriteRequested = null;
    unawaited(_mediaItemSubscription.cancel());
    unawaited(_playbackSubscription.cancel());
    unawaited(_connectivitySubscription?.cancel());
    _nextPrefetch.cancel();
    if (_ownsLanLibraryGateway && _lanLibraryGateway is LanLibraryClient) {
      _lanLibraryGateway.close();
    }
    super.dispose();
  }
}
