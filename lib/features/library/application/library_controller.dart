import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_providers.dart';
import '../../source_import/data/lan_music_source_client.dart';
import '../data/library_repository.dart';
import '../domain/track.dart';

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
      LibraryController.new,
    );

class LibraryState {
  const LibraryState({
    required this.tracks,
    this.isImporting = false,
    this.downloadProgress = const {},
    this.lastSourceUri,
    this.errorMessage,
  });

  const LibraryState.empty()
    : tracks = const [],
      isImporting = false,
      downloadProgress = const {},
      lastSourceUri = null,
      errorMessage = null;

  final List<Track> tracks;
  final bool isImporting;
  final Map<String, double> downloadProgress;
  final Uri? lastSourceUri;
  final String? errorMessage;

  int get cachedCount => tracks.where((track) => track.isCached).length;

  LibraryState copyWith({
    List<Track>? tracks,
    bool? isImporting,
    Map<String, double>? downloadProgress,
    Uri? lastSourceUri,
    bool clearLastSourceUri = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      isImporting: isImporting ?? this.isImporting,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      lastSourceUri: clearLastSourceUri
          ? null
          : lastSourceUri ?? this.lastSourceUri,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class LibraryController extends AsyncNotifier<LibraryState> {
  late final LibraryRepository _repository;
  late final LanMusicSourceClient _sourceClient;

  @override
  Future<LibraryState> build() async {
    _repository = ref.watch(libraryRepositoryProvider);
    _sourceClient = ref.watch(lanMusicSourceClientProvider);

    final localTracks = await _repository.loadTracks();
    if (localTracks.isNotEmpty) {
      return LibraryState(tracks: localTracks);
    }

    try {
      final imported = await _fetchFirstAvailableSource();
      final merged = await _repository.mergeSourceTracks(imported.tracks);
      return LibraryState(tracks: merged, lastSourceUri: imported.uri);
    } catch (error) {
      return LibraryState(
        tracks: localTracks,
        errorMessage: _friendlyError(error),
      );
    }
  }

  Future<void> importFromSources() async {
    final current = state.value ?? const LibraryState.empty();
    state = AsyncData(current.copyWith(isImporting: true, clearError: true));

    try {
      final imported = await _fetchFirstAvailableSource();
      final merged = await _repository.mergeSourceTracks(imported.tracks);
      state = AsyncData(
        current.copyWith(
          tracks: merged,
          isImporting: false,
          lastSourceUri: imported.uri,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isImporting: false,
          errorMessage: _friendlyError(error),
        ),
      );
    }
  }

  Future<Track> cacheTrack(Track track) async {
    final current = state.value ?? const LibraryState.empty();
    _setProgress(track.id, 0);

    try {
      final cached = await _repository.cacheTrack(
        track,
        onProgress: (received, total) {
          if (total <= 0) {
            return;
          }
          _setProgress(track.id, received / total);
        },
      );
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          tracks: _replaceTrack(latest.tracks, cached),
          downloadProgress: _withoutProgress(latest.downloadProgress, track.id),
          clearError: true,
        ),
      );
      return cached;
    } catch (error) {
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          tracks: _replaceTrack(
            latest.tracks,
            track.copyWith(
              clearLocalPath: true,
              cacheState: TrackCacheState.failed,
            ),
          ),
          downloadProgress: _withoutProgress(latest.downloadProgress, track.id),
          errorMessage: _friendlyError(error),
        ),
      );
      rethrow;
    }
  }

  Future<({Uri uri, List<Track> tracks})> _fetchFirstAvailableSource() async {
    Object? lastError;
    for (final uri in ref.read(sourceCandidateUrisProvider)) {
      try {
        final tracks = await _sourceClient.fetchTracks(uri);
        if (tracks.isNotEmpty) {
          return (uri: uri, tracks: tracks);
        }
        lastError = StateError('No tracks at $uri');
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('No music source is reachable. Last error: $lastError');
  }

  void _setProgress(String trackId, double progress) {
    final current = state.value ?? const LibraryState.empty();
    state = AsyncData(
      current.copyWith(
        downloadProgress: {
          ...current.downloadProgress,
          trackId: progress.clamp(0, 1),
        },
      ),
    );
  }

  List<Track> _replaceTrack(List<Track> tracks, Track updated) {
    var found = false;
    final next = <Track>[];
    for (final track in tracks) {
      if (track.id == updated.id) {
        next.add(updated);
        found = true;
      } else {
        next.add(track);
      }
    }
    if (!found) {
      next.add(updated);
    }
    return next;
  }

  Map<String, double> _withoutProgress(
    Map<String, double> progress,
    String trackId,
  ) {
    return {
      for (final entry in progress.entries)
        if (entry.key != trackId) entry.key: entry.value,
    };
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('Connection refused') ||
        message.contains('SocketException')) {
      return '没有连上本地音源服务，请确认 8787 服务正在运行。';
    }
    return message.replaceFirst('Exception: ', '');
  }
}
