import 'package:ai_music/src/presentation/design/ambient_backdrop.dart';
import 'package:ai_music/src/presentation/design/ambient_clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('backdrop clocks hold still while a page change animates', (
    tester,
  ) async {
    var time = const Duration(seconds: 100);
    final realNow = AmbientClock.now;
    AmbientClock.now = () => time;
    addTearDown(() => AmbientClock.now = realNow);
    final sky = AmbientClock(fps: 15, backdrop: true);
    final record = AmbientClock(fps: 15);
    sky.run(true);
    record.run(true);
    await tester.pump(const Duration(milliseconds: 200));
    final skyBefore = sky.value, recordBefore = record.value;
    expect(skyBefore, greaterThan(0));

    AmbientClock.quietBackdrops(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 300));
    // The sky waits; the record in front keeps turning.
    expect(sky.value, skyBefore);
    expect(record.value, greaterThan(recordBefore));

    // Afterwards the sky goes on from where it stopped, without a jump.
    time += const Duration(milliseconds: 500);
    await tester.pump(const Duration(milliseconds: 70));
    expect(sky.value, closeTo(skyBefore + 1 / 15, 1e-9));
    sky.dispose();
    record.dispose();
  });

  testWidgets('the aurora is never cached apart from what it lights', (
    tester,
  ) async {
    // It adds light to what lies under it; cached into a clear texture of
    // its own it came out darker, and alternated with the direct drawing.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(enabled: false, child: AuroraLights()),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AuroraLights),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.willChange, isTrue);
  });
}
