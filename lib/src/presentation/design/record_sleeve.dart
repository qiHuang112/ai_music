import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'vinyl_disc.dart';

/// Album art as a printed sleeve with its record slipping out of the opening.
///
/// [reveal] is how far the disc shows, as a share of [size]; the widget is
/// that much wider than the cover. Raise it while the album plays.
class RecordSleeve extends StatelessWidget {
  const RecordSleeve({
    super.key,
    required this.cover,
    required this.size,
    this.reveal = .24,
    this.spinning = false,
    this.label,
    this.labelColor,
  });

  final Widget cover;
  final double size;
  final double reveal;
  final bool spinning;
  final Widget? label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(MusicUi.sleeveRadius));
    final disc = size * .94;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: reveal),
      duration: MusicMotion.slow,
      curve: MusicMotion.emphasized,
      builder: (context, shown, sleeve) => SizedBox(
        width: size * (1 + shown),
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: size - disc + size * shown,
              top: (size - disc) / 2,
              width: disc,
              height: disc,
              child: SpinningVinyl(
                spinning: spinning,
                label: label,
                labelColor: labelColor,
                shadow: false,
              ),
            ),
            sleeve!,
          ],
        ),
      ),
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .40),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .28),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              // Printed card: a crease along the spine, light on the top-left
              // edge and shade where the opening is.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: .26),
                    Colors.white.withValues(alpha: .14),
                    Colors.white.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: .22),
                  ],
                  stops: const [0, .035, .09, .93, 1],
                ),
              ),
              child: cover,
            ),
          ),
        ),
      ),
    );
  }
}
