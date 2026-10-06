import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/listening_stats_store.dart';
import '../data/music_playlists.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'date_groups.dart';
import 'music_thumbnail.dart';
import 'playlist_actions.dart';
import 'song_source_page.dart';

String listeningDuration(int milliseconds, bool zh) {
  final seconds = milliseconds ~/ 1000;
  if (seconds < 60) return zh ? '$seconds秒' : '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return zh ? '$minutes分${seconds % 60}秒' : '${minutes}m ${seconds % 60}s';
  }
  return zh
      ? '${minutes ~/ 60}小时${minutes % 60}分'
      : '${minutes ~/ 60}h ${minutes % 60}m';
}

Future<void> confirmClearListeningStats(
  BuildContext context,
  MusicController controller,
) async {
  final zh = AppStringsScope.of(context).isZh;
  final clear = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(zh ? '清空听歌统计？' : 'Clear listening history?'),
      content: Text(
        zh
            ? '会清空听歌时长、排行榜及听歌记录，从现在重新统计。歌单、收藏、缓存和正在播放的音乐不受影响。'
            : 'Reset listening time, rankings and history. Playlists, favorites, audio files and playback are preserved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(zh ? '清空' : 'Clear'),
        ),
      ],
    ),
  );
  if (clear != true) return;
  try {
    await controller.clearListeningStats();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '清空失败，请重试' : 'Could not clear history. Please retry.',
          ),
        ),
      );
    }
  }
}

class ListeningStatsPage extends StatefulWidget {
  const ListeningStatsPage({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
    this.bottomPlayer,
  });
  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  final Widget? bottomPlayer;
  @override
  State<ListeningStatsPage> createState() => _ListeningStatsPageState();
}

class _ListeningStatsPageState extends State<ListeningStatsPage> {
  String _period = 'today';
  String? _custom;
  bool _byTime = false;
  bool get zh => AppStringsScope.of(context).isZh;
  ListeningStatsStore get store => widget.controller.listeningStats;
  @override
  void initState() {
    super.initState();
    unawaited(store.load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refreshListeningStats();
    });
  }

  ({DateTime? from, DateTime? until}) _range() {
    final today = listeningDay(DateTime.now());
    if (_period == 'all') return (from: null, until: null);
    if (_period == 'custom') {
      final r = dateFilterRange(_custom);
      return (from: r?.start, until: r?.end);
    }
    if (_period == 'yesterday') {
      final d = DateTime(today.year, today.month, today.day - 1);
      return (from: d, until: d);
    }
    final days = _period == 'week'
        ? 7
        : _period == 'month'
        ? 30
        : 1;
    return (
      from: DateTime(today.year, today.month, today.day - days + 1),
      until: today,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final range = _range();
      final report = store.report(
        from: range.from,
        until: range.until,
        sortByTime: _byTime,
      );
      final cumulative = store.report();
      return Scaffold(
        appBar: AppBar(
          title: Text(zh ? '我的听歌' : 'My listening'),
          actions: [
            DateFilterButton(
              dates: [
                if (store.startedAt != null) store.startedAt,
                ...cumulative.days.keys.map(DateTime.parse),
              ],
              value: _custom,
              zh: zh,
              onChanged: (value) => setState(() {
                _custom = value;
                _period = value == null ? 'all' : 'custom';
              }),
            ),
          ],
        ),
        bottomNavigationBar: widget.bottomPlayer,
        body: SafeArea(
          child: ListView(
            padding: MusicUi.pageInsets,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    'today': zh ? '今天' : 'Today',
                    'yesterday': zh ? '昨天' : 'Yesterday',
                    'week': zh ? '近7天' : '7 days',
                    'month': zh ? '近30天' : '30 days',
                    'all': zh ? '累计' : 'All time',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _period == entry.key,
                      onSelected: (_) => setState(() => _period = entry.key),
                    ),
                ],
              ),
              if (_period == 'custom' && range.from != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${listeningDayKey(range.from!)} — ${listeningDayKey(range.until!)}',
                  ),
                ),
              const SizedBox(height: 16),
              if (store.error != null)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: colors.error),
                    title: Text(
                      zh
                          ? '统计暂时无法完整读取或保存'
                          : 'History could not be read or saved',
                    ),
                    trailing: TextButton(
                      onPressed: store.retry,
                      child: Text(zh ? '重试' : 'Retry'),
                    ),
                  ),
                ),
              if (!store.loaded && store.error == null)
                const LinearProgressIndicator(),
              Card(
                color: colors.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        zh ? '实际听歌时长' : 'Listening time',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        listeningDuration(report.milliseconds, zh),
                        key: const Key('listening-total-time'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: colors.primary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        zh
                            ? '只记录实际播放，暂停和缓冲不计时。'
                            : 'Actual playback only; pauses and buffering are excluded.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final metric in [
                      (zh ? '听过歌曲' : 'Songs heard', '${report.songCount}'),
                      (zh ? '有效播放' : 'Qualified plays', '${report.plays}'),
                      (zh ? '听歌天数' : 'Listening days', '${report.dayCount}'),
                      (
                        zh ? '连续听歌' : 'Current streak',
                        '${cumulative.streak(DateTime.now())}',
                      ),
                    ])
                      SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(MusicUi.radius),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  metric.$1,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  metric.$2,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                zh ? '听歌趋势' : 'Listening trend',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _ListeningTrend(
                report: report,
                from: range.from ?? store.startedAt ?? DateTime.now(),
                until: range.until ?? DateTime.now(),
                onOpen: (from, until, title) =>
                    _openHistory(from, until, title),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text(
                    zh ? '排行榜' : 'Rankings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  PopupMenuButton<bool>(
                    tooltip: zh ? '排行方式' : 'Ranking order',
                    initialValue: _byTime,
                    onSelected: (value) => setState(() => _byTime = value),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: false,
                        checked: !_byTime,
                        child: Text(zh ? '播放次数' : 'Play count'),
                      ),
                      CheckedPopupMenuItem(
                        value: true,
                        checked: _byTime,
                        child: Text(zh ? '听歌时长' : 'Listening time'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _byTime
                            ? (zh ? '按时长 ▾' : 'By time ▾')
                            : (zh ? '按次数 ▾' : 'By plays ▾'),
                        style: TextStyle(color: colors.primary),
                      ),
                    ),
                  ),
                ],
              ),
              _rankSection(
                zh ? '最常听歌曲' : 'Top songs',
                report.songRanks,
                false,
                range,
              ),
              const SizedBox(height: 16),
              _rankSection(
                zh ? '最常听歌单' : 'Top playlists',
                report.playlistRanks,
                true,
                range,
              ),
              const SizedBox(height: 24),
              Text(
                zh ? '每日记录' : 'Daily history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (report.records.isEmpty)
                _empty(
                  zh
                      ? '还没有听歌记录，播放音乐后会自动记录。'
                      : 'Play some music to start your listening history.',
                )
              else
                _HistoryTree(
                  days: report.days,
                  onOpen: (day) =>
                      _openHistory(day, day, dateGroupLabel(day, zh: zh)),
                ),
              const SizedBox(height: 20),
              Text(
                zh
                    ? '满30秒算一次有效播放；不足30秒的歌曲听满一半。暂停后继续不重复计次。'
                    : 'A play counts after 30s; tracks shorter than 30s count at halfway. Resuming does not count twice.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (store.startedAt != null)
                Text(
                  zh
                      ? '统计始于 ${listeningDayKey(store.startedAt!.toLocal())} · 仅保存在本机'
                      : 'Since ${listeningDayKey(store.startedAt!.toLocal())} · Stored on this device',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      );
    },
  );
  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
  Widget _rankSection(
    String title,
    List<ListeningRank> ranks,
    bool playlists,
    ({DateTime? from, DateTime? until}) range,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (ranks.length > 5)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _ListeningRankPage(
                    controller: widget.controller,
                    title: title,
                    playlists: playlists,
                    from: range.from,
                    until: range.until,
                    byTime: _byTime,
                    onOpenPlaylist: widget.onOpenPlaylist,
                    bottomPlayer: widget.bottomPlayer,
                  ),
                ),
              ),
              child: Text(zh ? '查看全部' : 'View all'),
            ),
        ],
      ),
      if (ranks.isEmpty)
        _empty(zh ? '暂无记录' : 'No history yet')
      else
        for (var i = 0; i < min(5, ranks.length); i++)
          _ListeningRankTile(
            controller: widget.controller,
            rank: ranks[i],
            number: i + 1,
            onOpenPlaylist: widget.onOpenPlaylist,
          ),
    ],
  );
  void _openHistory(DateTime from, DateTime until, String title) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _ListeningHistoryPage(
            controller: widget.controller,
            from: from,
            until: until,
            title: title,
            bottomPlayer: widget.bottomPlayer,
          ),
        ),
      );
}

class _ListeningTrend extends StatelessWidget {
  const _ListeningTrend({
    required this.report,
    required this.from,
    required this.until,
    required this.onOpen,
  });
  final ListeningReport report;
  final DateTime from, until;
  final void Function(DateTime, DateTime, String) onOpen;
  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh,
        colors = Theme.of(context).colorScheme;
    final span = until.difference(from).inDays;
    final yearly = span > 730, monthly = !yearly && span > 62;
    var cursor = yearly
        ? DateTime(from.year)
        : monthly
        ? DateTime(from.year, from.month)
        : listeningDay(from);
    final buckets = <({DateTime start, DateTime end, int ms, String label})>[];
    while (!cursor.isAfter(until)) {
      final next = yearly
          ? DateTime(cursor.year + 1)
          : monthly
          ? DateTime(cursor.year, cursor.month + 1)
          : DateTime(cursor.year, cursor.month, cursor.day + 1);
      final ms = report.days.entries
          .where(
            (e) =>
                e.key.compareTo(listeningDayKey(cursor)) >= 0 &&
                e.key.compareTo(listeningDayKey(next)) < 0,
          )
          .fold(0, (sum, e) => sum + e.value);
      final label = yearly
          ? '${cursor.year}'
          : monthly
          ? '${cursor.year}/${cursor.month}'
          : '${cursor.month}/${cursor.day}';
      buckets.add((
        start: cursor,
        end: DateTime(next.year, next.month, next.day - 1),
        ms: ms,
        label: label,
      ));
      cursor = next;
    }
    final maximum = buckets.fold(1, (m, b) => max(m, b.ms));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              yearly
                  ? (zh ? '按年汇总，点击查看' : 'Yearly totals; tap to explore')
                  : monthly
                  ? (zh ? '按月汇总，点击查看' : 'Monthly totals; tap to explore')
                  : (zh
                        ? '每日时长，左右滑动并点击查看'
                        : 'Daily totals; swipe and tap to explore'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in buckets)
                    Tooltip(
                      message: '${b.label} · ${listeningDuration(b.ms, zh)}',
                      child: Semantics(
                        label: '${b.label} · ${listeningDuration(b.ms, zh)}',
                        button: true,
                        child: InkWell(
                          onTap: () => onOpen(b.start, b.end, b.label),
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: monthly || yearly ? 72 : 48,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 80,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        height: b.ms == 0
                                            ? 3
                                            : max(5.0, b.ms / maximum * 80),
                                        width: 14,
                                        decoration: BoxDecoration(
                                          color: b.ms == 0
                                              ? colors.outlineVariant
                                              : colors.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    b.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTree extends StatelessWidget {
  const _HistoryTree({required this.days, required this.onOpen});
  final Map<String, int> days;
  final ValueChanged<DateTime> onOpen;
  @override
  Widget build(BuildContext context) {
    final years = days.keys.map((d) => d.substring(0, 4)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final zh = AppStringsScope.of(context).isZh;
    return Column(
      children: [
        for (final year in years)
          _HistoryBranch(
            key: ValueKey('history-year-$year'),
            title: zh ? '$year年' : year,
            initialOpen: year == '${DateTime.now().year}',
            builder: () {
              final months =
                  days.keys
                      .where((d) => d.startsWith(year))
                      .map((d) => d.substring(0, 7))
                      .toSet()
                      .toList()
                    ..sort((a, b) => b.compareTo(a));
              return [
                for (final month in months)
                  _HistoryBranch(
                    key: ValueKey('history-month-$month'),
                    title: zh ? '${int.parse(month.substring(5))}月' : month,
                    initialOpen:
                        month ==
                        listeningDayKey(DateTime.now()).substring(0, 7),
                    builder: () {
                      final dates =
                          days.keys.where((d) => d.startsWith(month)).toList()
                            ..sort((a, b) => b.compareTo(a));
                      return [
                        for (final date in dates)
                          ListTile(
                            title: Text(
                              dateGroupLabel(DateTime.parse(date), zh: zh),
                            ),
                            subtitle: Text(listeningDuration(days[date]!, zh)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => onOpen(DateTime.parse(date)),
                          ),
                      ];
                    },
                  ),
              ];
            },
          ),
      ],
    );
  }
}

class _HistoryBranch extends StatefulWidget {
  const _HistoryBranch({
    super.key,
    required this.title,
    required this.initialOpen,
    required this.builder,
  });
  final String title;
  final bool initialOpen;
  final List<Widget> Function() builder;
  @override
  State<_HistoryBranch> createState() => _HistoryBranchState();
}

class _HistoryBranchState extends State<_HistoryBranch> {
  late bool _open = widget.initialOpen;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: widget.initialOpen,
    title: Text(widget.title),
    onExpansionChanged: (open) => setState(() => _open = open),
    children: _open ? widget.builder() : const [],
  );
}

class _ListeningRankTile extends StatelessWidget {
  const _ListeningRankTile({
    required this.controller,
    required this.rank,
    required this.number,
    this.onOpenPlaylist,
  });
  final MusicController controller;
  final ListeningRank rank;
  final int number;
  final ValueChanged<MusicPlaylist>? onOpenPlaylist;
  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    final song = rank.song;
    final track = song == null ? null : controller.trackForListeningSong(song);
    final playlist = song != null
        ? null
        : controller.allPlaylists.where((p) => p.id == rank.id).firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 64,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '$number',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            MusicThumbnail(uri: Uri.tryParse(rank.artwork), size: 40),
          ],
        ),
      ),
      title: Text(rank.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${song?.artist ?? (zh ? '${rank.songIds.length} 首' : '${rank.songIds.length} songs')}\n${zh ? '${rank.plays}次' : '${rank.plays} plays'} · ${listeningDuration(rank.milliseconds, zh)}\n${zh ? '最近' : 'Last'} ${listeningDayKey(rank.lastPlayed!.toLocal())}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: song != null
          ? _ListeningSongMenu(controller: controller, track: track)
          : Icon(playlist == null ? Icons.info_outline : Icons.chevron_right),
      onTap: () {
        if (song != null && track != null) {
          _playListeningSong(context, controller, track);
        } else if (playlist != null) {
          onOpenPlaylist?.call(playlist);
        } else {
          _unavailable(context);
        }
      },
    );
  }
}

void _unavailable(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStringsScope.of(context).isZh
              ? '这条记录对应的歌曲或歌单已不在音乐库中'
              : 'This song or playlist is no longer in your library',
        ),
      ),
    );
Future<void> _playListeningSong(
  BuildContext context,
  MusicController controller,
  Track track,
) async {
  try {
    await controller.playTrack(track, queueTracks: [track]);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStringsScope.of(context).playTrackFailed(e.toString()),
          ),
        ),
      );
    }
  }
}

class _ListeningSongMenu extends StatelessWidget {
  const _ListeningSongMenu({required this.controller, required this.track});
  final MusicController controller;
  final Track? track;
  @override
  Widget build(BuildContext context) {
    final t = track;
    final strings = AppStringsScope.of(context);
    if (t == null) {
      return IconButton(
        tooltip: strings.isZh ? '内容已移除' : 'Unavailable',
        onPressed: () => _unavailable(context),
        icon: const Icon(Icons.info_outline),
      );
    }
    return PopupMenuButton<String>(
      tooltip: strings.more,
      onSelected: (choice) async {
        if (choice == 'favorite') {
          try {
            await controller.toggleFavorite(t);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    strings.isZh
                        ? '收藏保存失败，请重试'
                        : 'Could not save favorite. Please retry.',
                  ),
                ),
              );
            }
          }
        }
        if (choice == 'add' && context.mounted) {
          await showAddToPlaylistSheet(context, controller, t);
        }
        if (choice == 'source' && context.mounted) {
          await showSongSourcePicker(context, controller, t);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            controller.isFavorite(t)
                ? strings.removeFromFavorites
                : strings.addToFavorites,
          ),
        ),
        PopupMenuItem(value: 'add', child: Text(strings.addToPlaylist)),
        PopupMenuItem(
          value: 'source',
          enabled: controller.canSwitchSongSource(t),
          child: Text(
            '${strings.isZh ? '歌曲来源' : 'Song source'}（${controller.songSourceLabel(t, isZh: strings.isZh)}）',
          ),
        ),
      ],
    );
  }
}

class _ListeningRankPage extends StatelessWidget {
  const _ListeningRankPage({
    required this.controller,
    required this.title,
    required this.playlists,
    required this.from,
    required this.until,
    required this.byTime,
    required this.onOpenPlaylist,
    this.bottomPlayer,
  });
  final MusicController controller;
  final String title;
  final bool playlists, byTime;
  final DateTime? from, until;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  final Widget? bottomPlayer;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.listeningStats,
    builder: (context, _) {
      final report = controller.listeningStats.report(
        from: from,
        until: until,
        sortByTime: byTime,
      );
      final ranks = playlists ? report.playlistRanks : report.songRanks;
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        bottomNavigationBar: bottomPlayer,
        body: ListView.builder(
          padding: MusicUi.pageInsets,
          itemCount: ranks.length,
          itemBuilder: (_, i) => _ListeningRankTile(
            controller: controller,
            rank: ranks[i],
            number: i + 1,
            onOpenPlaylist: onOpenPlaylist,
          ),
        ),
      );
    },
  );
}

class _ListeningHistoryPage extends StatelessWidget {
  const _ListeningHistoryPage({
    required this.controller,
    required this.from,
    required this.until,
    required this.title,
    this.bottomPlayer,
  });
  final MusicController controller;
  final DateTime from, until;
  final String title;
  final Widget? bottomPlayer;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.listeningStats,
    builder: (context, _) {
      final report = controller.listeningStats.report(from: from, until: until);
      final zh = AppStringsScope.of(context).isZh;
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        bottomNavigationBar: bottomPlayer,
        body: report.records.isEmpty
            ? Center(
                child: Text(zh ? '这段时间没有听歌记录' : 'No history in this period'),
              )
            : ListView.builder(
                padding: MusicUi.pageInsets,
                itemCount: report.records.length,
                itemBuilder: (context, i) {
                  final record = report.records[i],
                      track = controller.trackForListeningSong(
                        report.records[i].song,
                      ),
                      at = record.startedAt.toLocal();
                  final time =
                      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: MusicThumbnail(
                      uri: Uri.tryParse(record.song.artwork),
                      size: 44,
                    ),
                    title: Text(
                      record.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${from == until ? time : '${record.day} $time'} · ${record.song.artist}\n${listeningDuration(record.milliseconds, zh)} · ${record.playlistId == null ? (zh ? '单曲播放' : 'Single-track playback') : record.playlistName}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _ListeningSongMenu(
                      controller: controller,
                      track: track,
                    ),
                    onTap: () => track == null
                        ? _unavailable(context)
                        : _playListeningSong(context, controller, track),
                  );
                },
              ),
      );
    },
  );
}
