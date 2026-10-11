import 'dart:async';

import '../data/auto_source_health.dart';
import '../data/music_cache.dart';
import '../data/music_resolver.dart';
import '../data/provider_request_scheduler.dart';
import 'download_queue_controller.dart';
import 'music_ui_message.dart';
import 'screenshot_matcher.dart';
import 'screenshot_song_parser.dart';

class DownloadUseCaseResult {
  const DownloadUseCaseResult({
    this.cached,
    this.statusMessage,
    this.errorDetail,
    this.failure,
  });

  final CachedTrack? cached;
  final MusicUiMessage? statusMessage;
  final String? errorDetail;
  final Object? failure;
}

class DownloadUseCase {
  const DownloadUseCase({
    required this.resolver,
    required this.cacheStore,
    required this.queue,
  });

  final MusicResolver resolver;
  final CachedTrackStore cacheStore;
  final DownloadQueueController queue;

  Future<DownloadUseCaseResult> downloadCandidate(
    MusicSearchCandidate candidate, {
    MusicQualityLevel quality = MusicQualityLevel.high,
    MusicDataSource? sourceMode,
    bool requireExactIdentity = false,
    required void Function(MusicUiMessage message) onStatus,
    required void Function() onChanged,
    void Function()? onProgressChanged,
  }) async {
    final taskId = queue.taskIdForCandidate(candidate);
    if (queue.hasActiveToken(taskId)) {
      return const DownloadUseCaseResult(
        statusMessage: MusicUiMessage(
          MusicUiMessageCode.downloadAlreadyRunning,
        ),
      );
    }
    final token = queue.start(taskId, candidate);
    // 下载流程分两段：先解析直链，再下载/复用缓存。UI 只关心这里吐出的状态。
    onStatus(
      MusicUiMessage(MusicUiMessageCode.resolving, subject: candidate.name),
    );
    onChanged();
    final sourceHealth = resolver is AutoSourceHealthResolver
        ? resolver as AutoSourceHealthResolver
        : null;
    MusicDataSource? downloadingSource;
    try {
      var resolved = await runZoned(
        () async => sourceHealth != null
            ? await sourceHealth.resolveForSourceMode(
                candidate,
                sourceMode ?? candidate.source,
                quality: quality,
              )
            : resolver is QualitySelectableMusicResolver
            ? await (resolver as QualitySelectableMusicResolver)
                  .resolveAtQuality(candidate, quality)
            : await resolver.resolve(candidate),
        zoneValues: {providerCancellationKey: () => token.isCanceled},
      );
      final attemptedSources = <MusicDataSource>{candidate.source};
      while (true) {
        attemptedSources.add(resolved.source);
        token.throwIfCanceled();
        if ((requireExactIdentity || resolved.source != candidate.source) &&
            !const ScreenshotMatchPolicy().resolvedStillMatches(
              ScreenshotSongDraft(
                imageId: '',
                row: 0,
                title: candidate.name,
                artist: candidate.artist,
                version: '',
                rawText: '',
              ),
              resolved,
            )) {
          throw const AudioValidationException(
            'Resolved song identity changed',
          );
        }
        onStatus(
          MusicUiMessage(
            MusicUiMessageCode.downloading,
            subject: resolved.name,
          ),
        );
        _updateTask(
          taskId,
          (task) => task.copyWith(
            title: resolved.name.isEmpty ? task.title : resolved.name,
            subtitle: resolved.artist.isEmpty ? task.subtitle : resolved.artist,
            status: DownloadTaskStatus.downloading,
            clearProgress: true,
          ),
          onChanged,
        );
        downloadingSource = resolved.source;
        late final CachedTrack cached;
        try {
          cached = await cacheStore.downloadOrReuse(
            resolved,
            onProgress: (progress) {
              final percent = progress.percent;
              onStatus(
                percent == null
                    ? MusicUiMessage(
                        MusicUiMessageCode.downloadingBytes,
                        value: _formatBytes(progress.bytes),
                      )
                    : MusicUiMessage(
                        MusicUiMessageCode.downloadingPercent,
                        value: (percent * 100).toStringAsFixed(0),
                      ),
              );
              queue.update(
                taskId,
                (task) => task.copyWith(
                  status: DownloadTaskStatus.downloading,
                  progress: percent,
                  bytes: progress.bytes,
                  totalBytes: progress.totalBytes,
                ),
              );
              (onProgressChanged ?? onChanged)();
            },
            cancelToken: token,
          );
        } catch (error) {
          token.throwIfCanceled();
          if (error is DownloadCancelledException) rethrow;
          sourceHealth?.reportSourceFailure(resolved.source, error);
          downloadingSource = null;
          final canFallback =
              sourceMode == MusicDataSource.auto &&
              resolver is AutoFallbackMusicResolver &&
              (sourceHealth == null ||
                  sourceHealth.availableAutoSources.any(
                    (source) => !attemptedSources.contains(source),
                  )) &&
              (isSourceServiceFailure(error) ||
                  error is AudioValidationException ||
                  error is AudioRetryAfterException);
          if (!canFallback) rethrow;
          try {
            resolved = await runZoned(
              () => (resolver as AutoFallbackMusicResolver).resolveAlternative(
                candidate,
                excludedSources: attemptedSources,
                quality: quality,
                isCancelled: () => token.isCanceled,
              ),
              zoneValues: {providerCancellationKey: () => token.isCanceled},
            );
          } catch (_) {
            token.throwIfCanceled();
            rethrow;
          }
          token.throwIfCanceled();
          if (attemptedSources.contains(resolved.source)) {
            throw StateError('备用来源已尝试');
          }
          continue;
        }
        token.throwIfCanceled();
        if (!cached.fromCache) {
          sourceHealth?.reportSourceSuccess(resolved.source);
        }
        final statusMessage = MusicUiMessage(
          cached.fromCache
              ? MusicUiMessageCode.alreadyInCache
              : MusicUiMessageCode.downloadedToCache,
        );
        _updateTask(
          taskId,
          (task) => task.copyWith(
            status: DownloadTaskStatus.completed,
            progress: 1,
            bytes: cached.sizeBytes,
            totalBytes: cached.sizeBytes,
            cachedTrackId: cached.cacheId,
            reusedCache: cached.fromCache,
          ),
          onChanged,
        );
        return DownloadUseCaseResult(
          cached: cached,
          statusMessage: statusMessage,
        );
      }
    } catch (exception) {
      // Cancellation may settle before an in-flight resolver reports a network
      // error. Keep the user's terminal state and its original completion day.
      if (token.isCanceled || exception is DownloadCancelledException) {
        _updateTask(
          taskId,
          (task) => task.copyWith(
            status: DownloadTaskStatus.canceled,
            clearProgress: true,
          ),
          onChanged,
        );
        return const DownloadUseCaseResult(
          statusMessage: MusicUiMessage(MusicUiMessageCode.downloadCanceled),
        );
      }
      if (downloadingSource != null) {
        sourceHealth?.reportSourceFailure(downloadingSource, exception);
      }
      final errorDetail = friendlyError(exception);
      _updateTask(
        taskId,
        (task) => task.copyWith(
          status: DownloadTaskStatus.failed,
          error: errorDetail,
        ),
        onChanged,
      );
      return DownloadUseCaseResult(
        errorDetail: errorDetail,
        failure: exception,
      );
    } finally {
      queue.release(taskId);
      onChanged();
    }
  }

  void cancelDownload(String taskId) {
    queue.cancel(taskId);
  }

  void _updateTask(
    String taskId,
    DownloadTask Function(DownloadTask task) update,
    void Function() onChanged,
  ) {
    if (queue.update(taskId, update)) {
      onChanged();
    }
  }
}

String friendlyError(Object error) {
  return error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('Unsupported operation: ', '');
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
