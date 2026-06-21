import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/lyrics_artwork.dart';
import '../data/legacy_cache_repairer.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
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
    TrackMetadataRepository? metadataRepository,
    LegacyCacheRepairer? legacyRepairer,
  }) : _resolver = resolver ?? RemoteMusicResolver(),
       _cacheStore = cacheStore ?? CachedTrackStore(),
       _playlistStore = playlistStore ?? PlaylistStore(),
       _settingsStore = settingsStore ?? MusicSettingsStore(),
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
    _mediaItemSubscription = audioHandler.mediaItem.listen(
      _handleMediaItemChanged,
    );
  }

  final MusicAudioHandler audioHandler;
  final MusicResolver _resolver;
  final CachedTrackStore _cacheStore;
  final PlaylistStore _playlistStore;
  final MusicSettingsStore _settingsStore;
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
  bool _legacyRepairRunning = false;

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
    source = MusicDataSource.buguyy;
    language = settings.language;
    themePreference = settings.theme;
    await _cacheStore.cleanupTemporaryFiles();
    await loadCache();
    notifyListeners();
  }

  Future<void> loadCache({bool repairLegacy = true}) async {
    isLoadingCache = true;
    notifyListeners();
    try {
      _applyLibrarySnapshot(await libraryUseCase.loadCache());
      if (repairLegacy && !_legacyRepairRunning) {
        unawaited(repairLegacyCache());
      }
    } catch (exception) {
      errorDetail = friendlyError(exception);
    } finally {
      isLoadingCache = false;
      notifyListeners();
    }
  }

  Future<void> saveSource(MusicDataSource nextSource) async {
    // 当前 Android 版收敛为布谷歪歪单源；保留参数是为了兼容旧 UI 和测试接口。
    source = MusicDataSource.buguyy;
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
      await loadCache(repairLegacy: false);
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
    }
    if (record == null) {
      return;
    }
    final track = trackFromCached(record);
    final index = cachedTracks.indexWhere((item) => item.id == track.id);
    await playTrack(track, index: index == -1 ? null : index);
    statusMessage = const MusicUiMessage(MusicUiMessageCode.playingCachedFile);
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    int? index,
    List<Track>? queueTracks,
  }) async {
    final loaded = await playbackUseCase.playTrack(
      track,
      index: index,
      fallbackQueue: cachedTracks,
      queueTracks: queueTracks,
    );
    if (loaded) {
      // 同一首同一队列的重复点击不会重载队列，也不需要重设播放模式。
      await setPlaybackMode(playbackMode);
    }
  }

  Future<void> togglePlayPause() => playbackUseCase.togglePlayPause();

  Future<void> seek(Duration position) => playbackUseCase.seek(position);

  Future<void> seekToLyricLine(LyricLine line) => seek(line.time);

  Future<void> next() => playbackUseCase.next();

  Future<void> previous() => playbackUseCase.previous();

  Future<void> stop() => playbackUseCase.stop();

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
    playbackMode = mode;
    notifyListeners();
    await playbackUseCase.applyPlaybackMode(mode);
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
    return settingsController.save(language: language, theme: themePreference);
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
      return;
    }
    if (_metadataTrackId == item.id) {
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
      return;
    }
    unawaited(_loadMetadataForTrack(track));
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
      if (active?.id == track.id && metadata.artworkUri != null) {
        await audioHandler.updateCurrentMediaItem(
          active!.copyWith(artUri: metadata.artworkUri),
        );
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

  bool _isActiveMetadataRequest(int request, Track track) {
    return request == _metadataRequest &&
        audioHandler.mediaItem.value?.id == track.id;
  }

  @override
  void dispose() {
    unawaited(_mediaItemSubscription.cancel());
    super.dispose();
  }
}
