import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks the Mac window to move, zoom or change into the mini player. The
/// window's top edge is drawn by Flutter, so dragging and double-clicking it
/// are forwarded here. Without a native window (tests) every call is a no-op.
abstract final class DesktopWindow {
  static const _channel = MethodChannel('ai_music/desktop_navigation');

  /// The mini player's two shapes, as NetEase Cloud Music's: the strip and
  /// the square. The native window snaps a dragged edge to one of them.
  static const miniStrip = Size(336, 52);
  static const miniSquare = Size(336, 336);

  static Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Widget tests have no native window.
    } on PlatformException {
      // A window gesture must never interrupt playback.
    }
  }

  static Map<String, double> _size(Size size) => {
    'width': size.width,
    'height': size.height,
  };

  static Future<void> startDrag() => _call('startDrag');

  /// Fills the screen's usable area, or returns to the earlier size.
  static Future<void> zoom() => _call('zoom');

  static Future<void> enterMini(Size size) => _call('enterMini', _size(size));

  /// [fromBottom] keeps the window's foot in place, as the cover and 词 do.
  static Future<void> resizeMini(Size size, {bool fromBottom = false}) =>
      _call('miniSize', {..._size(size), 'fromBottom': fromBottom});

  /// Shows a native menu at [at] (from the window's top left) and returns
  /// the id of the item picked, or null.
  static Future<String?> popupMenu(
    Offset at,
    List<DesktopMenuItem> items,
  ) async {
    try {
      return await _channel.invokeMethod<String>('popupMenu', {
        'x': at.dx,
        'y': at.dy,
        'items': [for (final item in items) item.toMap()],
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> exitMini() => _call('exitMini');

  static Future<void> alwaysOnTop(bool on) => _call('alwaysOnTop', on);

  static Future<void> showTooltip(String text, Rect rect) =>
      _call('showTooltip', {
        'text': text,
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      });

  static Future<void> hideTooltip() => _call('hideTooltip');

  /// Hides the window; music keeps playing, as with the red button.
  static Future<void> close() => _call('close');
}

/// Empty window chrome: dragging it moves the window and a double click
/// fills the screen or returns to the earlier size.
class DesktopWindowDragArea extends StatelessWidget {
  const DesktopWindowDragArea({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: (_) => DesktopWindow.startDrag(),
    onDoubleTap: DesktopWindow.zoom,
    child: child ?? const SizedBox.expand(),
  );
}

/// One row of a native popup menu, or a separator.
class DesktopMenuItem {
  const DesktopMenuItem(
    this.id,
    this.title, {
    this.enabled = true,
    this.checked = false,
  }) : separator = false;

  const DesktopMenuItem.separator()
    : id = '',
      title = '',
      enabled = false,
      checked = false,
      separator = true;

  final String id, title;
  final bool enabled, checked, separator;

  Map<String, Object> toMap() => separator
      ? {'separator': true}
      : {'id': id, 'title': title, 'enabled': enabled, 'checked': checked};
}

/// Marks a subtree, such as the mini player, whose window is too small for
/// Flutter's own tooltips: its controls show native ones instead.
class DesktopNativeTooltips extends InheritedWidget {
  const DesktopNativeTooltips({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopNativeTooltips>() !=
      null;

  @override
  bool updateShouldNotify(DesktopNativeTooltips oldWidget) => false;
}

/// A tooltip drawn by macOS in its own small window, so it can reach past
/// the edge of a window as small as the mini strip. Under
/// [DesktopNativeTooltips] it stands in for [Tooltip]; elsewhere it is one.
class DesktopTooltip extends StatefulWidget {
  const DesktopTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<DesktopTooltip> createState() => _DesktopTooltipState();
}

class _DesktopTooltipState extends State<DesktopTooltip> {
  Timer? _wait;
  bool _shown = false;

  void _show() {
    final box = context.findRenderObject();
    if (!mounted || box is! RenderBox || !box.attached) return;
    _shown = true;
    unawaited(
      DesktopWindow.showTooltip(
        widget.message,
        box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _hide() {
    _wait?.cancel();
    _wait = null;
    if (_shown) unawaited(DesktopWindow.hideTooltip());
    _shown = false;
  }

  @override
  void didUpdateWidget(DesktopTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A label that changes under the pointer (play, then pause) follows.
    if (_shown && oldWidget.message != widget.message) _show();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopNativeTooltips.of(context)) {
      return Tooltip(
        message: widget.message,
        waitDuration: const Duration(milliseconds: 450),
        excludeFromSemantics: true,
        child: widget.child,
      );
    }
    return MouseRegion(
      onEnter: (_) {
        _wait?.cancel();
        _wait = Timer(const Duration(milliseconds: 450), _show);
      },
      onExit: (_) => _hide(),
      child: Listener(onPointerDown: (_) => _hide(), child: widget.child),
    );
  }
}
