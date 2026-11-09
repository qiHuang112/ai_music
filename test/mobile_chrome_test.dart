import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/duo_scaffold.dart';
import 'package:ai_music/src/presentation/mobile_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = ['首页', '音乐库', '下载', '设置'];

  Finder slotOpacity() => find
      .ancestor(
        of: find.byKey(const ValueKey('floating-tab-bar')),
        matching: find.byType(AnimatedOpacity),
      )
      .first;

  Widget page(String name, {bool immersive = false}) => DuoScaffold(
    extendBodyBehindAppBar: immersive,
    appBar: AppBar(title: Text(name)),
    body: Builder(
      builder: (context) =>
          Text('$name inset ${MediaQuery.paddingOf(context).bottom}'),
    ),
  );

  testWidgets(
    'floating tabs stay over pushed pages, pop to the root on a tap and '
    'step aside for immersive pages',
    (tester) async {
      final chrome = MobileChrome.instance..enabled = true;
      final selected = <int>[];
      chrome.onTabSelected = selected.add;
      addTearDown(() {
        chrome
          ..enabled = false
          ..onTabSelected = null;
        chrome.tabs.value = null;
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: MusicAppTheme.create(Brightness.light),
          navigatorObservers: [chrome],
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [child!, const MobileChromeOverlay()],
          ),
          home: Builder(
            builder: (context) {
              chrome.publishTabs(
                const MobileTabs(labels: labels, index: 0, floating: true),
              );
              return page('root');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The root keeps clear of the capsule: margin plus its height.
      final inset = ChromeMetrics.inset(EdgeInsets.zero, bar: false);
      expect(find.text('root inset $inset'), findsOneWidget);
      expect(find.byKey(const ValueKey('floating-tab-bar')), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(slotOpacity()).opacity, 1);

      // A pushed page keeps the bar and the same inset.
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('pushed')),
      );
      await tester.pumpAndSettle();
      expect(find.text('pushed inset $inset'), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(slotOpacity()).opacity, 1);

      // Tapping a tab over it returns to the root, then selects the tab.
      await tester.tap(find.byKey(const ValueKey('floating-tab-2')));
      await tester.pumpAndSettle();
      expect(find.text('pushed inset $inset'), findsNothing);
      expect(selected, [2]);

      // The player-like immersive page has the bar step aside, and keeps
      // only the system inset.
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => page('player', immersive: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('player inset 0.0'), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(slotOpacity()).opacity, 0);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(slotOpacity()).opacity, 1);

      // Sheets and dialogs cover it as the system's would.
      showModalBottomSheet<void>(
        context: navigator.currentContext!,
        builder: (_) => const SizedBox(height: 200),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(slotOpacity()).opacity, 0);
    },
  );

  testWidgets('the tab pill follows a drag and springs onto the nearest tab', (
    tester,
  ) async {
    final chrome = MobileChrome.instance..enabled = true;
    final selected = <int>[];
    chrome.onTabSelected = selected.add;
    addTearDown(() {
      chrome
        ..enabled = false
        ..onTabSelected = null;
      chrome.tabs.value = null;
    });
    // The chrome is shared: forget what an earlier test published.
    chrome.publishTabs(const MobileTabs(labels: [], index: 0, floating: false));
    var index = 0;
    late StateSetter rebuild;
    chrome.onTabSelected = (i) {
      selected.add(i);
      rebuild(() => index = i);
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.light),
        navigatorObservers: [chrome],
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [child!, const MobileChromeOverlay()],
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            chrome.publishTabs(
              MobileTabs(labels: labels, index: index, floating: true),
            );
            return page('root');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder pill() => find.byKey(const ValueKey('floating-tab-pill'));
    double centerOf(Finder f) => tester.getCenter(f).dx;
    expect(
      centerOf(pill()),
      closeTo(centerOf(find.byKey(const ValueKey('floating-tab-0'))), 1),
    );

    // Picked up and carried: it lifts and follows the finger.
    final start = tester.getCenter(
      find.byKey(const ValueKey('floating-tab-0')),
    );
    final third = tester.getCenter(
      find.byKey(const ValueKey('floating-tab-2')),
    );
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(Offset((third.dx - start.dx - 30) / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    // Held, a glass lens magnifies the tabs under it and overhangs the bar.
    final lens = find.byKey(const ValueKey('floating-tab-lens'));
    expect(tester.getRect(lens).height, greaterThan(62));
    expect(tester.getCenter(lens).dx, closeTo(third.dx, 8));
    // The whole capsule swells a little while the lens is held.
    expect(
      tester.getRect(find.byKey(const ValueKey('floating-tab-bar'))).width,
      greaterThan(530),
    );
    expect(selected, isEmpty);

    // Let go: the tab is chosen and the pill settles on it at rest size.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);
    expect(centerOf(pill()), closeTo(third.dx, 1));
    expect(lens, findsNothing);
    // The capsule has wobbled back to its own shape.
    final bar = tester.getRect(find.byKey(const ValueKey('floating-tab-bar')));
    expect(bar.width, closeTo(520, .5));
    expect(bar.height, closeTo(62, .5));
    expect(tester.takeException(), isNull);
  });
}
