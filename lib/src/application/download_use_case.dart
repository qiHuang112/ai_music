import '../data/music_cache.dart';
import '../data/music_resolver.dart';
import 'download_queue_controller.dart';
import 'music_ui_message.dart';

class DownloadUseCaseResult {
  const DownloadUseCaseResult({
    this.cached,
    this.statusMessage,
    this.errorDetail,
  });

  final CachedTrack? cached;
  final MusicUiMessage? statusMessage;
  final String? errorDetail;
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
    required void Function(MusicUiMessage message) onStatus,
    required void Function() onChanged,
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
    try {
      final resolved = await resolver.resolve(candidate);
      token.throwIfCanceled();
      onStatus(
        MusicUiMessage(MusicUiMessageCode.downloading, subject: resolved.name),
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
      final cached = await cacheStore.downloadOrReuse(
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
          onChanged();
        },
        cancelToken: token,
      );
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
        ),
        onChanged,
      );
      return DownloadUseCaseResult(
        cached: cached,
        statusMessage: statusMessage,
      );
    } on DownloadCancelledException {
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
    } catch (exception) {
      final errorDetail = friendlyError(exception);
      _updateTask(
        taskId,
        (task) => task.copyWith(
          status: DownloadTaskStatus.failed,
          error: errorDetail,
        ),
        onChanged,
      );
      return DownloadUseCaseResult(errorDetail: errorDetail);
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
