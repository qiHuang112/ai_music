import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'controls.dart';

class GlassTab {
  const GlassTab({required this.label, required this.tooltip, this.marker});

  final String label, tooltip;

  /// A small sign beside the label: a spinner while downloading, a dot when
  /// an update is waiting.
  final Widget? marker;
}

/// The app's main navigation, kept quiet: words only, the current one darker
/// and bolder. The mini player above it is the thing to look at.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelected,
  });

  final List<GlassTab> tabs;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final (i, tab) in tabs.indexed)
              Expanded(
                child: Tooltip(
                  message: tab.tooltip,
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: Pressable(
                      onTap: () => onSelected(i),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: AnimatedDefaultTextStyle(
                                duration: MusicMotion.fast,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.2,
                                  fontWeight: i == index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: i == index
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant.withValues(
                                          alpha: .75,
                                        ),
                                ),
                                child: Text(
                                  tab.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: MediaQuery.textScalerOf(
                                    context,
                                  ).clamp(maxScaleFactor: 1.3),
                                ),
                              ),
                            ),
                            if (tab.marker != null) ...[
                              const SizedBox(width: 5),
                              tab.marker!,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The frosted strip the tabs sit on: whatever scrolls behind is blurred and
/// washed with the page color. Only the navigation gets this; the mini player
/// above it floats free over the page.
class NavBlur extends StatelessWidget {
  const NavBlur({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = MusicTokens.of(context).background;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: .10),
                base.withValues(alpha: .38),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
