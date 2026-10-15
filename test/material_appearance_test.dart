import 'dart:io';
import 'dart:typed_data';

import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/design/ambient_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every appearance survives a fresh settings store', () async {
    final root = await Directory.systemTemp.createTemp('music_appearances_');
    addTearDown(() => root.delete(recursive: true));
    for (final appearance in AppThemePreference.values) {
      final store = MusicSettingsStore(rootProvider: () async => root);
      await store.saveSettings(MusicAppSettings(theme: appearance));
      final restored = await MusicSettingsStore(
        rootProvider: () async => root,
      ).loadSettings();
      expect(restored.theme, appearance, reason: appearance.name);
    }
  });

  for (final appearance in [
    AppThemePreference.neon,
    AppThemePreference.aurora,
  ]) {
    testWidgets('${appearance.name} animates and respects reduced motion', (
      tester,
    ) async {
      MusicMotion.perpetual = true;
      addTearDown(() => MusicMotion.perpetual = false);
      final boundary = GlobalKey();
      Widget scene(bool reduced) => MaterialApp(
        theme: MusicAppTheme.create(
          Brightness.dark,
          palette: MusicPalette.of(appearance),
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: const SizedBox(
                width: 320,
                height: 640,
                child: PageBackdrop(),
              ),
            ),
          ),
        ),
      );
      Future<Uint8List> pixels() async {
        final box =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await box.toImage();
          try {
            final bytes = await image.toByteData();
            return bytes!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        }))!;
      }

      await tester.pumpWidget(scene(false));
      await tester.pump(const Duration(seconds: 1));
      final before = await pixels();
      await tester.pump(const Duration(seconds: 3));
      expect(await pixels(), isNot(orderedEquals(before)));

      await tester.pumpWidget(scene(true));
      await tester.pump(const Duration(seconds: 1));
      final still = await pixels();
      await tester.pump(const Duration(seconds: 3));
      expect(await pixels(), orderedEquals(still));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
