import 'app_theme.dart';
import 'date_groups.dart';
import 'package:flutter/material.dart';

import '../application/download_queue_controller.dart';
import '../application/music_controller.dart';
import '../data/music_playlists.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'list_search.dart';
import 'music_thumbnail.dart';
import 'playlist_download_progress.dart';

enum _DownloadSortMode { initial, downloadedAt }

enum _DownloadSection { cached, tasks, playlists }

enum _TaskFilter { all, active, failed, completed, canceled }

class DownloadManagerPage extends StatefulWidget {
  const DownloadManagerPage({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
  });

  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> {
  _DownloadSortMode _sortMode = _DownloadSortMode.downloadedAt;
  final _searchController = TextEditingController();
  String _query = '';
  _DownloadSection _section = _DownloadSection.cached;
  _TaskFilter _taskFilter = _TaskFilter.all;
  final _scrollControllers = [for (var i = 0; i < 3; i++) ScrollController()];
  final _resetOffsets = <_DownloadSection>{};
  String? _dateFilter;
  final _collapsedTasks = <String>{};
  final _collapsedCache = <String>{};
  void _toggle(Set<String> dates, String key) => setState(() {
    if (!dates.remove(key)) dates.add(key);
  });

  @override
  void dispose() {
    _searchController.dispose();
    for (final scroll in _scrollControllers) {
      scroll.dispose();
    }
    super.dispose();
  }

  bool _matchesText(String text) {
    final haystack = text.toLowerCase();
    return _query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(haystack.contains);
  }

  bool _matchesTask(DownloadTask task) =>
      _matchesText('${task.title} ${task.subtitle} ${task.error}') &&
      switch (_taskFilter) {
        _TaskFilter.all => true,
        _TaskFilter.active => task.canCancel,
        _TaskFilter.failed => task.status == DownloadTaskStatus.failed,
        _TaskFilter.completed => task.status == DownloadTaskStatus.completed,
        _TaskFilter.canceled => task.status == DownloadTaskStatus.canceled,
      };

  void _resetScroll(Iterable<_DownloadSection> sections) {
    _resetOffsets.addAll(sections);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_resetOffsets.remove(_section)) return;
      final scroll = _scrollControllers[_section.index];
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  void _openLanSync() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
        maxWidth: 640,
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) =>
                _LanSyncCard(controller: widget.controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return DefaultTabController(
      length: _DownloadSection.values.length,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final activeTasks = controller.activeDownloadTasks
              .where(_matchesTask)
              .toList();
          final recentTasks = controller.recentDownloadTasks
              .where(
                (task) =>
                    _matchesTask(task) &&
                    matchesDateFilter(
                      task.finishedAt ?? task.createdAt,
                      _dateFilter,
                    ),
              )
              .toList();
          final cachedTracks = filterTracksByQuery(
            _sortedCachedTracks(
              controller.cachedTracks
                  .where(
                    (track) => matchesDateFilter(track.cachedAt, _dateFilter),
                  )
                  .toList(),
            ),
            _query,
          );
          final playlists = controller.customPlaylists
              .where((p) => _matchesText(p.name))
              .toList();
          final count = switch (_section) {
            _DownloadSection.cached => cachedTracks.length,
            _DownloadSection.tasks => activeTasks.length + recentTasks.length,
            _DownloadSection.playlists => playlists.length,
          };
          return Scaffold(
            appBar: AppBar(
              titleTextStyle: MusicType.masthead(context, size: 30),
              title: Text(strings.downloadManager),
              actions: [
                IconButton(
                  key: const Key('manager-lan-sync'),
                  tooltip: strings.lanSyncSection,
                  onPressed: _openLanSync,
                  icon: controller.isLanSyncing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded),
                ),
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
              top: false,
              // Lists run on under the floating bottom bars.
              bottom: false,
              child: Column(
                children: [
                  ListSearchField(
                    key: const Key('manager-search'),
                    controller: _searchController,
                    hintText: strings.isZh
                        ? switch (_section) {
                            _DownloadSection.cached => '搜索歌曲、歌手',
                            _DownloadSection.tasks => '搜索任务、歌曲或错误信息',
                            _DownloadSection.playlists => '搜索歌单',
                          }
                        : switch (_section) {
                            _DownloadSection.cached =>
                              'Search songs or artists',
                            _DownloadSection.tasks =>
                              'Search tasks, songs or errors',
                            _DownloadSection.playlists => 'Search playlists',
                          },
                    onChanged: (value) => setState(() {
                      _query = value;
                      _collapsedCache.clear();
                      _collapsedTasks.clear();
                      _resetScroll(_DownloadSection.values);
                    }),
                  ),
                  TabBar(
                    onTap: (index) => setState(() {
                      _section = _DownloadSection.values[index];
                      FocusScope.of(context).unfocus();
                      if (_resetOffsets.contains(_section)) {
                        _resetScroll([_section]);
                      }
                    }),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    tabs: [
                      for (final section in _DownloadSection.values)
                        Tab(
                          key: ValueKey('manager-tab-${section.name}'),
                          height:
                              MediaQuery.textScalerOf(context).scale(22) + 24,
                          text: switch (section) {
                            _DownloadSection.cached =>
                              strings.isZh ? '已下载' : 'Downloaded',
                            _DownloadSection.tasks =>
                              strings.isZh ? '任务' : 'Tasks',
                            _DownloadSection.playlists =>
                              strings.isZh ? '歌单' : 'Playlists',
                          },
                        ),
                    ],
                  ),
                  Padding(
                    padding: MusicUi.horizontalInsets,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.isZh
                                ? '$count ${_section == _DownloadSection.cached
                                      ? '首歌曲'
                                      : _section == _DownloadSection.tasks
                                      ? '个任务'
                                      : '个歌单'}'
                                : '$count ${_section.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (_section != _DownloadSection.playlists)
                          DateFilterButton(
                            dates: _section == _DownloadSection.cached
                                ? controller.cachedTracks.map((t) => t.cachedAt)
                                : controller.recentDownloadTasks.map(
                                    (t) => t.finishedAt ?? t.createdAt,
                                  ),
                            value: _dateFilter,
                            zh: strings.isZh,
                            onChanged: (value) => setState(() {
                              _dateFilter = value;
                              _collapsedTasks.clear();
                              _collapsedCache.clear();
                              _resetScroll([
                                _DownloadSection.cached,
                                _DownloadSection.tasks,
                              ]);
                            }),
                          ),
                        if (_section == _DownloadSection.cached)
                          _CachedSortButton(
                            value: _sortMode,
                            onChanged: (value) => setState(() {
                              _sortMode = value;
                              _resetScroll([_DownloadSection.cached]);
                            }),
                          ),
                      ],
                    ),
                  ),
                  if (_section == _DownloadSection.tasks)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: MusicUi.horizontalInsets,
                      child: Row(
                        children: [
                          for (final filter in _TaskFilter.values)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 8,
                                bottom: 8,
                              ),
                              child: ChoiceChip(
                                key: ValueKey('manager-task-${filter.name}'),
                                label: Text(switch (filter) {
                                  _TaskFilter.all =>
                                    strings.isZh ? '全部' : 'All',
                                  _TaskFilter.active =>
                                    strings.isZh ? '进行中' : 'Active',
                                  _TaskFilter.failed =>
                                    strings.isZh ? '失败' : 'Failed',
                                  _TaskFilter.completed =>
                                    strings.isZh ? '已完成' : 'Completed',
                                  _TaskFilter.canceled =>
                                    strings.isZh ? '已取消' : 'Canceled',
                                }),
                                selected: _taskFilter == filter,
                                onSelected: (_) => setState(() {
                                  _taskFilter = filter;
                                  _resetScroll([_DownloadSection.tasks]);
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: CustomScrollView(
                      key: PageStorageKey('manager-${_section.name}'),
                      controller: _scrollControllers[_section.index],
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        if (_section == _DownloadSection.cached)
                          ..._cacheSlivers(controller, cachedTracks, strings),
                        if (_section == _DownloadSection.tasks)
                          ..._taskSlivers(
                            controller,
                            activeTasks,
                            recentTasks,
                            strings,
                          ),
                        if (_section == _DownloadSection.playlists)
                          SliverPadding(
                            padding: MusicUi.horizontalInsets,
                            sliver: playlists.isEmpty
                                ? SliverToBoxAdapter(
                                    child: _EmptyLine(
                                      text: strings.isZh
                                          ? '没有符合条件的歌单'
                                          : 'No matching playlists',
                                    ),
                                  )
                                : SliverList.builder(
                                    itemCount: playlists.length,
                                    itemBuilder: (context, index) =>
                                        _playlistCard(
                                          controller,
                                          playlists[index],
                                          strings,
                                        ),
                                  ),
                          ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 32 + MediaQuery.paddingOf(context).bottom,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _playlistCard(
    MusicController controller,
    MusicPlaylist playlist,
    AppStrings strings,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final originCover = playlist.entries
        .map((entry) => entry.song?.coverUrl ?? '')
        .where((url) => url.isNotEmpty)
        .firstOrNull;
    final artwork =
        (originCover == null ? null : Uri.tryParse(originCover)) ??
        controller
            .tracksForPlaylist(playlist)
            .where((track) => track.artworkUri != null)
            .firstOrNull
            ?.artworkUri;
    final downloading = controller.isPlaylistDownloading(playlist);
    return Card(
      key: ValueKey('manager-playlist-${playlist.id}'),
      color: colors.surfaceContainerLowest,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        horizontalTitleGap: 12,
        onTap: () => widget.onOpenPlaylist(playlist),
        leading: MusicThumbnail(
          uri: artwork,
          label: playlist.name,
          size: 56,
          radius: 14,
        ),
        title: Text(
          playlist.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.playlistDownloadCounts(
                  playlist.entries.length,
                  controller.cachedCountForPlaylist(playlist),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (controller.playlistDownloadProgress(playlist) != null) ...[
                const SizedBox(height: 8),
                PlaylistDownloadProgressView(
                  controller: controller,
                  playlist: playlist,
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton.filledTonal(
          key: ValueKey('manager-download-${playlist.id}'),
          tooltip: strings.downloadAllPlaylist,
          onPressed: downloading ? null : () => _downloadPlaylist(playlist),
          style: IconButton.styleFrom(
            backgroundColor: colors.secondaryContainer.withValues(alpha: .55),
            foregroundColor: colors.primary,
          ),
          icon: downloading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded, size: 21),
        ),
      ),
    );
  }

  List<Widget> _taskSlivers(
    MusicController controller,
    List<DownloadTask> active,
    List<DownloadTask> recent,
    AppStrings strings,
  ) => [
    SliverPadding(
      padding: MusicUi.horizontalInsets,
      sliver: SliverList.list(
        children: [
          if (_taskFilter == _TaskFilter.all ||
              _taskFilter == _TaskFilter.active) ...[
            _SectionHeader(title: strings.activeDownloads),
            if (active.isEmpty) _EmptyLine(text: strings.noDownloads),
          ],
        ],
      ),
    ),
    if (active.isNotEmpty)
      SliverPadding(
        padding: MusicUi.horizontalInsets,
        sliver: SliverList.builder(
          itemCount: active.length,
          itemBuilder: (context, index) =>
              _DownloadTaskTile(controller: controller, task: active[index]),
        ),
      ),
    if (_taskFilter != _TaskFilter.active)
      SliverPadding(
        padding: MusicUi.horizontalInsets,
        sliver: SliverToBoxAdapter(
          child: _SectionHeader(title: strings.recentDownloads),
        ),
      ),
    if (recent.isEmpty && _taskFilter != _TaskFilter.active)
      SliverToBoxAdapter(
        child: _EmptyLine(
          text:
              _query.trim().isEmpty &&
                  _dateFilter == null &&
                  _taskFilter == _TaskFilter.all
              ? strings.noRecentDownloads
              : (strings.isZh ? '没有符合条件的任务' : 'No matching tasks'),
        ),
      ),
    for (final group in groupByDateHierarchy(
      [...recent]..sort(
        (a, b) => (b.finishedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
          a.finishedAt ?? a.createdAt ?? DateTime(1970),
        ),
      ),
      (task) => task.finishedAt ?? task.createdAt,
    ))
      DateHierarchySliver<DownloadTask>(
        key: ValueKey('tasks-${group.key}'),
        bucket: group,
        summary: (items) => _taskCounts(items, strings.isZh),
        zh: strings.isZh,
        toggled: _collapsedTasks,
        onToggle: (key) => _toggle(_collapsedTasks, key),
        expandInitially:
            _dateFilter != null ||
            _query.trim().isNotEmpty ||
            _taskFilter != _TaskFilter.all,
        itemBuilder: (context, task) => Padding(
          padding: MusicUi.horizontalInsets,
          child: _DownloadTaskTile(controller: controller, task: task),
        ),
      ),
  ];

  List<Widget> _cacheSlivers(
    MusicController controller,
    List<Track> tracks,
    AppStrings strings,
  ) => [
    if (tracks.isEmpty)
      SliverToBoxAdapter(
        child: _EmptyLine(
          text: _query.trim().isEmpty && _dateFilter == null
              ? strings.noCachedMusic
              : strings.noMatchingTracks,
        ),
      ),
    if (_sortMode == _DownloadSortMode.downloadedAt)
      for (final group in groupByDateHierarchy(
        tracks.indexed,
        (item) => item.$2.cachedAt,
      ))
        DateHierarchySliver<(int, Track)>(
          key: ValueKey('cached-${group.key}'),
          bucket: group,
          summary: (items) => '${items.length} ${strings.isZh ? '首' : 'songs'}',
          zh: strings.isZh,
          toggled: _collapsedCache,
          onToggle: (key) => _toggle(_collapsedCache, key),
          expandInitially: _dateFilter != null || _query.trim().isNotEmpty,
          itemBuilder: (context, item) => Padding(
            padding: MusicUi.horizontalInsets,
            child: _CachedTrackTile(
              controller: controller,
              track: item.$2,
              queueTracks: tracks,
              index: item.$1,
            ),
          ),
        ),
    if (_sortMode == _DownloadSortMode.initial)
      SliverPadding(
        padding: MusicUi.horizontalInsets,
        sliver: SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) => _CachedTrackTile(
            controller: controller,
            track: tracks[index],
            queueTracks: tracks,
            index: index,
          ),
        ),
      ),
  ];

  String _taskCounts(List<DownloadTask> tasks, bool zh) {
    final downloaded = tasks
        .where(
          (t) => t.status == DownloadTaskStatus.completed && !t.reusedCache,
        )
        .length;
    final reused = tasks
        .where((t) => t.status == DownloadTaskStatus.completed && t.reusedCache)
        .length;
    final failed = tasks
        .where((t) => t.status == DownloadTaskStatus.failed)
        .length;
    final canceled = tasks
        .where((t) => t.status == DownloadTaskStatus.canceled)
        .length;
    return [
      zh ? '下载 $downloaded 首' : '$downloaded downloaded',
      if (reused > 0) zh ? '复用缓存 $reused 首' : '$reused reused',
      if (failed > 0) zh ? '失败 $failed' : '$failed failed',
      if (canceled > 0) zh ? '取消 $canceled' : '$canceled canceled',
    ].join(' · ');
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

  Future<void> _downloadPlaylist(MusicPlaylist playlist) async {
    final result = await widget.controller.downloadPlaylist(playlist);
    if (!mounted) return;
    final strings = AppStringsScope.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            strings.playlistDownloadSummary(
              result.downloaded,
              result.skipped,
              result.failed,
            ),
          ),
        ),
      );
  }
}

class _LanSyncCard extends StatelessWidget {
  const _LanSyncCard({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final result = controller.lastLanSyncResult;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget status(IconData icon, Widget content, {bool error = false}) =>
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: error
                ? colors.errorContainer.withValues(alpha: .45)
                : colors.secondaryContainer.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: error ? colors.error : colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(child: content),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.devices_rounded,
                  color: colors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  strings.lanSyncSection,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: strings.isZh ? '关闭' : 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            strings.isZh
                ? '从同一网络的设备同步歌曲和歌单。'
                : 'Sync songs and playlists from a device on the same network.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.dns_outlined,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.isZh ? '设备地址' : 'Device address',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.lanLibraryUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.isLanSyncing
                  ? null
                  : controller.syncLanLibrary,
              icon: const Icon(Icons.sync_rounded, size: 20),
              label: Text(
                controller.isLanSyncing
                    ? (strings.isZh ? '正在同步' : 'Syncing')
                    : strings.scanAndSync,
              ),
            ),
          ),
          if (controller.isLanSyncing)
            status(
              Icons.sync_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.lanSyncProgress(
                      controller.lanSyncCompleted,
                      controller.lanSyncTotal,
                      controller.lanSyncCurrentTitle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: controller.lanSyncTotal > 0
                          ? controller.lanSyncCompleted /
                                controller.lanSyncTotal
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          if (result != null)
            status(
              Icons.check_circle_outline_rounded,
              Text(
                strings.lanSyncSummary(
                  result.added,
                  result.updated,
                  result.skipped,
                  result.failed,
                  playlistsCreated: result.playlistsCreated,
                  playlistsUpdated: result.playlistsUpdated,
                ),
              ),
            ),
          if (result?.playlistError != null)
            status(
              Icons.info_outline_rounded,
              Text(strings.lanPlaylistMergeFailed),
              error: true,
            ),
          if (controller.lanSyncError != null)
            status(
              Icons.error_outline_rounded,
              Text(controller.lanSyncError!),
              error: true,
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
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
      child: MusicUi.compactActions(context)
          ? const SizedBox.square(dimension: 48, child: Icon(Icons.sort))
          : Padding(
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
    if (!task.canCancel) return _buildTask(context, task);
    return AnimatedBuilder(
      animation: controller.downloadProgressChanges,
      builder: (context, _) => _buildTask(
        context,
        controller.downloadQueue.taskById(task.id) ?? task,
      ),
    );
  }

  Widget _buildTask(BuildContext context, DownloadTask task) {
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
