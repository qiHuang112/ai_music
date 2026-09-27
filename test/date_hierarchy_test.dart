import 'package:ai_music/src/presentation/date_groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a year of daily history is bounded at the root and counted exactly once',
    () {
      final now = DateTime(2026, 1, 3);
      final dates = [
        for (var i = 0; i < 365; i++)
          DateTime(now.year, now.month, now.day - i),
        null,
      ];
      final groups = groupByDateHierarchy(dates, (d) => d, now: now);
      expect(groups.length, 9); // seven recent days, previous year, unknown
      expect(
        groups.where((g) => g.kind == DateBucketKind.year).single.items.length,
        358,
      );
      expect(groups.expand((g) => g.items).toSet().length, 366);
      expect(groups.expand((g) => g.items).length, 366);
      expect(groups.last.day, isNull);
      final previousYear = groups[7];
      expect(previousYear.initiallyCollapsed, true);
      expect(
        previousYear.children.every((m) => m.kind == DateBucketKind.month),
        true,
      );
      expect(
        previousYear.children
            .expand((m) => m.children)
            .every((d) => d.kind == DateBucketKind.day),
        true,
      );
    },
  );

  test('range includes both local end days and excludes unknown dates', () {
    final filter =
        '${dateGroupKey(DateTime(2025, 12, 31))}|${dateGroupKey(DateTime(2026, 1, 2))}';
    expect(
      matchesDateFilter(DateTime(2025, 12, 31, 0, 1).toUtc(), filter),
      true,
    );
    expect(matchesDateFilter(DateTime(2026, 1, 2, 23, 59), filter), true);
    expect(matchesDateFilter(DateTime(2026, 1, 3), filter), false);
    expect(matchesDateFilter(null, filter), false);
  });

  testWidgets(
    'old years build no song rows until year and month are expanded',
    (tester) async {
      final now = DateTime.now();
      final dates = [
        for (var i = 0; i < 365; i++) DateTime(now.year - 1, 1, 1 + i),
      ];
      final groups = groupByDateHierarchy(dates, (d) => d, now: now);
      var builds = 0;
      final toggled = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => CustomScrollView(
                slivers: [
                  for (final group in groups)
                    DateHierarchySliver<DateTime>(
                      bucket: group,
                      toggled: toggled,
                      onToggle: (key) => update(() {
                        if (!toggled.remove(key)) toggled.add(key);
                      }),
                      summary: (items) => '${items.length} 首',
                      zh: true,
                      itemBuilder: (_, item) {
                        builds++;
                        return SizedBox(
                          height: 56,
                          child: Text('song-${item.month}-${item.day}'),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, 0);
      await tester.tap(find.text('${now.year - 1}年 · 365 首'));
      await tester.pumpAndSettle();
      expect(builds, 0);
      final monthHeader = find.text('${now.year - 1}年12月 · 31 首');
      await tester.tap(monthHeader);
      await tester.pumpAndSettle();
      expect(builds, greaterThan(0));
      expect(builds, lessThan(70));
      expect(find.text('song-12-31'), findsOneWidget);
      await tester.tap(monthHeader);
      await tester.pumpAndSettle();
      expect(find.text('song-12-31'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar menu stays small for hundreds of days and cancel preserves filter',
    (tester) async {
      String? selected = dateGroupKey(DateTime(2026, 9, 10));
      final original = selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                DateFilterButton(
                  dates: [
                    for (var i = 0; i < 365; i++) DateTime(2026, 9, 27 - i),
                  ],
                  value: selected,
                  zh: true,
                  onChanged: (value) => selected = value,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('按日期筛选'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      await tester.tap(find.text('选择一天'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(selected, original);
      await tester.tap(find.byTooltip('按日期筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择日期范围'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      // Choosing a new start clears the previous range before choosing the end.
      await tester.tap(find.text('12').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      final range = dateFilterRange(selected)!;
      expect(range.start, DateTime(2026, 9, 12));
      expect(range.end, DateTime(2026, 9, 15));
    },
  );
}
