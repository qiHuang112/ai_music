import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The surface of xuan paper laid over the whole app: a dense felt of short
/// pressed fibres seen as soft relief, with no drawn strands. One tile is
/// drawn once and repeated.
abstract final class PaperTexture {
  static const _tileSide = 320.0;
  static ui.Image? _tile;

  /// Fibres wrap around the edges, so the tile repeats without a seam.
  static ui.Image _draw() {
    const side = _tileSide;
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    final random = math.Random(1959);
    const fibre = Color(0xFF7A6248);

    void wrapped(void Function() paint) {
      for (final dx in const [-side, 0.0, side]) {
        for (final dy in const [-side, 0.0, side]) {
          canvas
            ..save()
            ..translate(dx, dy);
          paint();
          canvas.restore();
        }
      }
    }

    // Faint unevenness in how thick the sheet is.
    for (var i = 0; i < 22; i++) {
      final center = Offset(
        random.nextDouble() * side,
        random.nextDouble() * side,
      );
      final radius = 24 + random.nextDouble() * 46;
      final paint = Paint()
        ..color = fibre.withValues(alpha: .008 + random.nextDouble() * .010)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .5);
      wrapped(() => canvas.drawCircle(center, radius, paint));
    }

    // The felted surface: thousands of short fibres pressed flat, most lying
    // along one diagonal. Each gets a shadow on one side and a highlight on
    // the other, so it reads as relief, not as drawn lines.
    for (var i = 0; i < 3400; i++) {
      final start = Offset(
        random.nextDouble() * side,
        random.nextDouble() * side,
      );
      final angle =
          -math.pi / 3 +
          (random.nextDouble() - .5) * (random.nextBool() ? 1.1 : 3.1);
      final length = 2.5 + random.nextDouble() * random.nextDouble() * 11;
      final end = start + Offset.fromDirection(angle, length);
      final strength = random.nextDouble();
      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = .7 + random.nextDouble() * .9
        ..color = fibre.withValues(alpha: .014 + strength * .036)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5);
      final light = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = shadow.strokeWidth
        ..color = Colors.white.withValues(alpha: .035 + strength * .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5);
      wrapped(() {
        canvas
          ..drawLine(
            start + const Offset(.6, .7),
            end + const Offset(.6, .7),
            shadow,
          )
          ..drawLine(start, end, light);
      });
    }

    final pixels = (side * scale).round();
    return recorder.endRecording().toImageSync(pixels, pixels);
  }

  /// Paints the paper surface across [size], starting at the origin.
  static void paintOn(Canvas canvas, Size size) {
    final tile = _tile ??= _draw();
    final scale = _tileSide / tile.width;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          (Matrix4.identity()..scaleByDouble(scale, scale, 1, 1)).storage,
          filterQuality: FilterQuality.medium,
        ),
    );
  }
}
