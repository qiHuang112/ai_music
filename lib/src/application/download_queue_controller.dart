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
    this.createdAt,
    this.finishedAt,
    this.reusedCache = false,
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
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final bool reusedCache;

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
    DateTime? finishedAt,
    bool? reusedCache,
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
      createdAt: createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      reusedCache: reusedCache ?? this.reusedCache,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'status': status.name,
    'bytes': bytes,
    'totalBytes': totalBytes,
    'error': error,
    'cachedTrackId': cachedTrackId,
    'createdAt': createdAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'reusedCache': reusedCache,
  };
  static DownloadTask? fromJson(Map<String, dynamic> value) {
    final status = DownloadTaskStatus.values
        .where((s) => s.name == value['status'])
        .firstOrNull;
    if (status == null ||
        status == DownloadTaskStatus.resolving ||
        status == DownloadTaskStatus.downloading ||
        value['id'] is! String ||
        value['id'] == '') {
      return null;
    }
    return DownloadTask(
      id: value['id'] as String,
      title: value['title']?.toString() ?? '',
      subtitle: value['subtitle']?.toString() ?? '',
      status: status,
      bytes: value['bytes'] is num ? (value['bytes'] as num).toInt() : 0,
      totalBytes: value['totalBytes'] is num
          ? (value['totalBytes'] as num).toInt()
          : null,
      error: value['error']?.toString() ?? '',
      cachedTrackId: value['cachedTrackId']?.toString() ?? '',
      createdAt: DateTime.tryParse(value['createdAt']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(value['finishedAt']?.toString() ?? ''),
      reusedCache: value['reusedCache'] == true,
    );
  }
}

class DownloadQueueController {
  DownloadQueueController({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  void Function()? onHistoryChanged;
  final _clearedHistoryIds = <String>{};
  bool _clearedAllHistory = false;
  void restoreHistory(List<DownloadTask> history) {
    if (_clearedAllHistory) return;
    final liveIds = tasks.map((t) => t.id).toSet();
    tasks = [
      for (final task in history)
        if (!task.canCancel &&
            !liveIds.contains(task.id) &&
            !_clearedHistoryIds.contains(task.id))
          task,
      ...tasks,
    ];
  }

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
        createdAt: _now(),
      ),
    );
    return token;
  }

  void cancel(String taskId) {
    if (_cancelTokens[taskId]?.cancel() != true) return;
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
    final previous = taskById(taskId);
    if (previous == null) return false;
    var next = update(previous);
    if (previous.canCancel && !next.canCancel) {
      next = next.copyWith(finishedAt: _now());
    }
    tasks = [
      for (final task in tasks)
        if (task.id == taskId) next else task,
    ];
    if (!next.canCancel &&
        (previous.canCancel || next.status != previous.status)) {
      onHistoryChanged?.call();
    }
    return true;
  }

  void clearTask(String taskId) {
    if (_cancelTokens.containsKey(taskId)) {
      return;
    }
    _clearedHistoryIds.add(taskId);
    tasks = [
      for (final task in tasks)
        if (task.id != taskId) task,
    ];
    onHistoryChanged?.call();
  }

  void clearTerminalTasks() {
    _clearedAllHistory = true;
    tasks = [
      for (final task in tasks)
        if (task.canCancel) task,
    ];
    onHistoryChanged?.call();
  }
}

String _candidateDownloadKey(MusicSearchCandidate candidate) {
  // Ephemeral direct URLs must not split one song into concurrent tasks.
  final id = candidate.id.trim();
  return [
    candidate.source.storageValue,
    candidate.platform.trim().toLowerCase(),
    if (id.isNotEmpty) ...[
      'id',
      id,
    ] else ...[
      'metadata',
      candidate.name.trim().toLowerCase(),
      candidate.artist.trim().toLowerCase(),
    ],
  ].join('|');
}
