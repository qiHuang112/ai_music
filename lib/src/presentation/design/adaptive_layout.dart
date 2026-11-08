import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How much room a page has, in the three classes every page shares.
///
/// Decide from the space a page is given ([MusicLayout.classOf] with a
/// `LayoutBuilder` width), not from the window, so a page inside a desktop
/// pane or a Duo half adapts to what it actually has.
enum WindowClass {
  /// Under 600: a phone held upright, the Duo outer screen.
  compact,

  /// 600–839: a phone on its side, a small tablet, the Duo opened upright.
  medium,

  /// 840 and wider: a tablet on its side, a desktop window.
  expanded;

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}

/// One set of widths for every page, so the same thing is never wide on one
/// page and capped on the next.
abstract final class MusicLayout {
  static const mediumWidth = 600.0;
  static const expandedWidth = 840.0;

  /// Below this height the page is "short" (landscape phone, a folded half).
  static const shortHeight = 480.0;

  /// Text and forms: lines longer than this are hard to read.
  static const readableWidth = 720.0;

  /// Pages that use two columns stop growing here and centre.
  static const wideWidth = 1200.0;

  /// A single card or entry tile.
  static const cardMaxWidth = 560.0;

  /// A button never stretches past this, however wide its row.
  static const actionMaxWidth = 240.0;

  /// The floating and inline now-playing bars share one width.
  static const barMaxWidth = 520.0;

  /// Space between the columns of a two-column page.
  static const columnGap = 24.0;

  /// [base] widened on both sides so the content between stays within
  /// [maxWidth] of a [width]-wide scroll view. The scroll view itself stays
  /// full width, so it still scrolls from the margins.
  static EdgeInsets centered(
    EdgeInsets base,
    double width, {
    double maxWidth = readableWidth,
  }) {
    final content = width - base.horizontal;
    final side = content > maxWidth ? (content - maxWidth) / 2 : 0.0;
    return base.copyWith(left: base.left + side, right: base.right + side);
  }

  static WindowClass classOf(double width) {
    if (width >= expandedWidth) return WindowClass.expanded;
    if (width >= mediumWidth) return WindowClass.medium;
    return WindowClass.compact;
  }

  /// The class for the whole window; prefer [classOf] with the page's own
  /// width where one is at hand.
  static WindowClass of(BuildContext context) =>
      classOf(MediaQuery.sizeOf(context).width);

  static bool isShort(BuildContext context) =>
      MediaQuery.sizeOf(context).height < shortHeight;

  /// How many tiles of at least [minTileWidth] fit in [width], between
  /// [minColumns] and [maxColumns].
  static int columnsFor(
    double width, {
    required double minTileWidth,
    double spacing = 12,
    int minColumns = 1,
    int maxColumns = 6,
  }) {
    final fit = ((width + spacing) / (minTileWidth + spacing)).floor();
    return math.max(minColumns, math.min(maxColumns, fit));
  }
}

/// Caps a page's content at [maxWidth] and centres it; narrower spaces get
/// the content at full width, unchanged.
class AdaptiveBody extends StatelessWidget {
  const AdaptiveBody({
    super.key,
    this.maxWidth = MusicLayout.readableWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Two columns once the space reaches [breakpoint], one stacked column below
/// it. Wide screens get filled with content instead of empty margins.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.primary,
    required this.secondary,
    this.breakpoint = MusicLayout.expandedWidth,
    this.gap = MusicLayout.columnGap,
    this.stackedGap = 24,
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
  });

  final List<Widget> primary, secondary;
  final double breakpoint, gap, stackedGap;
  final int primaryFlex, secondaryFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
      if (constraints.maxWidth < breakpoint) {
        return column([
          ...primary,
          if (primary.isNotEmpty && secondary.isNotEmpty)
            SizedBox(height: stackedGap),
          ...secondary,
        ]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: primaryFlex, child: column(primary)),
          SizedBox(width: gap),
          Expanded(flex: secondaryFlex, child: column(secondary)),
        ],
      );
    },
  );
}

/// Equal tiles in as many columns as fit: two on a phone, more when there is
/// room, so a tile never stretches to half a tablet.
class AdaptiveTiles extends StatelessWidget {
  const AdaptiveTiles({
    super.key,
    required this.children,
    this.minTileWidth = 150,
    this.minColumns = 2,
    this.maxColumns = 4,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double minTileWidth, spacing;
  final int minColumns, maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var columns = MusicLayout.columnsFor(
        constraints.maxWidth,
        minTileWidth: minTileWidth,
        spacing: spacing,
        minColumns: minColumns,
        maxColumns: maxColumns,
      );
      // Full rows only: four tiles go 4 or 2 across, never 3 and an orphan.
      while (columns > minColumns &&
          columns < children.length &&
          children.length % columns != 0) {
        columns -= 1;
      }
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children)
            SizedBox(width: width.floorToDouble(), child: child),
        ],
      );
    },
  );
}

/// A row of page actions: shared equally on a phone, where every pixel
/// counts, and at their natural width (up to [MusicLayout.actionMaxWidth])
/// at the trailing end once the row is wider than [MusicLayout.mediumWidth].
class AdaptiveActions extends StatelessWidget {
  const AdaptiveActions({
    super.key,
    required this.actions,
    this.trailing = const [],
    this.spacing = 8,
  });

  /// The buttons that share the row.
  final List<Widget> actions;

  /// Small extras (icon buttons) that keep their own size at the end.
  final List<Widget> trailing;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < MusicLayout.mediumWidth;
      List<Widget> spaced(Iterable<Widget> items) => [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) SizedBox(width: spacing),
          item,
        ],
      ];
      if (compact) {
        return Row(
          children: spaced([
            for (final child in actions) Expanded(child: child),
            ...trailing,
          ]),
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: spaced([
          for (final child in actions)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 140,
                maxWidth: MusicLayout.actionMaxWidth,
              ),
              child: child,
            ),
          ...trailing,
        ]),
      );
    },
  );
}
