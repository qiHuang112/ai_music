import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
}

void main() {
  testWidgets('page wash stays opaque over different window backgrounds', (
    tester,
  ) async {
    Future<List<int>> pixels(Color backing) async {
      await tester.pumpWidget(
        Theme(
          data: MusicAppTheme.create(Brightness.light),
          child: RepaintBoundary(
            key: const ValueKey('surface-capture'),
            child: ColoredBox(
              color: backing,
              child: const Directionality(
                textDirection: TextDirection.ltr,
                child: MusicPageBackdrop(child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('surface-capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (10 * image.width + image.width - 10) * 4;
        final sample = data!.buffer.asUint8List().sublist(offset, offset + 4);
        image.dispose();
        return sample;
      }))!;
    }

    expect(await pixels(Colors.red), await pixels(Colors.blue));
  });

  test('reading text stays legible on both themes and player materials', () {
    for (final brightness in Brightness.values) {
      final theme = MusicAppTheme.create(brightness);
      final colors = theme.colorScheme;
      final surfaces = theme.extension<MusicSurfaces>()!;
      for (final surface in [
        colors.surface,
        colors.surfaceContainerLowest,
        colors.surfaceContainerHigh,
        surfaces.playerStart,
        surfaces.playerEnd,
      ]) {
        expect(contrast(colors.onSurface, surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(colors.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        contrast(colors.onPrimaryContainer, colors.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onPrimaryContainer, surfaces.accentEnd),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('switching appearance interpolates branded surfaces with theme', () {
    final light = MusicAppTheme.create(Brightness.light);
    final dark = MusicAppTheme.create(Brightness.dark);
    final midpoint = ThemeData.lerp(
      light,
      dark,
      .5,
    ).extension<MusicSurfaces>()!;
    expect(
      midpoint.cache,
      Color.lerp(MusicPalette.light.cache, MusicPalette.dark.cache, .5),
    );
    expect(
      midpoint.playerStart,
      Color.lerp(
        MusicPalette.light.playerStart,
        MusicPalette.dark.playerStart,
        .5,
      ),
    );
  });
}
