import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Also completes a partial drag after the scroll position has laid out.
class PlaylistScrollView extends StatefulWidget {
  const PlaylistScrollView({
    super.key,
    required this.slivers,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });
  final List<Widget> slivers;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  State<PlaylistScrollView> createState() => _PlaylistScrollViewState();
}

class _PlaylistScrollViewState extends State<PlaylistScrollView> {
  final _headerKey = GlobalKey();
  ScrollDirection _direction = ScrollDirection.idle;
  int _gesture = 0;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _gesture++;
      _direction = ScrollDirection.idle;
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _direction = notification.direction;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0) != 0) {
      _direction = notification.scrollDelta! > 0
          ? ScrollDirection.reverse
          : ScrollDirection.forward;
    } else if (notification is ScrollEndNotification &&
        _direction != ScrollDirection.idle) {
      final direction = _direction;
      final gesture = _gesture;
      _direction = ScrollDirection.idle;
      // Near the top, a floating header cannot shrink further than the actual
      // scroll offset. Finish that partial scroll before snapping its paint.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || gesture != _gesture) return;
        final header = _headerKey.currentContext?.findRenderObject();
        if (header is RenderSliverFloatingPersistentHeader) {
          final position = Scrollable.of(_headerKey.currentContext!).position;
          final collapseExtent = header.maxExtent - header.minExtent;
          if (position.pixels > 0 && position.pixels < collapseExtent) {
            final target = direction == ScrollDirection.reverse
                ? collapseExtent.clamp(0.0, position.maxScrollExtent)
                : 0.0;
            unawaited(
              position.animateTo(
                target,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              ),
            );
          } else {
            header.maybeStartSnapAnimation(direction);
          }
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          keyboardDismissBehavior: widget.keyboardDismissBehavior,
          slivers: [
            for (final sliver in widget.slivers)
              if (sliver is PlaylistSliverHeader)
                KeyedSubtree(key: _headerKey, child: sliver)
              else
                sliver,
          ],
        ),
      );
}

/// A full playlist name that moves into the toolbar as its list scrolls.
class PlaylistSliverHeader extends StatelessWidget {
  const PlaylistSliverHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.toolbarTitle,
  });

  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? toolbarTitle;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge!;
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: MediaQuery.sizeOf(context).width - 40);
    final expandedHeight = kToolbarHeight + painter.height + 28;
    painter.dispose();
    return SliverAppBar(
      key: const ValueKey('playlist-sliver-app-bar'),
      pinned: true,
      floating: true,
      snap: true,
      expandedHeight: expandedHeight,
      titleTextStyle: style.copyWith(fontSize: 16),
      actions: actions,
      leading: leading,
      title: toolbarTitle ?? _CompactPlaylistTitle(title: title),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final top = MediaQuery.paddingOf(context).top;
          final collapse =
              ((expandedHeight + top - constraints.maxHeight) /
                      (expandedHeight - kToolbarHeight))
                  .clamp(0.0, 1.0);
          // Keep only one title in semantics once the crossfade has finished.
          if (collapse >= 0.7) return const SizedBox.shrink();
          return ClipRect(
            child: Stack(
              children: [
                PositionedDirectional(
                  start: 20 + 36 * collapse,
                  end: 20,
                  top: top + kToolbarHeight + 12 - 48 * collapse,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - collapse / 0.7).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1 - 0.15 * collapse,
                        alignment: AlignmentDirectional.topStart,
                        child: Text(
                          title,
                          key: const ValueKey('playlist-detail-title'),
                          softWrap: true,
                          style: style,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompactPlaylistTitle extends StatelessWidget {
  const _CompactPlaylistTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
    final range = settings.maxExtent - settings.minExtent;
    final collapse = range <= 0
        ? 1.0
        : ((settings.maxExtent - settings.currentExtent) / range).clamp(
            0.0,
            1.0,
          );
    if (collapse <= 0.35) return const SizedBox.shrink();
    return Opacity(
      opacity: ((collapse - 0.35) / 0.65).clamp(0.0, 1.0),
      child: Text(
        title,
        key: const ValueKey('playlist-compact-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
