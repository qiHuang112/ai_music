import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'duo_window.dart';

/// Page chrome shares the system's vertical strip instead of allocating another
/// column beside it. Nested tab pages leave navigation to their parent shell.
class DuoScaffold extends StatelessWidget {
  const DuoScaffold({
    super.key,
    this.appBar,
    this.railAppBar,
    this.railKey,
    this.body,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.navigationItems = const [],
    this.extraActions = const [],
    this.preferSideNavigation = false,
  });

  final Key? railKey;
  // Sliver pages keep their title in the content but move these controls.
  final AppBar? appBar, railAppBar;
  final Widget? body, bottomNavigationBar, floatingActionButton;
  final Color? backgroundColor;
  final bool extendBody, extendBodyBehindAppBar, preferSideNavigation;
  final bool? resizeToAvoidBottomInset;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final List<DuoRailItem> navigationItems, extraActions;

  static bool usesSystemRail(BuildContext context) =>
      DuoWindowScope.of(context).edge != DuoBarEdge.none &&
      !(_DuoChrome.of(context));

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final geometry = DuoWindowScope.of(context);
    final nested = _DuoChrome.of(context);
    final systemRail = usesSystemRail(context);
    final rail = !nested && (systemRail || preferSideNavigation);
    final left = systemRail && geometry.edge == DuoBarEdge.left;
    final width = rail
        ? math.max(
            76.0,
            systemRail ? (left ? data.padding.left : data.padding.right) : 0.0,
          )
        : 0.0;
    final origin = Offset(left ? width : 0, 0);
    EdgeInsets contentInsets(EdgeInsets value) => !rail
        ? value
        : EdgeInsets.fromLTRB(
            left ? 0 : value.left,
            value.top,
            left ? value.right : 0,
            value.bottom,
          );
    final controls = appBar ?? railAppBar;
    final items = <DuoRailItem>[
      if (systemRail) ...[
        if (controls?.leading != null)
          DuoRailItem.fromWidget(controls!.leading!, context)
        else if ((controls?.automaticallyImplyLeading ?? true) &&
            Navigator.of(context).canPop())
          DuoRailItem(
            icon: Icons.arrow_back_rounded,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        for (final action in controls?.actions ?? const <Widget>[])
          DuoRailItem.fromWidget(action, context),
        ...extraActions,
      ],
      ...navigationItems,
    ];
    final titleBar = systemRail && appBar != null
        ? AppBar(
            automaticallyImplyLeading: false,
            title: appBar!.title,
            titleTextStyle: appBar!.titleTextStyle,
            centerTitle: appBar!.centerTitle,
            backgroundColor: appBar!.backgroundColor,
            foregroundColor: appBar!.foregroundColor,
            elevation: appBar!.elevation,
            toolbarHeight: 40,
            bottom: appBar!.bottom,
          )
        : appBar;
    final railRect = Rect.fromLTWH(
      left ? 0 : data.size.width - width,
      0,
      width,
      data.size.height,
    );
    // Keep this tree stable when a fold changes chrome placement: tab state,
    // scrolling and the mounted playback route must survive the transition.
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: left ? width : 0,
            right: !left ? width : 0,
          ),
          child: MediaQuery(
            data: data.copyWith(
              size: Size(data.size.width - width, data.size.height),
              padding: contentInsets(data.padding),
              viewPadding: contentInsets(data.viewPadding),
              displayFeatures: [
                for (final f in data.displayFeatures)
                  ui.DisplayFeature(
                    bounds: f.bounds.shift(-origin),
                    type: f.type,
                    state: f.state,
                  ),
              ],
            ),
            child: _DuoChrome(
              consumed: nested || rail,
              child: Scaffold(
                appBar: titleBar,
                body: body,
                backgroundColor: backgroundColor,
                extendBody: extendBody,
                extendBodyBehindAppBar: extendBodyBehindAppBar,
                resizeToAvoidBottomInset: resizeToAvoidBottomInset,
                bottomNavigationBar: bottomNavigationBar,
                floatingActionButton: floatingActionButton,
                floatingActionButtonLocation: floatingActionButtonLocation,
              ),
            ),
          ),
        ),
        if (rail)
          Positioned.fromRect(
            rect: railRect,
            child: DuoRail(
              key: railKey,
              items: items,
              bounds: railRect,
              obstructions: systemRail
                  ? [...geometry.obstructions, ...geometry.divisions]
                  : const [],
              top: data.padding.top,
              bottom: math.max(data.padding.bottom, data.viewInsets.bottom),
            ),
          ),
      ],
    );
  }
}

class _DuoChrome extends InheritedWidget {
  const _DuoChrome({required this.consumed, required super.child});
  final bool consumed;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DuoChrome>()?.consumed ??
      false;
  @override
  bool updateShouldNotify(_DuoChrome oldWidget) =>
      consumed != oldWidget.consumed;
}

class DuoRailItem {
  const DuoRailItem({
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.navigation = false,
    this.marker,
    this.custom,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected, navigation;
  final Widget? marker, custom;

  factory DuoRailItem.fromWidget(Widget widget, BuildContext context) {
    if (widget is IconButton) {
      return DuoRailItem(
        icon: widget.icon is Icon
            ? (widget.icon as Icon).icon ?? Icons.circle_outlined
            : Icons.more_horiz,
        label: widget.tooltip ?? '',
        onPressed: widget.onPressed,
        custom: widget,
      );
    }
    if (widget is BackButton) {
      return DuoRailItem(
        icon: Icons.arrow_back_rounded,
        label: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: widget.onPressed ?? () => Navigator.of(context).maybePop(),
      );
    }
    if (widget is TextButton) {
      return DuoRailItem(
        icon: Icons.check_rounded,
        label: widget.child is Text ? (widget.child as Text).data ?? '' : '',
        onPressed: widget.onPressed,
        custom: widget,
      );
    }
    return DuoRailItem(
      icon: Icons.more_horiz,
      label: MaterialLocalizations.of(context).moreButtonTooltip,
      custom: widget,
    );
  }
}

/// The same coordinate system as UIKit, including split-view leading rails.
/// Slots skip *rectangles*, not a whole edge; the camera's column stays usable.
class DuoRail extends StatelessWidget {
  const DuoRail({
    super.key,
    required this.items,
    required this.bounds,
    required this.obstructions,
    this.top = 0,
    this.bottom = 0,
  });
  final List<DuoRailItem> items;
  final Rect bounds;
  final List<Rect> obstructions;
  final double top, bottom;

  static List<double> slots(
    Rect bounds,
    List<Rect> obstructions, {
    double top = 0,
    double bottom = 0,
  }) {
    final result = <double>[];
    var y = bounds.top + math.max(8, top);
    final limit = bounds.bottom - math.max(8, bottom);
    final blocks =
        obstructions
            .where((r) => r.left < bounds.right && r.right > bounds.left)
            .map((r) => r.inflate(4))
            .toList()
          ..sort((a, b) => a.top.compareTo(b.top));
    while (y + 52 <= limit) {
      final cell = Rect.fromLTWH(bounds.left + 4, y, bounds.width - 8, 52);
      final overlaps = blocks.where(cell.overlaps);
      if (overlaps.isNotEmpty) {
        y = overlaps.map((r) => r.bottom).reduce(math.max);
      } else {
        result.add(y - bounds.top);
        y += 56;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final positions = slots(bounds, obstructions, top: top, bottom: bottom);
    if (positions.isEmpty) return const SizedBox.shrink();
    final capacity = positions.length;
    final overflow = items.length > capacity;
    final visible = items.take(overflow ? capacity - 1 : capacity).toList();
    final colors = Theme.of(context).colorScheme;
    final firstNavigation = visible.indexWhere((item) => item.navigation);
    return DecoratedBox(
      key: const ValueKey('duo-system-rail'),
      decoration: BoxDecoration(color: colors.surface.withValues(alpha: .20)),
      child: Stack(
        children: [
          for (final (i, item) in visible.indexed)
            Positioned(
              left: 4,
              right: 4,
              top:
                  positions[!overflow &&
                          firstNavigation >= 0 &&
                          i >= firstNavigation
                      ? positions.length - (visible.length - i)
                      : i],
              height: 52,
              child:
                  item.custom ??
                  Semantics(
                    selected: item.selected,
                    label: item.navigation ? null : item.label,
                    button: true,
                    child: Tooltip(
                      message: item.label,
                      excludeFromSemantics: true,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: item.selected
                              ? colors.secondaryContainer
                              : null,
                          foregroundColor: item.selected
                              ? colors.onSecondaryContainer
                              : colors.onSurface,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: item.onPressed,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.icon, size: 22),
                            if (item.navigation)
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.linear(
                                  MediaQuery.textScalerOf(context).scale(11) /
                                              11 >
                                          1.3
                                      ? 1.3
                                      : MediaQuery.textScalerOf(
                                              context,
                                            ).scale(11) /
                                            11,
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            if (item.marker != null) item.marker!,
                          ],
                        ),
                      ),
                    ),
                  ),
            ),
          if (overflow)
            Positioned(
              left: 4,
              right: 4,
              top: positions.last,
              height: 52,
              child: PopupMenuButton<int>(
                key: const ValueKey('duo-rail-overflow'),
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (index) => items[index].onPressed?.call(),
                itemBuilder: (context) => [
                  for (var i = visible.length; i < items.length; i++)
                    PopupMenuItem(
                      value: i,
                      enabled: items[i].onPressed != null,
                      child:
                          items[i].onPressed == null && items[i].custom != null
                          ? items[i].custom!
                          : Row(
                              children: [
                                Icon(items[i].icon),
                                const SizedBox(width: 12),
                                Flexible(child: Text(items[i].label)),
                              ],
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
