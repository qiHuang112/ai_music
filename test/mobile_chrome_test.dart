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
}
