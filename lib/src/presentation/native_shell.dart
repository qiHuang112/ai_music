import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// UIKit draws the tab bar, navigation bars, bar buttons and menus; Flutter
/// draws the content. This is the Dart end of `ios/Runner/MusicShell.swift`.
///
/// Pages describe themselves (title, actions, tabs) and the shell shows them
/// with system controls. Page routes on the root navigator are mirrored as
/// native navigation pushes, so the system provides back buttons and keeps
/// everything in the vertical bar on iPhone Duo.
class NativeShell extends NavigatorObserver {
  NativeShell._();

  static final NativeShell instance = NativeShell._();

  /// True once the iOS shell answered; tests and other platforms stay false.
  static bool get active => instance._active;

  static const _channel = MethodChannel('ai_music/shell');
  bool _active = false;

  Future<void> connect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    for (var attempt = 0; attempt < 5 && !_active; attempt++) {
      try {
        _active = await _channel.invokeMethod<bool>('hello') ?? false;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      } on PlatformException {
        break;
      }
    }
    if (_active) _channel.setMethodCallHandler(_onCall);
  }

  // ---- Routes -------------------------------------------------------------

  final Expando<int> _ids = Expando<int>('shell-route');
  final Map<int, Route<dynamic>> _routes = {};
  final Set<int> _pendingPush = {};
  int _nextId = 1;
  int? _nativePopping;

  /// The shell's id for a page route, or null for anything it does not mirror.
  int? idOf(Route<dynamic>? route) => route == null ? null : _ids[route];

  bool _isPage(Route<dynamic> route) => route is PageRoute;

  bool _isModal(Route<dynamic> route) =>
      route is ModalBottomSheetRoute || route is RawDialogRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_active) return;
    if (_isPage(route)) {
      final id = previousRoute == null ? 0 : _nextId++;
      _ids[route] = id;
      _routes[id] = route;
      if (id > 0) {
        _pendingPush.add(id);
        // The page registers its title and actions during this frame; send
        // the push with them so the bar is right from the first frame.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!_pendingPush.remove(id) || _routes[id] != route) return;
          _channel.invokeMethod('push', {'id': id, 'spec': _effective(id)});
        });
      }
    } else if (_isModal(route)) {
      _channel.invokeMethod('modal', {'active': true});
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _left(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _left(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _left(oldRoute);
    if (newRoute != null) didPush(newRoute, oldRoute);
  }

  void _left(Route<dynamic> route) {
    if (!_active) return;
    if (_isModal(route)) {
      _channel.invokeMethod('modal', {'active': false});
      return;
    }
    final id = _ids[route];
    if (id == null) return;
    _routes.remove(id);
    _roots.remove(id);
    _nested.remove(id);
    _callbacks.removeWhere((key, _) => key.startsWith('$id-'));
    if (id == 0) return;
    final pending = _pendingPush.remove(id);
    if (_nativePopping == id) {
      _nativePopping = null;
    } else if (!pending) {
      _channel.invokeMethod('pop', {'id': id});
    }
  }

  // ---- Page descriptions ---------------------------------------------------

  final Map<int, Map<String, Object?>> _roots = {}, _nested = {};
  final Map<String, VoidCallback> _callbacks = {};
  final Set<int> _dirty = {};
  bool _flushScheduled = false;

  /// Who switches the home tabs when the system tab bar is tapped.
  void Function(int index)? onTabSelected;

  void updatePage(int id, Map<String, Object?> spec, {bool nested = false}) {
    final target = nested ? _nested : _roots;
    final previous = target[id];
    target[id] = spec;
    if (previous != null && _sameSpec(previous, spec)) return;
    _markDirty(id);
  }

  void clearPage(int id, {bool nested = false}) {
    final target = nested ? _nested : _roots;
    if (target.remove(id) != null) _markDirty(id);
  }

  void register(String id, VoidCallback callback) => _callbacks[id] = callback;

  void _markDirty(int id) {
    _dirty.add(id);
    if (_flushScheduled) return;
    _flushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      final ids = _dirty.toList();
      _dirty.clear();
      for (final id in ids) {
        if (_pendingPush.contains(id) || !_routes.containsKey(id)) continue;
        final spec = _effective(id);
        if (id == 0) {
          _channel.invokeMethod('tabs', {
            'items': spec.remove('tabs') ?? const [],
            'selected': spec.remove('selectedTab') ?? 0,
            'spec': spec,
          });
        } else {
          _channel.invokeMethod('page', {'id': id, 'spec': spec});
        }
      }
    });
  }

  /// A tab page inside the home shell supplies the bar while it is visible;
  /// the home route keeps the tabs themselves.
  Map<String, Object?> _effective(int id) {
    final root = Map<String, Object?>.of(_roots[id] ?? const {});
    final nested = _nested[id];
    if (nested == null) return root;
    final tabs = root['tabs'], selected = root['selectedTab'];
    final merged = Map<String, Object?>.of(nested);
    if (tabs != null) merged['tabs'] = tabs;
    if (selected != null) merged['selectedTab'] = selected;
    return merged;
  }

  static bool _sameSpec(Map<String, Object?> a, Map<String, Object?> b) =>
      _describe(a) == _describe(b);

  static String _describe(Object? value) {
    if (value is Map) {
      return '{${value.entries.map((e) => '${e.key}:${_describe(e.value)}').join(',')}}';
    }
    if (value is List) return '[${value.map(_describe).join(',')}]';
    if (value is Uint8List) return 'bytes${value.length}';
    return '$value';
  }

  // ---- Shell → Flutter -----------------------------------------------------

  Future<Object?> _onCall(MethodCall call) async {
    final args = call.arguments is Map
        ? Map<Object?, Object?>.from(call.arguments as Map)
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'tabSelected':
        final index = args['index'] as int? ?? 0;
        navigator?.popUntil((route) => route.isFirst);
        onTabSelected?.call(index);
      case 'popped':
        final id = args['id'] as int?;
        final route = id == null ? null : _routes[id];
        final nav = navigator;
        if (route != null && nav != null) {
          _nativePopping = id;
          if (route.isCurrent) {
            nav.pop();
          } else {
            nav.removeRoute(route);
          }
          _nativePopping = null;
        }
      case 'action':
        _callbacks[args['id']]?.call();
    }
    return null;
  }

  // ---- Theme ---------------------------------------------------------------

  String? _themeKey;

  void syncTheme({
    required Brightness brightness,
    required Color tint,
    required Color text,
    String? font,
  }) {
    if (!_active) return;
    final key = '$brightness-${tint.toARGB32()}-${text.toARGB32()}-$font';
    if (key == _themeKey) return;
    _themeKey = key;
    _channel.invokeMethod('theme', {
      'dark': brightness == Brightness.dark,
      'tint': tint.toARGB32(),
      'text': text.toARGB32(),
      'font': font,
    });
  }
}

/// SF Symbols for the icons the app uses in bars. Anything else is rendered
/// from its icon font as a template image.
String? sfSymbol(IconData icon) => _symbols[icon];

final _symbols = <IconData, String>{
  Icons.arrow_back: 'chevron.backward',
  Icons.arrow_back_rounded: 'chevron.backward',
  Icons.arrow_back_ios: 'chevron.backward',
  Icons.arrow_back_ios_new: 'chevron.backward',
  CupertinoIcons.chevron_back: 'chevron.backward',
  Icons.close: 'xmark',
  Icons.close_rounded: 'xmark',
  CupertinoIcons.xmark: 'xmark',
  Icons.check: 'checkmark',
  Icons.check_rounded: 'checkmark',
  CupertinoIcons.checkmark: 'checkmark',
  Icons.favorite: 'heart.fill',
  CupertinoIcons.heart_fill: 'heart.fill',
  Icons.favorite_border: 'heart',
  CupertinoIcons.heart: 'heart',
  Icons.playlist_add: 'text.badge.plus',
  Icons.playlist_add_rounded: 'text.badge.plus',
  CupertinoIcons.text_badge_plus: 'text.badge.plus',
  Icons.queue_music: 'list.bullet',
  Icons.queue_music_rounded: 'list.bullet',
  CupertinoIcons.music_note_list: 'list.bullet',
  Icons.lyrics_outlined: 'quote.bubble',
  CupertinoIcons.text_quote: 'quote.bubble',
  Icons.refresh: 'arrow.clockwise',
  Icons.refresh_rounded: 'arrow.clockwise',
  CupertinoIcons.arrow_clockwise: 'arrow.clockwise',
  Icons.search: 'magnifyingglass',
  Icons.search_rounded: 'magnifyingglass',
  CupertinoIcons.search: 'magnifyingglass',
  Icons.more_vert: 'ellipsis',
  Icons.more_horiz: 'ellipsis',
  Icons.more_horiz_rounded: 'ellipsis',
  CupertinoIcons.ellipsis: 'ellipsis',
  Icons.delete: 'trash',
  Icons.delete_outline: 'trash',
  Icons.delete_outline_rounded: 'trash',
  CupertinoIcons.trash: 'trash',
  Icons.share: 'square.and.arrow.up',
  Icons.share_rounded: 'square.and.arrow.up',
  CupertinoIcons.share: 'square.and.arrow.up',
  Icons.edit: 'pencil',
  Icons.edit_rounded: 'pencil',
  Icons.edit_outlined: 'pencil',
  CupertinoIcons.pencil: 'pencil',
  Icons.sort: 'arrow.up.arrow.down',
  Icons.sort_rounded: 'arrow.up.arrow.down',
  CupertinoIcons.arrow_up_arrow_down: 'arrow.up.arrow.down',
  Icons.swap_horiz: 'arrow.left.arrow.right',
  CupertinoIcons.arrow_right_arrow_left: 'arrow.left.arrow.right',
  Icons.download: 'arrow.down.circle',
  Icons.download_rounded: 'arrow.down.circle',
  Icons.downloading_rounded: 'arrow.down.circle',
  CupertinoIcons.arrow_down_circle: 'arrow.down.circle',
  CupertinoIcons.arrow_down_circle_fill: 'arrow.down.circle.fill',
  Icons.home_outlined: 'house',
  CupertinoIcons.house: 'house',
  CupertinoIcons.house_fill: 'house.fill',
  Icons.library_music_outlined: 'music.note.list',
  CupertinoIcons.music_albums: 'music.note.list',
  CupertinoIcons.music_albums_fill: 'music.note.list',
  Icons.settings_outlined: 'gearshape',
  CupertinoIcons.gear_alt: 'gearshape',
  CupertinoIcons.gear_alt_fill: 'gearshape.fill',
  Icons.chat_bubble_outline_rounded: 'bubble.left',
  CupertinoIcons.chat_bubble: 'bubble.left',
  Icons.info_outline: 'info.circle',
  CupertinoIcons.info: 'info.circle',
  Icons.add: 'plus',
  Icons.add_rounded: 'plus',
  CupertinoIcons.add: 'plus',
  Icons.select_all: 'checkmark.circle',
  CupertinoIcons.checkmark_circle: 'checkmark.circle',
  Icons.folder_open: 'folder',
  CupertinoIcons.folder: 'folder',
  Icons.sync: 'arrow.triangle.2.circlepath',
  Icons.sync_rounded: 'arrow.triangle.2.circlepath',
  Icons.filter_list: 'line.3.horizontal.decrease',
  Icons.filter_list_rounded: 'line.3.horizontal.decrease',
  Icons.calendar_today: 'calendar',
  Icons.calendar_month: 'calendar',
  Icons.play_arrow: 'play.fill',
  Icons.play_arrow_rounded: 'play.fill',
  Icons.shuffle: 'shuffle',
  Icons.shuffle_rounded: 'shuffle',
  Icons.done: 'checkmark',
  Icons.done_all: 'checkmark.circle',
  Icons.link: 'link',
  Icons.open_in_new: 'arrow.up.right.square',
  Icons.open_in_new_rounded: 'arrow.up.right.square',
  Icons.history: 'clock.arrow.circlepath',
  Icons.insights_outlined: 'chart.bar',
  Icons.bar_chart: 'chart.bar',
  Icons.tune: 'slider.horizontal.3',
  Icons.tune_rounded: 'slider.horizontal.3',
  Icons.image_search: 'photo.on.rectangle',
  Icons.photo_library_outlined: 'photo.on.rectangle',
  Icons.system_update: 'arrow.down.app',
  Icons.clear: 'xmark.circle',
  Icons.clear_all: 'xmark.circle',
};

/// A bar glyph for an icon with no SF Symbol: the icon font character drawn
/// black on clear at 3x, which UIKit tints as a template.
class ShellGlyphs {
  ShellGlyphs._();

  static final Map<IconData, Future<Uint8List?>> _cache = {};
  static final Map<IconData, Uint8List> _done = {};

  /// The bytes once rendered; null until [of] has completed for the icon.
  static Uint8List? cached(IconData icon) => _done[icon];

  static Future<Uint8List?> of(IconData icon) => _cache.putIfAbsent(icon, () async {
    final bytes = await _render(icon);
    if (bytes != null) _done[icon] = bytes;
    return bytes;
  });

  static Future<Uint8List?> _render(IconData icon) async {
    const size = 66.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size * .82,
          color: const Color(0xFF000000),
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );
    try {
      final image = await recorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      painter.dispose();
    }
  }
}

/// The text a menu entry or text button shows, found inside common wrappers.
String? shellLabelOf(Widget? widget) {
  switch (widget) {
    case null:
      return null;
    case Text(:final data, :final textSpan):
      return data ?? textSpan?.toPlainText();
    case ListTile(:final title):
      return shellLabelOf(title);
    case Row(:final children) || Column(:final children) || Wrap(:final children):
      for (final child in children) {
        final label = shellLabelOf(child);
        if (label != null && label.isNotEmpty) return label;
      }
      return null;
    case SingleChildRenderObjectWidget(:final child):
      return shellLabelOf(child);
    case ProxyWidget(:final child):
      return shellLabelOf(child);
    case Container(:final child):
      return shellLabelOf(child);
    case Tooltip(:final child):
      return shellLabelOf(child);
    default:
      return null;
  }
}
