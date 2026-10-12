import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// How much of the room shows through.
enum GlassLevel {
  thin(sigma: 14, fill: .30),
  regular(sigma: 26, fill: .50),
  thick(sigma: 42, fill: .72);

  const GlassLevel({required this.sigma, required this.fill});

  final double sigma, fill;
}

/// Smoked acrylic, like a turntable dust cover: it blurs and saturates what is
/// behind it, lays a warm tint over that and catches light along its top edge.
///
/// Each blurred surface is a separate compositing pass. Keep to a few per
/// screen and pass `blur: false` for controls that already sit on glass.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.level = GlassLevel.regular,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(MusicUi.glassRadius),
    ),
    this.padding = EdgeInsets.zero,
    this.tint,
    this.blur = true,
    this.shadow = true,
  });

  final Widget child;
  final GlassLevel level;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final bool blur, shadow;

  @override
  Widget build(BuildContext context) {
    final palette = MusicTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ?? palette.glass;
    Widget surface = CustomPaint(
      foregroundPainter: _GlassEdgePainter(
        radius: borderRadius,
        sheen: palette.sheen,
        strength: dark ? 1 : 1.6,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withValues(alpha: level.fill + .10),
              base.withValues(alpha: level.fill - .06),
            ],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (blur) {
      surface = BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: level.sigma, sigmaY: level.sigma),
          inner: const ColorFilter.matrix(_saturate),
        ),
        child: surface,
      );
    }
    surface = ClipRRect(borderRadius: borderRadius, child: surface);
    if (!shadow) return surface;
    return CustomPaint(
      painter: _GlassShadowPainter(
        radius: borderRadius,
        color: dark
            ? Colors.black.withValues(alpha: .42)
            : palette.text.withValues(alpha: .14),
      ),
      child: surface,
    );
  }

  // Saturation 1.5 on Rec. 709 luma weights.
  static const _saturate = <double>[
    1.3937, -.3576, -.0361, 0, 0, //
    -.1063, 1.1424, -.0361, 0, 0, //
    -.1063, -.3576, 1.4639, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({
    required this.radius,
    required this.sheen,
    required this.strength,
  });

  final BorderRadius radius;
  final Color sheen;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.5);
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sheen.withValues(alpha: .34 * strength),
            sheen.withValues(alpha: .05 * strength),
            sheen.withValues(alpha: .14 * strength),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) =>
      old.radius != radius || old.sheen != sheen || old.strength != strength;
}

/// Draws the drop shadow only outside the pane, so the blur behind the glass
/// does not pick it up and turn muddy.
class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter({required this.radius, required this.color});

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pane = radius.toRRect(Offset.zero & size);
    canvas
      ..save()
      ..clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect((Offset.zero & size).inflate(80)),
          Path()..addRRect(pane),
        ),
      )
      ..drawRRect(
        pane.shift(const Offset(0, 12)),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_GlassShadowPainter old) =>
      old.radius != radius || old.color != color;
}
