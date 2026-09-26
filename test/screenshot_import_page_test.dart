import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/platform/screenshot_ocr.dart';
import 'package:ai_music/src/presentation/screenshot_import_page.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected screenshot batch starts in capture order', () {
    final ordered = orderPickedScreenshots([
      XFile('/tmp/Screenshot_2026-09-25-18-44-40.jpg'),
      XFile('/tmp/Screenshot_2026-09-25-18-44-20.jpg'),
      XFile('/tmp/Screenshot_2026-09-25-18-44-31.jpg'),
    ]);
    expect(ordered.map((image) => image.name), [
      'Screenshot_2026-09-25-18-44-20.jpg',
      'Screenshot_2026-09-25-18-44-31.jpg',
      'Screenshot_2026-09-25-18-44-40.jpg',
    ]);
  });

  testWidgets(
    'OCR verification selects valid matches and edit refreshes one song',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('screenshot_import_'),
      );
      if (root == null) fail('could not create test image directory');
      final image = File('${root.path}/shot.png');
      await tester.runAsync(
        () => image.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
            'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
          ),
        ),
      );
      final handler = MusicAudioHandler();
      final controller = MusicController(audioHandler: handler);
      final resolver = _Resolver();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ScreenshotImportPage(
              controller: controller,
              ocr: _Ocr(),
              openPickerOnStart: true,
              pickImages: () async => [XFile(image.path)],
              matcher: ScreenshotMatcher(
                resolver: resolver,
                wait: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('稻向'), findsOneWidget);
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(find.textContaining('周杰伦 · 图1'), findsOneWidget);
        expect(resolver.queries, ['稻向']);
        expect(find.text('一键匹配推荐项'), findsNothing);

        await tester.tap(find.byTooltip('修改识别结果'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '稻香');
        await tester.tap(find.text('保存并重新搜索'));
        await tester.pumpAndSettle();

        expect(resolver.queries, ['稻向', '稻香']);
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(resolver.resolveCount, 0);

        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expect(find.text('已选 0 首'), findsOneWidget);
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(resolver.resolveCount, 0);

        await tester.tap(find.text('稻香'));
        await tester.pumpAndSettle();
        expect(resolver.queries, ['稻向', '稻香']);
        expect(find.text('稻香', skipOffstage: false), findsWidgets);
        expect(find.text('加入歌单'), findsOneWidget);
        expect(find.text('下载已选'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(handler.dispose());
        root.deleteSync(recursive: true);
      }
    },
  );

  testWidgets(
    'expanding a song shows actual returned choices without searching',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('screenshot_choices_'),
      );
      if (root == null) fail('could not create test image directory');
      final image = File('${root.path}/shot.png');
      await tester.runAsync(
        () => image.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
            'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
          ),
        ),
      );
      final handler = MusicAudioHandler();
      final controller = MusicController(audioHandler: handler);
      final resolver = _Resolver(choiceCount: 3);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ScreenshotImportPage(
              controller: controller,
              ocr: const _Ocr('稻香 - 周杰伦'),
              openPickerOnStart: true,
              pickImages: () async => [XFile(image.path)],
              matcher: ScreenshotMatcher(
                resolver: resolver,
                wait: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(resolver.queries, ['稻香']);
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(find.textContaining('候选 3 首'), findsOneWidget);
        expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

        await tester.tap(find.text('稻香'));
        await tester.pumpAndSettle();
        expect(resolver.queries, ['稻香']);
        expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
        expect(find.text('候选 2'), findsOneWidget);
        await tester.tap(find.text('候选 2'));
        await tester.pumpAndSettle();
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(resolver.queries, ['稻香']);
        expect(resolver.resolveCount, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        unawaited(handler.dispose());
        root.deleteSync(recursive: true);
      }
    },
  );

  testWidgets('OCR rows stay pending until interface verification finishes', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('screenshot_pending_'),
    );
    if (root == null) fail('could not create test image directory');
    final image = File('${root.path}/shot.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
          'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
        ),
      ),
    );
    final handler = MusicAudioHandler();
    final controller = MusicController(audioHandler: handler);
    final gate = Completer<void>();
    final resolver = _Resolver(searchGate: gate);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenshotImportPage(
            controller: controller,
            ocr: const _Ocr('稻香 - 周杰伦'),
            openPickerOnStart: true,
            pickImages: () async => [XFile(image.path)],
            matcher: ScreenshotMatcher(resolver: resolver, wait: (_) async {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(resolver.queries, ['稻香']);
      expect(find.text('稻香'), findsNothing);
      expect(find.textContaining('正在搜索'), findsOneWidget);
      expect(find.text('下载已选'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('稻香'), findsOneWidget);
      expect(find.text('已选 1 首'), findsOneWidget);
      expect(find.text('下载已选'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('verified songs appear while later songs are still checking', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('screenshot_progress_'),
    );
    if (root == null) fail('could not create test image directory');
    final image = File('${root.path}/shot.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
          'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
        ),
      ),
    );
    final handler = MusicAudioHandler();
    final controller = MusicController(audioHandler: handler);
    final gate = Completer<void>();
    final resolver = _Resolver(searchGate: gate, gatedQuery: '晴天');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenshotImportPage(
            controller: controller,
            ocr: const _TwoSongsOcr(),
            openPickerOnStart: true,
            pickImages: () async => [XFile(image.path)],
            matcher: ScreenshotMatcher(resolver: resolver, wait: (_) async {}),
          ),
        ),
      );
      for (var i = 0; i < 8; i += 1) {
        await tester.pump();
      }
      expect(find.text('稻香'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);
      expect(find.textContaining('正在搜索 · 1/2 首'), findsOneWidget);
      expect(find.text('下载已选'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('已选 2 首'), findsWidgets);
      expect(find.text('下载已选'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('empty search can be retried without automatic extra requests', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('screenshot_empty_retry_'),
    );
    if (root == null) fail('could not create test image directory');
    final image = File('${root.path}/shot.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
          'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
        ),
      ),
    );
    final handler = MusicAudioHandler();
    final controller = MusicController(audioHandler: handler);
    final resolver = _Resolver(choiceCount: 0);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenshotImportPage(
            controller: controller,
            ocr: const _Ocr('稻香 - 周杰伦'),
            openPickerOnStart: true,
            pickImages: () async => [XFile(image.path)],
            matcher: ScreenshotMatcher(resolver: resolver, wait: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(resolver.queries, ['稻香']);
      expect(find.textContaining('未搜到'), findsOneWidget);
      expect(find.byTooltip('重试查找'), findsOneWidget);

      resolver.choiceCount = 1;
      await tester.tap(find.byTooltip('重试查找'));
      await tester.pumpAndSettle();
      expect(resolver.queries, ['稻香', '稻香']);
      expect(find.text('已选 1 首'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('multiple screenshots OCR concurrently but keep image order', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('screenshot_parallel_ocr_'),
    );
    if (root == null) fail('could not create test image directory');
    final firstImage = File('${root.path}/first.png');
    final secondImage = File('${root.path}/second.png');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
      'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
    );
    await tester.runAsync(() async {
      await firstImage.writeAsBytes(bytes);
      await secondImage.writeAsBytes(bytes);
    });
    final ocr = _GatedOcr();
    final handler = MusicAudioHandler();
    final controller = MusicController(audioHandler: handler);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenshotImportPage(
            controller: controller,
            ocr: ocr,
            openPickerOnStart: true,
            pickImages: () async => [
              XFile(firstImage.path),
              XFile(secondImage.path),
            ],
            matcher: ScreenshotMatcher(
              resolver: _Resolver(),
              wait: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(ocr.started, [firstImage.path, secondImage.path]);

      ocr.complete(secondImage.path, '晴天 - 周杰伦');
      await tester.pump();
      expect(find.text('晴天'), findsNothing);
      ocr.complete(firstImage.path, '稻香 - 周杰伦');
      await tester.pumpAndSettle();
      expect(find.text('已选 2 首'), findsWidgets);
      expect(
        tester.getTopLeft(find.text('稻香')).dy,
        lessThan(tester.getTopLeft(find.text('晴天')).dy),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('saved song concurrency controls the import search pool', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('screenshot_search_pool_'),
    );
    if (root == null) fail('could not create test image directory');
    final image = File('${root.path}/shot.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
          'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
        ),
      ),
    );
    final handler = MusicAudioHandler();
    final controller = MusicController(audioHandler: handler)
      ..screenshotSearchConcurrency = 5;
    final gate = Completer<void>();
    final resolver = _Resolver(searchGate: gate);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenshotImportPage(
            controller: controller,
            ocr: const _SixSongsOcr(),
            openPickerOnStart: true,
            pickImages: () async => [XFile(image.path)],
            matcher: ScreenshotMatcher(resolver: resolver, wait: (_) async {}),
          ),
        ),
      );
      for (var i = 0; i < 12; i += 1) {
        await tester.pump();
      }
      expect(resolver.queries, hasLength(5));
      gate.complete();
      await tester.pumpAndSettle();
      expect(resolver.queries, hasLength(6));
      expect(find.text('已选 6 首'), findsWidgets);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('out-of-order failures do not pause a later healthy row', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('screenshot_failure_order_'),
    );
    if (root == null) fail('could not create test image directory');
    final image = File('${root.path}/shot.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
          'z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
        ),
      ),
    );
    final handler = MusicAudioHandler();
    final controller = MusicController(audioHandler: handler);
    final firstGate = Completer<void>();
    final fifthGate = Completer<void>();
    final resolver = _OutOfOrderFailureResolver(firstGate, fifthGate);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenshotImportPage(
            controller: controller,
            ocr: const _SevenSongsOcr(),
            openPickerOnStart: true,
            pickImages: () async => [XFile(image.path)],
            matcher: ScreenshotMatcher(resolver: resolver, wait: (_) async {}),
          ),
        ),
      );
      for (var i = 0; i < 16; i += 1) {
        await tester.pump();
      }
      expect(
        resolver.started,
        containsAll(['稻香', '晴天', '青花瓷', '七里香', '夜曲', '菊花台']),
      );
      expect(resolver.started, isNot(contains('告白气球')));

      firstGate.complete();
      for (var i = 0; i < 12; i += 1) {
        await tester.pump();
      }
      expect(resolver.started, contains('告白气球'));
      expect(find.textContaining('已暂停后续查找'), findsNothing);

      fifthGate.complete();
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      unawaited(handler.dispose());
      root.deleteSync(recursive: true);
    }
  });
}

class _SixSongsOcr implements ScreenshotOcr {
  const _SixSongsOcr();

  @override
  Future<List<ScreenshotTextLine>> recognize(String imagePath) async => [
    for (var index = 0; index < 6; index += 1)
      ScreenshotTextLine(
        text: '${['稻香', '晴天', '青花瓷', '七里香', '夜曲', '菊花台'][index]} - 周杰伦',
        bounds: Rect.fromLTWH(10, 20 + index * 45, 200, 20),
      ),
  ];
}

class _SevenSongsOcr implements ScreenshotOcr {
  const _SevenSongsOcr();

  @override
  Future<List<ScreenshotTextLine>> recognize(String imagePath) async => [
    for (var index = 0; index < 7; index += 1)
      ScreenshotTextLine(
        text: '${['稻香', '晴天', '青花瓷', '七里香', '夜曲', '菊花台', '告白气球'][index]} - 周杰伦',
        bounds: Rect.fromLTWH(10, 20 + index * 45, 200, 20),
      ),
  ];
}

class _GatedOcr implements ScreenshotOcr {
  final started = <String>[];
  final _requests = <String, Completer<List<ScreenshotTextLine>>>{};

  @override
  Future<List<ScreenshotTextLine>> recognize(String imagePath) {
    started.add(imagePath);
    final request = Completer<List<ScreenshotTextLine>>();
    _requests[imagePath] = request;
    return request.future;
  }

  void complete(String imagePath, String text) {
    _requests[imagePath]!.complete([
      ScreenshotTextLine(
        text: text,
        bounds: const Rect.fromLTWH(10, 20, 200, 20),
      ),
    ]);
  }
}

class _Ocr implements ScreenshotOcr {
  const _Ocr([this.line = '稻向 - 周杰伦']);

  final String line;

  @override
  Future<List<ScreenshotTextLine>> recognize(String imagePath) async => [
    ScreenshotTextLine(
      text: line,
      bounds: const Rect.fromLTWH(10, 20, 200, 20),
    ),
  ];
}

class _TwoSongsOcr implements ScreenshotOcr {
  const _TwoSongsOcr();

  @override
  Future<List<ScreenshotTextLine>> recognize(String imagePath) async => [
    const ScreenshotTextLine(
      text: '稻香 - 周杰伦',
      bounds: Rect.fromLTWH(10, 20, 200, 20),
    ),
    const ScreenshotTextLine(
      text: '晴天 - 周杰伦',
      bounds: Rect.fromLTWH(10, 100, 200, 20),
    ),
  ];
}

class _Resolver implements MusicResolver {
  _Resolver({this.choiceCount = 1, this.searchGate, this.gatedQuery});

  int choiceCount;
  final Completer<void>? searchGate;
  final String? gatedQuery;
  final queries = <String>[];
  int resolveCount = 0;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    queries.add(query);
    if (searchGate != null && (gatedQuery == null || gatedQuery == query)) {
      await searchGate!.future;
    }
    return [
      for (var index = 0; index < choiceCount; index += 1)
        MusicSearchCandidate(
          query: query,
          source: MusicDataSource.buguyy,
          platform: 'buguyy',
          keyword: query,
          page: 1,
          id: 'song-$index',
          name: index == 0 ? (query == '稻向' ? '稻香' : query) : '候选 $index',
          artist: '周杰伦',
          album: '',
          duration: 220,
          link: '',
          coverUrl: '',
          qualities: const [],
          score: 250,
          raw: const {},
        ),
    ];
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveCount += 1;
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: '',
      url: 'https://example.test/audio.mp3',
      quality: const MusicQuality(format: 'mp3'),
    );
  }
}

class _OutOfOrderFailureResolver extends _Resolver {
  _OutOfOrderFailureResolver(this.firstGate, this.fifthGate);

  final Completer<void> firstGate;
  final Completer<void> fifthGate;
  final started = <String>[];

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    started.add(query);
    if (query == '稻香') await firstGate.future;
    if (query == '夜曲' || query == '菊花台') await fifthGate.future;
    if (query == '稻香' || query == '青花瓷' || query == '七里香') {
      throw StateError('offline');
    }
    return super.search(query, source);
  }
}
