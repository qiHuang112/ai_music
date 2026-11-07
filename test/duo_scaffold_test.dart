import 'package:ai_music/src/presentation/duo_scaffold.dart';
import 'package:ai_music/src/presentation/duo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rail slots avoid camera, status and fold without wasting the edge', () {
    const bounds = Rect.fromLTWH(524, 0, 76, 500);
    const blocks = [
      Rect.fromLTWH(530, 8, 60, 80),
      Rect.fromLTWH(530, 100, 60, 40),
      Rect.fromLTWH(0, 260, 600, 20),
    ];
    final slots = DuoRail.slots(bounds, blocks);
    expect(slots, isNotEmpty);
    expect(slots.first, lessThan(200));
    for (final y in slots) {
      final button = Rect.fromLTWH(528, y, 68, 52);
      expect(blocks.any(button.overlaps), isFalse);
    }
  });

  testWidgets(
    'system rail uses the right safe area and actions remain usable',
    (tester) async {
      tester.view.physicalSize = const Size(600, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(right: 76)),
            child: DuoWindowScope(
              geometry: const DuoGeometry(
                EdgeInsets.only(right: 76),
                [],
                edge: DuoBarEdge.right,
                obstructions: [Rect.fromLTWH(530, 0, 70, 120)],
              ),
              child: child!,
            ),
          ),
          home: DuoScaffold(
            appBar: AppBar(
              title: const Text('Player'),
              actions: [
                IconButton(
                  tooltip: 'Favorite',
                  onPressed: () => taps++,
                  icon: const Icon(Icons.favorite),
                ),
              ],
            ),
            body: const SizedBox.expand(key: ValueKey('content')),
          ),
        ),
      );
      expect(tester.getRect(find.byKey(const ValueKey('content'))).right, 524);
      final action = tester.getRect(find.byTooltip('Favorite'));
      expect(action.left, greaterThanOrEqualTo(524));
      expect(action.top, greaterThanOrEqualTo(120));
      await tester.tap(find.byTooltip('Favorite'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('physical rail edge changes without resetting nested content', (
    tester,
  ) async {
    final edge = ValueNotifier(DuoBarEdge.right);
    addTearDown(edge.dispose);
    final text = TextEditingController(text: 'song');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder(
          valueListenable: edge,
          builder: (context, value, _) => Directionality(
            textDirection: TextDirection.rtl,
            child: DuoWindowScope(
              geometry: DuoGeometry(EdgeInsets.zero, const [], edge: value),
              child: child!,
            ),
          ),
        ),
        home: DuoScaffold(
          extraActions: [
            DuoRailItem(
              icon: Icons.queue_music,
              label: 'Queue',
              onPressed: () {},
            ),
          ],
          body: DuoScaffold(body: TextField(controller: text)),
        ),
      ),
    );
    final input = tester.state(find.byType(TextField));
    expect(tester.getRect(find.byType(DuoRail)).right, 800);
    expect(find.bySemanticsLabel('Queue'), findsOneWidget);
    edge.value = DuoBarEdge.left;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(DuoRail)).left, 0);
    expect(tester.state(find.byType(TextField)), same(input));
    edge.value = DuoBarEdge.none;
    await tester.pumpAndSettle();
    expect(find.byType(DuoRail), findsNothing);
    expect(text.text, 'song');
    expect(tester.state(find.byType(TextField)), same(input));
  });

  testWidgets('short rail keeps overflow actions reachable', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 76,
            height: 140,
            child: DuoRail(
              bounds: const Rect.fromLTWH(0, 0, 76, 140),
              obstructions: const [],
              items: List.generate(
                5,
                (i) => DuoRailItem(
                  icon: Icons.music_note,
                  label: 'Action $i',
                  onPressed: () => selected = i,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('duo-rail-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action 4'));
    await tester.pumpAndSettle();
    expect(selected, 4);
    expect(tester.takeException(), isNull);
  });
}
