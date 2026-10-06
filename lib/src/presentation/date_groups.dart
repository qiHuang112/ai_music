import 'app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';

class DateGroup<T> {
  const DateGroup(this.day, this.items);
  final DateTime? day;
  final List<T> items;
}

List<DateGroup<T>> groupByLocalDay<T>(
  Iterable<T> items,
  DateTime? Function(T) time,
) {
  final groups = <DateTime?, List<T>>{};
  for (final item in items) {
    final local = time(item)?.toLocal();
    final day = local == null
        ? null
        : DateTime(local.year, local.month, local.day);
    (groups[day] ??= []).add(item);
  }
  final days = groups.keys.toList()
    ..sort(
      (a, b) => a == null
          ? (b == null ? 0 : 1)
          : b == null
          ? -1
          : b.compareTo(a),
    );
  return [for (final day in days) DateGroup(day, groups[day]!)];
}

String dateGroupLabel(DateTime? day, {required bool zh, DateTime? now}) {
  if (day == null) return zh ? '日期未知' : 'Unknown date';
  final today = (now ?? DateTime.now()).toLocal();
  final value = day.toLocal();
  final ago = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(value.year, value.month, value.day)).inDays;
  if (ago == 0) return zh ? '今天' : 'Today';
  if (ago == 1) return zh ? '昨天' : 'Yesterday';
  if (ago == 2) return zh ? '前天' : '2 days ago';
  if (ago >= 3 && ago <= 6) return zh ? '$ago天前' : '$ago days ago';
  final date = zh
      ? '${value.month}月${value.day}日'
      : '${value.month}/${value.day}';
  return value.year == today.year
      ? date
      : (zh ? '${value.year}年$date' : '${value.year}/$date');
}

class DateGroupHeader extends StatelessWidget {
  const DateGroupHeader({
    super.key,
    required this.day,
    required this.summary,
    required this.zh,
    this.label,
    this.indent = 0,
  });
  final DateTime? day;
  final String? label;
  final double indent;
  final String summary;
  final bool zh;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      MusicUi.pagePadding + indent,
      16,
      MusicUi.pagePadding,
      6,
    ),
    child: Text(
      '${label ?? dateGroupLabel(day, zh: zh)} · $summary',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

String dateGroupKey(DateTime? time) {
  if (time == null) return 'unknown';
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day).toIso8601String();
}

bool matchesDateFilter(DateTime? time, String? filter) {
  if (filter == null) return true;
  if (filter == 'unknown') return time == null;
  if (time == null) return false;
  final range = dateFilterRange(filter);
  final day = DateUtils.dateOnly(time.toLocal());
  return range != null && !day.isBefore(range.start) && !day.isAfter(range.end);
}

class DateFilterButton extends StatelessWidget {
  const DateFilterButton({
    super.key,
    required this.dates,
    required this.value,
    required this.onChanged,
    required this.zh,
  });
  final Iterable<DateTime?> dates;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool zh;
  Future<void> _pick(BuildContext context, String choice) async {
    if (choice == 'all' || choice == 'unknown') {
      onChanged(choice == 'all' ? null : 'unknown');
      return;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final known =
        dates
            .whereType<DateTime>()
            .map((d) => DateUtils.dateOnly(d.toLocal()))
            .toList()
          ..sort();
    final first = known.isEmpty || known.first.isAfter(today)
        ? today
        : known.first;
    final last = known.isEmpty || known.last.isBefore(today)
        ? today
        : known.last;
    final selected = dateFilterRange(value);
    final initial = (selected?.start ?? today);
    final safeInitial = initial.isBefore(first)
        ? first
        : initial.isAfter(last)
        ? last
        : initial;
    if (choice == 'day') {
      final picked = await showDatePicker(
        context: context,
        builder: (context, child) => Localizations.override(
          context: context,
          locale: Locale(zh ? 'zh' : 'en'),
          delegates: GlobalMaterialLocalizations.delegates,
          child: child,
        ),
        firstDate: first,
        lastDate: last,
        initialDate: safeInitial,
        helpText: zh ? '选择日期' : 'Choose date',
        cancelText: zh ? '取消' : 'Cancel',
        confirmText: zh ? '确定' : 'OK',
      );
      if (context.mounted && picked != null) onChanged(dateGroupKey(picked));
    } else {
      final picked = await showDateRangePicker(
        context: context,
        builder: (context, child) => Localizations.override(
          context: context,
          locale: Locale(zh ? 'zh' : 'en'),
          delegates: GlobalMaterialLocalizations.delegates,
          child: child,
        ),
        firstDate: first,
        lastDate: last,
        initialDateRange:
            selected != null &&
                !selected.start.isBefore(first) &&
                !selected.end.isAfter(last)
            ? selected
            : null,
        helpText: zh ? '选择日期范围' : 'Choose date range',
        cancelText: zh ? '取消' : 'Cancel',
        saveText: zh ? '确定' : 'Apply',
      );
      if (context.mounted && picked != null) {
        onChanged('${dateGroupKey(picked.start)}|${dateGroupKey(picked.end)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = dateFilterRange(value);
    final label = value == null
        ? (zh ? '全部日期' : 'All dates')
        : range != null && range.start != range.end
        ? (zh ? '日期范围' : 'Date range')
        : dateGroupLabel(range?.start, zh: zh);
    return PopupMenuButton<String>(
      tooltip: zh ? '按日期筛选' : 'Filter by date',
      onSelected: (choice) => _pick(context, choice),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'all', child: Text(zh ? '全部日期' : 'All dates')),
        PopupMenuItem(value: 'day', child: Text(zh ? '选择一天' : 'Choose a day')),
        PopupMenuItem(
          value: 'range',
          child: Text(zh ? '选择日期范围' : 'Choose a date range'),
        ),
        if (dates.any((d) => d == null))
          PopupMenuItem(
            value: 'unknown',
            child: Text(zh ? '日期未知' : 'Unknown date'),
          ),
      ],
      child: MusicUi.compactActions(context)
          ? Semantics(
              value: label,
              child: SizedBox.square(
                dimension: 48,
                child: Icon(
                  value == null ? Icons.filter_alt_outlined : Icons.filter_alt,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    value == null
                        ? Icons.filter_alt_outlined
                        : Icons.filter_alt,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(label),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
    );
  }
}

DateTimeRange? dateFilterRange(String? value) {
  if (value == null || value == 'unknown') return null;
  final parts = value.split('|');
  final start = DateTime.tryParse(parts.first);
  final end = DateTime.tryParse(parts.last);
  return start == null || end == null || end.isBefore(start)
      ? null
      : DateTimeRange(start: start, end: end);
}

enum DateBucketKind { day, month, year }

class DateBucket<T> {
  const DateBucket(this.kind, this.day, this.items, [this.children = const []]);
  final DateBucketKind kind;
  final DateTime? day;
  final List<T> items;
  final List<DateBucket<T>> children;
  String get key => '${kind.name}:${dateGroupKey(day)}';
  bool get initiallyCollapsed => kind != DateBucketKind.day;
  String label(bool zh) => switch (kind) {
    DateBucketKind.day => dateGroupLabel(day, zh: zh),
    DateBucketKind.month =>
      zh ? '${day!.year}年${day!.month}月' : '${day!.year}/${day!.month}',
    DateBucketKind.year => zh ? '${day!.year}年' : '${day!.year}',
  };
}

List<DateBucket<T>> groupByDateHierarchy<T>(
  Iterable<T> items,
  DateTime? Function(T) time, {
  DateTime? now,
}) {
  final today = DateUtils.dateOnly((now ?? DateTime.now()).toLocal());
  final recentStart = DateTime(today.year, today.month, today.day - 6);
  final roots = <DateBucket<T>>[];
  final older = <DateGroup<T>>[];
  DateGroup<T>? unknown;
  for (final group in groupByLocalDay(items, time)) {
    if (group.day == null) {
      unknown = group;
    } else if (!group.day!.isBefore(recentStart)) {
      roots.add(DateBucket(DateBucketKind.day, group.day, group.items));
    } else {
      older.add(group);
    }
  }
  final months = <DateTime, List<DateBucket<T>>>{};
  for (final group in older) {
    final d = group.day!;
    (months[DateTime(d.year, d.month)] ??= []).add(
      DateBucket(DateBucketKind.day, d, group.items),
    );
  }
  final years = <int, List<DateBucket<T>>>{};
  for (final entry in months.entries) {
    final month = DateBucket(DateBucketKind.month, entry.key, [
      for (final day in entry.value) ...day.items,
    ], entry.value);
    if (entry.key.year == today.year) {
      roots.add(month);
    } else {
      (years[entry.key.year] ??= []).add(month);
    }
  }
  for (final entry in years.entries) {
    roots.add(
      DateBucket(DateBucketKind.year, DateTime(entry.key), [
        for (final month in entry.value) ...month.items,
      ], entry.value),
    );
  }
  if (unknown != null) {
    roots.add(DateBucket(DateBucketKind.day, null, unknown.items));
  }
  return roots;
}

/// Older periods do not build child slivers until explicitly expanded.
/// Only leaf day headers pin, avoiding three stacked headers over the songs.
class DateHierarchySliver<T> extends StatelessWidget {
  const DateHierarchySliver({
    super.key,
    required this.bucket,
    required this.toggled,
    required this.onToggle,
    required this.summary,
    required this.itemBuilder,
    required this.zh,
    this.expandInitially = false,
    this.depth = 0,
  });
  final DateBucket<T> bucket;
  final Set<String> toggled;
  final ValueChanged<String> onToggle;
  final String Function(List<T>) summary;
  final Widget Function(BuildContext, T) itemBuilder;
  final bool zh;
  final bool expandInitially;
  final int depth;
  @override
  Widget build(BuildContext context) {
    final collapsed =
        (bucket.initiallyCollapsed && !expandInitially) !=
        toggled.contains(bucket.key);
    return DateGroupSliver(
      day: bucket.day,
      label: bucket.label(zh),
      summary: summary(bucket.items),
      zh: zh,
      collapsed: collapsed,
      onToggle: () => onToggle(bucket.key),
      depth: depth,
      pinned: bucket.kind == DateBucketKind.day,
      itemCount: bucket.items.length,
      itemBuilder: (context, index) =>
          itemBuilder(context, bucket.items[index]),
      childSlivers: bucket.children.isEmpty
          ? null
          : [
              if (!collapsed)
                for (final child in bucket.children)
                  DateHierarchySliver<T>(
                    key: ValueKey(child.key),
                    bucket: child,
                    toggled: toggled,
                    onToggle: onToggle,
                    summary: summary,
                    itemBuilder: itemBuilder,
                    zh: zh,
                    expandInitially: expandInitially,
                    depth: depth + 1,
                  ),
            ],
    );
  }
}

/// Limits the pinned header to its own section so the next day pushes it away.
class DateGroupSliver extends StatelessWidget {
  const DateGroupSliver({
    super.key,
    required this.day,
    required this.summary,
    required this.zh,
    required this.collapsed,
    required this.onToggle,
    required this.itemCount,
    required this.itemBuilder,
    this.childSlivers,
    this.label,
    this.pinned = true,
    this.depth = 0,
  });
  final DateTime? day;
  final String? label;
  final bool pinned;
  final int depth;
  final List<Widget>? childSlivers;
  final String summary;
  final bool zh;
  final bool collapsed;
  final VoidCallback onToggle;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      SliverPersistentHeader(
        pinned: pinned,
        delegate: _DateHeaderDelegate(
          height: 64 * MediaQuery.textScalerOf(context).scale(1),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Semantics(
              button: true,
              expanded: !collapsed,
              child: InkWell(
                onTap: () {
                  final render = context.findRenderObject();
                  if (!collapsed && render is RenderSliver) {
                    final position = Scrollable.of(context).position;
                    final start = render.constraints.precedingScrollExtent;
                    if (position.pixels > start) {
                      position.jumpTo(
                        start.clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        ),
                      );
                    }
                  }
                  onToggle();
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DateGroupHeader(
                        day: day,
                        label: label,
                        indent: depth * 12,
                        summary: summary,
                        zh: zh,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (!collapsed && childSlivers != null) ...childSlivers!,
      if (!collapsed && childSlivers == null)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
          ),
        ),
    ],
  );
}

class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DateHeaderDelegate({required this.child, required this.height});
  final Widget child;
  final double height;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(_DateHeaderDelegate oldDelegate) => true;
}
