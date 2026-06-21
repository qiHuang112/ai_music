import 'package:flutter/material.dart';

import '../application/download_queue_controller.dart';
import '../application/music_controller.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'list_search.dart';

enum _DownloadSortMode { initial, downloadedAt }

class DownloadManagerPage extends StatefulWidget {
  const DownloadManagerPage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> {
  _DownloadSortMode _sortMode = _DownloadSortMode.downloadedAt;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final activeTasks = controller.activeDownloadTasks;
        final recentTasks = controller.recentDownloadTasks;
        final cachedTracks = filterTracksByQuery(
          _sortedCachedTracks(controller.cachedTracks),
          _query,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(strings.downloadManager),
            actions: [
              IconButton(
                tooltip: strings.refresh,
                onPressed: controller.isLoadingCache
                    ? null
                    : controller.loadCache,
                icon: controller.isLoadingCache
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                _SectionHeader(title: strings.activeDownloads),
                if (activeTasks.isEmpty)
                  _EmptyLine(text: strings.noDownloads)
                else
                  for (final task in activeTasks)
                    _DownloadTaskTile(controller: controller, task: task),
                _SectionHeader(title: strings.recentDownloads),
                if (recentTasks.isEmpty)
                  _EmptyLine(text: strings.noRecentDownloads)
                else
                  for (final task in recentTasks.reversed)
                    _DownloadTaskTile(controller: controller, task: task),
                _RepairLegacyTile(controller: controller),
                const SizedBox(height: 18),
                ListSearchField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                ),
                _SectionHeader(
                  title: strings.cachedMusic,
                  trailing: _CachedSortButton(
                    value: _sortMode,
                    onChanged: (value) => setState(() => _sortMode = value),
                  ),
                ),
                if (cachedTracks.isEmpty)
                  _EmptyLine(
                    text: _query.trim().isEmpty
                        ? strings.noCachedMusic
                        : strings.noMatchingTracks,
                  )
                else
                  for (var index = 0; index < cachedTracks.length; index += 1)
                    _CachedTrackTile(
                      controller: controller,
                      track: cachedTracks[index],
                      queueTracks: cachedTracks,
                      index: index,
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Track> _sortedCachedTracks(List<Track> tracks) {
    final sorted = [...tracks];
    switch (_sortMode) {
      case _DownloadSortMode.initial:
        sorted.sort(_compareTrackInitial);
        break;
      case _DownloadSortMode.downloadedAt:
        sorted.sort((a, b) {
          final left = a.cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final byTime = right.compareTo(left);
          return byTime == 0 ? _compareTrackInitial(a, b) : byTime;
        });
        break;
    }
    return sorted;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _RepairLegacyTile extends StatelessWidget {
  const _RepairLegacyTile({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return ListTile(
      leading: controller.isRepairingLegacyCache
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_fix_high),
      title: Text(strings.repairLegacy),
      onTap: controller.isRepairingLegacyCache
          ? null
          : controller.repairLegacyCache,
    );
  }
}

class _CachedSortButton extends StatelessWidget {
  const _CachedSortButton({required this.value, required this.onChanged});

  final _DownloadSortMode value;
  final ValueChanged<_DownloadSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return PopupMenuButton<_DownloadSortMode>(
      tooltip: strings.sort,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _DownloadSortMode.initial,
          child: Text(strings.sortByInitial),
        ),
        PopupMenuItem(
          value: _DownloadSortMode.downloadedAt,
          child: Text(strings.sortByDownloadTime),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 18),
            const SizedBox(width: 6),
            Text(
              value == _DownloadSortMode.initial
                  ? strings.sortByInitial
                  : strings.sortByDownloadTime,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: const Icon(Icons.info_outline), title: Text(text));
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({required this.controller, required this.task});

  final MusicController controller;
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final subtitle = [
      if (task.subtitle.isNotEmpty) task.subtitle,
      _taskStatusLabel(strings, task),
      if (task.error.isNotEmpty) task.error,
    ].join(' - ');
    return ListTile(
      leading: _TaskLeading(task: task),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (task.status == DownloadTaskStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: task.progress),
            ),
        ],
      ),
      trailing: task.canCancel
          ? IconButton(
              tooltip: AppStringsScope.of(context).cancel,
              onPressed: () => controller.cancelDownload(task.id),
              icon: const Icon(Icons.close),
            )
          : IconButton(
              tooltip: strings.clear,
              onPressed: () => controller.clearDownloadTask(task.id),
              icon: const Icon(Icons.clear),
            ),
    );
  }
}

class _TaskLeading extends StatelessWidget {
  const _TaskLeading({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    return switch (task.status) {
      DownloadTaskStatus.completed => const Icon(Icons.check_circle),
      DownloadTaskStatus.failed => const Icon(Icons.error_outline),
      DownloadTaskStatus.canceled => const Icon(Icons.cancel_outlined),
      _ => const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }
}

class _CachedTrackTile extends StatelessWidget {
  const _CachedTrackTile({
    required this.controller,
    required this.track,
    required this.queueTracks,
    required this.index,
  });

  final MusicController controller;
  final Track track;
  final List<Track> queueTracks;
  final int index;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return ListTile(
      leading: IconButton.filledTonal(
        tooltip: strings.play,
        onPressed: () =>
            controller.playTrack(track, index: index, queueTracks: queueTracks),
        icon: const Icon(Icons.play_arrow),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          track.artist,
          track.sizeLabel,
        ].where((value) => value.isNotEmpty).join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: strings.delete,
        onPressed: () => controller.deleteCachedTrack(track),
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

int _compareTrackInitial(Track a, Track b) {
  final byTitle = _trackSortKey(a).compareTo(_trackSortKey(b));
  if (byTitle != 0) {
    return byTitle;
  }
  return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
}

String _trackSortKey(Track track) {
  final raw = track.title.trim().isEmpty ? track.artist : track.title;
  return raw.trim().toLowerCase().replaceFirst(
    RegExp(r'^[^a-z0-9\u4e00-\u9fff]+'),
    '',
  );
}

String _taskStatusLabel(AppStrings strings, DownloadTask task) {
  return switch (task.status) {
    DownloadTaskStatus.resolving => strings.statusResolving,
    DownloadTaskStatus.downloading =>
      task.progress == null
          ? strings.statusDownloading
          : strings.downloadingPercent(
              (task.progress! * 100).toStringAsFixed(0),
            ),
    DownloadTaskStatus.completed => strings.statusCompleted,
    DownloadTaskStatus.failed => strings.statusFailed,
    DownloadTaskStatus.canceled => strings.statusCanceled,
  };
}
