import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import 'glass_surface.dart';

/// Touch feedback for anything tappable: it sinks under the finger, springs
/// back and ticks the haptic engine.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.pressedScale = .95,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController.unbounded(vsync: this);
  }

  void _down() =>
      _press.animateTo(1, duration: MusicMotion.fast, curve: Curves.easeOut);

  void _release() => _press.animateWith(
    SpringSimulation(MusicMotion.bouncy, _press.value, 0, 0),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _down() : null,
      onTapCancel: enabled ? _release : null,
      onTapUp: enabled ? (_) => _release() : null,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.pressedScale) * _press.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// A round control cut from glass. Set [blur] to false when it already sits on
/// a glass surface.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.selected = false,
    this.blur = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool selected, blur;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        selected: selected,
        child: Pressable(
          onTap: onPressed,
          child: GlassSurface(
            level: selected ? GlassLevel.thick : GlassLevel.thin,
            borderRadius: BorderRadius.circular(size / 2),
            tint: selected ? colors.primaryContainer : null,
            blur: blur,
            shadow: false,
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                icon,
                size: size * .5,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurface.withValues(
                        alpha: onPressed == null ? .38 : 1,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one loud control: a button lit from inside like a pilot lamp. While
/// the song plays its light breathes, slowly swelling and easing back.
class PlayPauseButton extends StatefulWidget {
  const PlayPauseButton({
    super.key,
    required this.playing,
    required this.tooltip,
    required this.onPressed,
    this.size = 76,
  });

  final bool playing;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.playing && MusicMotion.allowsPerpetual(context);
    if (run && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!run && (_breath.isAnimating || _breath.value != 0)) {
      _breath.animateBack(0, duration: MusicMotion.slow);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = colors.primaryContainer;
    final palette = MusicTokens.of(context);
    final neon = palette.neon;
    final skin = palette.skin;
    final size = widget.size;
    final playing = widget.playing;
    final onPressed = widget.onPressed;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: Pressable(
          pressedScale: .92,
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onPressed();
                },
          haptic: false,
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, icon) {
              final breath = Curves.easeInOut.transform(_breath.value);
              final lit = Color.lerp(accent, Colors.white, .10 * breath)!;
              // Printed: flat ink, an outline and an off-register block.
              if (skin == MusicSkin.riso) {
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    border: Border.all(color: palette.text, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: palette.haze,
                        offset: const Offset(4, 4),
                      ),
                    ],
                  ),
                  child: icon,
                );
              }
              // A knurled aluminium knob round an orange lens.
              if (skin == MusicSkin.silver && size >= 60) {
                return Container(
                  width: size,
                  height: size,
                  padding: EdgeInsets.all(size * .18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        for (var i = 0; i < 60; i++)
                          i.isEven
                              ? const Color(0xFFF6F6F4)
                              : const Color(0xFF96979A),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: .35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFFA36B),
                          lit,
                          const Color(0xFFC9440F),
                        ],
                        stops: const [0, .7, 1],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(
                            alpha: playing ? .5 + .3 * breath : .2,
                          ),
                          blurRadius: size * .12,
                        ),
                      ],
                    ),
                    child: icon,
                  ),
                );
              }
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-.3, -.45),
                    radius: .95,
                    colors: [
                      Color.lerp(lit, Colors.white, .42)!,
                      lit,
                      Color.lerp(lit, Colors.black, .22)!,
                    ],
                    stops: const [0, .55, 1],
                  ),
                  // A neon tube: a white inner ring and a harder glow.
                  border: neon
                      ? Border.all(color: Colors.white.withValues(alpha: .4))
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(
                        alpha:
                            (playing ? .34 + .26 * breath : .22) +
                            (neon || skin == MusicSkin.aurora ? .3 : 0),
                      ),
                      blurRadius:
                          size *
                          (playing ? .26 + .22 * breath : .2) *
                          (neon ? 1.5 : 1),
                      spreadRadius: playing ? size * .03 * breath : 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .30),
                      blurRadius: size * .13,
                      offset: Offset(0, size * .07),
                    ),
                  ],
                ),
                child: icon,
              );
            },
            child: AnimatedSwitcher(
              duration: MusicMotion.base,
              switchInCurve: Curves.easeOutBack,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                size: size * .5,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Playback position as a hairline that thickens under the finger. [buffered]
/// draws the downloaded part behind it.
class GrooveSlider extends StatefulWidget {
  const GrooveSlider({
    super.key,
    required this.value,
    this.buffered = 0,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    this.semanticLabel,
  });

  /// Both run from 0 to 1.
  final double value, buffered;
  final ValueChanged<double>? onChangeStart, onChanged, onChangeEnd;
  final String? semanticLabel;

  @override
  State<GrooveSlider> createState() => _GrooveSliderState();
}

class _GrooveSliderState extends State<GrooveSlider>
    with SingleTickerProviderStateMixin {
  static const _height = 32.0;

  late final AnimationController _grip;
  double? _dragValue;
  int _lastStep = 0;

  @override
  void initState() {
    super.initState();
    _grip = AnimationController(vsync: this, duration: MusicMotion.base);
  }

  static String _percent(double value) => '${(value * 100).round()}%';

  double _at(Offset local, double width) =>
      (local.dx / width).clamp(0.0, 1.0).toDouble();

  void _start(double value) {
    _grip.animateTo(1, curve: MusicMotion.emphasized);
    HapticFeedback.selectionClick();
    _lastStep = (value * 10).floor();
    setState(() => _dragValue = value);
    widget.onChangeStart?.call(value);
    widget.onChanged?.call(value);
  }

  void _move(double value) {
    // A soft tick every tenth, like detents on a dial.
    final step = (value * 10).floor();
    if (step != _lastStep) {
      _lastStep = step;
      HapticFeedback.selectionClick();
    }
    setState(() => _dragValue = value);
    widget.onChanged?.call(value);
  }

  void _end() {
    final value = _dragValue;
    _grip.animateBack(0, curve: MusicMotion.standard);
    setState(() => _dragValue = null);
    if (value != null) widget.onChangeEnd?.call(value);
  }

  @override
  void dispose() {
    _grip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null || widget.onChangeEnd != null;
    final value = (_dragValue ?? widget.value).clamp(0.0, 1.0).toDouble();
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: _percent(value),
      increasedValue: _percent(math.min(1, value + .05)),
      decreasedValue: _percent(math.max(0, value - .05)),
      onIncrease: enabled
          ? () => widget.onChangeEnd?.call(math.min(1, value + .05))
          : null,
      onDecrease: enabled
          ? () => widget.onChangeEnd?.call(math.max(0, value - .05))
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: enabled
                ? (details) => _start(_at(details.localPosition, width))
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) => _move(_at(details.localPosition, width))
                : null,
            onHorizontalDragEnd: enabled ? (_) => _end() : null,
            onHorizontalDragCancel: enabled ? _end : null,
            // A tap seeks on release. Engaging on touch-down would leave the
            // scrub open whenever a scroll takes the gesture instead.
            onTapUp: enabled
                ? (details) {
                    _start(_at(details.localPosition, width));
                    _end();
                  }
                : null,
            child: CustomPaint(
              size: Size(width, _height),
              painter: _GrooveSliderPainter(
                value: value,
                buffered: widget.buffered.clamp(0.0, 1.0).toDouble(),
                grip: _grip,
                active: colors.primary,
                head: colors.primaryContainer,
                rail: colors.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GrooveSliderPainter extends CustomPainter {
  _GrooveSliderPainter({
    required this.value,
    required this.buffered,
    required this.grip,
    required this.active,
    required this.head,
    required this.rail,
  }) : super(repaint: grip);

  final double value, buffered;
  final Animation<double> grip;
  final Color active, head, rail;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = 4 + 6 * grip.value;
    final top = (size.height - thickness) / 2;
    final radius = Radius.circular(thickness / 2);
    RRect bar(double fraction) => RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width * fraction, thickness),
      radius,
    );

    canvas
      ..save()
      ..clipRRect(bar(1))
      ..drawRRect(bar(1), Paint()..color = rail.withValues(alpha: .13))
      ..drawRRect(bar(buffered), Paint()..color = rail.withValues(alpha: .20));
    if (value > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width * value, thickness),
        Paint()
          ..shader = LinearGradient(
            colors: [active.withValues(alpha: .75), head],
          ).createShader(Rect.fromLTWH(0, top, size.width * value, thickness)),
      );
    }
    canvas.restore();

    // The playhead: a pinpoint at rest, a knob when held.
    final center = Offset(size.width * value, size.height / 2);
    final knob = 3 + 6 * grip.value;
    canvas
      ..drawCircle(
        center,
        knob + 5,
        Paint()
          ..color = head.withValues(alpha: .28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawCircle(center, knob, Paint()..color = head);
  }

  @override
  bool shouldRepaint(_GrooveSliderPainter old) =>
      old.value != value ||
      old.buffered != buffered ||
      old.active != active ||
      old.head != head ||
      old.rail != rail;
}

/// Marks the row that is playing: level-meter bars that rise and fall, or rest
/// low while paused.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.size = 18,
    this.color,
  });

  final bool playing;
  final double size;
  final Color? color;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat;

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.playing && MusicMotion.allowsPerpetual(context);
    if (run && !_beat.isAnimating) {
      _beat.repeat();
    } else if (!run && _beat.isAnimating) {
      _beat.stop();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _BarsPainter(
        beat: _beat,
        playing: widget.playing,
        color: widget.color ?? Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.beat, required this.playing, required this.color})
    : super(repaint: beat);

  final Animation<double> beat;
  final bool playing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 4;
    final width = size.width / (bars * 2 - 1);
    final turn = beat.value * 2 * math.pi;
    for (var i = 0; i < bars; i++) {
      // Whole-number speeds, so the loop closes without a jump.
      final level = playing
          ? .5 +
                .32 * math.sin(turn * (2 + i % 2) + i * 1.9) +
                .16 * math.sin(turn * (5 - i) + i)
          : .16;
      final height = size.height * level.clamp(.14, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * width * 2, size.height - height, width, height),
          Radius.circular(width / 2),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.playing != playing || old.color != color;
}

/// Small capitals over a section, in the engraved voice.
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: MusicType.eyebrow(context).copyWith(color: color),
  );
}

/// Section heading: eyebrow, serif title and an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              EyebrowLabel(eyebrow!),
              const SizedBox(height: 6),
            ],
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MusicType.masthead(context, size: 24),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// A pill for filters and choices. The selected one lights up amber.
class LabelChip extends StatelessWidget {
  const LabelChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MusicMotion.base,
          curve: MusicMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.onSurface.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : colors.onSurface.withValues(alpha: .10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Audio quality stamped like the lettering on a faceplate: FLAC, 24BIT, 320K.
class QualityBadge extends StatelessWidget {
  const QualityBadge(this.text, {super.key, this.highlighted = false});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = highlighted ? colors.primary : colors.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 2, 5, 1),
        child: Text(
          text.toUpperCase(),
          style: MusicType.readout(
            context,
            size: 10,
          ).copyWith(color: color, letterSpacing: 1),
        ),
      ),
    );
  }
}

/// Puts the keyboard away when a blank part of the screen is tapped. Taps on
/// buttons, rows and fields still go to them; only a tap nothing else wants
/// lands here.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    // Not a control: screen readers must not see the whole app as tappable.
    excludeFromSemantics: true,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}
