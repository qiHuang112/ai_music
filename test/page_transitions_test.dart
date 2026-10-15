import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android route content keeps fading while zoom snapshots animate', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.android),
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: ColoredBox(color: Colors.black, child: child!),
        ),
        navigatorKey: navigator,
        home: const Scaffold(),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Future<int> blue() async {
      final box =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await box.toImage();
        try {
          final data = (await image.toByteData())!;
          return data.getUint8(
            ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4 + 2,
          );
        } finally {
          image.dispose();
        }
      }))!;
    }

    await tester.pump(const Duration(milliseconds: 90));
    final early = await blue();
    expect(early, lessThan(220));
    await tester.pump(const Duration(milliseconds: 160));
    final later = await blue();
    expect(
      later,
      greaterThan(220),
      reason:
          'The page must continue appearing during the transition, not freeze until the last frame',
    );
    await tester.pumpAndSettle();
    expect(await blue(), greaterThan(200));
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      await blue(),
      lessThan(30),
      reason: 'Leaving content must fade during the reverse transition',
    );
    await tester.pumpAndSettle();
    expect(await blue(), 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('iOS retains its interactive edge swipe', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        navigatorKey: navigator,
        home: const Scaffold(body: Text('settings')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('appearance')),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(600, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(navigator.currentState!.canPop(), isFalse);
    expect(find.text('settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
