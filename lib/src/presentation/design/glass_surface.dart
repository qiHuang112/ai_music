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
    final skin = palette.skin;
    // Two skins have no glass at all.
    if (skin == MusicSkin.riso) return _paper(context, palette);
    if (skin == MusicSkin.silver) return _metal(context, palette);
    final base = tint ?? palette.glass;
    // Milk glass is nearly opaque; ice lets more through.
    final lift = switch (skin) {
      MusicSkin.berry => .14,
      MusicSkin.aurora => -.08,
      _ => 0.0,
    };
    Widget surface = CustomPaint(
      foregroundPainter: _GlassEdgePainter(
        radius: borderRadius,
        sheen: palette.sheen,
        strength: dark ? 1 : 1.6,
        lower: switch (skin) {
          MusicSkin.neon => palette.accent,
          // Ice: one fine bright line all round.
          MusicSkin.aurora => palette.sheen.withValues(alpha: .4),
          _ => null,
        },
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withValues(alpha: level.fill + .10 + lift),
              base.withValues(alpha: level.fill - .06 + lift),
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
        color: skin == MusicSkin.berry
            ? const Color(0xFFF06491).withValues(alpha: .26)
            : dark
            ? Colors.black.withValues(alpha: .42)
            : palette.text.withValues(alpha: .14),
        glow: palette.neon ? palette.accent.withValues(alpha: .22) : null,
      ),
      child: surface,
    );
  }

  /// Riso: a piece of paper with an ink line round it and, where glass
  /// would cast a shadow, a hard off-register block of the second ink.
  Widget _paper(BuildContext context, MusicPalette palette) => DecoratedBox(
    decoration: BoxDecoration(
      color: tint ?? palette.panel,
      borderRadius: borderRadius,
      border: Border.all(color: palette.text, width: 1.4),
      boxShadow: shadow
          ? [BoxShadow(color: palette.haze, offset: const Offset(4, 4))]
          : null,
    ),
    child: ClipRRect(
      borderRadius: borderRadius,
      child: Padding(padding: padding, child: child),
    ),
  );

  /// Silver face: small controls are aluminium buttons. Larger panes are the
  /// black display window, where everything is lit in meter-lamp amber.
  Widget _metal(BuildContext context, MusicPalette palette) {
    final button = level == GlassLevel.thin || tint != null;
    final theme = Theme.of(context);
    const amber = Color(0xFFFFC773);
    const dim = Color(0xFFB98B45);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tint != null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: button
                    ? const [Color(0xFFF4F3EF), Color(0xFFCBCAC5)]
                    : const [Color(0xFF232427), Color(0xFF0E0E10)],
              ),
        color: tint,
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.black.withValues(alpha: button ? .16 : .6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: button ? .3 : .25),
            blurRadius: button ? 4 : 14,
            offset: Offset(0, button ? 2 : 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: padding,
          child: button
              ? child
              : Theme(
                  data: theme.copyWith(
                    colorScheme: theme.colorScheme.copyWith(
                      onSurface: amber,
                      onSurfaceVariant: dim,
                    ),
                    textTheme: theme.textTheme.apply(
                      bodyColor: amber,
                      displayColor: amber,
                    ),
                    iconTheme: theme.iconTheme.copyWith(color: amber),
                  ),
                  child: child,
                ),
        ),
      ),
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
    this.lower,
  });

  final BorderRadius radius;
  final Color sheen;
  final double strength;

  /// Neon glass: the rim is lit cyan from above and this color from below.
  final Color? lower;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.5);
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: lower == null ? Alignment.topLeft : Alignment.topCenter,
          end: lower == null ? Alignment.bottomRight : Alignment.bottomCenter,
          colors: lower == null
              ? [
                  sheen.withValues(alpha: .34 * strength),
                  sheen.withValues(alpha: .05 * strength),
                  sheen.withValues(alpha: .14 * strength),
                ]
              : [
                  sheen.withValues(alpha: .6),
                  sheen.withValues(alpha: .04),
                  lower!.withValues(alpha: .55),
                ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) =>
      old.radius != radius ||
      old.sheen != sheen ||
      old.strength != strength ||
      old.lower != lower;
}

/// Draws the drop shadow only outside the pane, so the blur behind the glass
/// does not pick it up and turn muddy.
class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter({
    required this.radius,
    required this.color,
    this.glow,
  });

  final BorderRadius radius;
  final Color color;

  /// A halo all round, for glass that is itself lit.
  final Color? glow;

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
      );
    if (glow != null) {
      canvas.drawRRect(
        pane,
        Paint()
          ..color = glow!
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassShadowPainter old) =>
      old.radius != radius || old.color != color || old.glow != glow;
}
