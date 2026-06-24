import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/lyrics_artwork.dart';
import '../data/legacy_cache_repairer.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
import '../data/playback_state_store.dart';
import '../domain/music_models.dart';
import '../playback/music_audio_handler.dart';
import 'download_queue_controller.dart';
import 'download_use_case.dart';
import 'library_controller.dart';
import 'library_use_case.dart';
import 'metadata_use_case.dart';
import 'music_mappers.dart';
import 'music_ui_message.dart';
import 'playback_use_case.dart';
import 'settings_controller.dart';

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
    PlaybackStateStore? playbackStateStore,
    TrackMetadataRepository? metadataRepository,
    LegacyCacheRepairer? legacyRepairer,
  }) : _resolver = resolver ?? RemoteMusicResolver(),
       _cacheStore = cacheStore ?? CachedTrackStore(),
       _playlistStore = playlistStore ?? PlaylistStore(),
       _settingsStore = settingsStore ?? MusicSettingsStore(),
       _playbackStateStore = playbackStateStore ?? PlaybackStateStore(),
       _metadataRepository = metadataRepository ?? TrackMetadataRepository(),
       _legacyRepairerOverride = legacyRepairer {
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
    playbackUseCase = PlaybackUseCase(audioHandler: audioHandler);
    metadataUseCase = MetadataUseCase(repository: _metadataRepository);
    audioHandler.onOhosLoopModeRequested = _handleOhosLoopModeRequested;
    audioHandler.onOhosToggleFavoriteRequested =
        _handleOhosToggleFavoriteRequested;
    audioHandler.onToggleFavoriteRequested = _handleToggleFavoriteRequested;
    _mediaItemSubscription = audioHandler.mediaItem.listen(
      _handleMediaItemChanged,
    );
  }

  final MusicAudioHandler audioHandler;
  final MusicResolver _resolver;
  final CachedTrackStore _cacheStore;
  final PlaylistStore _playlistStore;
  final MusicSettingsStore _settingsStore;
  final PlaybackStateStore _playbackStateStore;
  final TrackMetadataRepository _metadataRepository;
  final LegacyCacheRepairer? _legacyRepairerOverride;
  final LibraryController libraryController = const LibraryController();
  final DownloadQueueController downloadQueue = DownloadQueueController();
  late final SettingsController settingsController;
  late final LibraryUseCase libraryUseCase;
  late final DownloadUseCase downloadUseCase;
  late final PlaybackUseCase playbackUseCase;
  late final MetadataUseCase metadataUseCase;
  late final StreamSubscription<MediaItem?> _mediaItemSubscription;
  List<CachedTrack> _cachedRecords = const [];
  PlaylistLibrary _playlistLibrary = const PlaylistLibrary.empty();
  int _metadataRequest = 0;
  // 搜索框允许“非空换非空”快速输入；request id 用来丢弃晚返回的旧结果。
  int _searchRequest = 0;
  String? _metadataTrackId;
  final Set<String> _autoMetadataRecoveryAttempted = {};
  PlaybackQueueSource _activeQueueSource =
      const PlaybackQueueSource.localCache();
  List<String> _activeQueueTrackIds = const [];
  bool _legacyRepairRunning = false;
  bool _isDisposed = false;

  MusicDataSource source = MusicDataSource.buguyy;
  List<MusicSearchCandidate> candidates = const [];
  List<Track> cachedTracks = const [];
  List<Track> favoriteTracks = const [];
  List<MusicPlaylist> customPlaylists = const [];
  List<DownloadTask> get downloadTasks => downloadQueue.tasks;
  MusicSearchCandidate? get busyCandidate => downloadQueue.busyCandidate;
  Set<String> get busyCandidateKeys => downloadQueue.busyCandidateKeys;
  PlaybackMode playbackMode = PlaybackMode.sequential;
  AppLanguage language = AppLanguage.zh;
  AppThemePreference themePreference = AppThemePreference.dark;
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
    return cachedTracks.where((track) => track.id == item.id).firstOrNull;
  }

  Future<void> initialize() async {
    final settings = await settingsController.load();
    final savedPlayback = await _playbackStateStore.load();
    source = settings.source;
    language = settings.language;
    themePreference = settings.theme;
    if (savedPlayback != null) {
      playbackMode = savedPlayback.playbackMode;
    }
    await _cacheStore.cleanupTemporaryFiles();
    await loadCache();
    await _restorePlaybackState(savedPlayback);
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

  Future<void> downloadCandidate(MusicSearchCandidate candidate) async {
    // 重复点击同一候选时只提示已有任务，避免清掉当前下载进度和状态。
    if (downloadQueue.hasActiveToken(
      downloadQueue.taskIdForCandidate(candidate),
    )) {
      statusMessage = const MusicUiMessage(
        MusicUiMessageCode.downloadAlreadyRunning,
      );
      notifyListeners();
      return;
    }
    errorDetail = null;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();
    final result = await downloadUseCase.downloadCandidate(
      candidate,
      onStatus: (message) {
        statusMessage = message;
        notifyListeners();
      },
      onChanged: notifyListeners,
    );
    if (result.cached != null) {
      _upsertCachedRecord(result.cached!);
      statusMessage = result.statusMessage ?? statusMessage;
      errorDetail = result.errorDetail;
      notifyListeners();
      unawaited(_primeMetadataAndReloadCache(result.cached!));
      return;
    }
    statusMessage = result.statusMessage ?? statusMessage;
    errorDetail = result.errorDetail;
    notifyListeners();
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
    var record = _cachedRecordForCandidate(candidate);
    if (record == null) {
      await downloadCandidate(candidate);
      record = _cachedRecordForCandidate(candidate);
    } else {
      record = await _refreshCachedCandidateMetadata(candidate, record);
    }
    if (record == null) {
      return;
    }
    final track = trackFromCached(record);
    final searchQueue = _searchCachedQueue();
    final searchIndex = searchQueue.indexWhere((item) => item.id == track.id);
    if (searchIndex != -1) {
      await playTrack(
        track,
        index: searchIndex,
        queueTracks: searchQueue,
        queueSource: const PlaybackQueueSource.searchCache(),
      );
    } else {
      final index = cachedTracks.indexWhere((item) => item.id == track.id);
      await playTrack(
        track,
        index: index == -1 ? null : index,
        queueSource: const PlaybackQueueSource.localCache(),
      );
    }
    statusMessage = const MusicUiMessage(MusicUiMessageCode.playingCachedFile);
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    int? index,
    List<Track>? queueTracks,
    PlaybackQueueSource? queueSource,
  }) async {
    final queue = (queueTracks ?? cachedTracks).isEmpty
        ? <Track>[track]
        : queueTracks ?? cachedTracks;
    final loaded = await playbackUseCase.playTrack(
      track,
      index: index,
      fallbackQueue: cachedTracks,
      queueTracks: queueTracks,
    );
    if (loaded) {
      _activeQueueSource = queueSource ?? _inferQueueSource(queue);
      _activeQueueTrackIds = [for (final item in queue) item.id];
      await _savePlaybackState(currentTrackId: track.id);
      // 同一首同一队列的重复点击不会重载队列，也不需要重设播放模式。
      await setPlaybackMode(playbackMode);
    }
  }

  Future<void> togglePlayPause() => playbackUseCase.togglePlayPause();

  Future<void> seek(Duration position) => playbackUseCase.seek(position);

  Future<void> seekToLyricLine(LyricLine line) => seek(line.time);

  Future<void> next() => playbackUseCase.next();

  Future<void> previous() => playbackUseCase.previous();

  Future<void> stop() async {
    await playbackUseCase.stop();
    _activeQueueTrackIds = const [];
    await _clearPlaybackState();
  }

  Future<void> deleteCachedTrack(Track track) async {
    await _handleDeletedTracksPlaybackImpact({track.id});
    _applyLibrarySnapshot(
      await libraryUseCase.deleteCachedTrack(track, current: _librarySnapshot),
    );
    await _refreshPersistedQueueAfterLibraryChange();
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
    await _refreshPersistedQueueAfterLibraryChange();
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
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    playbackMode = mode;
    notifyListeners();
    await playbackUseCase.applyPlaybackMode(mode);
    await _savePlaybackState();
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
    return libraryController.tracksForIds(playlist.trackIds, cachedTracks);
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
    await _refreshPersistedQueueAfterLibraryChange();
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
    await _refreshPersistedQueueAfterLibraryChange();
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
    await _refreshPersistedQueueAfterLibraryChange();
    notifyListeners();
  }

  Future<void> _saveSettings() {
    return settingsController.save(
      source: source,
      language: language,
      theme: themePreference,
    );
  }

  LibrarySnapshot get _librarySnapshot {
    return LibrarySnapshot(
      cachedRecords: _cachedRecords,
      cachedTracks: cachedTracks,
      playlistLibrary: _playlistLibrary,
      favoriteTracks: favoriteTracks,
      customPlaylists: customPlaylists,
    );
  }

  void _applyLibrarySnapshot(LibrarySnapshot snapshot) {
    _cachedRecords = snapshot.cachedRecords;
    _playlistLibrary = snapshot.playlistLibrary;
    cachedTracks = snapshot.cachedTracks;
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
      await _clearPlaybackState();
      return;
    }
    final queuedIds = [for (final item in audioHandler.queue.value) item.id];
    if (!queuedIds.any(deletedIds.contains)) {
      return;
    }
    if (currentId == null) {
      await stop();
      await _clearPlaybackState();
      return;
    }
    final byId = {for (final track in cachedTracks) track.id: track};
    final remainingQueue = [
      for (final id in queuedIds)
        if (!deletedIds.contains(id) && byId[id] != null) byId[id]!,
    ];
    final currentIndex = remainingQueue.indexWhere(
      (track) => track.id == currentId,
    );
    if (currentIndex == -1) {
      await stop();
      await _clearPlaybackState();
      return;
    }
    final wasPlaying = audioHandler.playbackState.value.playing;
    final loaded = await playbackUseCase.playTrack(
      remainingQueue[currentIndex],
      index: currentIndex,
      fallbackQueue: remainingQueue,
      queueTracks: remainingQueue,
    );
    if (loaded) {
      await playbackUseCase.applyPlaybackMode(playbackMode);
      _activeQueueTrackIds = [for (final track in remainingQueue) track.id];
      await _savePlaybackState(currentTrackId: currentId);
    }
    if (!wasPlaying) {
      await audioHandler.pause();
    }
  }

  void _handleMediaItemChanged(MediaItem? item) {
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
      unawaited(_savePlaybackState(currentTrackId: item.id));
      return;
    }
    final track = cachedTracks
        .where((track) => track.id == item.id)
        .firstOrNull;
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
    unawaited(_savePlaybackState(currentTrackId: item.id));
    unawaited(_syncOhosControlState());
  }

  Future<void> _loadMetadataForTrack(Track track) async {
    _metadataTrackId = track.id;
    // 切歌时歌词/封面请求可能晚返回；request id 保证只写入当前歌曲的结果。
    final request = ++_metadataRequest;
    final cached = _cachedRecords
        .where((record) => record.cacheId == track.id)
        .firstOrNull;
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
    bool bypassMetadataMiss = false,
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
      final cached = _cachedRecords
          .where((record) => record.cacheId == track.id)
          .firstOrNull;
      if (cached == null) {
        return;
      }
      final refreshed = await _resolveAndUpdateCachedMetadata(cached);
      final metadata = bypassMetadataMiss
          ? await metadataUseCase.loadBypassingMetadataMiss(refreshed)
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

  Future<void> _restorePlaybackState(SavedPlaybackState? saved) async {
    if (saved == null) {
      return;
    }
    playbackMode = saved.playbackMode;
    if (!saved.hasQueue) {
      await playbackUseCase.applyPlaybackMode(playbackMode);
      return;
    }
    final queue = _queueForSavedState(saved);
    if (queue.isEmpty) {
      await _clearPlaybackState();
      return;
    }
    final currentIndex = _restoredCurrentIndex(queue, saved);
    if (currentIndex == -1) {
      await _clearPlaybackState();
      return;
    }
    _activeQueueSource = saved.queueSource;
    _activeQueueTrackIds = [for (final track in queue) track.id];
    await playbackUseCase.restoreQueue(queue, currentIndex: currentIndex);
    await playbackUseCase.applyPlaybackMode(playbackMode);
    await audioHandler.pause();
    await _savePlaybackState(currentTrackId: queue[currentIndex].id);
  }

  List<Track> _queueForSavedState(SavedPlaybackState saved) {
    final savedIds = saved.queueTrackIds;
    final byId = {for (final track in cachedTracks) track.id: track};
    switch (saved.queueSource.type) {
      case PlaybackQueueSourceType.favorite:
        return _orderedTracks(savedIds, favoriteTracks, byId);
      case PlaybackQueueSourceType.customPlaylist:
        final playlist = customPlaylists
            .where((item) => item.id == saved.queueSource.id)
            .firstOrNull;
        if (playlist == null) {
          return _orderedTracks(savedIds, const [], byId);
        }
        return _orderedTracks(savedIds, tracksForPlaylist(playlist), byId);
      case PlaybackQueueSourceType.localCache:
      case PlaybackQueueSourceType.searchCache:
        return _orderedTracks(savedIds, cachedTracks, byId);
    }
  }

  List<Track> _orderedTracks(
    List<String> savedIds,
    List<Track> sourceTracks,
    Map<String, Track> cachedById,
  ) {
    final sourceById = {for (final track in sourceTracks) track.id: track};
    final tracks = <Track>[];
    final seen = <String>{};
    for (final id in savedIds) {
      final track = sourceById[id] ?? cachedById[id];
      if (track != null && seen.add(track.id)) {
        tracks.add(track);
      }
    }
    return tracks;
  }

  int _restoredCurrentIndex(List<Track> queue, SavedPlaybackState saved) {
    final direct = queue.indexWhere(
      (track) => track.id == saved.currentTrackId,
    );
    if (direct != -1) {
      return direct;
    }
    final savedCurrentIndex = saved.queueTrackIds.indexOf(saved.currentTrackId);
    if (savedCurrentIndex == -1) {
      return queue.isEmpty ? -1 : 0;
    }
    for (
      var i = savedCurrentIndex + 1;
      i < saved.queueTrackIds.length;
      i += 1
    ) {
      final nextIndex = queue.indexWhere(
        (track) => track.id == saved.queueTrackIds[i],
      );
      if (nextIndex != -1) {
        return nextIndex;
      }
    }
    return queue.isEmpty ? -1 : 0;
  }

  PlaybackQueueSource _inferQueueSource(List<Track> queue) {
    final ids = [for (final track in queue) track.id];
    if (_sameTrackIds(ids, [for (final track in favoriteTracks) track.id])) {
      return const PlaybackQueueSource.favorite();
    }
    for (final playlist in customPlaylists) {
      if (_sameTrackIds(ids, playlist.trackIds)) {
        return PlaybackQueueSource.customPlaylist(playlist.id);
      }
    }
    return const PlaybackQueueSource.localCache();
  }

  bool _sameTrackIds(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  List<Track> _searchCachedQueue() {
    final tracks = <Track>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final record = _cachedRecordForCandidate(candidate);
      if (record != null && seen.add(record.cacheId)) {
        tracks.add(trackFromCached(record));
      }
    }
    return tracks;
  }

  Future<void> _refreshPersistedQueueAfterLibraryChange() async {
    final currentId = audioHandler.mediaItem.value?.id;
    if (currentId == null) {
      await _clearPlaybackState();
      return;
    }
    final queue = _queueForSource(_activeQueueSource);
    if (queue.isEmpty || !queue.any((track) => track.id == currentId)) {
      await _clearPlaybackState();
      return;
    }
    _activeQueueTrackIds = [for (final track in queue) track.id];
    await _savePlaybackState(currentTrackId: currentId);
  }

  List<Track> _queueForSource(PlaybackQueueSource source) {
    switch (source.type) {
      case PlaybackQueueSourceType.favorite:
        return favoriteTracks;
      case PlaybackQueueSourceType.customPlaylist:
        final playlist = customPlaylists
            .where((item) => item.id == source.id)
            .firstOrNull;
        return playlist == null ? const [] : tracksForPlaylist(playlist);
      case PlaybackQueueSourceType.localCache:
        return cachedTracks;
      case PlaybackQueueSourceType.searchCache:
        final savedIds = _activeQueueTrackIds;
        final byId = {for (final track in cachedTracks) track.id: track};
        return [
          for (final id in savedIds)
            if (byId[id] != null) byId[id]!,
        ];
    }
  }

  Future<void> _savePlaybackState({String? currentTrackId}) async {
    if (_activeQueueTrackIds.isEmpty) {
      return;
    }
    final id = currentTrackId ?? audioHandler.mediaItem.value?.id ?? '';
    if (id.isEmpty) {
      return;
    }
    try {
      await _playbackStateStore.save(
        SavedPlaybackState(
          playbackMode: playbackMode,
          queueSource: _activeQueueSource,
          queueTrackIds: _activeQueueTrackIds,
          currentTrackId: id,
        ),
      );
    } catch (_) {
      // 播放状态持久化是恢复体验增强，不能反向影响播放、切歌或删除。
    }
  }

  Future<void> _clearPlaybackState() async {
    try {
      await _playbackStateStore.clear();
    } catch (_) {
      // 清理陈旧快照失败不应影响当前播放主链路。
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    audioHandler.onOhosLoopModeRequested = null;
    audioHandler.onOhosToggleFavoriteRequested = null;
    audioHandler.onToggleFavoriteRequested = null;
    unawaited(_mediaItemSubscription.cancel());
    super.dispose();
  }
}
