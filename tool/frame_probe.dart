// Records a profile build's timeline around one page change and says where
// each frame's time went. The deep-dive step after the in-app page-change
// log has said which change stutters; see docs/performance-diagnostics.md.
//
//   dart run tool/frame_probe.dart --device 192.168.31.78:38015 \
//       --tap 500,1165 [--widgets] [--seconds 1.5]
//   dart run tool/frame_probe.dart --device ... --back   # the back key
//
// The app must be a profile build (flutter build apk --profile) already
// running on the device. Without --tap it records for --seconds while you
// make the change by hand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stdout.writeln(_usage);
    exitCode = 64;
    return;
  }
  final uri = await _serviceUri(options.device);
  final service = await vmServiceConnectUri(uri);
  try {
    final isolate = (await service.getVM()).isolates!
        .firstWhere((i) => i.name == 'main')
        .id!;
    Future<void> detail(bool on) async {
      for (final name in [
        'profileUserWidgetBuilds',
        'profileRenderObjectLayouts',
      ]) {
        await service.callServiceExtension(
          'ext.flutter.$name',
          isolateId: isolate,
          args: {'enabled': '$on'},
        );
      }
    }

    if (options.widgets) await detail(true);
    await service.setVMTimelineFlags(['Embedder', 'Dart', 'GC']);
    await service.clearVMTimeline();
    if (options.back || options.tap != null) {
      // Never press keys or tap in whatever else is in front.
      final focus = await _adb(options.device, ['shell', 'dumpsys', 'window']);
      final front = RegExp(r'mCurrentFocus=\S+ \S+ (\S+)').firstMatch(focus);
      if (!(front?.group(1) ?? '').startsWith('com.qi.ai.music')) {
        throw StateError(
          'The app is not in front (${front?.group(1) ?? 'unknown'}); '
          'nothing was pressed.',
        );
      }
    }
    if (options.back) {
      await _adb(options.device, ['shell', 'input', 'keyevent', '4']);
    } else if (options.tap != null) {
      await _adb(options.device, ['shell', 'input', 'tap', ...options.tap!]);
    } else {
      stdout.writeln('Recording ${options.seconds} s: make the change now.');
    }
    await Future<void>.delayed(
      Duration(milliseconds: (options.seconds * 1000).round()),
    );
    final timeline = await service.getVMTimeline();
    if (options.widgets) await detail(false);
    final events = <Map<String, dynamic>>[
      for (final e in timeline.traceEvents ?? const []) e.json!,
    ];
    final out = Directory(options.out)..createSync(recursive: true);
    final file = File(
      '${out.path}/probe-${DateTime.now().millisecondsSinceEpoch}.json',
    )..writeAsStringSync(jsonEncode(events));
    stdout
      ..writeln(
        _report(events, options.hz, Duration(milliseconds: options.window)),
      )
      ..writeln('Timeline: ${file.path} (open in ui.perfetto.dev)');
  } finally {
    await service.dispose();
  }
}

const _usage = '''
dart run tool/frame_probe.dart --device <adb serial or host:port>
    [--tap x,y | --back] [--seconds 1.5] [--widgets] [--hz 90] [--window 450]
    [--out build/frame_probe]''';

class _Options {
  _Options(
    this.device,
    this.tap,
    this.back,
    this.seconds,
    this.widgets,
    this.hz,
    this.window,
    this.out,
  );

  final String device;
  final List<String>? tap;
  final bool back;
  final double seconds, hz;
  final bool widgets;
  final String out;
  final int window;

  static _Options? parse(List<String> args) {
    String? device, out;
    List<String>? tap;
    var back = false;
    var seconds = 1.5, hz = 90.0;
    var window = 450;
    var widgets = false;
    for (var i = 0; i < args.length; i++) {
      String next() => i + 1 < args.length ? args[++i] : '';
      switch (args[i]) {
        case '--device':
          device = next();
        case '--tap':
          tap = next().split(',');
        case '--back':
          back = true;
        case '--seconds':
          seconds = double.tryParse(next()) ?? seconds;
        case '--hz':
          hz = double.tryParse(next()) ?? hz;
        case '--window':
          window = int.tryParse(next()) ?? window;
        case '--widgets':
          widgets = true;
        case '--out':
          out = next();
        default:
          return null;
      }
    }
    if (device == null || (tap != null && tap.length != 2)) return null;
    return _Options(
      device,
      tap,
      back,
      seconds,
      widgets,
      hz,
      window,
      out ?? 'build/frame_probe',
    );
  }
}

Future<String> _adb(String device, List<String> args) async {
  final result = await Process.run('adb', ['-s', device, ...args]);
  if (result.exitCode != 0) {
    throw StateError('adb ${args.join(' ')}: ${result.stderr}');
  }
  return result.stdout as String;
}

/// The app's VM service, from its startup line in logcat, forwarded here.
Future<String> _serviceUri(String device) async {
  final log = await _adb(device, ['logcat', '-d', '-s', 'flutter']);
  final match = RegExp(
    r'http://127\.0\.0\.1:(\d+)/([^/\s]+)/',
  ).allMatches(log).lastOrNull;
  if (match == null) {
    throw StateError(
      'No Dart VM service in logcat: start a profile build of the app '
      '(release builds have none), then run this again.',
    );
  }
  final forward = await _adb(device, ['forward', 'tcp:0', 'tcp:${match[1]}']);
  return 'ws://127.0.0.1:${forward.trim()}/${match[2]}/ws';
}

class _Span {
  _Span(this.name, this.start, this.ms, this.depth);

  final String name;
  final int start, depth;
  final double ms;
}

/// Complete spans per thread, matching begin and end events.
Map<Object?, List<_Span>> _spans(List<Map<String, dynamic>> events) {
  events.sort((a, b) => (a['ts'] as num? ?? 0).compareTo(b['ts'] as num? ?? 0));
  final open = <Object?, List<Map<String, dynamic>>>{};
  final spans = <Object?, List<_Span>>{};
  for (final event in events) {
    final thread = event['tid'];
    switch (event['ph']) {
      case 'B':
        open.putIfAbsent(thread, () => []).add(event);
      case 'E':
        final stack = open[thread];
        if (stack == null || stack.isEmpty) continue;
        final begin = stack.removeLast();
        final start = (begin['ts'] as num).toInt();
        spans
            .putIfAbsent(thread, () => [])
            .add(
              _Span(
                begin['name'] as String,
                start,
                ((event['ts'] as num) - start) / 1000,
                stack.length,
              ),
            );
      case 'X':
        spans
            .putIfAbsent(thread, () => [])
            .add(
              _Span(
                event['name'] as String,
                (event['ts'] as num).toInt(),
                (event['dur'] as num? ?? 0) / 1000,
                0,
              ),
            );
    }
  }
  return spans;
}

String _report(List<Map<String, dynamic>> events, double hz, Duration window) {
  final budget = 1000 / hz;
  final threads = _spans(events);
  final all = [for (final list in threads.values) ...list]
    ..sort((a, b) => a.start.compareTo(b.start));
  // The change starts at the last touch (a tap's lift) or key; the frames that
  // count are the ones in the window after it.
  final touches = all.where(
    (s) => s.name == 'Engine::DispatchPointerDataPacket',
  );
  final frames = all.where((s) => s.name == 'Animator::BeginFrame').toList();
  if (frames.isEmpty) return 'No frames drawn while recording.';
  // A key (back) has no touch; it arrives as a platform message.
  final keys = all.where(
    (s) => s.name == 'RuntimeController::DispatchPlatformMessage',
  );
  final t0 =
      touches.lastOrNull?.start ??
      keys.firstOrNull?.start ??
      frames.first.start;
  final end = t0 + window.inMicroseconds;
  bool inside(_Span s) => s.start >= t0 && s.start <= end;
  final ui = frames.where(inside).toList();
  if (ui.isEmpty) return 'No frames drawn after the touch.';
  // Each raster pass belongs to the last frame built before it began.
  final raster = <_Span, _Span>{};
  for (final pass in all.where((s) => s.name == 'GPURasterizer::Draw')) {
    final owner = ui.lastWhere(
      (f) => f.start + f.ms * 1000 <= pass.start,
      orElse: () => ui.first,
    );
    if (inside(pass) || pass.start <= end + 50000) raster[owner] ??= pass;
  }
  String at(int t) => ((t - t0) / 1000).toStringAsFixed(1).padLeft(7);
  String mark(double ms) => ms > budget ? '*' : ' ';
  final b = StringBuffer()
    ..writeln(
      'Frames in the ${window.inMilliseconds} ms after the touch '
      '(budget ${budget.toStringAsFixed(1)} ms; * over):',
    );
  var dropped = 0;
  for (var i = 0; i < ui.length; i++) {
    final frame = ui[i];
    final pass = raster[frame];
    if (i > 1) {
      final gap = (frame.start - ui[i - 1].start) / 1000;
      dropped += math.max(0, (gap / budget).round() - 1);
    }
    b.writeln(
      '  ${at(frame.start)} ms  UI ${frame.ms.toStringAsFixed(1).padLeft(5)}'
      '${mark(frame.ms)}  raster '
      '${pass == null ? '    -' : pass.ms.toStringAsFixed(1).padLeft(5)}'
      '${mark(pass?.ms ?? 0)}',
    );
  }
  final compiles = all.where((s) => s.name == 'cache_miss' && inside(s));
  b
    ..writeln(
      'Dropped vsyncs after the first frame: $dropped; shaders compiled: '
      '${compiles.length} '
      '(${compiles.fold(0.0, (t, s) => t + s.ms).toStringAsFixed(1)} ms)',
    )
    ..writeln('UI-thread own time by name (widgets need --widgets):');
  // The UI thread is the one that runs BeginFrame.
  final uiThread =
      threads.values
          .firstWhere((l) => l.any((s) => s.name == 'Animator::BeginFrame'))
          .where(inside)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  // Own time: a span's time less its direct children's.
  final own = <_Span, double>{for (final s in uiThread) s: s.ms};
  final stack = <_Span>[];
  for (final span in uiThread) {
    while (stack.isNotEmpty &&
        stack.last.start + stack.last.ms * 1000 <= span.start) {
      stack.removeLast();
    }
    if (stack.isNotEmpty) own[stack.last] = own[stack.last]! - span.ms;
    stack.add(span);
  }
  const structure = {
    'Animator::BeginFrame',
    'VsyncProcessCallback',
    'AsyncWaitForVsync',
    'DartIsolate::HandleMessage',
    'NotifyIdle',
    'BeginFrame idle callback',
    'BUILD',
    'LAYOUT',
    'LAYOUT (root)',
    'PAINT',
    'PAINT (root)',
    'COMPOSITING',
    'POST_FRAME',
    'FINALIZE TREE',
    'SEMANTICS',
  };
  final byName = <String, (int, double)>{};
  own.forEach((span, ms) {
    if (structure.contains(span.name)) return;
    final (count, total) = byName[span.name] ?? (0, 0.0);
    byName[span.name] = (count + 1, total + math.max(0, ms));
  });
  final ranked = byName.entries.toList()
    ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
  for (final entry in ranked.take(15)) {
    if (entry.value.$2 < 1) break;
    b.writeln(
      '  ${entry.value.$2.toStringAsFixed(1).padLeft(6)} ms  ${entry.key}'
      '  ×${entry.value.$1}',
    );
  }
  return b.toString();
}
