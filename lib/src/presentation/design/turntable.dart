import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'vinyl_disc.dart';

/// A record with its tonearm. The arm swings in and lowers when [playing] and
/// rests in the middle of the grooves until it is lifted again.
class Turntable extends StatelessWidget {
  const Turntable({
    super.key,
    required this.playing,
    this.armDown,
    this.label,
    this.labelColor,
  });

  /// Whether the record turns.
  final bool playing;

  /// Whether the needle is in the groove; follows [playing] when null. Set it
  /// ahead of [playing] to lower the arm before the record starts.
  final bool? armDown;
  final Widget? label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final palette = MusicTokens.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return Stack(
            children: [
              // Silver face: the record sits on an aluminium platter with
              // strobe dots round its edge.
              if (palette.skin == MusicSkin.silver)
                Positioned.fromRect(
                  rect: Rect.fromCircle(
                    center: _Deck.spindle * side,
                    radius: _Deck.discRadius * side * 1.055,
                  ),
                  child: const CustomPaint(painter: _PlatterPainter()),
                ),
              Positioned.fromRect(
                rect: Rect.fromCircle(
                  center: _Deck.spindle * side,
                  radius: _Deck.discRadius * side,
                ),
                child: SpinningVinyl(
                  spinning: playing,
                  label: label,
                  labelColor: labelColor,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: _ToneArm(
                      angle: armDown ?? playing ? _Deck.midGroove : _Deck.rest,
                      lift: armDown ?? playing ? 0 : 1,
                      brass: palette.brass,
                      sheen: palette.sheen,
                      stylus: palette.accent,
                      metal: palette.gun,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Deck layout in fractions of its side. The arm is as long as the distance
/// from its pivot to the spindle, as on a real deck, so the stylus sweeps an
/// arc across the grooves.
abstract final class _Deck {
  static const spindle = Offset(.47, .53);
  static const discRadius = .445;
  static const pivot = Offset(.885, .115);
  static const reach = .585;

  static final midGroove = _angleAt(discRadius * .7);
  static final rest = _angleAt(discRadius * 1.2);

  /// Direction from the pivot that puts the stylus [radius] from the spindle.
  static double _angleAt(double radius) {
    final toSpindle = spindle - pivot;
    final distance = toSpindle.distance;
    final cosine =
        (reach * reach + distance * distance - radius * radius) /
        (2 * reach * distance);
    return toSpindle.direction - math.acos(cosine.clamp(-1.0, 1.0));
  }
}

class _ToneArm extends StatefulWidget {
  const _ToneArm({
    required this.angle,
    required this.lift,
    required this.brass,
    required this.sheen,
    required this.stylus,
    required this.metal,
  });

  final double angle, lift;
  final Color brass, sheen, stylus, metal;

  @override
  State<_ToneArm> createState() => _ToneArmState();
}

class _ToneArmState extends State<_ToneArm>
    with SingleTickerProviderStateMixin {
  late final _move = AnimationController(
    vsync: this,
    duration: MusicMotion.toneArm,
    value: 1,
  );
  late double _fromAngle = widget.angle, _fromLift = widget.lift;

  double get _t => Curves.easeInOutCubic.transform(_move.value);

  @override
  void didUpdateWidget(_ToneArm old) {
    super.didUpdateWidget(old);
    if (old.lift == widget.lift && old.angle == widget.angle) return;
    final t = _t;
    _fromAngle = lerpDouble(_fromAngle, old.angle, t)!;
    _fromLift = lerpDouble(_fromLift, old.lift, t)!;
    _move.forward(from: 0);
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _move,
    builder: (context, _) => CustomPaint(
      painter: _ToneArmPainter(
        angle: lerpDouble(_fromAngle, widget.angle, _t)!,
        lift: lerpDouble(_fromLift, widget.lift, _t)!,
        brass: widget.brass,
        sheen: widget.sheen,
        stylus: widget.stylus,
        metal: widget.metal,
      ),
    ),
  );
}

class _ToneArmPainter extends CustomPainter {
  const _ToneArmPainter({
    required this.angle,
    required this.lift,
    required this.brass,
    required this.sheen,
    required this.stylus,
    required this.metal,
  });

  final double angle, lift;
  final Color brass, sheen, stylus, metal;

  /// The dark metal of the pivot and counterweight.
  Color get _gunmetal => metal;

  /// The cartridge is turned inwards so it sits along the groove.
  static const _offsetAngle = .33;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final pivot = _Deck.pivot * side;
    final reach = _Deck.reach * side;

    canvas.drawCircle(
      pivot,
      reach * .105,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(_gunmetal, Colors.white, .16)!,
            _gunmetal,
            Colors.black,
          ],
          stops: const [0, .78, 1],
        ).createShader(Rect.fromCircle(center: pivot, radius: reach * .105)),
    );
    canvas.drawCircle(
      pivot,
      reach * .088,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, reach * .007)
        ..color = brass.withValues(alpha: .65),
    );

    // A raised arm throws its shadow further and softer.
    canvas
      ..save()
      ..translate(
        pivot.dx + side * (.006 + .016 * lift),
        pivot.dy + side * (.012 + .030 * lift),
      )
      ..rotate(angle);
    _arm(
      canvas,
      reach,
      silhouette: Paint()
        ..color = Colors.black.withValues(alpha: .42 - .14 * lift)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          side * (.006 + .012 * lift),
        ),
    );
    canvas
      ..restore()
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(angle);
    _arm(canvas, reach);
    canvas.restore();
  }

  /// Draws the arm with the pivot at the origin and the stylus at (reach, 0).
  void _arm(Canvas canvas, double reach, {Paint? silhouette}) {
    final shellLength = reach * .16;
    // The tube meets the back of the angled headshell, not the stylus.
    final shellBack = Offset(
      reach - shellLength * math.cos(_offsetAngle),
      -shellLength * math.sin(_offsetAngle),
    );
    final tubeLength = shellBack.distance;
    final tubeWidth = reach * .024;
    final metal = [
      Color.lerp(brass, Colors.black, .55)!,
      Color.lerp(brass, sheen, .75)!,
      brass,
      Color.lerp(brass, Colors.black, .5)!,
    ];

    canvas
      ..save()
      ..rotate(shellBack.direction);
    final weight = RRect.fromRectAndRadius(
      Rect.fromLTRB(-reach * .27, -reach * .052, -reach * .11, reach * .052),
      Radius.circular(reach * .018),
    );
    final stub = Rect.fromLTRB(
      -reach * .12,
      -tubeWidth * .7,
      0,
      tubeWidth * .7,
    );
    final tube = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, -tubeWidth / 2, tubeLength, tubeWidth / 2),
      Radius.circular(tubeWidth / 2),
    );
    if (silhouette != null) {
      canvas
        ..drawRRect(weight, silhouette)
        ..drawRect(stub, silhouette)
        ..drawRRect(tube, silhouette);
    } else {
      canvas
        ..drawRect(
          stub,
          Paint()..color = Color.lerp(_gunmetal, Colors.white, .2)!,
        )
        ..drawRRect(
          weight,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black,
                Color.lerp(_gunmetal, Colors.white, .28)!,
                _gunmetal,
                Colors.black,
              ],
              stops: const [0, .3, .62, 1],
            ).createShader(weight.outerRect),
        )
        ..drawRRect(
          tube,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: metal,
              stops: const [0, .32, .6, 1],
            ).createShader(tube.outerRect),
        );
    }
    canvas.restore();

    canvas
      ..save()
      ..translate(reach, 0)
      ..rotate(_offsetAngle);
    final cartridge = RRect.fromRectAndRadius(
      Rect.fromLTRB(-reach * .118, -reach * .032, reach * .012, reach * .032),
      Radius.circular(reach * .008),
    );
    final shell = RRect.fromRectAndRadius(
      Rect.fromLTRB(-shellLength, -reach * .021, -reach * .012, reach * .021),
      Radius.circular(reach * .01),
    );
    final fingerLift = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = reach * .013
      ..color = brass;
    final liftFrom = Offset(-reach * .125, -reach * .018);
    final liftTo = Offset(-reach * .105, -reach * .082);
    if (silhouette != null) {
      canvas
        ..drawRRect(cartridge, silhouette)
        ..drawRRect(shell, silhouette);
    } else {
      canvas
        ..drawLine(liftFrom, liftTo, fingerLift)
        ..drawRRect(cartridge, Paint()..color = const Color(0xFF151312))
        ..drawRRect(
          shell,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: metal,
              stops: const [0, .3, .6, 1],
            ).createShader(shell.outerRect),
        )
        // The one lit point on the deck: the needle in the groove.
        ..drawCircle(
          Offset.zero,
          reach * .011,
          Paint()..color = stylus.withValues(alpha: 1 - lift),
        );
    }
    canvas.restore();

    if (silhouette == null) {
      canvas.drawCircle(
        Offset.zero,
        reach * .052,
        Paint()
          ..shader =
              RadialGradient(
                center: const Alignment(-.3, -.35),
                colors: [
                  Color.lerp(brass, sheen, .7)!,
                  brass,
                  Color.lerp(brass, Colors.black, .6)!,
                ],
                stops: const [0, .5, 1],
              ).createShader(
                Rect.fromCircle(center: Offset.zero, radius: reach * .052),
              ),
      );
    }
  }

  @override
  bool shouldRepaint(_ToneArmPainter old) =>
      old.angle != angle ||
      old.lift != lift ||
      old.brass != brass ||
      old.sheen != sheen ||
      old.stylus != stylus ||
      old.metal != metal;
}

class _PlatterPainter extends CustomPainter {
  const _PlatterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas
      ..drawCircle(
        center.translate(0, radius * .03),
        radius,
        Paint()
          ..color = Colors.black.withValues(alpha: .3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .05),
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFFF6F6F4),
              Color(0xFFA9AAAD),
              Color(0xFFF2F2F0),
              Color(0xFF9B9C9F),
              Color(0xFFF6F6F4),
            ],
          ).createShader(bounds),
      );
    final dot = Paint()..color = const Color(0xFF2E2F32);
    for (var i = 0; i < 72; i++) {
      canvas.drawCircle(
        center + Offset.fromDirection(i * math.pi / 36, radius * .974),
        radius * .009,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_PlatterPainter old) => false;
}
