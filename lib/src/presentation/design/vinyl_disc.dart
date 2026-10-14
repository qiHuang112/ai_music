import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'ambient_clock.dart';

/// A record drawn from scratch: grooves, track gaps, dead wax, a light sheen
/// that stays put while the disc turns, and a centre label that turns with
/// [rotation] (radians).
class VinylDisc extends StatelessWidget {
  const VinylDisc({
    super.key,
    this.label,
    this.labelColor,
    this.rotation,
    this.shadow = true,
    this.labelFraction = .37,
  });

  /// Shown on the centre label, clipped to a circle. Usually the cover art.
  final Widget? label;
  final Color? labelColor;
  final ValueListenable<double>? rotation;
  final bool shadow;

  /// Label radius as a share of the disc radius. Small discs raise it so the
  /// cover stays readable.
  final double labelFraction;

  @override
  Widget build(BuildContext context) {
    final palette = MusicTokens.of(context);
    final turn = rotation ?? const AlwaysStoppedAnimation(0.0);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: !shadow
                ? null
                : switch (palette.skin) {
                    // A second, off-register print of the disc.
                    MusicSkin.riso => [
                      BoxShadow(
                        color: palette.haze,
                        offset: const Offset(8, 8),
                      ),
                    ],
                    MusicSkin.berry => [
                      BoxShadow(
                        color: const Color(0xFFD65078).withValues(alpha: .3),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                    _ => [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .45),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  },
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Baked(
                painter: _GroovePainter(
                  vinyl: palette.vinyl,
                  label: labelFraction,
                  skin: palette.skin,
                  sheen: palette.sheen,
                  rim: switch (palette.skin) {
                    MusicSkin.neon => palette.accent,
                    MusicSkin.aurora => palette.sheen,
                    _ => null,
                  },
                ),
              ),
              FractionallySizedBox(
                widthFactor: labelFraction,
                heightFactor: labelFraction,
                child: AnimatedBuilder(
                  animation: turn,
                  builder: (context, child) =>
                      Transform.rotate(angle: turn.value, child: child),
                  child: RepaintBoundary(
                    child: ClipOval(
                      child: CustomPaint(
                        painter: _LabelPainter(
                          color: labelColor ?? palette.label,
                          print: palette.sheen,
                        ),
                        child: label,
                      ),
                    ),
                  ),
                ),
              ),
              // No record is perfectly flat: the reflection sways a little
              // each turn. The sheen is drawn once and only turned, so the
              // sway costs no repaint.
              AnimatedBuilder(
                animation: turn,
                builder: (context, child) => Transform.rotate(
                  angle: math.sin(turn.value) * .045,
                  child: child,
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SheenPainter(
                      sheen: palette.sheen,
                      brass: palette.brass,
                      label: labelFraction,
                      holo: switch (palette.skin) {
                        MusicSkin.neon => [
                          palette.haze,
                          palette.accent,
                          palette.label,
                        ],
                        // Mint and violet, with a line of ice round the rim.
                        MusicSkin.aurora => [
                          palette.haze,
                          palette.sheen,
                          palette.haze,
                        ],
                        _ => null,
                      },
                      dots: palette.skin == MusicSkin.riso
                          ? palette.haze
                          : null,
                      outline: switch (palette.skin) {
                        MusicSkin.riso => palette.text,
                        MusicSkin.berry => Colors.white.withValues(alpha: .7),
                        _ => null,
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  const _GroovePainter({
    required this.vinyl,
    required this.label,
    required this.skin,
    required this.sheen,
    this.rim,
  });

  final double label;
  final MusicSkin skin;

  final Color vinyl, sheen;

  /// Neon rain and aurora: the edge of the disc glows in this color.
  final Color? rim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    switch (skin) {
      case MusicSkin.riso:
        // One flat ink.
        canvas.drawCircle(center, radius, Paint()..color = vinyl);
      case MusicSkin.aurora:
        // Clear ice: the light behind shows through.
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0x478FF5DC), Color(0x80185C62), Color(0xD1061E24)],
              stops: [0, .48, 1],
            ).createShader(bounds),
        );
      case MusicSkin.berry:
        _marble(canvas, center, radius);
      default:
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Color.lerp(vinyl, Colors.white, .10)!,
                vinyl,
                Color.lerp(vinyl, Colors.white, .05)!,
              ],
              stops: const [0, .7, 1],
            ).createShader(bounds),
        );
    }
    // What the grooves and the gaps between tracks are drawn in.
    final (Color? ink, double bandAlpha) = switch (skin) {
      MusicSkin.berry => (const Color(0xFFAA285A), .16),
      MusicSkin.riso => (Colors.white, .3),
      MusicSkin.aurora => (sheen, .25),
      _ => (null, .6),
    };

    // Each groove catches a different amount of light. A fixed seed keeps the
    // pattern identical between repaints.
    final random = math.Random(7);
    final inner = radius * (label + .07);
    final outer = radius * .965;
    final step = math.max(1.1, radius / 92);
    final groove = Paint()..style = PaintingStyle.stroke;
    for (var r = inner; r < outer; r += step) {
      groove
        ..strokeWidth = step * .55
        ..color = (ink ?? (random.nextBool() ? Colors.white : Colors.black))
            .withValues(alpha: .025 + random.nextDouble() * .075);
      canvas.drawCircle(center, r, groove);
    }

    // Silent bands between tracks.
    for (final fraction in const [.56, .69, .81, .91]) {
      if (fraction < label + .12) continue;
      canvas
        ..drawCircle(
          center,
          radius * fraction,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = step * 1.7
            ..color =
                (ink == null || skin == MusicSkin.aurora ? Colors.black : ink)
                    .withValues(alpha: bandAlpha),
        )
        ..drawCircle(
          center,
          radius * fraction + step * 1.1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .6
            ..color = Colors.white.withValues(alpha: .07),
        );
    }

    // Dead wax around the label, then the rolled outer edge.
    canvas
      ..drawCircle(
        center,
        radius * (label + .035),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * .07
          ..color = Color.lerp(vinyl, Colors.white, .035)!,
      )
      ..drawCircle(
        center,
        radius - .75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: .10),
      );

    if (rim != null) {
      canvas
        ..drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * .05
            ..color = rim!.withValues(alpha: .28)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .07),
        )
        ..drawCircle(
          center,
          radius - .5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = rim!.withValues(alpha: .4),
        );
    }
  }

  @override
  bool shouldRepaint(_GroovePainter old) =>
      old.rim != rim ||
      old.vinyl != vinyl ||
      old.label != label ||
      old.skin != skin ||
      old.sheen != sheen;

  /// Pink and white marbled vinyl: soft veins swept across the disc.
  void _marble(Canvas canvas, Offset center, double radius) {
    final disc = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas
      ..save()
      ..clipPath(disc)
      ..drawCircle(center, radius, Paint()..color = vinyl);
    final random = math.Random(3);
    for (var i = 0; i < 16; i++) {
      final white = i.isEven;
      final from =
          center +
          Offset.fromDirection(random.nextDouble() * 2 * math.pi, radius * 1.1);
      final to =
          center +
          Offset.fromDirection(random.nextDouble() * 2 * math.pi, radius * 1.1);
      final bend =
          center +
          Offset.fromDirection(
            random.nextDouble() * 2 * math.pi,
            radius * random.nextDouble() * .9,
          );
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * (.05 + random.nextDouble() * .16)
          ..color = (white ? const Color(0xFFFFF6F8) : const Color(0xFFF06292))
              .withValues(alpha: white ? .6 : .3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .05),
      );
    }
    canvas.restore();
  }
}

/// The paper label when there is no artwork: a flat colour with printed rings
/// and one off-centre mark, so the turning still reads.
class _LabelPainter extends CustomPainter {
  const _LabelPainter({required this.color, required this.print});

  final Color color, print;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = color);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.6, radius * .012)
      ..color = print.withValues(alpha: .42);
    canvas
      ..drawCircle(center, radius * .90, ring)
      ..drawCircle(center, radius * .84, ring)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, -radius * .54),
            width: radius * .52,
            height: radius * .09,
          ),
          Radius.circular(radius * .05),
        ),
        Paint()..color = print.withValues(alpha: .7),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, radius * .5),
            width: radius * .34,
            height: radius * .05,
          ),
          Radius.circular(radius * .03),
        ),
        Paint()..color = print.withValues(alpha: .4),
      );
  }

  @override
  bool shouldRepaint(_LabelPainter old) =>
      old.color != color || old.print != print;
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter({
    required this.sheen,
    required this.brass,
    required this.label,
    this.holo,
    this.dots,
    this.outline,
  });

  final double label;

  /// Neon rain: cyan, magenta and yellow for a holographic reflection and a
  /// lit rim in place of the plain white sheen.
  final List<Color>? holo;

  /// Riso: the reflection is printed as two wedges of halftone dots.
  final Color? dots;

  /// A plain line round the rim.
  final Color? outline;

  final Color sheen, brass;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final labelRadius = radius * label;
    final clear = sheen.withValues(alpha: 0);
    final bright = sheen.withValues(alpha: dots == null ? .24 : 0);
    final faint = sheen.withValues(alpha: dots == null ? .055 : 0);

    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(bounds.deflate(radius * .03))
        ..addOval(Rect.fromCircle(center: center, radius: labelRadius)),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = SweepGradient(
          colors: holo == null
              ? [
                  clear, clear, bright, clear, //
                  clear, faint, clear, //
                  clear, bright, clear, //
                  clear, faint, clear, clear, //
                ]
              : [
                  clear, clear, //
                  holo![0].withValues(alpha: .42),
                  const Color(0xFF7B5CFF).withValues(alpha: .38),
                  holo![1].withValues(alpha: .42),
                  holo![2].withValues(alpha: .26),
                  clear, clear, //
                  holo![0].withValues(alpha: .38),
                  const Color(0xFF7B5CFF).withValues(alpha: .34),
                  holo![1].withValues(alpha: .38),
                  holo![2].withValues(alpha: .22),
                  clear, clear, //
                ],
          stops: holo == null
              ? const [
                  0, .035, .105, .175, //
                  .29, .345, .40, //
                  .535, .605, .675, //
                  .79, .845, .90, 1, //
                ]
              : const [
                  0, .04, .08, .11, .14, .17, .21, //
                  .54, .58, .61, .64, .67, .71, 1, //
                ],
          transform: const GradientRotation(.13),
        ).createShader(bounds),
    );

    if (dots != null) {
      final wedges = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + radius, center.dy - radius * .76)
        ..lineTo(center.dx + radius, center.dy - radius * .12)
        ..close()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx - radius, center.dy + radius * .76)
        ..lineTo(center.dx - radius, center.dy + radius * .16)
        ..close();
      final ring = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(bounds.deflate(radius * .04))
        ..addOval(Rect.fromCircle(center: center, radius: labelRadius * 1.12));
      canvas
        ..save()
        ..clipPath(Path.combine(PathOperation.intersect, wedges, ring));
      final cell = math.max(3.0, radius / 30);
      final dot = Paint()..color = dots!;
      for (var y = bounds.top; y < bounds.bottom; y += cell) {
        for (var x = bounds.left; x < bounds.right; x += cell) {
          canvas.drawCircle(Offset(x, y), cell * .27, dot);
        }
      }
      canvas.restore();
    }
    if (outline != null) {
      canvas.drawCircle(
        center,
        radius - .7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = outline!,
      );
    }

    canvas
      ..drawCircle(
        center,
        labelRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, radius * .008)
          ..color = Colors.black.withValues(alpha: .38),
      )
      ..drawCircle(
        center,
        radius * .034,
        Paint()..color = Colors.black.withValues(alpha: .82),
      )
      ..drawCircle(
        center,
        radius * .024,
        Paint()
          ..shader =
              RadialGradient(
                center: const Alignment(-.35, -.4),
                colors: [
                  Colors.white,
                  brass,
                  Color.lerp(brass, Colors.black, .6)!,
                ],
                stops: const [0, .45, 1],
              ).createShader(
                Rect.fromCircle(center: center, radius: radius * .024),
              ),
      );
  }

  @override
  bool shouldRepaint(_SheenPainter old) =>
      old.sheen != sheen ||
      old.brass != brass ||
      old.label != label ||
      old.holo != holo ||
      old.dots != dots ||
      old.outline != outline;
}

/// Draws [painter] once into an image and shows that image from then on.
///
/// The renderer rasterizes every layer again on every frame, so a still
/// drawing made of many strokes and blurs under something that moves is paid
/// for at the frame rate. Baked, it is one textured quad.
class _Baked extends StatefulWidget {
  const _Baked({required this.painter});

  final CustomPainter painter;

  /// Room round the edge, as a share of the shortest side, for glows.
  static const _bleed = .14;

  @override
  State<_Baked> createState() => _BakedState();
}

class _BakedState extends State<_Baked> {
  ui.Image? _image;
  Size? _size;
  double? _scale;
  CustomPainter? _of;

  ui.Image _bake(Size size, double scale) {
    final painter = widget.painter;
    final image = _image;
    if (image != null &&
        _size == size &&
        _scale == scale &&
        !painter.shouldRepaint(_of!)) {
      return image;
    }
    image?.dispose();
    final margin = size.shortestSide * _Baked._bleed;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(margin, margin);
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    _size = size;
    _scale = scale;
    _of = painter;
    _image = picture.toImageSync(
      ((size.width + margin * 2) * scale).ceil(),
      ((size.height + margin * 2) * scale).ceil(),
    );
    picture.dispose();
    return _image!;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _BakedPainter(
        this,
        widget.painter,
        MediaQuery.devicePixelRatioOf(context),
      ),
    ),
  );
}

class _BakedPainter extends CustomPainter {
  const _BakedPainter(this.state, this.painter, this.scale);

  final _BakedState state;
  final CustomPainter painter;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = state._bake(size, scale);
    final margin = size.shortestSide * _Baked._bleed;
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        -margin,
        -margin,
        image.width / scale,
        image.height / scale,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_BakedPainter old) =>
      old.scale != scale || painter.shouldRepaint(old.painter);
}

/// Turns a [VinylDisc] with the inertia of a platter: it winds up to speed and
/// coasts to a stop instead of snapping.
class SpinningVinyl extends StatefulWidget {
  const SpinningVinyl({
    super.key,
    required this.spinning,
    this.label,
    this.labelColor,
    this.shadow = true,
    this.labelFraction = .37,
  });

  final bool spinning;
  final double labelFraction;
  final Widget? label;
  final Color? labelColor;
  final bool shadow;

  @override
  State<SpinningVinyl> createState() => _SpinningVinylState();
}

class _SpinningVinylState extends State<SpinningVinyl> {
  static final _cruise =
      2 * math.pi / (MusicMotion.revolution.inMicroseconds / 1e6);

  // A slow turn reads fine at the ambient heartbeat's rate.
  final _clock = AmbientClock();
  final _angle = ValueNotifier<double>(0);
  double _velocity = 0;
  bool _allowed = true;

  bool get _driven => widget.spinning && _allowed;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allowed = AmbientClock.wanted(context);
    _wake();
  }

  @override
  void didUpdateWidget(SpinningVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _wake();
  }

  void _wake() {
    if (_driven) {
      _clock.run(true);
    } else if (!_allowed) {
      // Hidden or motion reduced: stop where it is.
      _velocity = 0;
      _clock.run(false);
    }
  }

  void _tick() {
    final dt = _clock.step;
    final target = _driven ? _cruise : 0.0;
    final settle = _driven ? MusicMotion.spinUp : MusicMotion.spinDown;
    _velocity +=
        (target - _velocity) *
        (1 - math.exp(-dt / (settle.inMicroseconds / 1e6)));
    if (!_driven && _velocity < _cruise * .01) {
      _velocity = 0;
      _clock.run(false);
      return;
    }
    _angle.value = (_angle.value + _velocity * dt) % (2 * math.pi);
  }

  @override
  void dispose() {
    _clock.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VinylDisc(
    labelFraction: widget.labelFraction,
    label: widget.label,
    labelColor: widget.labelColor,
    rotation: _angle,
    shadow: widget.shadow,
  );
}
