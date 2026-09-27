import 'package:flutter/material.dart';
import 'dart:io';
import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/data/download_history_store.dart';
import 'package:ai_music/src/presentation/date_groups.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'date headers collapse and stay pinned until the next date replaces them',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var collapsed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => CustomScrollView(
                controller: scroll,
                slivers: [
                  DateGroupSliver(
                    day: DateTime(2026, 1, 1),
                    summary: '20 首',
                    zh: true,
                    collapsed: collapsed,
                    onToggle: () => update(() => collapsed = !collapsed),
                    itemCount: 20,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 56, child: Text('first-$i')),
                  ),
                  DateGroupSliver(
                    day: DateTime(2025, 12, 31),
                    summary: '20 首',
                    zh: true,
                    collapsed: false,
                    onToggle: () {},
                    itemCount: 20,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 56, child: Text('second-$i')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      final first = find.byType(DateGroupHeader).first;
      final pinnedY = tester.getTopLeft(first).dy;
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first).dy, pinnedY);
      expect(pinnedY, 0);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(collapsed, true);
      expect(scroll.offset, 0);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('first-0'), findsNothing);
      expect(find.text('second-0'), findsOneWidget);
      await tester.tap(find.byType(DateGroupHeader).first);
      await tester.pumpAndSettle();
      expect(find.text('first-0'), findsOneWidget);
      scroll.jumpTo(1300);
      await tester.pumpAndSettle();
      final second = find.byWidgetPredicate(
        (w) => w is DateGroupHeader && w.day == DateTime(2025, 12, 31),
      );
      expect(tester.getTopLeft(second).dy, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'date filters use local calendar days and include unknown only explicitly',
    () {
      final day = DateTime(2026, 9, 27);
      expect(matchesDateFilter(day.toUtc(), dateGroupKey(day)), true);
      expect(
        matchesDateFilter(DateTime(2026, 9, 26, 23), dateGroupKey(day)),
        false,
      );
      expect(matchesDateFilter(null, dateGroupKey(day)), false);
      expect(matchesDateFilter(null, 'unknown'), true);
      expect(matchesDateFilter(null, null), true);
    },
  );

  test(
    'calendar labels cross month and year and leave unknown dates explicit',
    () {
      final now = DateTime(2026, 1, 2, 1);
      String label(DateTime? date) => dateGroupLabel(date, zh: true, now: now);
      expect(label(DateTime(2026, 1, 2)), '今天');
      expect(label(DateTime(2026, 1, 1, 23)), '昨天');
      expect(label(DateTime(2025, 12, 31)), '前天');
      expect(label(DateTime(2025, 12, 30)), '3天前');
      expect(label(DateTime(2025, 12, 20)), '2025年12月20日');
      expect(label(null), '日期未知');
      expect(
        dateGroupLabel(
          DateTime(2026, 9, 1),
          zh: true,
          now: DateTime(2026, 9, 27),
        ),
        '9月1日',
      );
    },
  );

  test('groups use local calendar dates, keep indexes and unknown last', () {
    final dates = [
      DateTime(2026, 9, 26, 23),
      DateTime(2026, 9, 27, 1).toUtc(),
      null,
      DateTime(2026, 9, 27, 23),
    ];
    final groups = groupByLocalDay(dates.asMap().keys, (i) => dates[i]);
    expect(groups.map((g) => g.items), [
      [1, 3],
      [0],
      [2],
    ]);
    expect(groups.first.day, DateTime(2026, 9, 27));
    expect(groups.last.day, isNull);
  });

  test(
    'terminal date uses completion day; byte updates never write history',
    () {
      var now = DateTime(2026, 9, 26, 23, 59);
      final queue = DownloadQueueController(now: () => now);
      var writes = 0;
      queue.onHistoryChanged = () => writes++;
      queue.upsert(
        DownloadTask(
          id: 'a',
          title: 'a',
          subtitle: '',
          status: DownloadTaskStatus.downloading,
          createdAt: now,
        ),
      );
      for (var i = 0; i < 100; i++) {
        queue.update('a', (t) => t.copyWith(bytes: i));
      }
      expect(writes, 0);
      now = DateTime(2026, 9, 27, 0, 1);
      queue.update(
        'a',
        (t) =>
            t.copyWith(status: DownloadTaskStatus.completed, reusedCache: true),
      );
      final task = queue.recentTasks.single;
      expect(task.finishedAt, now);
      expect(task.createdAt!.day, 26);
      expect(writes, 1);
      expect(DownloadTask.fromJson(task.toJson())!.reusedCache, true);
      queue.clearTask('a');
      queue.restoreHistory([task]);
      expect(queue.tasks, isEmpty);
      expect(writes, 2);
    },
  );

  test(
    'restored history cannot replace active retry or resurrect cleared history',
    () {
      final queue = DownloadQueueController();
      const saved = DownloadTask(
        id: 'a',
        title: 'saved',
        subtitle: '',
        status: DownloadTaskStatus.failed,
      );
      queue.upsert(
        const DownloadTask(
          id: 'a',
          title: 'retry',
          subtitle: '',
          status: DownloadTaskStatus.downloading,
        ),
      );
      queue.restoreHistory([saved]);
      expect(queue.tasks.single.title, 'retry');
      queue.clearTerminalTasks();
      queue.restoreHistory([
        const DownloadTask(
          id: 'b',
          title: '',
          subtitle: '',
          status: DownloadTaskStatus.completed,
        ),
      ]);
      expect(queue.tasks.single.title, 'retry');
      expect(DownloadTask.fromJson(queue.tasks.single.toJson()), isNull);
    },
  );

  test(
    'history persists serialized terminal snapshots and clears after reload',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'download-history-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = DownloadHistoryStore(rootProvider: () async => root);
      final date = DateTime(2026, 9, 26);
      final task = DownloadTask(
        id: 'a',
        title: 'Alpha',
        subtitle: 'Artist',
        status: DownloadTaskStatus.completed,
        finishedAt: date,
      );
      await store.write([task.toJson()]);
      final restored = DownloadHistoryStore(rootProvider: () async => root);
      expect(
        DownloadTask.fromJson((await restored.read()).single)!.finishedAt,
        date,
      );
      await Future.wait([
        store.write([task.toJson()]),
        store.write([]),
      ]);
      expect(await restored.read(), isEmpty);
      await File('${root.path}/download_history.json').writeAsString('{bad');
      expect(await restored.read(), isEmpty);
      expect(root.listSync().any((f) => f.path.contains('.corrupt-')), true);
    },
  );
}
