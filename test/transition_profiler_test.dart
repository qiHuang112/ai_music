import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:ai_music/src/application/transition_profiler.dart';
import 'package:ai_music/src/presentation/app_page_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A frame [number] that started at [atMs] and spent [uiMs] building and
/// [rasterMs] rasterizing.
FrameTiming _frame(int number, double atMs, double uiMs, double rasterMs) {
  final start = (atMs * 1000).round();
  final built = start + (uiMs * 1000).round();
  final rastered = built + (rasterMs * 1000).round();
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: built,
    rasterStart: built,
    rasterFinish: rastered,
    rasterFinishWallTime: rastered,
    frameNumber: number,
  );
}

class _Notifier extends ChangeNotifier {
  void recordUsage() => TransitionProfiler.noteNotify(this);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<(String, Map<String, Object?>)> logs;
  late int frameNumber;
  late TransitionProfiler profiler;

  setUp(() {
    logs = [];
    frameNumber = 100;
    profiler = TransitionProfiler(
      log: (name, details) => logs.add((name, details)),
      displayHz: () => 90,
      frameNumber: () => frameNumber,
      summaryEvery: 3,
    );
    TransitionProfiler.instance = profiler;
  });

  tearDown(() => TransitionProfiler.instance = null);

  /// Opens a change, draws [frames] (number, ui, raster) a vsync apart
  /// unless [gaps] says otherwise, and closes it.
  void transition(
    String to,
    List<(double, double)> frames, {
    void Function(int index)? during,
    Map<int, double> gaps = const {},
    bool deliver = true,
    Duration duration = const Duration(milliseconds: 450),
  }) {
    profiler.begin('push', from: 'home', to: to, duration: duration);
    final timings = <FrameTiming>[];
    var at = 0.0;
    for (final (i, (ui, raster)) in frames.indexed) {
      frameNumber++;
      during?.call(i);
      profiler.recordFrame();
      at += gaps[i] ?? 11.1;
      timings.add(_frame(frameNumber, at, ui, raster));
    }
    profiler.finish();
    if (deliver) profiler.addTimings(timings);
  }

  List<Map<String, Object?>> janky() => [
    for (final (name, details) in logs)
      if (name == 'perf.transition') details,
  ];

  test('a smooth change logs nothing on its own', () {
    transition('playlist', [for (var i = 0; i < 30; i++) (4.0, 6.0)]);
    expect(janky(), isEmpty);
  });

  test('a notification mid-slide is named with its caller', () {
    final notifier = _Notifier();
    transition(
      'playlist',
      [
        (30.0, 8.0),
        (20.0, 8.0),
        (18.0, 8.0),
        for (var i = 0; i < 27; i++) (4.0, 6.0),
      ],
      during: (i) {
        if (i == 1) notifier.recordUsage();
      },
      gaps: {2: 22.2, 3: 22.2},
    );
    final entry = janky().single;
    expect(entry['to'], 'playlist');
    expect(entry['dropped'], 2);
    expect(entry['overBudgetUi'], 2);
    expect(entry['hints'], contains('notify_mid_slide'));
    final notify = (entry['notifies']! as List).single as Map;
    expect(notify['source'], '_Notifier');
    expect(notify['caller'], contains('recordUsage'));
  });

  test('slow raster on a first open points at shader compilation, later '
      'opens at heavy drawing', () {
    final heavy = [for (var i = 0; i < 30; i++) (4.0, i < 4 ? 30.0 : 6.0)];
    transition('player', heavy);
    transition('player', heavy);
    final entries = janky();
    expect(entries[0]['firstOpen'], true);
    expect(entries[0]['hints'], contains('raster_first_open'));
    expect(entries[1]['firstOpen'], false);
    expect(entries[1]['hints'], contains('raster_heavy'));
  });

  test('timings that arrive in a later batch still count', () {
    transition('lyrics', [
      (40.0, 6.0),
      for (var i = 0; i < 29; i++) (4.0, 6.0),
    ], deliver: false);
    expect(janky(), isEmpty);
    // Release sends timings up to a second late, in one batch.
    final late = <FrameTiming>[
      for (var n = 101; n <= 130; n++)
        _frame(n, n * 11.1, n == 101 ? 60.0 : 4.0, 6.0),
    ];
    profiler.addTimings(late);
    expect(janky().single['hints'], contains('first_frame_build'));
  });

  test(
    'a settled page drawing a few times a second is not dropping frames',
    () {
      transition(
        'playlist',
        [for (var i = 0; i < 30; i++) (4.0, 6.0)],
        duration: const Duration(milliseconds: 350),
        // After the slide the backdrop redraws at 15 frames a second.
        gaps: {for (var i = 33; i < 40; i++) i: 66.7},
      );
      transition(
        'playlist',
        [for (var i = 0; i < 40; i++) (4.0, 6.0)],
        duration: const Duration(milliseconds: 350),
        gaps: {for (var i = 33; i < 40; i++) i: 66.7},
      );
      expect(janky(), isEmpty);
    },
  );

  test('a notification just after the slide is told apart from one during '
      'it', () {
    final notifier = _Notifier();
    transition(
      'playlist',
      [for (var i = 0; i < 33; i++) (4.0, 6.0), (41.0, 6.0)],
      duration: const Duration(milliseconds: 350),
      during: (i) {
        if (i == 33) notifier.recordUsage();
      },
    );
    final entry = janky().single;
    expect(entry['hints'], ['notify_after_slide']);
    expect(entry['dropped'], 0);
    expect(entry['afterSlideWorstUiMs'], '41.0');
  });

  test('a route that says when its slide ended splits the frames there', () {
    final notifier = _Notifier();
    // Ten frames' slide that ends early, then a notification and a heavy
    // frame still inside the reckoned length.
    transition(
      'playlist',
      [for (var i = 0; i < 10; i++) (4.0, 6.0), (40.0, 6.0)],
      during: (i) {
        if (i == 9) {
          TransitionProfiler.noteSettled();
          notifier.recordUsage();
        }
      },
    );
    expect(janky().single['hints'], ['notify_after_slide']);
  });

  test('every few changes a summary per page goes to the log', () {
    for (var i = 0; i < 3; i++) {
      transition('settings', [for (var i = 0; i < 30; i++) (4.0, 6.0)]);
    }
    final summary = logs.singleWhere((e) => e.$1 == 'perf.transitions').$2;
    expect(
      TransitionProfiler.nameOf(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/'),
          builder: (_) => const SizedBox(),
        ),
      ),
      'home',
    );
    expect((summary['pages']! as Map)['push:settings'], {
      'n': 3,
      'janky': 0,
      'dropped': 0,
      'worstUiMs': 4.0,
      'worstRasterMs': 6.0,
    });
  });

  testWidgets('pages pushed without a name are logged by their widget', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [profiler],
        home: const SizedBox.expand(),
      ),
    );
    final route = AppPageRoute<void>(builder: (_) => const Placeholder());
    unawaited(navigator.currentState!.push(route));
    await tester.pumpAndSettle();
    profiler.finish();
    expect(TransitionProfiler.nameOf(route), 'Placeholder');
  });
}
