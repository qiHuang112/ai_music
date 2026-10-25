import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get isMacMusicDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

enum DesktopDetail { lyrics, comments, queue }

/// Keep a Material slider's value-indicator portal in its own subtree. Flutter
/// 3.44 can otherwise send orphan nodes to the native desktop accessibility
/// bridge when the surrounding route changes (flutter/flutter#190357).
class DesktopSliderOverlay extends StatelessWidget {
  const DesktopSliderOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => isMacMusicDesktop
      ? Overlay.wrap(
          alwaysSizeToContent: true,
          clipBehavior: Clip.none,
          child: child,
        )
      : child;
}

/// Keeps desktop chrome outside the content navigator. Mobile routes do not
/// inherit this scope and continue to own their mini player.
class DesktopMusicScope extends InheritedWidget {
  const DesktopMusicScope({
    super.key,
    required super.child,
    required this.openPlayer,
    required this.openDetail,
    required this.selection,
    required this.locate,
  });

  final VoidCallback openPlayer;
  final ValueChanged<DesktopDetail> openDetail;
  final ValueNotifier<String?> selection;
  final ValueNotifier<({String id, int revision})?> locate;

  static DesktopMusicScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopMusicScope>();

  @override
  bool updateShouldNotify(DesktopMusicScope oldWidget) =>
      selection != oldWidget.selection;
}

/// Separate row selection from playback, without altering touch interactions.
class DesktopSongInteraction extends StatelessWidget {
  const DesktopSongInteraction({
    super.key,
    required this.id,
    required this.onPlay,
    required this.builder,
    this.onContextMenu,
    this.enabled = true,
  });

  final String id;
  final VoidCallback? onPlay, onContextMenu;
  final bool enabled;
  final Widget Function(VoidCallback? onTap, bool selected) builder;

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopMusicScope.maybeOf(context);
    if (desktop == null || !enabled) return builder(onPlay, false);
    return ValueListenableBuilder<String?>(
      valueListenable: desktop.selection,
      builder: (context, selected, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: onPlay,
        onSecondaryTapUp: onContextMenu == null
            ? null
            : (_) {
                desktop.selection.value = id;
                onContextMenu!();
              },
        child: builder(() => desktop.selection.value = id, selected == id),
      ),
    );
  }
}
