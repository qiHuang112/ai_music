import 'dart:async';

import 'package:ai_music/src/application/performance_monitor.dart';
import 'package:ai_music/src/presentation/performance_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ProcessCounters counters(double cpu, double time, {int mib = 128}) =>
    ProcessCounters(
      cpuTimeMs: cpu,
      elapsedTimeMs: time,
      memoryBytes: mib * 1024 * 1024,
      memoryKind: 'PSS',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CPU uses elapsed process time, preserves multicore usage and resets invalid baselines',
    () {
      expect(counters(3100, 3000).cpuPercentSince(counters(100, 1000)), 150);
      expect(counters(1, 3000).cpuPercentSince(counters(100, 1000)), isNull);
      expect(counters(110, 1000).cpuPercentSince(counters(100, 1000)), isNull);
      expect(counters(110, 1000).cpuPercentSince(null), isNull);
    },
  );

  test(
    'frames use display budget and elapsed sampling time, idle is not a slow frame',
    () {
      final frames = FrameAccumulator();
      frames.add(List.filled(58, const FrameObservation(3, 4, 12)));
      frames.add(const [
        FrameObservation(12, 3, 15),
        FrameObservation(3, 20, 30),
      ]);
      final summary = frames.drain(const Duration(seconds: 2), 120);
      expect(summary.fps, 30);
      expect(summary.slowFrames, 2);
      expect(summary.maxUiMs, 12);
      expect(summary.maxRasterMs, 20);
      expect(summary.p95RasterMs, 4);
      expect(summary.idle, isFalse);
      final idle = frames.drain(const Duration(seconds: 2), 120);
      expect(idle.frames, 0);
      expect(idle.idle, isTrue);
      expect(idle.slowFrames, 0);
    },
  );

  test(
    'sampler bridge returns native counters and does not fabricate unavailable values',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var calls = 0;
      messenger.setMockMethodCallHandler(NativePerformanceSampler.channel, (
        call,
      ) async {
        calls++;
        if (calls == 2) throw MissingPluginException();
        return {
          'cpuTimeMs': 120,
          'elapsedTimeMs': 1000,
          'memoryBytes': 134217728,
          'memoryKind': 'PSS',
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativePerformanceSampler.channel,
          null,
        ),
      );
      final sampler = NativePerformanceSampler();
      expect((await sampler.sample())!.memoryBytes, 134217728);
      expect(await sampler.sample(), isNull);
      expect((await sampler.sample())!.memoryBytes, 134217728);
      expect(calls, 3, reason: 'A bridge attached after startup must recover');
      expect(await NativePerformanceSampler(supported: false).sample(), isNull);
      expect(calls, 3);
    },
  );

  test(
    'monitor aggregates logs, throttles long frames and retains scene context',
    () async {
      var now = Duration.zero;
      final logs = <Map<String, Object?>>[];
      final monitor = PerformanceMonitor(
        automaticSampling: false,
        now: () => now,
        displayHz: () => 60,
        sampleProcess: () async =>
            counters(now.inMilliseconds * .25, now.inMilliseconds.toDouble()),
        context: () => {'skin': 'neon', 'playing': true},
        log: (name, details) => logs.add({'name': name, ...details}),
      );
      addTearDown(monitor.dispose);
      monitor.setEnabled(true);
      for (var i = 1; i <= 5; i++) {
        now = Duration(seconds: i * 2);
        monitor.recordFrames([
          ...List.filled(60, const FrameObservation(3, 4, 12)),
          const FrameObservation(140, 10, 180),
        ]);
        await monitor.sampleNow();
      }
      expect(monitor.snapshot!.cpuPercent, 25);
      expect(monitor.snapshot!.memoryMiB, 128);
      final samples = logs
          .where((e) => e['name'] == 'performance.sample')
          .toList();
      expect(samples.length, 1);
      expect(samples.single['fps'], 30.5);
      expect(samples.single['frames'], 305);
      expect(samples.single['slowFrames'], 5);
      expect(samples.single['skin'], 'neon');
      expect(samples.single['playing'], isTrue);
      expect(logs.where((e) => e['name'] == 'performance.jank').length, 2);
    },
  );

  test(
    'closing, reopening and backgrounding discard stale asynchronous samples',
    () async {
      var now = Duration.zero, calls = 0;
      final pending = Completer<ProcessCounters?>();
      final monitor = PerformanceMonitor(
        automaticSampling: false,
        now: () => now,
        sampleProcess: () {
          calls++;
          return calls == 1
              ? pending.future
              : Future.value(counters(10, now.inMilliseconds.toDouble()));
        },
        log: (_, _) {},
      );
      addTearDown(monitor.dispose);
      monitor.setEnabled(true);
      final old = monitor.sampleNow();
      monitor.setEnabled(false);
      monitor.setEnabled(true);
      await monitor.sampleNow();
      expect(calls, 1, reason: 'Resource reads never overlap');
      pending.complete(counters(999, 1000, mib: 999));
      await old;
      expect(monitor.snapshot, isNull);
      now = const Duration(seconds: 2);
      await monitor.sampleNow();
      expect(monitor.snapshot!.memoryMiB, 128);
      expect(monitor.snapshot!.cpuPercent, isNull);
      monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = const Duration(seconds: 30);
      await monitor.sampleNow();
      expect(calls, 2);
      monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = const Duration(seconds: 32);
      await monitor.sampleNow();
      expect(
        monitor.snapshot!.cpuPercent,
        isNull,
        reason: 'Background CPU is not attributed to foreground UI',
      );
      monitor.setEnabled(false);
      await monitor.sampleNow();
      expect(calls, 3);
    },
  );

  test(
    'skin/page changes end the old logging segment before the new context',
    () async {
      var now = Duration.zero, skin = 'dark';
      final logs = <Map<String, Object?>>[];
      final monitor = PerformanceMonitor(
        automaticSampling: false,
        now: () => now,
        context: () => {'skin': skin},
        sampleProcess: () async => counters(0, now.inMilliseconds.toDouble()),
        log: (name, details) => logs.add({'name': name, ...details}),
      );
      addTearDown(monitor.dispose);
      monitor.setEnabled(true);
      monitor.recordFrames(List.filled(60, const FrameObservation(3, 4, 12)));
      now = const Duration(seconds: 2);
      await monitor.sampleNow();
      monitor.contextWillChange('skin');
      skin = 'silver';
      final old = logs.where((e) => e['name'] == 'performance.sample').single;
      expect(old['skin'], 'dark');
      expect(old['reason'], 'skin_change');
      monitor.recordFrames(List.filled(30, const FrameObservation(3, 4, 12)));
      now = const Duration(seconds: 3);
      monitor.setRoute('player');
      await monitor.sampleNow();
      expect(
        monitor.snapshot!.cpuPercent,
        0,
        reason: 'Process CPU stays continuous across navigation',
      );
      final last = logs.where((e) => e['name'] == 'performance.sample').last;
      expect(last['skin'], 'silver');
      expect(last['frames'], 30);
      expect(last['route'], '/');
      expect(monitor.route, 'player');
    },
  );

  testWidgets(
    'small three-row overlay survives routes, drags and stops with the setting',
    (tester) async {
      final monitor = PerformanceMonitor(
        automaticSampling: false,
        sampleProcess: () async => counters(0, 1000),
        log: (_, _) {},
      );
      addTearDown(monitor.dispose);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [monitor.routes],
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              child!,
              PerformanceOverlayPanel(monitor: monitor),
            ],
          ),
          home: const Scaffold(body: Center(child: Text('home content'))),
        ),
      );
      expect(find.byKey(const Key('performance-overlay')), findsNothing);
      monitor.setEnabled(true);
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('performance-overlay'));
      final before = tester.getTopLeft(panel);
      await tester.drag(panel, const Offset(-140, 150));
      await tester.pump();
      expect(tester.getTopLeft(panel).dx, lessThan(before.dx));
      expect(tester.getTopLeft(panel).dy, greaterThan(before.dy));
      final pointer = await tester.startGesture(
        tester.getTopLeft(panel) + const Offset(40, 16),
      );
      await pointer.moveBy(const Offset(-25, 0));
      await tester.pump();
      final burstStart = tester.getTopLeft(panel);
      for (var i = 0; i < 6; i++) {
        await pointer.moveBy(const Offset(10, 0));
      }
      await pointer.up();
      await tester.pump();
      expect(
        tester.getTopLeft(panel).dx - burstStart.dx,
        closeTo(60, 1),
        reason: 'All pointer deltas between frames must be accumulated',
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'detail'),
          builder: (_) => const Scaffold(body: Text('detail content')),
        ),
      );
      await tester.pumpAndSettle();
      expect(monitor.route, 'detail');
      expect(panel, findsOneWidget);
      expect(find.text('detail content'), findsOneWidget);
      expect(find.text('FPS'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      final text = tester.widgetList<Text>(
        find.descendant(of: panel, matching: find.byType(Text)),
      );
      expect(text.length, 6, reason: 'Only three labels and three values');
      expect(find.byType(Icon), findsNothing);
      expect(tester.getSize(panel), const Size(128, 72));
      monitor.setEnabled(false);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(monitor.active, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'event-loop stalls are logged without counting time spent in background',
    (tester) async {
      var now = Duration.zero;
      final logs = <Map<String, Object?>>[];
      final monitor = PerformanceMonitor(
        now: () => now,
        sampleProcess: () async => counters(1, now.inMilliseconds.toDouble()),
        log: (name, details) => logs.add({'name': name, ...details}),
      );
      monitor.setEnabled(true);
      now = const Duration(seconds: 8);
      await tester.pump(const Duration(seconds: 2));
      expect(
        logs.where((e) => e['name'] == 'performance.stall').single['delayMs'],
        6000,
      );
      monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = const Duration(seconds: 100);
      await tester.pump(const Duration(seconds: 4));
      monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = const Duration(seconds: 102);
      await tester.pump(const Duration(seconds: 2));
      expect(logs.where((e) => e['name'] == 'performance.stall').length, 1);
      monitor.dispose();
    },
  );

  testWidgets(
    'small screen and keyboard keep the dragged overlay in the visible area',
    (tester) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final monitor = PerformanceMonitor(
        automaticSampling: false,
        log: (_, _) {},
      );
      addTearDown(monitor.dispose);
      monitor.setEnabled(true);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 360),
              padding: EdgeInsets.only(top: 24, bottom: 20),
              viewInsets: EdgeInsets.only(bottom: 180),
              textScaler: TextScaler.linear(3),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child!,
                PerformanceOverlayPanel(monitor: monitor),
              ],
            ),
          ),
          home: const Scaffold(),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('performance-overlay'));
      await tester.drag(panel, const Offset(1000, 1000));
      await tester.pump();
      final rect = tester.getRect(panel);
      expect(rect.top, greaterThanOrEqualTo(30));
      expect(rect.bottom, lessThanOrEqualTo(160));
      expect(rect.right, lessThanOrEqualTo(314));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
