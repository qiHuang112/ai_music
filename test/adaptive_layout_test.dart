import 'package:ai_music/src/presentation/design/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _sized(double width, Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  // Room for the widest case; each test sizes its own box inside.
  void wideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('window classes share one set of breakpoints', () {
    expect(MusicLayout.classOf(390), WindowClass.compact);
    expect(MusicLayout.classOf(600), WindowClass.medium);
    expect(MusicLayout.classOf(839), WindowClass.medium);
    expect(MusicLayout.classOf(840), WindowClass.expanded);
  });

  test('centered insets cap the content and keep phones unchanged', () {
    const base = EdgeInsets.fromLTRB(20, 16, 20, 24);
    expect(MusicLayout.centered(base, 390), base);
    final wide = MusicLayout.centered(base, 1200);
    expect(1200 - wide.horizontal, MusicLayout.readableWidth);
    expect(wide.top, 16);
    expect(wide.left, wide.right);
  });

  testWidgets('tiles add columns instead of stretching', (tester) async {
    wideView(tester);
    Future<double> tileWidth(double width) async {
      await tester.pumpWidget(
        _sized(
          width,
          AdaptiveTiles(
            children: [
              for (var i = 0; i < 4; i++) SizedBox(key: Key('t$i'), height: 40),
            ],
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('t0'))).width;
    }

    expect(await tileWidth(350), closeTo((350 - 12) / 2, 1));
    expect(await tileWidth(1000), closeTo((1000 - 36) / 4, 1));
    // A growing list keeps every column that fits, last row partly filled.
    await tester.pumpWidget(
      _sized(
        1000,
        AdaptiveTiles(
          minTileWidth: 300,
          minColumns: 1,
          fullRows: false,
          children: [
            for (var i = 0; i < 4; i++) SizedBox(key: Key('l$i'), height: 40),
          ],
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('l2'))).dy,
      tester.getTopLeft(find.byKey(const Key('l0'))).dy,
    );
    // 3 would fit at 500 but leave an orphan; 4 tiles go two across.
    expect(await tileWidth(500), closeTo((500 - 12) / 2, 1));
  });

  testWidgets('columns stack on narrow space and sit side by side on wide', (
    tester,
  ) async {
    wideView(tester);
    Future<(Offset, Offset)> place(double width) async {
      await tester.pumpWidget(
        _sized(
          width,
          const AdaptiveColumns(
            primary: [SizedBox(key: Key('a'), height: 40)],
            secondary: [SizedBox(key: Key('b'), height: 40)],
          ),
        ),
      );
      return (
        tester.getTopLeft(find.byKey(const Key('a'))),
        tester.getTopLeft(find.byKey(const Key('b'))),
      );
    }

    final (a, b) = await place(500);
    expect(b.dx, a.dx);
    expect(b.dy, greaterThan(a.dy));
    final (wa, wb) = await place(1000);
    expect(wb.dy, wa.dy);
    expect(wb.dx, greaterThan(wa.dx + 400));
  });

  testWidgets('actions share a phone row and keep their size when wide', (
    tester,
  ) async {
    wideView(tester);
    Future<double> width(double rowWidth) async {
      await tester.pumpWidget(
        _sized(
          rowWidth,
          AdaptiveActions(
            actions: [
              FilledButton(
                key: const Key('one'),
                onPressed: () {},
                child: const Text('New'),
              ),
              TextButton(onPressed: () {}, child: const Text('Add')),
            ],
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('one'))).width;
    }

    expect(await width(360), closeTo((360 - 8) / 2, 1));
    expect(await width(1000), lessThanOrEqualTo(MusicLayout.actionMaxWidth));
  });
}
