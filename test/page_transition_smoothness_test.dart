import 'dart:async';

import 'package:ai_music/src/presentation/app_page_route.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/distinct_stream_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _Entrance extends StatefulWidget {
  const _Entrance(this.log);

  final List<String> log;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    afterRouteEntrance(context, () => widget.log.add('ran'));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => Text('$value');
}

Widget _app(GlobalKey<NavigatorState> navigator) => MaterialApp(
  theme: MusicAppTheme.create(Brightness.dark),
  navigatorKey: navigator,
  home: const SizedBox.expand(),
);

void main() {
  testWidgets('afterRouteEntrance waits for the slide, past the offstage '
      'first frame', (tester) async {
    // MaterialApp's hero controller lays a pushed page out offstage first,
    // when its animation reads as complete.
    final log = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      navigator.currentState!.push(
        AppPageRoute(builder: (_) => _Entrance(log)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    expect(log, isEmpty, reason: 'ran in the middle of the push');
    await tester.pumpAndSettle();
    expect(log, ['ran']);
  });

  test('a slow first frame does not jump the clock ahead', () {
    final grab = _Grab();
    final ticks = <Duration>[];
    final ticker = SlowFirstFrameVsync(grab).createTicker(ticks.add);
    grab.onTick!(Duration.zero);
    // The first frame took 45 ms: the next shows one frame's progress.
    grab.onTick!(const Duration(milliseconds: 45));
    grab.onTick!(const Duration(milliseconds: 56));
    expect(ticks, [
      Duration.zero,
      const Duration(microseconds: 16667),
      const Duration(microseconds: 27667),
    ]);
    // A new run with an ordinary first frame keeps its own pace.
    grab.onTick!(Duration.zero);
    grab.onTick!(const Duration(milliseconds: 11));
    expect(ticks.last, const Duration(milliseconds: 11));
    // A stall is only partly left out.
    grab.onTick!(Duration.zero);
    grab.onTick!(const Duration(milliseconds: 500));
    expect(ticks.last, const Duration(milliseconds: 350));
    ticker.dispose();
  });

  testWidgets('an opaque page pushed over another leaves it in place, state '
      'and all', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final navigator = GlobalKey<NavigatorState>();
      final counter = GlobalKey<_CounterState>();
      await tester.pumpWidget(_app(navigator));
      unawaited(
        navigator.currentState!.push(
          AppPageRoute(builder: (_) => _Counter(key: counter)),
        ),
      );
      await tester.pumpAndSettle();
      counter.currentState!.value = 7;
      final state = counter.currentState;
      unawaited(
        navigator.currentState!.push(
          AppPageRoute(
            coversBackdrop: true,
            builder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // Neither page sits in a fading layer: the new one arrives opaque and
      // the one under it need not fade out beneath it.
      final under = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(_Counter),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(under.every((fade) => fade.opacity.value == 1), isTrue);
      final over = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(ColoredBox).last,
          matching: find.byType(FadeTransition),
        ),
      );
      expect(over.every((fade) => fade.opacity.value == 1), isTrue);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Popped, the page below fades back in as pages always do, so the two
      // full pages are not both drawn for the whole slide.
      final returning = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(_Counter),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(returning.any((fade) => fade.opacity.value < 1), isTrue);
      await tester.pumpAndSettle();
      expect(counter.currentState, same(state));
      expect(counter.currentState!.value, 7);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('DistinctStreamBuilder ignores a replay of the shown value', (
    tester,
  ) async {
    final values = StreamController<int>.broadcast();
    var builds = 0;
    await tester.pumpWidget(
      DistinctStreamBuilder<int>(
        stream: values.stream,
        initialData: 1,
        builder: (context, value) {
          builds++;
          return Text('$value', textDirection: TextDirection.ltr);
        },
      ),
    );
    values.add(1);
    await tester.pump();
    await tester.pump();
    expect(builds, 1);
    values.add(2);
    await tester.pump();
    await tester.pump();
    expect(builds, 2);
    expect(find.text('2'), findsOneWidget);
    await values.close();
  });
}

/// Hands the wrapped callback to the test to call with chosen times.
class _Grab implements TickerProvider {
  TickerCallback? onTick;

  @override
  Ticker createTicker(TickerCallback onTick) {
    this.onTick = onTick;
    return Ticker(onTick);
  }
}
