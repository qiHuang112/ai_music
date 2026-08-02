import '../data/lan_library_client.dart';
import '../data/music_cache.dart';

class LanSyncFailure {
  const LanSyncFailure({
    required this.trackId,
    required this.title,
    required this.error,
  });

  final String trackId;
  final String title;
  final Object error;
}

class LanSyncProgress {
  const LanSyncProgress({
    required this.completed,
    required this.total,
    required this.currentTitle,
  });

  final int completed;
  final int total;
  final String currentTitle;
}

class LanSyncResult {
  const LanSyncResult({
    required this.total,
    required this.added,
    required this.updated,
    required this.skipped,
    required this.failed,
    required this.failures,
  });

  final int total;
  final int added;
  final int updated;
  final int skipped;
  final int failed;
  final List<LanSyncFailure> failures;
}

class LanSyncUseCase {
  LanSyncUseCase({required this.gateway, required this.cacheStore});

  final LanLibraryGateway gateway;
  final CachedTrackStore cacheStore;

  Future<LanSyncResult> sync(
    String baseUrl, {
    void Function(LanSyncProgress progress)? onProgress,
  }) async {
    final manifest = await gateway.fetchLibrary(baseUrl);
    final tracks = manifest.tracks;
    var nextIndex = 0;
    var completed = 0;
    var added = 0;
    var updated = 0;
    var skipped = 0;
    final failures = <LanSyncFailure>[];

    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        if (index >= tracks.length) {
          return;
        }
        nextIndex += 1;
        final track = tracks[index];
        try {
          final imported = await cacheStore.importLanTrack(
            track,
            baseUrl: baseUrl,
            libraryId: manifest.libraryId,
            gateway: gateway,
          );
          if (imported.skipped) {
            skipped += 1;
          } else if (imported.updated) {
            updated += 1;
          } else {
            added += 1;
          }
        } on Object catch (error) {
          failures.add(
            LanSyncFailure(trackId: track.id, title: track.title, error: error),
          );
        } finally {
          completed += 1;
          onProgress?.call(
            LanSyncProgress(
              completed: completed,
              total: tracks.length,
              currentTitle: track.title,
            ),
          );
        }
      }
    }

    final workerCount = tracks.length < 2 ? tracks.length : 2;
    await Future.wait([for (var i = 0; i < workerCount; i += 1) worker()]);
    return LanSyncResult(
      total: tracks.length,
      added: added,
      updated: updated,
      skipped: skipped,
      failed: failures.length,
      failures: List.unmodifiable(failures),
    );
  }
}
