import '../data/music_cache.dart';
import '../data/music_resolver.dart';

enum DownloadTaskStatus { resolving, downloading, completed, failed, canceled }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    this.progress,
    this.bytes = 0,
    this.totalBytes,
    this.error = '',
    this.cachedTrackId = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final DownloadTaskStatus status;
  final double? progress;
  final int bytes;
  final int? totalBytes;
  final String error;
  final String cachedTrackId;

  bool get canCancel {
    return status == DownloadTaskStatus.resolving ||
        status == DownloadTaskStatus.downloading;
  }

  DownloadTask copyWith({
    String? title,
    String? subtitle,
    DownloadTaskStatus? status,
    double? progress,
    bool clearProgress = false,
    int? bytes,
    int? totalBytes,
    String? error,
    String? cachedTrackId,
  }) {
    return DownloadTask(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      status: status ?? this.status,
      progress: clearProgress ? null : progress ?? this.progress,
      bytes: bytes ?? this.bytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
      cachedTrackId: cachedTrackId ?? this.cachedTrackId,
    );
  }
}

class DownloadQueueController {
  final Map<String, DownloadCancelToken> _cancelTokens = {};

  List<DownloadTask> tasks = const [];
  MusicSearchCandidate? busyCandidate;
  Set<String> busyCandidateKeys = const {};

  List<DownloadTask> get activeTasks {
    return tasks.where((task) => task.canCancel).toList(growable: false);
  }

  List<DownloadTask> get recentTasks {
    return tasks.where((task) => !task.canCancel).toList(growable: false);
  }

  List<DownloadTask> get visibleTasks {
    return List<DownloadTask>.unmodifiable(tasks);
  }

  String taskIdForCandidate(MusicSearchCandidate candidate) {
    return _candidateDownloadKey(candidate);
  }

  bool hasActiveToken(String taskId) => _cancelTokens.containsKey(taskId);

  DownloadTask? taskById(String taskId) {
    return tasks.where((task) => task.id == taskId).firstOrNull;
  }

  DownloadCancelToken start(String taskId, MusicSearchCandidate candidate) {
    final token = DownloadCancelToken();
    _cancelTokens[taskId] = token;
    busyCandidateKeys = {...busyCandidateKeys, taskId};
    busyCandidate = candidate;
    upsert(
      DownloadTask(
        id: taskId,
        title: candidate.name.isEmpty ? candidate.keyword : candidate.name,
        subtitle: candidate.artist,
        status: DownloadTaskStatus.resolving,
      ),
    );
    return token;
  }

  void cancel(String taskId) {
    _cancelTokens[taskId]?.cancel();
    update(
      taskId,
      (task) => task.copyWith(status: DownloadTaskStatus.canceled),
    );
  }

  void release(String taskId) {
    _cancelTokens.remove(taskId);
    busyCandidateKeys = {
      for (final key in busyCandidateKeys)
        if (key != taskId) key,
    };
    if (busyCandidate != null &&
        _candidateDownloadKey(busyCandidate!) == taskId) {
      busyCandidate = null;
    }
  }

  bool isCandidateDownloading(MusicSearchCandidate candidate) {
    return busyCandidateKeys.contains(_candidateDownloadKey(candidate));
  }

  void upsert(DownloadTask task) {
    tasks = [
      for (final item in tasks)
        if (item.id != task.id) item,
      task,
    ];
  }

  bool update(String taskId, DownloadTask Function(DownloadTask task) update) {
    var changed = false;
    tasks = [
      for (final task in tasks)
        if (task.id == taskId) ...[update(task)] else task,
    ];
    changed = tasks.any((task) => task.id == taskId);
    return changed;
  }

  void clearTask(String taskId) {
    if (_cancelTokens.containsKey(taskId)) {
      return;
    }
    tasks = [
      for (final task in tasks)
        if (task.id != taskId) task,
    ];
  }

  void clearTerminalTasks() {
    tasks = [
      for (final task in tasks)
        if (task.canCancel) task,
    ];
  }
}

String _candidateDownloadKey(MusicSearchCandidate candidate) {
  return [
    candidate.source.name,
    candidate.platform,
    candidate.id,
    candidate.link,
    candidate.name,
    candidate.artist,
  ].join('|');
}
