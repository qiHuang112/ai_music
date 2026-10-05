// ignore_for_file: experimental_member_use

import '../data/download_history_store.dart';
import '../data/playlist_usage_store.dart';
import 'online_playlist_tasks.dart';
import 'dart:async';
import 'song_cache_progress.dart';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/lyrics_artwork.dart';
import '../data/legacy_cache_repairer.dart';
import '../data/lan_library_client.dart';
import '../data/lan_library_models.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
import '../data/song_search_cache.dart';
import '../data/playlist_auto_download_store.dart';
import '../data/saved_online_track.dart';
import '../data/playlist_song.dart';
import '../data/online_playlists.dart';
import '../domain/music_models.dart';
import '../playback/music_audio_handler.dart';
import '../playback/on_demand_audio_source.dart';
import '../playback/resumable_audio_source.dart';
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
import 'playback_cache_prefetch.dart';
import 'settings_controller.dart';
import 'screenshot_matcher.dart';
import 'screenshot_song_parser.dart';
import 'app_update_controller.dart';

class PlaylistDownloadSummary {
  const PlaylistDownloadSummary({
    this.downloaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.stoppedForWifi = false,
  });

  final int downloaded;
  final int skipped;
  final int failed;
  final bool stoppedForWifi;
}

class PlaylistDownloadProgress {
  const PlaylistDownloadProgress({
    required this.total,
    required this.processed,
    required this.failed,
  });

  final int total;
  final int processed;
  final int failed;

  double get fraction => total == 0 ? 1 : processed / total;
}

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
    PlaylistAutoDownloadStore? playlistAutoDownloadStore,
    PlaylistUsageStore? playlistUsageStore,
    DownloadHistoryStore? downloadHistoryStore,
    TrackMetadataRepository? metadataRepository,
    LegacyCacheRepairer? legacyRepairer,
    LanLibraryGateway? lanLibraryGateway,
    LanSyncUseCase? lanSyncUseCase,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    AppUpdateController? appUpdates,
    SongSearchCache? songSearchCache,
  }) : _resolver = resolver ?? RemoteMusicResolver(),
       _cacheStore = cacheStore ?? CachedTrackStore(),
       _playlistStore = playlistStore ?? PlaylistStore(),
       _downloadHistoryStore = downloadHistoryStore ?? DownloadHistoryStore(),
       _playlistUsageStore = playlistUsageStore ?? PlaylistUsageStore(),
       _settingsStore = settingsStore ?? MusicSettingsStore(),
       _playlistAutoDownloadStore =
           playlistAutoDownloadStore ?? PlaylistAutoDownloadStore(),
       _metadataRepository = metadataRepository ?? TrackMetadataRepository(),
       _legacyRepairerOverride = legacyRepairer {
    this.appUpdates = appUpdates ?? AppUpdateController();
    _songSearchCache = songSearchCache ?? SongSearchCache();
    downloadQueue.onHistoryChanged = () => unawaited(_saveDownloadHistory());
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
      prepareOnlineStream: _prepareOnlineStream,
    );
    _playbackPrefetch = PlaybackCachePrefetch(prepare: _prefetchPlaybackAudio);
    try {
      final connectivity = Connectivity();
      _connectivitySubscription =
          (connectivityChanges ?? connectivity.onConnectivityChanged).listen((
            results,
          ) {
            _connectivityEventSeen = true;
            _handleConnectivity(results);
          }, onError: (Object _) {});
      unawaited(
        (checkConnectivity ?? connectivity.checkConnectivity)()
            .then((results) {
              if (!_isDisposed && !_connectivityEventSeen) {
                _handleConnectivity(results);
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
    audioHandler.onTogglePlaybackModeRequested = cyclePlaybackMode;
    _mediaItemSubscription = audioHandler.mediaItem.listen(
      _handleMediaItemChanged,
    );
    _playbackSubscription = audioHandler.playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.error) {
        // A resolved URL alone is not proof that its audio can be played.
        _pendingSongSources.remove(audioHandler.mediaItem.value?.id);
      }
      if (state.playing) {
        if (state.processingState == AudioProcessingState.ready) {
          unawaited(_rememberPlayingSource());
        }
        _maybePrefetchNext();
        _maybePrefetchUpcomingLyrics();
      } else {
        unawaited(_playbackPrefetch.cancel());
      }
    });
  }

  final MusicAudioHandler audioHandler;
  late final AppUpdateController appUpdates;
  final MusicResolver _resolver;
  late final SongSearchCache _songSearchCache;
  final CachedTrackStore _cacheStore;
  final PlaylistStore _playlistStore;
  final MusicSettingsStore _settingsStore;
  final PlaylistAutoDownloadStore _playlistAutoDownloadStore;
  final TrackMetadataRepository _metadataRepository;
  final LegacyCacheRepairer? _legacyRepairerOverride;
  late final LanLibraryGateway _lanLibraryGateway;
  late final bool _ownsLanLibraryGateway;
  final LibraryController libraryController = const LibraryController();
  final DownloadQueueController downloadQueue = DownloadQueueController();
  // Byte progress does not change library contents or playlist layout.
  final ChangeNotifier downloadProgressChanges = ChangeNotifier();
  final SongCacheProgressController songCacheProgress =
      SongCacheProgressController();
  final Map<String, String> _cacheProgressTrackKeys = {};
  final playlistSourceProgress =
      ValueNotifier<
        Map<String, ({bool matching, int completed, int total, int failed})>
      >({});
  final Map<String, Future<void>> _playlistSourceMatching = {};
  ScreenshotMatcher? _playlistSongMatcher;
  ValueListenable<SongCacheProgress> cacheProgressFor(Track track) =>
      cacheProgressForId(track.id);

  ValueListenable<SongCacheProgress> cacheProgressForId(String trackId) {
    final pending =
        _pendingSongSources[trackId]?.candidate ??
        _adHocPlayCandidates[trackId];
    final key = pending == null
        ? _cacheProgressTrackKeys[trackId] ?? 'unresolved|$trackId'
        : downloadQueue.taskIdForCandidate(pending);
    return songCacheProgress.listenable(key);
  }

  Future<void> _refreshPartialProgress() async {
    final generation = _playbackCacheGeneration;
    final parts = await _cacheStore.partialProgress();
    if (!_isDisposed && generation == _playbackCacheGeneration) {
      songCacheProgress.replaceInactiveParts(parts);
    }
  }

  late final SettingsController settingsController;
  late final LibraryUseCase libraryUseCase;
  late final DownloadUseCase downloadUseCase;
  late final LanSyncUseCase lanSyncUseCase;
  late final PlaybackUseCase playbackUseCase;
  late final MetadataUseCase metadataUseCase;
  late final StreamSubscription<MediaItem?> _mediaItemSubscription;
  late final StreamSubscription<PlaybackState> _playbackSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  late final PlaybackCachePrefetch _playbackPrefetch;
  bool _prefetchOnline = true;
  final Map<String, Future<void>> _downloadsInFlight = {};
  final Map<String, Object> _downloadFailures = {};
  final Map<String, Future<PlaylistDownloadSummary>>
  _playlistDownloadsInFlight = {};
  final Map<String, PlaylistDownloadProgress> _playlistDownloadProgress = {};
  final Set<String> _visiblePlaylistProgressIds = {};
  final Set<String> _wifiPlaylistRunsPending = {};
  final Map<String, PlaylistAutoDownloadAttempt> _wifiPlaylistAttempts = {};
  final Map<String, String> _wifiPlaylistRunFailures = {};
  final Set<String> _wifiDownloadTaskIds = {};
  int _wifiPauseGeneration = 0;
  bool _isOnWifi = false;
  bool _connectivityKnown = false;
  bool _connectivityEventSeen = false;
  List<Track> _activeQueueTracks = const [];
  String? _activePlaylistId;
  final Set<String> _retiredQueueTrackIds = {};
  final Map<String, MusicSearchCandidate> _adHocPlayCandidates = {};
  final Map<
    String,
    ({MusicSearchCandidate candidate, SavedOnlineTrack? previous, int revision})
  >
  _pendingSongSources = {};
  final Map<String, Future<MusicSearchCandidate>> _songSearches = {};
  final Map<String, int> _songSourceRevisions = {};
  final Set<String> _rememberingSongSources = {};
  final Map<String, CachedTrack> _streamingMetadataTracks = {};
  final Set<String> _activeStreamPartPaths = {};
  final Map<String, int> _activeStreamPartCounts = {};
  int _playbackCacheGeneration = 0;
  bool _retiredQueueCleanupRunning = false;
  int _playRequest = 0;
  Future<void> _playLoadTail = Future<void>.value();
  String? _lyricsPrefetchQueueKey;
  int _lyricsPrefetchRequest = 0;
  @visibleForTesting
  String? get pendingPrefetchTrackId => _playbackPrefetch.activeTrackId;
  List<CachedTrack> _cachedRecords = const [];
  PlaylistLibrary _playlistLibrary = const PlaylistLibrary.empty();
  int _metadataRequest = 0;
  // 搜索框允许“非空换非空”快速输入；request id 用来丢弃晚返回的旧结果。
  int _searchRequest = 0;
  String? _metadataTrackId;
  final Set<String> _autoMetadataRecoveryAttempted = {};
  final Set<String> _timedLyricsUpgradeAttempted = {};
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
  Future<void> _playbackModeChange = Future<void>.value();
  AppLanguage language = AppLanguage.zh;
  AppThemePreference themePreference = AppThemePreference.dark;
  int screenshotSearchConcurrency = 3;
  int playlistDownloadConcurrency = 3;
  bool downloadPlaylistsOnWifi = true;
  MusicQualityLevel defaultDownloadQuality = MusicQualityLevel.high;
  bool get isOnWifi => _isOnWifi;
  bool get isConnectivityKnown => _connectivityKnown;
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

  bool get hasActiveDownloads =>
      activeDownloadTasks.isNotEmpty || _playlistDownloadsInFlight.isNotEmpty;

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
    return _trackForMediaId(item.id);
  }

  Track? _trackForMediaId(String id) => [
    ..._activeQueueTracks,
    ...cachedTracks,
    ...onlineTracks,
  ].where((track) => track.id == id).firstOrNull;

  final DownloadHistoryStore _downloadHistoryStore;
  Future<void>? _historyLoaded;
  Future<void> _loadDownloadHistory() =>
      _historyLoaded ??= _restoreDownloadHistory();
  Future<void> _restoreDownloadHistory() async {
    try {
      final saved = await _downloadHistoryStore.read();
      if (_isDisposed || saved.isEmpty) return;
      downloadQueue.restoreHistory([
        for (final item in saved) ?DownloadTask.fromJson(item),
      ]);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveDownloadHistory() async {
    try {
      await _loadDownloadHistory();
      await _downloadHistoryStore.write([
        for (final task in downloadQueue.recentTasks) task.toJson(),
      ]);
    } catch (_) {}
  }

  final PlaylistUsageStore _playlistUsageStore;
  List<MusicPlaylist> get frequentlyUsedPlaylists =>
      _playlistUsageStore.rank(customPlaylists);

  Future<void> recordPlaylistUsage(String id, {bool played = false}) async {
    if (!customPlaylists.any((p) => p.id == id)) return;
    try {
      await _playlistUsageStore.record(id, played: played);
      if (!_isDisposed) notifyListeners();
    } catch (_) {
      // Usage statistics must never block opening a playlist or playback.
    }
  }

  Future<void> _loadPlaylistUsage() async {
    try {
      await _playlistUsageStore.load();
      if (!_isDisposed) notifyListeners();
    } catch (_) {}
  }

  Future<void> initialize() async {
    unawaited(appUpdates.check());
    unawaited(_loadPlaylistUsage());
    unawaited(_loadDownloadHistory());
    final settings = await settingsController.load();
    source = settings.source;
    language = settings.language;
    themePreference = settings.theme;
    lanLibraryUrl = settings.lanLibraryUrl;
    screenshotSearchConcurrency = settings.screenshotSearchConcurrency;
    playlistDownloadConcurrency = settings.playlistDownloadConcurrency;
    downloadPlaylistsOnWifi = settings.downloadPlaylistsOnWifi;
    defaultDownloadQuality = settings.defaultDownloadQuality;
    await _cacheStore.cleanupTemporaryFiles();
    await loadCache();
    notifyListeners();
  }

  Future<void> loadCache({
    bool repairLegacy = true,
    bool showLoading = true,
  }) async {
    if (_isDisposed) {
      return;
    }
    if (showLoading) {
      isLoadingCache = true;
      notifyListeners();
    }
    try {
      _applyLibrarySnapshot(await libraryUseCase.loadCache());
      await _refreshPartialProgress();
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
        if (showLoading) isLoadingCache = false;
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

  Future<void> saveScreenshotSearchConcurrency(int value) async {
    screenshotSearchConcurrency = value.clamp(1, 10);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> savePlaylistDownloadConcurrency(int value) async {
    playlistDownloadConcurrency = value.clamp(1, 10);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> saveDownloadPlaylistsOnWifi(bool value) async {
    if (downloadPlaylistsOnWifi && !value) _wifiPauseGeneration += 1;
    downloadPlaylistsOnWifi = value;
    if (!value) {
      for (final taskId in _wifiDownloadTaskIds.toList()) {
        cancelDownload(taskId);
      }
    }
    notifyListeners();
    await _saveSettings();
  }

  Future<void> saveDefaultDownloadQuality(MusicQualityLevel value) async {
    defaultDownloadQuality = value;
    notifyListeners();
    await _saveSettings();
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    if (_isDisposed) return;
    final wasKnown = _connectivityKnown;
    _connectivityKnown = true;
    _prefetchOnline = results.any(
      (result) => result != ConnectivityResult.none,
    );
    _maybePrefetchNext();
    final onWifi = results.contains(ConnectivityResult.wifi);
    if (_isOnWifi == onWifi && wasKnown) return;
    _isOnWifi = onWifi;
    if (!onWifi) {
      _wifiPauseGeneration += 1;
      for (final taskId in _wifiDownloadTaskIds.toList()) {
        cancelDownload(taskId);
      }
    }
    notifyListeners();
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

  Future<void> search(String query, {bool refresh = false}) async {
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
      final searchSource = source;
      final result = await _songSearchCache.search(
        SongSearchCache.searchKey(trimmed, searchSource),
        () async {
          final progressive = _resolver is ProgressiveMusicResolver
              ? _resolver as ProgressiveMusicResolver
              : null;
          if (progressive == null) {
            return _resolver.search(trimmed, searchSource);
          }
          var latest = <MusicSearchCandidate>[];
          await for (final progress in progressive.searchProgressively(
            trimmed,
            searchSource,
          )) {
            latest = progress.candidates;
            if (request == _searchRequest && !_isDisposed) {
              candidates = latest;
              notifyListeners();
            }
            if (progress.isComplete && progress.error != null) {
              throw progress.error!;
            }
          }
          return latest;
        },
        refresh: refresh,
      );
      if (request != _searchRequest || _isDisposed) return;
      candidates = result;
      if (result.isEmpty) {
        errorMessage = const MusicUiMessage(
          MusicUiMessageCode.noOnlineMatchesFound,
        );
      }
    } catch (exception) {
      if (request != _searchRequest || _isDisposed) {
        return;
      }
      errorDetail = friendlyError(exception);
      errorMessage = null;
    } finally {
      if (request == _searchRequest && !_isDisposed) {
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
    if (!background) await _playbackPrefetch.cancel();
    final key = downloadQueue.taskIdForCandidate(candidate);
    final inFlight = _downloadsInFlight[key];
    if (inFlight != null) {
      if (!background) {
        _wifiDownloadTaskIds.remove(key);
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
      if (!_isDisposed) _maybePrefetchNext();
    }
  }

  Future<DownloadTask?> downloadCandidateAndWait(
    MusicSearchCandidate candidate, {
    bool? requireExactIdentity,
    bool background = false,
  }) async {
    final key = downloadQueue.taskIdForCandidate(candidate);
    final inFlight = _downloadsInFlight[key];
    if (inFlight != null) {
      if (!background) _wifiDownloadTaskIds.remove(key);
      await inFlight;
    } else {
      await downloadCandidate(
        candidate,
        requireExactIdentity: requireExactIdentity,
        background: background,
      );
    }
    return downloadQueue.taskById(key);
  }

  bool isPlaylistDownloading(MusicPlaylist playlist) =>
      _playlistDownloadsInFlight.containsKey(playlist.id);

  PlaylistDownloadProgress? playlistDownloadProgress(MusicPlaylist playlist) =>
      _visiblePlaylistProgressIds.contains(playlist.id)
      ? _playlistDownloadProgress[playlist.id]
      : null;

  Future<bool> claimFirstPlaylistOpening(MusicPlaylist playlist) async {
    final result = await libraryUseCase.claimFirstPlaylistOpening(
      playlist,
      current: _librarySnapshot,
    );
    if (result.first) {
      _applyLibrarySnapshot(result.snapshot);
      notifyListeners();
    }
    return result.first;
  }

  int cachedCountForPlaylist(MusicPlaylist playlist) {
    final current =
        customPlaylists.where((item) => item.id == playlist.id).firstOrNull ??
        playlist;
    return current.entries.where((entry) {
      final candidate = entry.onlineTrack?.candidate;
      return candidate == null
          ? cachedTracks.any((track) => track.id == entry.trackId)
          : isCandidateManuallyDownloaded(candidate);
    }).length;
  }

  Future<PlaylistDownloadSummary>? startWifiPlaylistDownloadOnce(
    MusicPlaylist playlist, {
    bool showProgress = false,
  }) {
    final current = customPlaylists
        .where((item) => item.id == playlist.id)
        .firstOrNull;
    if (current == null || current.entries.isEmpty) return null;
    if (_wifiPlaylistRunsPending.contains(playlist.id) ||
        isPlaylistDownloading(playlist) ||
        !downloadPlaylistsOnWifi ||
        !isOnWifi) {
      return null;
    }
    final revision = _playlistDownloadRevision(current);
    if (_wifiPlaylistRunFailures[playlist.id] == revision) return null;
    final previous = _wifiPlaylistAttempts[playlist.id];
    if (previous?.completed == true &&
        previous?.revision == revision &&
        DateTime.now().isBefore(
          previous!.startedAt.add(const Duration(hours: 24)),
        )) {
      return null;
    }
    _wifiPlaylistRunsPending.add(playlist.id);
    return _runWifiPlaylistDownload(current, showProgress: showProgress);
  }

  Future<PlaylistDownloadSummary> _runWifiPlaylistDownload(
    MusicPlaylist playlist, {
    required bool showProgress,
  }) async {
    var ranBatch = false;
    String? attemptedRevision;
    try {
      final previous = await _playlistAutoDownloadStore.get(playlist.id);
      final current = customPlaylists
          .where((item) => item.id == playlist.id)
          .firstOrNull;
      if (current == null || current.entries.isEmpty) {
        return const PlaylistDownloadSummary();
      }
      final revision = _playlistDownloadRevision(current);
      attemptedRevision = revision;
      final now = DateTime.now();
      if (previous?.completed == true &&
          previous?.revision == revision &&
          now.isBefore(previous!.startedAt.add(const Duration(hours: 24)))) {
        _wifiPlaylistAttempts[playlist.id] = previous;
        return const PlaylistDownloadSummary();
      }
      if (!downloadPlaylistsOnWifi || !isOnWifi) {
        return const PlaylistDownloadSummary(stoppedForWifi: true);
      }
      final attempt = PlaylistAutoDownloadAttempt(
        revision: revision,
        startedAt: now,
        completed: false,
      );
      await _playlistAutoDownloadStore.record(playlist.id, attempt);
      _wifiPlaylistAttempts[playlist.id] = attempt;
      ranBatch = true;
      final latest = customPlaylists
          .where((item) => item.id == playlist.id)
          .firstOrNull;
      if (latest == null || _playlistDownloadRevision(latest) != revision) {
        await _playlistAutoDownloadStore.clearIfCurrent(playlist.id, attempt);
        _wifiPlaylistAttempts.remove(playlist.id);
        return const PlaylistDownloadSummary(stoppedForWifi: true);
      }
      if (showProgress) _visiblePlaylistProgressIds.add(playlist.id);
      final result = await downloadPlaylist(
        current,
        wifiOnly: true,
        playlistSnapshot: current,
      );
      if (result.stoppedForWifi) {
        await _playlistAutoDownloadStore.clearIfCurrent(playlist.id, attempt);
        if (identical(_wifiPlaylistAttempts[playlist.id], attempt)) {
          _wifiPlaylistAttempts.remove(playlist.id);
        }
      } else {
        final completed = PlaylistAutoDownloadAttempt(
          revision: revision,
          startedAt: now,
        );
        await _playlistAutoDownloadStore.record(playlist.id, completed);
        _wifiPlaylistAttempts[playlist.id] = completed;
      }
      return result;
    } on Object catch (error) {
      _wifiPlaylistRunFailures[playlist.id] =
          attemptedRevision ?? _playlistDownloadRevision(playlist);
      if (!_isDisposed) {
        errorDetail = friendlyError(error);
        notifyListeners();
      }
      return const PlaylistDownloadSummary(failed: 1);
    } finally {
      _wifiPlaylistRunsPending.remove(playlist.id);
      // If the playlist changed during the batch, let the open detail page
      // check its new revision after the old batch settles.
      if (ranBatch && !_isDisposed) notifyListeners();
    }
  }

  String _playlistDownloadRevision(MusicPlaylist playlist) {
    final members = jsonEncode([
      for (final entry in playlist.entries) entry.trackId,
    ]);
    return '${playlist.updatedAt.toUtc().toIso8601String()}:${sha256.convert(utf8.encode(members))}';
  }

  Future<PlaylistDownloadSummary> downloadPlaylist(
    MusicPlaylist playlist, {
    bool wifiOnly = false,
    MusicPlaylist? playlistSnapshot,
  }) async {
    final running = _playlistDownloadsInFlight[playlist.id];
    if (running != null) {
      if (!wifiOnly && _visiblePlaylistProgressIds.add(playlist.id)) {
        notifyListeners();
      }
      return running;
    }
    if (!wifiOnly) _visiblePlaylistProgressIds.add(playlist.id);
    final work = Future<PlaylistDownloadSummary>.microtask(
      () => _downloadPlaylistNow(
        playlist,
        wifiOnly: wifiOnly,
        playlistSnapshot: playlistSnapshot,
      ),
    );
    _playlistDownloadsInFlight[playlist.id] = work;
    notifyListeners();
    try {
      return await work;
    } finally {
      _playlistDownloadsInFlight.remove(playlist.id);
      _playlistDownloadProgress.remove(playlist.id);
      _visiblePlaylistProgressIds.remove(playlist.id);
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<PlaylistDownloadSummary> _downloadPlaylistNow(
    MusicPlaylist playlist, {
    required bool wifiOnly,
    MusicPlaylist? playlistSnapshot,
  }) async {
    final current = customPlaylists
        .where((item) => item.id == playlist.id)
        .firstOrNull;
    if (current == null) return const PlaylistDownloadSummary();
    var downloaded = 0;
    var skipped = 0;
    var failed = 0;
    var processed = 0;
    var nextEntry = 0;
    // Auto attempts are recorded against this exact snapshot. New members
    // added while it runs belong to the next revision's batch.
    final entries = playlistSnapshot?.entries ?? current.entries;
    final wifiPauseGenerationAtStart = _wifiPauseGeneration;

    bool autoPaused() =>
        wifiOnly &&
        (_isDisposed ||
            !customPlaylists.any((item) => item.id == playlist.id) ||
            !_isOnWifi ||
            !downloadPlaylistsOnWifi ||
            _wifiPauseGeneration != wifiPauseGenerationAtStart);

    void reportProgress() {
      _playlistDownloadProgress[playlist.id] = PlaylistDownloadProgress(
        total: entries.length,
        processed: processed,
        failed: failed,
      );
      if (!_isDisposed && _visiblePlaylistProgressIds.contains(playlist.id)) {
        notifyListeners();
      }
    }

    reportProgress();

    Future<void> downloadNext() async {
      while (nextEntry < entries.length) {
        if (_isDisposed ||
            !customPlaylists.any((item) => item.id == playlist.id) ||
            autoPaused()) {
          return;
        }
        final entry = entries[nextEntry++];
        MusicSearchCandidate? candidate = entry.onlineTrack?.candidate;
        if (candidate == null && entry.song != null) {
          try {
            candidate = await _ensureSongCandidate(
              Track(
                id: entry.trackId,
                title: entry.song!.title,
                artist: entry.song!.artist,
                album: '',
              ),
            );
          } catch (_) {
            failed++;
            processed++;
            reportProgress();
            continue;
          }
        }
        if (candidate == null || isCandidateManuallyDownloaded(candidate)) {
          if (candidate != null) await _rememberSongSource(entry.trackId);
          skipped += 1;
          processed += 1;
          reportProgress();
          continue;
        }
        final taskId = downloadQueue.taskIdForCandidate(candidate);
        final ownedWifiTask =
            wifiOnly && !_downloadsInFlight.containsKey(taskId);
        if (ownedWifiTask) _wifiDownloadTaskIds.add(taskId);
        var finished = false;
        try {
          final task = await downloadCandidateAndWait(
            candidate,
            background: true,
          );
          if (task?.status == DownloadTaskStatus.completed ||
              isCandidateCached(candidate)) {
            downloaded += 1;
            finished = true;
            await _rememberSongSource(entry.trackId);
          } else if (!autoPaused()) {
            failed += 1;
            finished = true;
          }
        } catch (_) {
          if (!autoPaused()) {
            failed += 1;
            finished = true;
          }
        } finally {
          if (ownedWifiTask) _wifiDownloadTaskIds.remove(taskId);
        }
        if (finished) {
          processed += 1;
          reportProgress();
        }
      }
    }

    await Future.wait([
      for (
        var i = 0;
        i < entries.length && i < playlistDownloadConcurrency;
        i += 1
      )
        downloadNext(),
    ]);
    return PlaylistDownloadSummary(
      downloaded: downloaded,
      skipped: skipped,
      failed: failed,
      stoppedForWifi: autoPaused(),
    );
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
      quality: defaultDownloadQuality,
      requireExactIdentity: requireExactIdentity ?? false,
      onStatus: (message) {
        if (!background) {
          statusMessage = message;
        }
      },
      onChanged: () {
        if (!_isDisposed) {
          _updateSongDownloadProgress(taskId);
          notifyListeners();
        }
      },
      onProgressChanged: () {
        if (!_isDisposed) {
          _updateSongDownloadProgress(taskId);
          downloadProgressChanges.notifyListeners();
        }
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
      unawaited(_primeMetadataForCached(result.cached!));
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
    _updateSongDownloadProgress(taskId);
    notifyListeners();
  }

  void _updateSongDownloadProgress(String key) {
    final task = downloadQueue.taskById(key);
    songCacheProgress.download(
      key,
      active: task?.canCancel == true,
      bytes: task?.bytes ?? 0,
      total: task?.totalBytes,
    );
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

  bool isCandidateManuallyDownloaded(MusicSearchCandidate candidate) =>
      _matchingCachedRecords(candidate).any((record) => !record.playbackCache);

  Future<void> playCandidate(MusicSearchCandidate candidate) async {
    final request = ++_playRequest;
    _activePlaylistId = null;
    _retiredQueueTrackIds.clear();
    var record = _cachedRecordForCandidate(candidate);
    if (record != null) {
      record = await _refreshCachedCandidateMetadata(candidate, record);
    }
    if (request != _playRequest) return;
    final saved = SavedOnlineTrack(candidate: candidate);
    _adHocPlayCandidates[saved.trackId] = candidate;
    final track = record == null
        ? Track(
            id: saved.trackId,
            title: candidate.name,
            artist: candidate.artist,
            album: candidate.album,
            artworkUri: Uri.tryParse(candidate.coverUrl),
          )
        : trackFromCached(record);
    final index = cachedTracks.indexWhere((item) => item.id == track.id);
    await _playTrack(
      track,
      request: request,
      index: index == -1 ? null : index,
    );
    if (request != _playRequest) return;
    statusMessage = MusicUiMessage(
      record == null
          ? MusicUiMessageCode.playingOnlineStream
          : MusicUiMessageCode.playingCachedFile,
    );
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    int? index,
    List<Track>? queueTracks,
    String? playlistId,
  }) => _playTrack(
    track,
    request: ++_playRequest,
    playlistId: playlistId,
    index: index,
    queueTracks: queueTracks,
  );

  Future<void> _playTrack(
    Track track, {
    required int request,
    String? playlistId,
    int? index,
    List<Track>? queueTracks,
    bool forceReload = false,
  }) async {
    await _playbackPrefetch.cancel();
    if (request != _playRequest || _isDisposed) return;
    _activePlaylistId = null;
    _retiredQueueTrackIds.clear();
    _streamingMetadataTracks.removeWhere((id, _) => id != track.id);
    var prepared = track;
    StreamAudioSource? preparedSource;
    if (track.playbackSource.isEmpty) {
      final candidate = _candidateForOnlineTrack(track.id);
      final cached = candidate == null
          ? null
          : _cachedRecordForCandidate(candidate);
      final file = cached == null ? null : File(cached.filePath);
      if (file != null && await file.exists()) {
        prepared = track.copyWith(filePath: file.path);
      } else {
        preparedSource = await _prepareOnlineStream(track);
      }
      if (request != _playRequest) return;
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
    var catchUpPlaylist = false;
    try {
      if (request != _playRequest) return;
      final sameQueue =
          audioHandler.mediaItem.value?.id == prepared.id &&
          _activeQueueTracks.length == queue.length &&
          queue.asMap().entries.every(
            (entry) => _activeQueueTracks[entry.key].id == entry.value.id,
          );
      if (!sameQueue) {
        unawaited(_playbackPrefetch.cancel());
        _lyricsPrefetchQueueKey = null;
        _lyricsPrefetchRequest += 1;
      }
      _activeQueueTracks = queue;
      final loaded = await playbackUseCase.playTrack(
        prepared,
        index: index,
        fallbackQueue: cachedTracks,
        queueTracks: queue,
        selectedSource: preparedSource,
        shouldPlay: () => request == _playRequest && !_isDisposed,
        forceReload: forceReload,
      );
      if (request == _playRequest) {
        _activePlaylistId = playlistId;
        catchUpPlaylist = playlistId != null;
      }
      if (loaded && request == _playRequest) {
        if (playlistId != null) {
          unawaited(recordPlaylistUsage(playlistId, played: true));
        }
        await setPlaybackMode(playbackMode);
      }
      _maybePrefetchNext();
    } finally {
      done.complete();
    }
    if (catchUpPlaylist) {
      final current = customPlaylists
          .where((item) => item.id == playlistId)
          .firstOrNull;
      if (current != null) await _appendSyncedPlaylistTracksToQueue(current);
    }
  }

  Future<void> togglePlayPause() => playbackUseCase.togglePlayPause();

  Future<void> seek(Duration position) => playbackUseCase.seek(position);

  Future<void> seekToLyricLine(LyricLine line) => seek(line.time);

  Future<void> next() => playbackUseCase.next();

  Future<void> previous() => playbackUseCase.previous();

  Future<void> stop() async {
    _playRequest += 1;
    _streamingMetadataTracks.clear();
    _activePlaylistId = null;
    _retiredQueueTrackIds.clear();
    await _playbackPrefetch.cancel();
    _activeQueueTracks = const [];
    _lyricsPrefetchQueueKey = null;
    _lyricsPrefetchRequest += 1;
    await _playLoadTail;
    await playbackUseCase.stop();
  }

  Future<File> _prepareOnlineTrack(Track track) async {
    final source = await _prepareOnlineStream(track);
    final response = await source.request();
    await response.stream.drain<void>();
    if (source is ResumableAudioSource) await source.waitForCache();
    final candidate = _candidateForOnlineTrack(track.id);
    final cached = candidate == null
        ? null
        : _cachedRecordForCandidate(candidate);
    if (cached == null || !await File(cached.filePath).exists()) {
      throw StateError('Audio is unavailable for ${track.title}');
    }
    return File(cached.filePath);
  }

  MusicSearchCandidate? _candidateForOnlineTrack(String id) =>
      _pendingSongSources[id]?.candidate ??
      _onlineTrackForId(id)?.candidate ??
      _adHocPlayCandidates[id];

  PlaylistTrackEntry? _songEntry(String id) => [
    for (final playlist in _playlistLibrary.playlists) ...playlist.entries,
    ..._playlistLibrary.favoriteEntries,
  ].where((entry) => entry.trackId == id).firstOrNull;

  bool canSwitchSongSource(Track track) => _songEntry(track.id) != null;

  MusicSearchCandidate? selectedSongSource(Track track) {
    final selected = _candidateForOnlineTrack(track.id);
    if (selected != null) return selected;
    final record = _cachedRecords
        .where((r) => r.cacheId == track.id)
        .firstOrNull;
    return record != null &&
            (record.music.source == MusicDataSource.buguyy ||
                record.music.source == MusicDataSource.flac)
        ? _candidateFromCached(record)
        : null;
  }

  String songSourceLabel(Track track, {bool isZh = true}) {
    final candidate = _candidateForOnlineTrack(track.id);
    final cached = _cachedRecordForTrack(track);
    final resolved = _streamingMetadataTracks[track.id]?.music;
    final actual =
        resolved?.source ?? candidate?.source ?? cached?.music.source;
    final label = switch (actual) {
      MusicDataSource.buguyy => isZh ? '布谷YY' : 'BuguYY',
      MusicDataSource.flac => 'FLAC',
      MusicDataSource.lan => isZh ? '局域网' : 'LAN',
      _ =>
        track.playbackSource.isNotEmpty
            ? (isZh ? '本地' : 'Local')
            : (isZh ? '待匹配' : 'Pending'),
    };
    final platform =
        resolved?.platform ??
        candidate?.platform ??
        cached?.music.platform ??
        '';
    return actual == MusicDataSource.flac && platform.isNotEmpty
        ? '$label · $platform'
        : label;
  }

  Future<List<MusicSearchCandidate>> searchSongSources(
    Track track, {
    String? query,
    MusicDataSource? searchSource,
    bool refresh = false,
  }) {
    final text =
        (query ??
                _songEntry(track.id)?.song?.query ??
                '${track.title} ${track.artist}')
            .trim();
    final selected = searchSource ?? MusicDataSource.auto;
    return _songSearchCache.search(
      SongSearchCache.searchKey(text, selected),
      () => _resolver.search(text, selected),
      refresh: refresh,
    );
  }

  Future<MusicSearchCandidate> _ensureSongCandidate(
    Track track, {
    bool refresh = false,
  }) async {
    final existing = _candidateForOnlineTrack(track.id);
    if (!refresh && existing != null) return existing;
    if (_songEntry(track.id)?.song == null) {
      throw StateError('No online source for ${track.title}');
    }
    final inFlight = _songSearches[track.id];
    if (inFlight != null) return inFlight;
    final revision = _songSourceRevisions[track.id] ?? 0;
    final previous = _onlineTrackForId(track.id);
    final rejectedId = existing == null
        ? null
        : SavedOnlineTrack(candidate: existing).trackId;
    final future = () async {
      final draft = ScreenshotSongDraft(
        imageId: 'playlist-song',
        row: 1,
        title: _songEntry(track.id)?.song?.title ?? track.title,
        artist: _songEntry(track.id)?.song?.artist ?? track.artist,
        version: '',
        rawText: '${track.title} ${track.artist}',
      );
      if (refresh) _playlistSongMatcher = createOnlinePlaylistMatcher();
      final matcher = _playlistSongMatcher ??= createOnlinePlaylistMatcher();
      final matched = await _songSearchCache.search(
        'match|${jsonEncode([draft.title, draft.artist, draft.version])}',
        () async => (await matcher.match(
          draft,
          failOnSourceErrorWhenEmpty: true,
        )).candidates,
        refresh: refresh,
      );
      final match = matcher.rankCached(draft, matched);
      final results = match.candidates;
      if (results.isEmpty) {
        throw StateError('没有找到「${track.title}」的可播放来源，请切换来源重试');
      }
      if (_isDisposed ||
          _songEntry(track.id)?.song == null ||
          (_songSourceRevisions[track.id] ?? 0) != revision) {
        throw const DownloadCancelledException();
      }
      final candidate = refresh
          ? results
                    .where(
                      (c) =>
                          SavedOnlineTrack(candidate: c).trackId != rejectedId,
                    )
                    .firstOrNull ??
                results.first
          : match.recommended ?? results.first;
      _pendingSongSources[track.id] = (
        candidate: candidate,
        previous: previous,
        revision: revision,
      );
      if (!_isDisposed) notifyListeners();
      return candidate;
    }();
    _songSearches[track.id] = future;
    try {
      return await future;
    } finally {
      if (identical(_songSearches[track.id], future)) {
        _songSearches.remove(track.id);
      }
    }
  }

  Future<void> _rememberPlayingSource() async {
    final id = audioHandler.mediaItem.value?.id;
    if (id != null) await _rememberSongSource(id);
  }

  Future<void> _rememberSongSource(String id) async {
    final pending = _pendingSongSources[id];
    final entry = _songEntry(id);
    if (pending == null ||
        entry == null ||
        (_songSourceRevisions[id] ?? 0) != pending.revision ||
        !_rememberingSongSources.add(id)) {
      return;
    }
    final song = entry.song;
    final track = Track(
      id: id,
      title: song?.title ?? pending.candidate.name,
      artist: song?.artist ?? pending.candidate.artist,
      album: '',
    );
    try {
      final result = await libraryUseCase.saveSongSource(
        track,
        SavedOnlineTrack(candidate: pending.candidate),
        current: _librarySnapshot,
        manual: false,
        expectedSource: pending.previous,
      );
      if (!_isDisposed) {
        if (_pendingSongSources[id] == pending) _pendingSongSources.remove(id);
        _applyLibrarySnapshot(result);
        notifyListeners();
      }
    } catch (_) {
      // Keep the pending source for the next successful-playback notification.
    } finally {
      _rememberingSongSources.remove(id);
    }
  }

  Future<void> chooseSongSource(
    Track track,
    MusicSearchCandidate candidate,
  ) async {
    await _playbackPrefetch.cancel();
    _streamingMetadataTracks.remove(track.id);
    final revision = (_songSourceRevisions[track.id] ?? 0) + 1;
    _songSourceRevisions[track.id] = revision;
    _pendingSongSources.remove(track.id);
    _songSearches.remove(track.id);
    final snapshot = await libraryUseCase.saveSongSource(
      track,
      SavedOnlineTrack(candidate: candidate),
      current: _librarySnapshot,
      manual: true,
    );
    _applyLibrarySnapshot(snapshot);
    _metadataTrackId = null;
    _autoMetadataRecoveryAttempted.remove(track.id);
    _timedLyricsUpgradeAttempted.remove(track.id);
    notifyListeners();
    final updated = onlineTracks.where((t) => t.id == track.id).firstOrNull;

    if (updated == null) {
      _maybePrefetchNext();
      return;
    }
    // Deferred items consult the current source on preparation. Replace already
    // prepared queue items as well so changing a pending song takes effect.
    final index = _activeQueueTracks.indexWhere((t) => t.id == track.id);
    if (index < 0) {
      _maybePrefetchNext();
      return;
    }
    final playlistId = _activePlaylistId;
    if (audioHandler.mediaItem.value?.id == track.id) {
      await _playTrack(
        updated,
        request: ++_playRequest,
        playlistId: playlistId,
        index: index,
        queueTracks: [
          for (final t in _activeQueueTracks) t.id == track.id ? updated : t,
        ],
        forceReload: true,
      );
      await loadMetadataForCurrentTrack();
    } else {
      final prior = _playLoadTail;
      final done = Completer<void>();
      _playLoadTail = done.future;
      await prior;
      try {
        if ((_songSourceRevisions[track.id] ?? 0) != revision ||
            _activePlaylistId != playlistId) {
          return;
        }
        final currentIndex = _activeQueueTracks.indexWhere(
          (t) => t.id == track.id,
        );
        if (currentIndex >= 0 && audioHandler.mediaItem.value?.id != track.id) {
          await playbackUseCase.replaceTrackAt(
            _activeQueueTracks,
            currentIndex,
            updated,
          );
          _activeQueueTracks = [..._activeQueueTracks]
            ..[currentIndex] = updated;
        }
      } finally {
        done.complete();
      }
    }
    _maybePrefetchNext();
  }

  Future<StreamAudioSource> _prepareOnlineStream(
    Track track, {
    CachePrefetchToken? prefetchToken,
  }) async {
    if (prefetchToken == null) await _playbackPrefetch.cancel();
    prefetchToken?.check();
    Future<T> prepareWait<T>(Future<T> work) =>
        prefetchToken == null ? work : prefetchToken.wait(work);
    var candidate = await prepareWait(_ensureSongCandidate(track));
    prefetchToken?.check();
    final cached = _cachedRecordForCandidate(candidate);
    if (cached != null && await File(cached.filePath).exists()) {
      return OnDemandAudioSource(
        tag: mediaItemFromTrack(track),
        prepare: () async => File(cached.filePath),
      );
    }
    Future<ResolvedMusic> resolve(MusicSearchCandidate choice) async =>
        _resolver is QualitySelectableMusicResolver
        ? await (_resolver as QualitySelectableMusicResolver).resolveAtQuality(
            choice,
            MusicQualityLevel.low,
          )
        : await _resolver.resolve(choice);
    ResolvedMusic resolved;
    try {
      resolved = await prepareWait(resolve(candidate));
    } catch (_) {
      prefetchToken?.check();
      if (_songEntry(track.id)?.song == null ||
          _songEntry(track.id)?.manualSource == true) {
        rethrow;
      }
      candidate = await prepareWait(_ensureSongCandidate(track, refresh: true));
      resolved = await prepareWait(resolve(candidate));
    }
    prefetchToken?.check();
    if (_isDisposed) throw const CachePrefetchCancelled();
    if (resolved.panLink) {
      throw StateError('This source cannot stream audio');
    }
    final target = await _cacheStore.playbackTargetFor(resolved);
    prefetchToken?.check();
    _streamingMetadataTracks[track.id] = CachedTrack(
      cacheId: cacheIdForResolved(resolved),
      music: resolved,
      filePath: target.path,
      sizeBytes: 0,
      fromCache: false,
      playbackCache: true,
    );
    if (await target.exists()) {
      prefetchToken?.check();
      final recovered = await _cacheStore.finishPlaybackCache(resolved, target);
      _upsertCachedRecord(recovered);
      _streamingMetadataTracks.remove(track.id);
      return OnDemandAudioSource(
        tag: mediaItemFromTrack(track),
        prepare: () async => target,
      );
    }
    final part = File('${target.path}.part');
    final generation = _playbackCacheGeneration;
    final progressKey = downloadQueue.taskIdForCandidate(candidate);
    return ResumableAudioSource(
      tag: mediaItemFromTrack(track),
      url: Uri.parse(resolved.url),
      partFile: part,
      completeFile: target,
      onStarted: () => _retainStreamPart(part.path),
      onLength: (total) async {
        if (generation == _playbackCacheGeneration && !_isDisposed) {
          await _cacheStore.savePartialProgress(part, progressKey, total);
        }
      },
      onProgress: (progress) {
        if (generation == _playbackCacheGeneration && !_isDisposed) {
          songCacheProgress.streaming(
            progressKey,
            bytes: progress.bytes,
            total: progress.totalBytes,
            active: true,
          );
        }
      },
      onComplete: (file) async {
        _releaseStreamPart(part.path);
        await _cacheStore.removePartialProgress(part);
        if (generation != _playbackCacheGeneration) {
          if (await file.exists()) await file.delete();
          return;
        }
        try {
          final record = await _cacheStore.finishPlaybackCache(resolved, file);
          if (!_isDisposed) {
            songCacheProgress.removePartial(progressKey);
            _upsertCachedRecord(record);
            _streamingMetadataTracks.remove(track.id);
            notifyListeners();
          }
        } catch (_) {
          if (await file.exists()) await file.delete();
          if (!_isDisposed) songCacheProgress.removePartial(progressKey);
        }
        await _cacheStore.trimPlaybackParts(
          protectedPaths: _activeStreamPartPaths,
        );
      },
      onStopped: () {
        _releaseStreamPart(part.path);
        if (!_isDisposed &&
            generation == _playbackCacheGeneration &&
            !_activeStreamPartPaths.contains(part.path)) {
          songCacheProgress.stopStreaming(progressKey);
        }
        unawaited(_trimPartsAndRefreshProgress());
      },
    );
  }

  Future<void> _trimPartsAndRefreshProgress() async {
    await _cacheStore.trimPlaybackParts(protectedPaths: _activeStreamPartPaths);
    await _refreshPartialProgress();
  }

  Future<int> playbackCacheBytes() => _cacheStore.playbackCacheBytes();

  int get manuallyDownloadedSongCount {
    final ids = <String>{};
    for (final record in _cachedRecords) {
      if (record.playbackCache) continue;
      final music = record.music;
      ids.add(
        '${music.source.storageValue}:${music.platform}:${music.id.isEmpty ? record.cacheId : music.id}',
      );
    }
    return ids.length;
  }

  Future<void> clearPlaybackCache() async {
    _playbackCacheGeneration++;
    await stop();
    _applyLibrarySnapshot(
      await libraryUseCase.preservePlaybackReferences(
        current: _librarySnapshot,
      ),
    );
    await _cacheStore.clearPlaybackCache();
    songCacheProgress.clearParts();
    await loadCache(repairLegacy: false, showLoading: false);
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
    final state = audioHandler.playbackState.value;
    if (_isDisposed ||
        !_prefetchOnline ||
        !state.playing ||
        state.processingState != AudioProcessingState.ready ||
        playbackMode == PlaybackMode.repeatOne ||
        _activeQueueTracks.length < 2) {
      unawaited(_playbackPrefetch.cancel());
      return;
    }
    final currentId = audioHandler.mediaItem.value?.id;
    if (currentId == null) return;
    final playlist = customPlaylists
        .where((p) => p.id == _activePlaylistId)
        .firstOrNull;
    if (_activePlaylistId != null && playlist == null) {
      unawaited(_playbackPrefetch.cancel());
      return;
    }
    final members = playlist?.trackIds.toSet();
    final seen = {currentId};
    final upcoming = <String>[];
    var cursor = currentId;
    for (var i = 0; i < 5; i++) {
      final index = audioHandler.followingQueueIndex(cursor);
      if (index == null || index < 0 || index >= _activeQueueTracks.length) {
        break;
      }
      final track = _activeQueueTracks[index];
      if (!seen.add(track.id)) break;
      if (members == null || members.contains(track.id)) upcoming.add(track.id);
      cursor = track.id;
    }
    _playbackPrefetch.activate(upcoming);
  }

  Future<void> _prefetchPlaybackAudio(
    String id,
    CachePrefetchToken token,
  ) async {
    final track = _activeQueueTracks.where((t) => t.id == id).firstOrNull;
    if (track == null ||
        track.playbackSource.isNotEmpty ||
        audioHandler.mediaItem.value?.id == id) {
      return;
    }
    final streamRecord = _streamingMetadataTracks[track.id];
    if (streamRecord != null &&
        _activeStreamPartPaths.contains('${streamRecord.filePath}.part')) {
      return;
    }
    final candidate = _candidateForOnlineTrack(track.id);
    if (candidate != null &&
        _downloadsInFlight.containsKey(
          downloadQueue.taskIdForCandidate(candidate),
        )) {
      return;
    }
    final source = await _prepareOnlineStream(track, prefetchToken: token);
    token.check();
    if (source is! ResumableAudioSource) return;
    final done = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    Future<void>? cancelling;
    token.onCancel(() {
      source.cancelRequests();
      cancelling = subscription?.cancel();
      if (!done.isCompleted) done.completeError(const CachePrefetchCancelled());
    });
    // Attach the error handler before an asynchronous HTTP header request.
    final completion = done.future;
    unawaited(completion.catchError((Object _) {}));
    try {
      final response = await source.request();
      subscription = response.stream.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      if (token.isCancelled) {
        source.cancelRequests();
        cancelling = subscription.cancel();
      }
      await completion;
    } finally {
      await cancelling;
      await subscription?.cancel();
      source.cancelRequests();
      await source.waitForCache();
    }
  }

  void _maybePrefetchUpcomingLyrics() {
    if (playbackMode == PlaybackMode.repeatOne) return;
    final currentId = audioHandler.mediaItem.value?.id;
    if (currentId == null) return;
    final upcoming = <Track>[];
    final seen = {currentId};
    var cursor = currentId;
    for (var i = 0; i < 3; i += 1) {
      final index = audioHandler.followingQueueIndex(cursor);
      if (index == null || index < 0 || index >= _activeQueueTracks.length) {
        break;
      }
      final track = _activeQueueTracks[index];
      if (!seen.add(track.id)) break;
      upcoming.add(track);
      cursor = track.id;
    }
    if (upcoming.isEmpty) return;
    final key = '$currentId|${upcoming.map((track) => track.id).join('|')}';
    if (_lyricsPrefetchQueueKey == key) return;
    _lyricsPrefetchQueueKey = key;
    final request = ++_lyricsPrefetchRequest;
    unawaited(_prefetchUpcomingLyrics(upcoming, request));
  }

  Future<void> _prefetchUpcomingLyrics(
    List<Track> upcoming,
    int request,
  ) async {
    await Future.wait([
      for (var i = 0; i < upcoming.length; i += 1)
        () async {
          if (i > 0) {
            await Future<void>.delayed(Duration(milliseconds: i * 350));
          }
          if (_isDisposed || request != _lyricsPrefetchRequest) return;
          final track = upcoming[i];
          final cached = _cachedRecordForTrack(track);
          final record = cached ?? _lyricsPrefetchRecordForOnline(track);
          if (record == null) return;
          try {
            await metadataUseCase.prefetchLyrics(record);
          } catch (_) {
            // Lyrics prefetch is best effort and never interrupts playback.
          }
        }(),
    ]);
  }

  CachedTrack? _lyricsPrefetchRecordForOnline(Track track) {
    final candidate = _onlineTrackForId(track.id)?.candidate;
    if (candidate == null) return null;
    return CachedTrack(
      cacheId: 'online-lyrics-${track.id}',
      filePath: '',
      sizeBytes: 0,
      fromCache: false,
      music: ResolvedMusic(
        query: candidate.query,
        source: candidate.source,
        platform: candidate.platform,
        id: candidate.id,
        name: candidate.name,
        artist: candidate.artist,
        album: candidate.album,
        url: '',
        quality:
            candidate.qualities.firstOrNull ?? const MusicQuality(format: ''),
        coverUrl: candidate.coverUrl,
      ),
    );
  }

  Future<void> deleteCachedTrack(Track track) async {
    await _playbackPrefetch.cancel();
    await _handleDeletedTracksPlaybackImpact({track.id});
    _applyLibrarySnapshot(
      await libraryUseCase.deleteCachedTrack(track, current: _librarySnapshot),
    );
    notifyListeners();
  }

  Future<void> deleteCachedTracks(List<Track> tracks) async {
    await _playbackPrefetch.cancel();
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

  Future<void> setPlaybackMode(PlaybackMode mode) {
    final changed = playbackMode != mode;
    playbackMode = mode;
    notifyListeners();
    // Keep the user-visible mode immediate, but apply each two-step player update
    // in tap order so an older request cannot overwrite a newer selection.
    final operation = _playbackModeChange.then((_) async {
      await playbackUseCase.applyPlaybackMode(mode);
      if (changed) {
        unawaited(_playbackPrefetch.cancel());
        _lyricsPrefetchQueueKey = null;
        _lyricsPrefetchRequest += 1;
        if (audioHandler.playbackState.value.playing) {
          _maybePrefetchNext();
          _maybePrefetchUpcomingLyrics();
        }
      }
      await _syncOhosControlState();
    });
    _playbackModeChange = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  Future<void> cyclePlaybackMode() {
    final nextMode = switch (playbackMode) {
      PlaybackMode.sequential => PlaybackMode.repeatOne,
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

  OnlinePlaylistTasks? _onlinePlaylistTasks;
  OnlinePlaylistTasks get onlinePlaylistTasks =>
      _onlinePlaylistTasks ??= OnlinePlaylistTasks(
        matcher: createOnlinePlaylistMatcher(),
        concurrency: () => screenshotSearchConcurrency,
        createPlaylist: createPlaylist,
        importRows: (name, candidates, target, sourceOrderTrackIds) =>
            importPlaylistSelection(
              name,
              candidates,
              target: target,
              sourceOrderTrackIds: sourceOrderTrackIds,
            ),
      );

  ScreenshotMatcher createOnlinePlaylistMatcher() =>
      ScreenshotMatcher(resolver: _resolver, allowTitleFragments: false);

  Future<MusicPlaylist?> importPlaylistCandidates(
    String name,
    List<MusicSearchCandidate> candidates, {
    MusicPlaylist? target,
  }) async => (await importPlaylistSelection(
    name,
    candidates,
    target: target,
  )).playlist;

  Future<MusicPlaylist?> addPlaylistDirectly(
    OnlinePlaylist origin,
    List<OnlinePlaylistSong> songs, {
    MusicPlaylist? target,
  }) async {
    final result = await libraryUseCase.importPlaylistSongs(
      origin.name,
      [
        for (final s in songs)
          PlaylistSong(
            key: '${origin.source.name}:${s.id}',
            title: s.title,
            artist: s.artist,
            coverUrl: origin.coverUrl,
          ),
      ],
      current: _librarySnapshot,
      target: target,
    );
    _applyLibrarySnapshot(result.snapshot);
    notifyListeners();
    if (result.playlist != null) {
      await _appendSyncedPlaylistTracksToQueue(result.playlist!);
      unawaited(matchPlaylistSources(result.playlist!.id));
    }
    return result.playlist;
  }

  /// Saving metadata comes first; matching continues after the page is closed.
  /// Recommendations stay pending until audio actually plays successfully.
  Future<void> matchPlaylistSources(String playlistId) {
    final existing = _playlistSourceMatching[playlistId];
    if (existing != null) return existing;
    if ((playlistSourceProgress.value[playlistId]?.failed ?? 0) > 0) {
      // Empty results may have been cached while a source was unavailable.
      _playlistSongMatcher = null;
    }
    final future = _runPlaylistSourceMatching(playlistId);
    _playlistSourceMatching[playlistId] = future;
    return future.whenComplete(() {
      if (identical(_playlistSourceMatching[playlistId], future)) {
        _playlistSourceMatching.remove(playlistId);
      }
    });
  }

  Future<void> _runPlaylistSourceMatching(String playlistId) async {
    final playlist = customPlaylists
        .where((p) => p.id == playlistId)
        .firstOrNull;
    if (playlist == null || _isDisposed) return;
    final indexed = {
      for (final track in _librarySnapshot.allTracks) track.id: track,
    };
    final tracks = playlist.trackIds
        .map((id) => indexed[id])
        .whereType<Track>()
        .where((t) => _songEntry(t.id)?.song != null)
        .toList();
    var next = 0;
    var completed = 0;
    var failed = 0;
    var nextOutcome = 0;
    var consecutiveErrors = 0;
    var paused = false;
    final outcomes = List<bool?>.filled(tracks.length, null);
    void publish(bool matching) {
      if (!_isDisposed) {
        playlistSourceProgress.value = {
          ...playlistSourceProgress.value,
          playlistId: (
            matching: matching,
            completed: completed,
            total: tracks.length,
            failed: failed,
          ),
        };
      }
    }

    publish(true);
    Future<void> worker() async {
      while (!_isDisposed && !paused && next < tracks.length) {
        final index = next++;
        final track = tracks[index];
        final current = customPlaylists
            .where((p) => p.id == playlistId)
            .firstOrNull;
        if (current == null) return;
        if (!current.trackIds.contains(track.id)) {
          outcomes[index] = true;
          completed++;
          continue;
        }
        try {
          await _ensureSongCandidate(track);
          outcomes[index] = true;
        } catch (_) {
          final chosen = _candidateForOnlineTrack(track.id) != null;
          outcomes[index] = chosen;
          if (!chosen) failed++;
        }
        while (nextOutcome < outcomes.length && outcomes[nextOutcome] != null) {
          consecutiveErrors = outcomes[nextOutcome++]!
              ? 0
              : consecutiveErrors + 1;
          if (consecutiveErrors >= 3) paused = true;
        }
        completed++;
        publish(true);
      }
    }

    await Future.wait([
      for (
        var i = 0;
        i < tracks.length && i < screenshotSearchConcurrency.clamp(1, 10);
        i++
      )
        worker(),
    ]);
    publish(false);
  }

  Future<MusicPlaylistResult> importPlaylistSelection(
    String name,
    List<MusicSearchCandidate> candidates, {
    MusicPlaylist? target,
    List<String>? sourceOrderTrackIds,
  }) async {
    final result = await libraryUseCase.importOnlinePlaylist(
      name,
      [
        for (final candidate in candidates)
          SavedOnlineTrack(candidate: candidate),
      ],
      target: target,
      sourceOrderTrackIds: sourceOrderTrackIds,
      current: _librarySnapshot,
    );
    _applyLibrarySnapshot(result.snapshot);
    notifyListeners();
    if (target != null && result.playlist != null) {
      await _appendSyncedPlaylistTracksToQueue(result.playlist!);
    }
    return result;
  }

  Future<void> _appendSyncedPlaylistTracksToQueue(
    MusicPlaylist playlist,
  ) async {
    if (_activePlaylistId != playlist.id) return;
    final request = _playRequest;
    final prior = _playLoadTail;
    final done = Completer<void>();
    _playLoadTail = done.future;
    await prior;
    try {
      if (_isDisposed ||
          request != _playRequest ||
          _activePlaylistId != playlist.id ||
          audioHandler.mediaItem.value == null) {
        return;
      }
      final existingIds = {for (final track in _activeQueueTracks) track.id};
      final additions = [
        for (final track in tracksForPlaylist(playlist))
          if (existingIds.add(track.id)) track,
      ];
      if (additions.isEmpty) return;
      try {
        await playbackUseCase.appendTracks(_activeQueueTracks, additions);
        _activeQueueTracks = [..._activeQueueTracks, ...additions];
        _lyricsPrefetchQueueKey = null;
        _maybePrefetchNext();
        _maybePrefetchUpcomingLyrics();
      } catch (_) {
        // The playlist is already saved. A playback-device failure must not
        // falsely mark its recognition task as a failed import.
        _activePlaylistId = null;
      }
    } finally {
      done.complete();
    }
  }

  Future<MusicPlaylistResult> replaceImportedCandidate(
    MusicPlaylist target,
    String previousId,
    MusicSearchCandidate replacement, {
    required bool removePrevious,
  }) async {
    final result = await libraryUseCase.replaceImportedCandidate(
      target,
      previousId,
      SavedOnlineTrack(candidate: replacement),
      removePrevious: removePrevious,
      current: _librarySnapshot,
    );
    _applyLibrarySnapshot(result.snapshot);
    notifyListeners();
    if (result.playlist != null) {
      try {
        await _replaceActivePlaylistQueueItem(
          result.playlist!,
          previousId,
          SavedOnlineTrack(candidate: replacement).trackId,
        );
      } catch (_) {
        // The replacement was persisted; audio-device queue errors must not
        // present it as an unsaved candidate.
        _activePlaylistId = null;
        _retiredQueueTrackIds.clear();
      }
    }
    return result;
  }

  Future<void> _replaceActivePlaylistQueueItem(
    MusicPlaylist playlist,
    String previousId,
    String replacementId,
  ) async {
    if (_activePlaylistId != playlist.id) return;
    final request = _playRequest;
    final prior = _playLoadTail;
    final done = Completer<void>();
    _playLoadTail = done.future;
    await prior;
    try {
      if (_isDisposed ||
          request != _playRequest ||
          _activePlaylistId != playlist.id ||
          audioHandler.mediaItem.value == null) {
        return;
      }
      final oldIndex = _activeQueueTracks.indexWhere(
        (track) => track.id == previousId,
      );
      if (oldIndex >= 0 && !playlist.trackIds.contains(previousId)) {
        if (audioHandler.mediaItem.value?.id == previousId) {
          // Let the current song finish; remove it as soon as playback moves.
          _retiredQueueTrackIds.add(previousId);
        } else {
          final replacement = tracksForPlaylist(
            playlist,
          ).where((track) => track.id == replacementId).firstOrNull;
          final alreadyQueued = _activeQueueTracks.any(
            (track) => track.id == replacementId,
          );
          if (replacement != null && !alreadyQueued) {
            await playbackUseCase.replaceTrackAt(
              _activeQueueTracks,
              oldIndex,
              replacement,
            );
            _activeQueueTracks = [
              for (var i = 0; i < _activeQueueTracks.length; i++)
                i == oldIndex ? replacement : _activeQueueTracks[i],
            ];
          } else {
            await playbackUseCase.removeTrackAt(_activeQueueTracks, oldIndex);
            _activeQueueTracks = [..._activeQueueTracks]..removeAt(oldIndex);
          }
          unawaited(_playbackPrefetch.cancel());
          _lyricsPrefetchQueueKey = null;
        }
      }
    } finally {
      done.complete();
    }
    await _appendSyncedPlaylistTracksToQueue(playlist);
  }

  Future<int> addCandidatesToPlaylist(
    MusicPlaylist playlist,
    List<MusicSearchCandidate> selected,
  ) async {
    final previousIds =
        customPlaylists
            .where((item) => item.id == playlist.id)
            .firstOrNull
            ?.trackIds
            .toSet() ??
        <String>{};
    final saved = [
      for (final candidate in selected) SavedOnlineTrack(candidate: candidate),
    ];
    final snapshot = await libraryUseCase.addOnlineTracksToPlaylist(
      playlist,
      saved,
      current: _librarySnapshot,
    );
    _applyLibrarySnapshot(snapshot);
    notifyListeners();
    final currentIds =
        customPlaylists
            .where((item) => item.id == playlist.id)
            .firstOrNull
            ?.trackIds
            .toSet() ??
        <String>{};
    final candidateIds = {for (final track in saved) track.trackId};
    return currentIds.difference(previousIds).intersection(candidateIds).length;
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
    final candidate = _adHocPlayCandidates[track.id];
    _applyLibrarySnapshot(
      await libraryUseCase.toggleFavorite(
        track,
        current: _librarySnapshot,
        onlineTrack: candidate == null
            ? null
            : SavedOnlineTrack(candidate: candidate),
      ),
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
    await _playbackPrefetch.cancel();
    if (_activePlaylistId == playlist.id) _activePlaylistId = null;
    _applyLibrarySnapshot(
      await libraryUseCase.deletePlaylist(playlist, current: _librarySnapshot),
    );
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(MusicPlaylist playlist, Track track) =>
      addTracksToPlaylist(playlist, [track]);

  Future<void> addTracksToPlaylist(
    MusicPlaylist playlist,
    List<Track> tracks,
  ) async {
    _applyLibrarySnapshot(
      await libraryUseCase.addTracksToPlaylist(
        playlist,
        tracks,
        current: _librarySnapshot,
        onlineTracksById: {
          for (final track in tracks)
            if (_adHocPlayCandidates[track.id] case final candidate?)
              track.id: SavedOnlineTrack(candidate: candidate),
        },
      ),
    );
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(
    MusicPlaylist playlist,
    Track track,
  ) async {
    await _playbackPrefetch.cancel();
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
    await _playbackPrefetch.cancel();
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
      screenshotSearchConcurrency: screenshotSearchConcurrency,
      playlistDownloadConcurrency: playlistDownloadConcurrency,
      downloadPlaylistsOnWifi: downloadPlaylistsOnWifi,
      defaultDownloadQuality: defaultDownloadQuality,
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
    _cacheProgressTrackKeys.clear();
    final completed = <String>{};
    for (final record in _cachedRecords) {
      final key = downloadQueue.taskIdForCandidate(
        _candidateFromCached(record),
      );
      _cacheProgressTrackKeys[record.cacheId] = key;
      completed.add(key);
    }
    for (final entry in [
      ..._playlistLibrary.favoriteEntries,
      for (final playlist in _playlistLibrary.playlists) ...playlist.entries,
    ]) {
      final candidate = entry.onlineTrack?.candidate;
      if (candidate != null) {
        _cacheProgressTrackKeys[entry.trackId] = downloadQueue
            .taskIdForCandidate(candidate);
      }
    }
    songCacheProgress.completeKeys(completed);
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
    CachedTrack? best;
    for (final record in _matchingCachedRecords(candidate)) {
      if (best == null ||
          cachedTrackPlaybackPreference(record) >
              cachedTrackPlaybackPreference(best)) {
        best = record;
      }
    }
    return best;
  }

  Iterable<CachedTrack> _matchingCachedRecords(
    MusicSearchCandidate candidate,
  ) => _cachedRecords.where((record) {
    final music = record.music;
    return music.source == candidate.source &&
        music.platform == candidate.platform &&
        (candidate.id.isNotEmpty
            ? music.id == candidate.id
            : music.name == candidate.name && music.artist == candidate.artist);
  });

  void _retainStreamPart(String path) {
    _activeStreamPartCounts.update(
      path,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    _activeStreamPartPaths.add(path);
  }

  void _releaseStreamPart(String path) {
    final count = _activeStreamPartCounts[path];
    if (count == null) return;
    if (count > 1) {
      _activeStreamPartCounts[path] = count - 1;
    } else {
      _activeStreamPartCounts.remove(path);
      _activeStreamPartPaths.remove(path);
    }
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
      await setPlaybackMode(playbackMode);
    }
    if (!wasPlaying) {
      await audioHandler.pause();
    }
  }

  void _handleMediaItemChanged(MediaItem? item) {
    if (item != null &&
        _retiredQueueTrackIds.isNotEmpty &&
        !_retiredQueueTrackIds.contains(item.id)) {
      unawaited(_removeRetiredQueueTracks());
    }
    if (item != null && audioHandler.playbackState.value.playing) {
      _maybePrefetchNext();
      _maybePrefetchUpcomingLyrics();
    }
    if (item == null) {
      _lyricsPrefetchQueueKey = null;
      _lyricsPrefetchRequest += 1;
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
    final track = _trackForMediaId(item.id);
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

  Future<void> _removeRetiredQueueTracks() async {
    if (_retiredQueueCleanupRunning || _retiredQueueTrackIds.isEmpty) return;
    _retiredQueueCleanupRunning = true;
    final request = _playRequest;
    final playlistId = _activePlaylistId;
    final prior = _playLoadTail;
    final done = Completer<void>();
    _playLoadTail = done.future;
    await prior;
    try {
      if (_isDisposed ||
          request != _playRequest ||
          playlistId == null ||
          _activePlaylistId != playlistId) {
        return;
      }
      for (final id in _retiredQueueTrackIds.toList()) {
        if (audioHandler.mediaItem.value?.id == id) continue;
        final index = _activeQueueTracks.indexWhere((track) => track.id == id);
        if (index >= 0) {
          try {
            await playbackUseCase.removeTrackAt(_activeQueueTracks, index);
            _activeQueueTracks = [..._activeQueueTracks]..removeAt(index);
          } catch (_) {
            continue;
          }
        }
        _retiredQueueTrackIds.remove(id);
      }
    } finally {
      done.complete();
      _retiredQueueCleanupRunning = false;
    }
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
      if (cached.music.source == MusicDataSource.buguyy &&
          metadata.hasLyrics &&
          !metadata.lyrics.any((line) => line.time > Duration.zero) &&
          _timedLyricsUpgradeAttempted.add(track.id)) {
        unawaited(_upgradeTimedLyricsForTrack(track, cached));
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

  Future<void> _upgradeTimedLyricsForTrack(
    Track track,
    CachedTrack cached,
  ) async {
    var hasTimedLyrics = false;
    try {
      final upgraded = await metadataUseCase.upgradeTimedLyrics(cached);
      hasTimedLyrics = upgraded.lyrics.any((line) => line.time > Duration.zero);
      if (!_isDisposed &&
          _metadataTrackId == track.id &&
          audioHandler.mediaItem.value?.id == track.id &&
          hasTimedLyrics) {
        currentMetadata = upgraded;
        notifyListeners();
      }
    } catch (_) {
      // Keep the existing plain lyrics when synchronized lyrics are unavailable.
    } finally {
      if (!hasTimedLyrics) _timedLyricsUpgradeAttempted.remove(track.id);
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
    final candidate = _candidateForOnlineTrack(track.id);
    if (candidate != null) {
      // A legacy cache ID can remain the logical playlist ID after a source
      // switch. Do not let that old file supply lyrics/artwork for the new audio.
      return _cachedRecordForCandidate(candidate) ??
          _streamingMetadataTracks[track.id];
    }
    return _cachedRecords
            .where((record) => record.cacheId == track.id)
            .firstOrNull ??
        _streamingMetadataTracks[track.id];
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
      'list' => PlaybackMode.sequential,
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
    appUpdates.dispose();
    _searchRequest += 1;
    _playRequest += 1;
    _isDisposed = true;
    downloadProgressChanges.dispose();
    songCacheProgress.dispose();
    playlistSourceProgress.dispose();
    _onlinePlaylistTasks?.dispose();
    audioHandler.onOhosLoopModeRequested = null;
    audioHandler.onOhosToggleFavoriteRequested = null;
    audioHandler.onToggleFavoriteRequested = null;
    audioHandler.onTogglePlaybackModeRequested = null;
    unawaited(_mediaItemSubscription.cancel());
    unawaited(_playbackSubscription.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_playbackPrefetch.cancel());
    if (_ownsLanLibraryGateway && _lanLibraryGateway is LanLibraryClient) {
      _lanLibraryGateway.close();
    }
    super.dispose();
  }
}
