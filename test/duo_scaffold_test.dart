import 'dart:ui' as ui;

import 'package:ai_music/src/presentation/duo_scaffold.dart';
import 'package:ai_music/src/presentation/duo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_music/src/presentation/design/app_icons.dart';

void main() {
  _foldTests();
  test('rail groups avoid camera, status and fold without wasting the edge', () {
    const bounds = Rect.fromLTWH(524, 0, 76, 500);
    const blocks = [
      Rect.fromLTWH(530, 8, 60, 80),
      Rect.fromLTWH(530, 100, 60, 40),
      Rect.fromLTWH(0, 260, 600, 20),
    ];
    final segments = DuoRail.freeSegments(bounds, blocks);
    expect(segments, hasLength(2));
    expect(segments.first.top, lessThan(200));
    for (final segment in segments) {
      expect(blocks.any(segment.overlaps), isFalse);
    }
    // Back and actions take the stretch under the camera; the tabs sit at the
    // bottom below the fold, like the system's own bar.
    final items = [
      const DuoRailItem(
        icon: AppIcons.back,
        label: 'Back',
        leading: true,
      ),
      for (var i = 0; i < 2; i++)
        DuoRailItem(icon: AppIcons.heartFill, label: 'Action $i'),
      for (var i = 0; i < 4; i++)
        DuoRailItem(icon: Icons.home, label: 'Tab $i', navigation: true),
    ];
    // Under the camera only back and a menu fit; the menu joins its capsule.
    final plan = DuoRail.layout(items, bounds, blocks);
    expect(plan.leading, hasLength(1));
    expect(plan.actions, isEmpty);
    expect(plan.overflow, hasLength(2));
    expect(plan.mergedOverflow, isTrue);
    expect(plan.tabs, hasLength(4));
    expect(plan.top, greaterThanOrEqualTo(140));
    expect(plan.tabsTop, greaterThan(280));
    expect(
      plan.tabsTop + DuoRail.capsuleHeight(4),
      lessThanOrEqualTo(bounds.height - 8),
    );
    // A tall open strip shows every group in place.
    final tall = DuoRail.layout(
      items,
      const Rect.fromLTWH(0, 0, 76, 600),
      const [],
    );
    expect(tall.leading, hasLength(1));
    expect(tall.actions, hasLength(2));
    expect(tall.overflow, isEmpty);
    expect(tall.tabs, hasLength(4));
    expect(tall.tabsTop, 600 - 8 - DuoRail.capsuleHeight(4));
    // A short strip keeps back, then tabs, and folds actions into the menu.
    final short = DuoRail.layout(
      items,
      const Rect.fromLTWH(0, 0, 76, 330),
      const [],
    );
    expect(short.leading, hasLength(1));
    expect(short.tabs, hasLength(4));
    expect(short.overflow, hasLength(2));
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
                  icon: const Icon(AppIcons.heartFill),
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
              icon: AppIcons.queue,
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
                  icon: AppIcons.music,
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

Widget _foldedApp({required bool immersive, double foldTop = 380}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(600, 800),
            displayFeatures: [
              ui.DisplayFeature(
                bounds: Rect.fromLTWH(0, foldTop, 600, 40),
                type: ui.DisplayFeatureType.hinge,
                state: ui.DisplayFeatureState.postureHalfOpened,
              ),
            ],
          ),
          child: DuoScaffold(
            extendBodyBehindAppBar: immersive,
            appBar: AppBar(title: const Text('Page')),
            body: ListView(
              key: const Key('fold-list'),
              children: [
                for (var i = 0; i < 40; i++) ListTile(title: Text('Row $i')),
              ],
            ),
          ),
        ),
      ),
    );

void _foldTests() {
  testWidgets('a list page keeps to one side of a tabletop fold', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_foldedApp(immersive: false));
    final list = tester.getRect(find.byKey(const Key('fold-list')));
    expect(list.bottom, lessThanOrEqualTo(380));
    expect(find.byKey(const ValueKey('fold-side-top')), findsOneWidget);

    // A lower fold leaves more room below: the page moves under it.
    await tester.pumpWidget(_foldedApp(immersive: false, foldTop: 200));
    expect(
      tester.getRect(find.byKey(const Key('fold-list'))).top,
      greaterThanOrEqualTo(240),
    );

    // Immersive pages (the player) lay out both halves themselves.
    await tester.pumpWidget(_foldedApp(immersive: true));
    expect(find.byKey(const ValueKey('fold-side-top')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('fold-list'))).bottom,
      greaterThan(420),
    );
  });
}
