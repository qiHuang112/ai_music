import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The room behind everything: the page color, two slow pools of light and a
/// veil of film grain. Pass colors from [ArtworkPalette] to light it from the
/// playing record; without them it takes the palette's accent and haze.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    this.glow,
    this.shade,
    this.drift = true,
    this.grain = true,
    this.child,
  });

  final Color? glow, shade;

  /// Whether the light wanders. Leave it off behind long lists.
  final bool drift;
  final bool grain;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = MusicTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: glow ?? palette.accent),
      duration: const Duration(milliseconds: 900),
      curve: MusicMotion.standard,
      builder: (context, glow, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: shade ?? palette.haze),
        duration: const Duration(milliseconds: 900),
        curve: MusicMotion.standard,
        builder: (context, shade, _) => _Drift(
          enabled: drift,
          builder: (phase) => CustomPaint(
            painter: _AmbientPainter(
              phase: phase,
              base: palette.background,
              glow: glow!,
              shade: shade!,
              ember: palette.accent,
              dark: dark,
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (grain)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: FilmGrain(opacity: dark ? .075 : .05),
                    ),
                  ),
                ?child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The night room's warm light over every page: amber from the upper left,
/// label red from the lower right, and film grain. It steps aside while an
/// [AmbientBackdrop] is on screen, which lights its page from the artwork.
class RoomGlow extends StatelessWidget {
  const RoomGlow({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  /// How many [AmbientBackdrop]s are mounted.
  static final covered = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final palette = MusicTokens.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<int>(
              valueListenable: covered,
              builder: (context, count, glow) => AnimatedOpacity(
                opacity: count > 0 ? 0 : 1,
                duration: MusicMotion.slow,
                child: glow,
              ),
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _AmbientPainter(
                        phase: const AlwaysStoppedAnimation(0),
                        base: palette.background,
                        glow: palette.accent,
                        shade: palette.haze,
                        ember: palette.accent,
                        dark: true,
                        overlay: true,
                      ),
                    ),
                    const FilmGrain(opacity: .075),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Drift extends StatefulWidget {
  const _Drift({required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(Animation<double> phase) builder;

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    RoomGlow.covered.value++;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Drift oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.enabled && MusicMotion.allowsPerpetual(context);
    if (run && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    RoomGlow.covered.value--;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.phase,
    required this.base,
    required this.glow,
    required this.shade,
    required this.ember,
    required this.dark,
    this.overlay = false,
  }) : super(repaint: phase);

  final Animation<double> phase;
  final Color base, glow, shade, ember;
  final bool dark;

  /// Paints only the light, screened over whatever is already there.
  final bool overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (overlay) {
      canvas.saveLayer(rect, Paint()..blendMode = BlendMode.screen);
    } else {
      canvas.drawRect(rect, Paint()..color = base);
    }
    final turn = phase.value * 2 * math.pi;
    final reach = size.longestSide;

    void pool(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .36),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .42, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // On a pale page the pools tint the page itself; keep daylight faint.
    final strength = dark ? 1.0 : .35;
    pool(
      Offset(
        size.width * (.14 + .10 * math.sin(turn)),
        size.height * (.10 + .05 * math.cos(turn)),
      ),
      reach * .56,
      glow,
      (dark ? .52 : .40) * strength,
    );
    pool(
      Offset(
        size.width * (.94 + .08 * math.cos(turn + 1)),
        size.height * (.64 + .07 * math.sin(turn + 2)),
      ),
      reach * .54,
      shade,
      (dark ? .40 : .34) * strength,
    );
    pool(
      Offset(size.width * .20, size.height * 1.06),
      reach * .40,
      ember,
      (dark ? .16 : .10) * strength,
    );

    if (overlay) {
      canvas.restore();
      return;
    }
    if (dark) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: .95,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: .34),
            ],
            stops: const [.55, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.phase != phase ||
      old.base != base ||
      old.glow != glow ||
      old.shade != shade ||
      old.ember != ember ||
      old.dark != dark;
}

/// Analogue grain: one small noise tile, generated once and repeated.
class FilmGrain extends StatefulWidget {
  const FilmGrain({super.key, this.opacity = .06});

  final double opacity;

  @override
  State<FilmGrain> createState() => _FilmGrainState();
}

class _FilmGrainState extends State<FilmGrain> {
  static const _side = 128;
  static ui.Image? _tile;
  static bool _requested = false;

  @override
  void initState() {
    super.initState();
    if (_tile != null || _requested) return;
    _requested = true;
    final random = math.Random(33);
    final pixels = Uint8List(_side * _side * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      // Premultiplied: a white or black speck of random strength.
      final alpha = random.nextInt(256);
      final value = random.nextBool() ? alpha : 0;
      pixels
        ..[i] = value
        ..[i + 1] = value
        ..[i + 2] = value
        ..[i + 3] = alpha;
    }
    ui.decodeImageFromPixels(pixels, _side, _side, ui.PixelFormat.rgba8888, (
      image,
    ) {
      _tile = image;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile;
    if (tile == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GrainPainter(
          tile: tile,
          opacity: widget.opacity,
          // Two device pixels per speck: visible, but finer than a point.
          scale: 2 / MediaQuery.devicePixelRatioOf(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({
    required this.tile,
    required this.opacity,
    required this.scale,
  });

  final ui.Image tile;
  final double opacity, scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..shader = ui.ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          (Matrix4.identity()..scaleByDouble(scale, scale, 1, 1)).storage,
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.tile != tile || old.opacity != opacity || old.scale != scale;
}
