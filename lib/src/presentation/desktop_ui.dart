import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_playlists.dart';
import 'app_theme.dart';
import 'desktop_window.dart';

/// Pieces of the Mac window that a pointer, not a finger, works: rows and
/// buttons that answer hover, a segmented switch, and hairline sliders that
/// grow under the cursor. Colors come from the active skin.
abstract final class DesktopUi {
  static const sidebarWidth = 232.0;
  static const panelWidth = 336.0;
  static const gutter = 10.0;
  static const rowRadius = 8.0;
  static const hover = Duration(milliseconds: 120);

  /// The faint fill under the pointer.
  static Color hoverFill(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: dark ? .07 : .055);
  }

  /// The fill of the chosen row: the skin's lit color, held back.
  static Color selectedFill(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: dark ? .17 : .13);
  }

  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  /// Small grey caption above a group, as in a Finder sidebar.
  static TextStyle groupLabel(BuildContext context) => TextStyle(
    fontSize: 11.5,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: muted(context).withValues(alpha: .85),
  );

  /// A page's own big title.
  static TextStyle pageTitle(BuildContext context, {double size = 30}) =>
      MusicType.masthead(context, size: size);

  /// Section title inside a page.
  static TextStyle sectionTitle(BuildContext context) => TextStyle(
    fontSize: 17,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: Theme.of(context).colorScheme.onSurface,
  );
}

/// The artwork that stands for a playlist: its first song with a cover.
Uri? playlistArtworkUri(MusicController controller, MusicPlaylist playlist) {
  for (final track in controller.tracksForPlaylist(playlist)) {
    if (track.artworkUri != null) return track.artworkUri;
  }
  for (final entry in playlist.entries) {
    final url = entry.song?.coverUrl ?? '';
    if (url.isNotEmpty) return Uri.tryParse(url);
  }
  return null;
}

/// Rebuilds with whether the pointer is over [child]'s area.
class DesktopHover extends StatefulWidget {
  const DesktopHover({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<DesktopHover> createState() => _DesktopHoverState();
}

class _DesktopHoverState extends State<DesktopHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

/// A row in a sidebar or list: lit when chosen, faintly filled under the
/// pointer.
class DesktopRow extends StatelessWidget {
  const DesktopRow({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.height = 32,
    this.radius = DesktopUi.rowRadius,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap, onDoubleTap, onSecondaryTap;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double? height;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: selected,
    label: semanticLabel,
    child: DesktopHover(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTap: onSecondaryTap,
        child: AnimatedContainer(
          duration: DesktopUi.hover,
          curve: Curves.easeOut,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: selected
                ? DesktopUi.selectedFill(context)
                : hovered
                ? DesktopUi.hoverFill(context)
                : DesktopUi.hoverFill(context).withValues(alpha: 0),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// A round icon button for toolbars and the playback bar. [active] lights it
/// in the skin's color with a small dot below, like a lit switch.
class DesktopToolButton extends StatelessWidget {
  const DesktopToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 32,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size, iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return DesktopTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: active ? true : null,
        enabled: enabled,
        label: tooltip,
        child: DesktopHover(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: DesktopUi.hover,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? colors.primary.withValues(alpha: hovered ? .24 : .16)
                    : hovered && enabled
                    ? DesktopUi.hoverFill(context)
                    : Colors.transparent,
              ),
              child: Center(
                child: ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: !enabled
                        ? colors.onSurface.withValues(alpha: .3)
                        : active
                        ? colors.primary
                        : color ??
                              colors.onSurface.withValues(
                                alpha: hovered ? 1 : .78,
                              ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Mac segmented control: a recessed track with a raised thumb that slides
/// to the chosen option.
class DesktopSegmented<T> extends StatelessWidget {
  const DesktopSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.height = 30,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = MusicTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final index = selected == null ? -1 : values.indexOf(selected as T);
    final thumb = switch (palette.skin) {
      MusicSkin.neon => BoxDecoration(
        color: palette.accent.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: palette.accent.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: .35),
            blurRadius: 12,
          ),
        ],
      ),
      MusicSkin.riso => BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: palette.text, width: 1.2),
      ),
      _ => BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: .13)
            : Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: .10)
              : palette.line.withValues(alpha: .9),
          width: .6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .3 : .08),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    };
    return Container(
      height: height,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: dark ? .07 : .06),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: MusicMotion.emphasized,
              alignment: Alignment(
                values.length == 1 ? 0 : -1 + 2 * index / (values.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / values.length,
                heightFactor: 1,
                child: DecoratedBox(decoration: thumb),
              ),
            ),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: value == selected,
                    child: DesktopHover(
                      cursor: SystemMouseCursors.click,
                      builder: (context, hovered) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(value),
                        child: Center(
                          child: Text(
                            label(value),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: value == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: value == selected
                                  ? (palette.neon
                                        ? colors.primary
                                        : colors.onSurface)
                                  : colors.onSurface.withValues(
                                      alpha: hovered ? .9 : .62,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Position or volume as a hairline. Under the pointer it thickens and shows
/// its knob; a click or drag sets it, and the change is committed on release.
class DesktopScrubber extends StatefulWidget {
  const DesktopScrubber({
    super.key,
    required this.value,
    this.buffered = 0,
    this.onChanged,
    this.onChangeEnd,
    this.semanticLabel,
    this.semanticValue,
  });

  /// Both run from 0 to 1.
  final double value, buffered;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final String? semanticLabel;
  final String Function(double value)? semanticValue;

  @override
  State<DesktopScrubber> createState() => _DesktopScrubberState();
}

class _DesktopScrubberState extends State<DesktopScrubber> {
  bool _hovered = false;
  double? _drag;

  bool get _enabled => widget.onChanged != null || widget.onChangeEnd != null;

  double _at(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0).toDouble();

  void _move(double value) {
    setState(() => _drag = value);
    widget.onChanged?.call(value);
  }

  void _end() {
    final value = _drag;
    setState(() => _drag = null);
    if (value != null) widget.onChangeEnd?.call(value);
  }

  String _describe(double value) =>
      widget.semanticValue?.call(value) ?? '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = MusicTokens.of(context);
    final value = (_drag ?? widget.value).clamp(0.0, 1.0).toDouble();
    final engaged = _hovered || _drag != null;
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: _describe(value),
      increasedValue: _describe(math.min(1, value + .05)),
      decreasedValue: _describe(math.max(0, value - .05)),
      onIncrease: _enabled
          ? () => widget.onChangeEnd?.call(math.min(1, value + .05))
          : null,
      onDecrease: _enabled
          ? () => widget.onChangeEnd?.call(math.max(0, value - .05))
          : null,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _enabled
                  ? (d) => _move(_at(d.localPosition, width))
                  : null,
              onHorizontalDragUpdate: _enabled
                  ? (d) => _move(_at(d.localPosition, width))
                  : null,
              onHorizontalDragEnd: _enabled ? (_) => _end() : null,
              onHorizontalDragCancel: _enabled ? _end : null,
              onTapUp: _enabled
                  ? (d) {
                      _move(_at(d.localPosition, width));
                      _end();
                    }
                  : null,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: engaged ? 1 : 0),
                duration: DesktopUi.hover,
                builder: (context, grip, _) => CustomPaint(
                  size: Size(width, 18),
                  painter: _ScrubberPainter(
                    value: value,
                    buffered: widget.buffered.clamp(0.0, 1.0).toDouble(),
                    grip: grip,
                    active: palette.neon ? palette.accent : colors.primary,
                    rail: colors.onSurface,
                    glow: palette.neon ? palette.accent : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  const _ScrubberPainter({
    required this.value,
    required this.buffered,
    required this.grip,
    required this.active,
    required this.rail,
    this.glow,
  });

  final double value, buffered, grip;
  final Color active, rail;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = 3 + 2 * grip;
    final top = (size.height - thickness) / 2;
    final radius = Radius.circular(thickness / 2);
    RRect bar(double fraction) => RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width * fraction, thickness),
      radius,
    );
    canvas
      ..drawRRect(bar(1), Paint()..color = rail.withValues(alpha: .14))
      ..drawRRect(bar(buffered), Paint()..color = rail.withValues(alpha: .14));
    if (value > 0) {
      if (glow != null) {
        canvas.drawRRect(
          bar(value),
          Paint()
            ..color = glow!.withValues(alpha: .55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawRRect(
        bar(value),
        Paint()..color = active.withValues(alpha: .7 + .3 * grip),
      );
    }
    if (grip > 0) {
      final center = Offset(size.width * value, size.height / 2);
      canvas
        ..drawCircle(
          center,
          6.5 * grip,
          Paint()
            ..color = Colors.black.withValues(alpha: .25 * grip)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        )
        ..drawCircle(
          center,
          6 * grip,
          Paint()..color = Color.lerp(Colors.white, active, .15)!,
        );
    }
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.value != value ||
      old.buffered != buffered ||
      old.grip != grip ||
      old.active != active ||
      old.rail != rail ||
      old.glow != glow;
}

/// A key cap, as macOS prints shortcuts in menus: ⌘K.
class DesktopKeyCap extends StatelessWidget {
  const DesktopKeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.onSurface.withValues(alpha: .16)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: colors.onSurface.withValues(alpha: .5),
        ),
      ),
    );
  }
}
