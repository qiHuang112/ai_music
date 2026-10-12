import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'controls.dart';
import 'glass_surface.dart';

class GlassTab {
  const GlassTab({
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  /// A widget, so a tab can carry a badge or a progress ring.
  final Widget icon;
  final String label, tooltip;
}

/// The app's main navigation: a floating glass pill. Content scrolls behind
/// it, and the selected tab is the one lit thing on the bar.
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
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(32),
          padding: const EdgeInsets.all(5),
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
                        child: AnimatedContainer(
                          duration: MusicMotion.base,
                          curve: MusicMotion.standard,
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: i == index
                                ? colors.primaryContainer.withValues(alpha: .22)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(27),
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(
                              size: 23,
                              color: i == index
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 24,
                                  child: Center(child: tab.icon),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tab.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: MediaQuery.textScalerOf(
                                    context,
                                  ).clamp(maxScaleFactor: 1.3),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    height: 1.2,
                                    fontWeight: i == index
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: i == index
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
