import 'dart:async';

import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../application/online_playlist_tasks.dart';
import '../data/saved_online_track.dart';
import '../application/online_playlist_search.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/online_playlists.dart';
import 'app_localizations.dart';

class OnlinePlaylistSearchPanel extends StatelessWidget {
  const OnlinePlaylistSearchPanel({
    super.key,
    required this.search,
    required this.controller,
    required this.onOpenPlaylist,
  });
  final OnlinePlaylistSearch search;
  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    final items = search.items;
    return Column(
      children: [
        for (final source in search.errors)
          ListTile(
            dense: true,
            title: Text(
              zh ? '${source.label}暂时搜索失败' : '${source.label}: search failed',
            ),
            trailing: TextButton(
              onPressed: () => search.retry(source),
              child: Text(zh ? '重试' : 'Retry'),
            ),
          ),
        if (search.isLoading) const LinearProgressIndicator(),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    search.query.isEmpty
                        ? (zh
                              ? '搜索网易云、QQ 音乐的歌单'
                              : 'Search NetEase and QQ Music playlists')
                        : search.isLoading
                        ? (zh ? '正在搜歌单…' : 'Searching playlists…')
                        : search.errors.isNotEmpty
                        ? (zh ? '搜索失败，请重试' : 'Search failed. Please retry.')
                        : (zh ? '没有找到相关歌单' : 'No playlists found'),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: search.hasMore
                              ? TextButton(
                                  onPressed: search.isLoading
                                      ? null
                                      : search.loadMore,
                                  child: Text(zh ? '加载更多' : 'Load more'),
                                )
                              : Text(zh ? '已显示全部结果' : 'All results shown'),
                        ),
                      );
                    }
                    final item = items[index];
                    return ListTile(
                      key: ValueKey(item.key),
                      leading: _PlaylistCover(url: item.coverUrl),
                      title: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.source.label} · ${item.creator}\n${item.trackCount} ${zh ? '首' : 'songs'}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OnlinePlaylistPage(
                            playlist: item,
                            repository: search.repository,
                            controller: controller,
                            onOpenPlaylist: onOpenPlaylist,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.queue_music, size: 36);
    final uri = Uri.tryParse(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 52,
        child: uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
            ? Image.network(
                uri.replace(scheme: 'https').toString(),
                headers: {
                  'User-Agent': 'Mozilla/5.0',
                  'Referer': uri.host.endsWith('.music.126.net')
                      ? 'https://music.163.com/'
                      : 'https://y.qq.com/',
                },
                cacheWidth: 192,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class OnlinePlaylistPage extends StatefulWidget {
  const OnlinePlaylistPage({
    super.key,
    required this.playlist,
    required this.repository,
    required this.controller,
    this.onOpenPlaylist,
  });
  final OnlinePlaylist playlist;
  final OnlinePlaylistRepository repository;
  final MusicController controller;
  final ValueChanged<MusicPlaylist>? onOpenPlaylist;
  @override
  State<OnlinePlaylistPage> createState() => _OnlinePlaylistPageState();
}

class _OnlinePlaylistPageState extends State<OnlinePlaylistPage> {
  late final OnlinePlaylistTask _task;
  String? _notice;
  bool get _busy => _task.matching || _task.saving;
  bool get _zh => AppStringsScope.of(context).isZh;

  @override
  void initState() {
    super.initState();
    _task = widget.controller.onlinePlaylistTasks.obtain(
      widget.playlist,
      widget.repository,
    );
    _task.addListener(_onTaskChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showUnavailableToast(),
    );
  }

  void _onTaskChanged() {
    if (!mounted) return;
    setState(() {});
    _showUnavailableToast();
  }

  void _showUnavailableToast() {
    if (!mounted ||
        _task.unavailableNotified ||
        (_task.detail?.unavailable ?? 0) == 0) {
      return;
    }
    _task.unavailableNotified = true;
    final detail = _task.detail!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 76),
        content: Text(
          _zh
              ? '已读取 ${detail.songs.length} 首，另 ${detail.unavailable} 首暂无法读取，不会导入。'
              : '${detail.songs.length} loaded; ${detail.unavailable} unavailable songs will not be imported.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _task.removeListener(_onTaskChanged);
    super.dispose();
  }

  Future<void> _load() => _task.load();

  @override
  Widget build(BuildContext context) {
    final zh = _zh;
    final detail = _task.detail;
    final ready = _task.selected
        .where(
          (i) =>
              _task.choices.containsKey(i) && !_task.savedRows.containsKey(i),
        )
        .length;
    return PopScope(
      canPop: !_task.saving || _task.autoSyncEnabled,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (detail != null) ...[
              Text(
                zh
                    ? '已选 ${_task.selected.length} 首'
                    : '${_task.selected.length} selected',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Tooltip(
                message: zh ? '全选' : 'Select all',
                child: Checkbox(
                  key: const Key('playlist-select-all'),
                  value:
                      _task.selected.length == detail.songs.length &&
                      detail.songs.isNotEmpty,
                  onChanged: _task.saving || detail.songs.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _task.selected.addAll(
                                Iterable.generate(detail.songs.length),
                              );
                            } else {
                              _task.selected.clear();
                            }
                          });
                          _task.changed();
                          unawaited(_task.syncReady());
                        },
                ),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: _task.loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        zh
                            ? '读取曲目 ${_task.loaded} / ${_task.loadTotal}'
                            : 'Loading songs ${_task.loaded} / ${_task.loadTotal}',
                      ),
                    ],
                  ),
                )
              : _task.loadFailed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        zh ? '歌单读取失败，可能暂不可访问' : 'Unable to read this playlist',
                      ),
                      TextButton(
                        onPressed: _load,
                        child: Text(zh ? '重试' : 'Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    ListTile(
                      leading: _PlaylistCover(url: widget.playlist.coverUrl),
                      title: Text(widget.playlist.source.label),
                      subtitle: Text(
                        '${widget.playlist.creator} · ${detail!.total} ${zh ? '首' : 'songs'}',
                      ),
                    ),
                    if (_notice != null) _Message(text: _notice!),
                    if (_task.autoSyncError)
                      _Message(
                        text: _task.destination == null
                            ? (zh
                                  ? '新建歌单失败，匹配结果已保留，请重试。'
                                  : 'Could not create playlist. Matches are retained; retry.')
                            : (zh
                                  ? '自动同步失败，匹配结果已保留，请重试同步。'
                                  : 'Auto sync failed. Matches are retained; retry.'),
                      ),
                    if (_busy) ...[
                      LinearProgressIndicator(
                        value: _task.saving || _task.matchTotal == 0
                            ? null
                            : _task.completed / _task.matchTotal,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _task.saving
                                ? (zh ? '正在保存…' : 'Saving…')
                                : (zh
                                      ? '正在匹配 ${_task.completed} / ${_task.matchTotal}'
                                      : 'Matching ${_task.completed} / ${_task.matchTotal}'),
                          ),
                          if (_task.matching)
                            TextButton(
                              onPressed: _cancel,
                              child: Text(zh ? '暂停' : 'Pause'),
                            ),
                        ],
                      ),
                    ],
                    Expanded(
                      child: detail.songs.isEmpty
                          ? Center(
                              child: Text(
                                zh
                                    ? '没有可导入的歌曲'
                                    : 'No songs available to import',
                              ),
                            )
                          : ListView.builder(
                              itemCount: detail.songs.length,
                              itemBuilder: (context, index) =>
                                  _songRow(index, detail.songs[index]),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          if (_task.destination != null)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _task.saving
                                    ? null
                                    : _openDestination,
                                icon: const Icon(Icons.open_in_new),
                                label: Text(zh ? '打开歌单' : 'Open playlist'),
                              ),
                            ),
                          if (_task.destination == null ||
                              (ready > 0 && !_task.autoSyncEnabled))
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    _task.saving ||
                                        (_task.destination != null &&
                                            ready == 0) ||
                                        (_task.destination == null &&
                                            detail.songs.isEmpty)
                                    ? null
                                    : _task.destination == null
                                    ? _task.startAutoSync
                                    : () => _import(_task.destination),
                                icon: const Icon(Icons.playlist_add),
                                label: Text(
                                  _task.destination == null
                                      ? (zh ? '新建歌单' : 'New playlist')
                                      : (zh
                                            ? '继续导入($ready)'
                                            : 'Import $ready more'),
                                ),
                              ),
                            ),
                          if (_task.destination == null)
                            Expanded(
                              child: TextButton(
                                onPressed: _task.saving || ready == 0
                                    ? null
                                    : _chooseTarget,
                                child: Text(zh ? '加入歌单' : 'Add to playlist'),
                              ),
                            ),
                          if (_task.autoSyncError && _task.destination != null)
                            IconButton(
                              onPressed: _task.saving
                                  ? null
                                  : _task.retryAutoSync,
                              tooltip: zh ? '重试同步' : 'Retry sync',
                              icon: const Icon(Icons.sync_problem),
                            ),
                          if (!_task.matching &&
                              _task.detail!.songs.asMap().keys.any(
                                (i) => !_task.choices.containsKey(i),
                              ))
                            IconButton(
                              onPressed: _task.saving ? null : _matchPending,
                              tooltip: zh ? '重试未匹配歌曲' : 'Retry unmatched songs',
                              icon: const Icon(Icons.refresh),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _songRow(int index, OnlinePlaylistSong song) {
    final zh = _zh;
    final match = _task.matches[index];
    final choice = _task.choices[index];
    final candidates =
        match?.result?.candidates ?? const <MusicSearchCandidate>[];
    final review =
        choice != null &&
        match?.result?.needsReview == true &&
        !_task.reviewed.contains(index);
    final saved = _task.savedRows.containsKey(index);
    final status = choice != null
        ? '${zh ? '已选资源' : 'Selected'}：${choice.name} / ${choice.artist} · ${choice.sourceLabel}'
        : match?.serviceFailed == true
        ? (zh ? '搜索失败，可重试' : 'Search failed; retry')
        : match != null
        ? (zh ? '未找到候选' : 'No matches')
        : (zh ? (_task.matching ? '正在匹配…' : '尚未匹配') : 'Waiting for match');
    return Column(
      children: [
        ListTile(
          tileColor: review
              ? Theme.of(
                  context,
                ).colorScheme.tertiaryContainer.withValues(alpha: .4)
              : null,
          leading: saved
              ? Tooltip(
                  message: zh ? '已导入' : 'Imported',
                  child: const Icon(Icons.check_circle_outline),
                )
              : Checkbox(
                  key: ValueKey('playlist-song-checkbox-$index'),
                  value: _task.selected.contains(index),
                  onChanged: _task.saving
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _task.selected.add(index);
                            } else {
                              _task.selected.remove(index);
                            }
                          });
                          _task.changed();
                          unawaited(_task.syncReady());
                        },
                ),
          title: Text('${index + 1}. ${song.title}'),
          subtitle: Text(
            '${song.artist}\n$status'
            '${review ? (zh ? '\n⚠ 需核对 · 点击展开候选' : '\n⚠ Check match · tap to expand') : ''}'
            '${candidates.isNotEmpty ? (zh ? '\n候选 ${candidates.length} 首${saved ? ' · 更换会更新「${_task.destination?.name}」' : ''}' : '\n${candidates.length} choices') : ''}',
          ),
          trailing: candidates.isNotEmpty
              ? Icon(
                  _task.expanded.contains(index)
                      ? Icons.expand_less
                      : Icons.expand_more,
                )
              : null,
          onTap: candidates.isEmpty
              ? null
              : () => setState(() {
                  if (!_task.expanded.remove(index)) _task.expanded.add(index);
                }),
        ),
        if (_task.expanded.contains(index))
          for (final candidate in candidates)
            ListTile(
              dense: true,
              title: Text(candidate.name),
              subtitle: Text('${candidate.artist} · ${candidate.sourceLabel}'),
              trailing: Icon(
                choice != null && _trackId(choice) == _trackId(candidate)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: _task.saving
                  ? null
                  : () => _chooseCandidate(index, candidate),
            ),
        const Divider(height: 1),
      ],
    );
  }

  void _openDestination() {
    final current = widget.controller.customPlaylists
        .where((p) => p.id == _task.destination?.id)
        .firstOrNull;
    if (current == null) {
      setState(
        () => _notice = _zh
            ? '目标歌单已被删除。'
            : 'The destination playlist was deleted.',
      );
      return;
    }
    widget.onOpenPlaylist?.call(current);
  }

  String _trackId(MusicSearchCandidate candidate) =>
      SavedOnlineTrack(candidate: candidate).trackId;

  Future<void> _chooseCandidate(
    int index,
    MusicSearchCandidate candidate,
  ) async {
    final previous = _task.savedRows[index];
    final next = _trackId(candidate);
    if (previous != null) {
      final removePrevious =
          previous != next &&
          widget.controller.onlinePlaylistTasks.canRemoveSavedMatch(
            _task,
            index,
            previous,
          );
      _task.saving = true;
      _task.changed();
      try {
        final result = await widget.controller.replaceImportedCandidate(
          _task.destination!,
          previous,
          candidate,
          removePrevious: removePrevious,
        );
        _task.destination = result.playlist;
        if (removePrevious) {
          widget.controller.onlinePlaylistTasks.forgetOwnedMatch(
            _task.destination!.id,
            previous,
          );
        }
        _task.ownedTrackIds.addAll(result.addedTrackIds);
        _task.savedRows[index] = next;
        _task.choices[index] = candidate;
        _task.reviewed.add(index);
        _task.selected.add(index);
        if (mounted) setState(() => _notice = null);
      } catch (_) {
        if (mounted) {
          setState(() {
            _notice = _zh
                ? '更换保存失败，原匹配未改动，请重试。'
                : 'Could not save. Original match kept; retry.';
          });
        }
        return;
      } finally {
        _task.saving = false;
        _task.changed();
        if (_task.autoSyncEnabled) unawaited(_task.syncReady());
      }
      return;
    }
    _task.choices[index] = candidate;
    _task.reviewed.add(index);
    _task.selected.add(index);
    _task.changed();
    if (mounted) setState(() => _notice = null);
    unawaited(_task.syncReady());
  }

  Future<void> _matchPending() {
    setState(() => _notice = null);
    return _task.matchPending();
  }

  void _cancel() {
    _task.pause();
    setState(
      () => _notice = _task.autoSyncEnabled
          ? (_zh
                ? '已暂停匹配，已匹配歌曲会自动同步。'
                : 'Matching paused. Matched songs will sync automatically.')
          : (_zh
                ? '已暂停匹配，可核对并导入已有结果。'
                : 'Matching paused. You can review and import ready matches.'),
    );
  }

  Future<void> _chooseTarget() async {
    final playlists = widget.controller.customPlaylists;
    final target = await showModalBottomSheet<MusicPlaylist>(
      context: context,
      builder: (context) => SafeArea(
        child: playlists.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _zh
                      ? '还没有歌单，请先使用“导入为新歌单”。'
                      : 'No playlists yet. Import as a new playlist first.',
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final playlist in playlists)
                    ListTile(
                      title: Text(playlist.name),
                      subtitle: Text(
                        '${playlist.trackIds.length} ${_zh ? '首' : 'songs'}',
                      ),
                      onTap: () => Navigator.pop(context, playlist),
                    ),
                ],
              ),
      ),
    );
    if (!mounted || target == null) return;
    await _import(target);
  }

  Future<void> _import(MusicPlaylist? target) async {
    if (_task.saving) return;
    final zh = _zh;
    final selected =
        _task.selected
            .where(
              (i) =>
                  _task.choices.containsKey(i) &&
                  !_task.savedRows.containsKey(i),
            )
            .toList()
          ..sort();
    if (selected.isEmpty) return;
    final candidates = [for (final index in selected) _task.choices[index]!];
    setState(() => _task.saving = true);
    try {
      final result = await widget.controller.importPlaylistSelection(
        widget.playlist.name,
        candidates,
        target: target,
      );
      if (result.playlist == null) throw StateError('Playlist was not saved');
      if (!mounted) return;
      _task.destination = result.playlist;
      _task.ownedTrackIds.addAll(result.addedTrackIds);
      for (final index in selected) {
        _task.savedRows[index] = _trackId(_task.choices[index]!);
      }
      setState(() {
        _task.saving = false;
        _notice = null;
        _task.changed();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _task.saving = false;
        _notice = zh
            ? '保存失败，匹配结果已保留，请重试导入。'
            : 'Save failed. Matches are retained; retry import.';
      });
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text),
  );
}

/// Only this strip rebuilds for background progress, not the home library.
class OnlinePlaylistTaskEntry extends StatelessWidget {
  const OnlinePlaylistTaskEntry({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
  });
  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.onlinePlaylistTasks,
    builder: (context, _) {
      final tasks = controller.onlinePlaylistTasks.tasks;
      if (tasks.isEmpty) return const SizedBox.shrink();
      final zh = AppStringsScope.of(context).isZh;
      final active = tasks.where((t) => t.busy).length;
      if (active == 0) return const SizedBox.shrink();
      final matched = tasks.fold<int>(0, (sum, t) => sum + t.choices.length);
      final total = tasks.fold<int>(
        0,
        (sum, t) => sum + (t.detail?.songs.length ?? t.loadTotal),
      );
      return ListTile(
        key: const Key('playlist-task-entry'),
        dense: true,
        leading: Icon(active > 0 ? Icons.sync : Icons.fact_check_outlined),
        title: Text(
          zh
              ? (active > 0 ? '歌单匹配 $matched / $total · 后台进行中' : '歌单匹配 · 查看结果')
              : (active > 0
                    ? 'Matching playlists $matched / $total'
                    : 'Playlist matches · View results'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OnlinePlaylistTasksPage(
              controller: controller,
              onOpenPlaylist: onOpenPlaylist,
            ),
          ),
        ),
      );
    },
  );
}

class OnlinePlaylistTasksPage extends StatelessWidget {
  const OnlinePlaylistTasksPage({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
  });
  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '歌单匹配' : 'Playlist matching')),
      body: SingleChildScrollView(
        child: OnlinePlaylistTaskList(
          controller: controller,
          onOpenPlaylist: onOpenPlaylist,
        ),
      ),
    );
  }
}

class OnlinePlaylistTaskList extends StatelessWidget {
  const OnlinePlaylistTaskList({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
  });
  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return AnimatedBuilder(
      animation: controller.onlinePlaylistTasks,
      builder: (context, _) => Column(
        children: [
          if (controller.onlinePlaylistTasks.tasks.isEmpty)
            ListTile(title: Text(zh ? '暂无匹配歌单' : 'No playlist matches yet')),
          for (final task in controller.onlinePlaylistTasks.tasks.reversed)
            ListTile(
              title: Text(task.playlist.name),
              subtitle: Text(
                '${task.playlist.source.label} · ${_status(task, zh)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OnlinePlaylistPage(
                    playlist: task.playlist,
                    repository: task.repository,
                    controller: controller,
                    onOpenPlaylist: onOpenPlaylist,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _status(OnlinePlaylistTask task, bool zh) {
    if (task.loading) {
      return zh
          ? '读取中 ${task.loaded}/${task.loadTotal}'
          : 'Loading ${task.loaded}/${task.loadTotal}';
    }
    if (task.loadFailed) return zh ? '读取失败 · 点击重试' : 'Load failed · Retry';
    if (task.matching) {
      return zh
          ? '匹配中 ${task.completed}/${task.matchTotal}'
          : 'Matching ${task.completed}/${task.matchTotal}';
    }
    if (task.saving) return zh ? '正在保存' : 'Saving';
    if (task.autoSyncError) {
      return zh ? '自动同步失败 · 点击重试' : 'Auto sync failed · Retry';
    }
    final total = task.detail?.songs.length ?? 0;
    if (task.choices.length < total) {
      return zh
          ? '已匹配 ${task.choices.length}/$total · 可核对或重试'
          : '${task.choices.length}/$total matched · Review or retry';
    }
    if (task.autoSyncEnabled) {
      return zh
          ? '已自动同步 ${task.savedRows.length} 首'
          : '${task.savedRows.length} songs synced automatically';
    }
    return zh
        ? '匹配完成 · ${task.ready} 首待导入'
        : 'Matched · ${task.ready} ready to import';
  }
}
