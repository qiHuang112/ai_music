import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'app_popup_menu.dart';
import 'design/controls.dart';
import 'design/glass_surface.dart';
import 'duo_window.dart';
import 'mini_player.dart';
import 'mobile_chrome.dart';
import 'native_shell.dart';

/// Page chrome shares the system's vertical strip instead of allocating another
/// column beside it. Nested tab pages leave navigation to their parent shell.
///
/// The strip follows the system bar: navigation controls (back, close) at the
/// top, then the page's actions, and the app's main tabs as one capsule at the
/// bottom. Nothing is drawn behind them; each group is its own piece of glass.
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
    this.background,
  });

  final Key? railKey;

  /// Painted under both the content and the strip while the strip is shown,
  /// so a page's own backdrop reaches the display edge with no seam.
  final Widget? background;
  // Sliver pages keep their title in the content but move these controls.
  final AppBar? appBar, railAppBar;
  final Widget? body, bottomNavigationBar, floatingActionButton;
  final Color? backgroundColor;
  final bool extendBody, extendBodyBehindAppBar, preferSideNavigation;
  final bool? resizeToAvoidBottomInset;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final List<DuoRailItem> navigationItems, extraActions;

  /// True when the system, not this page, draws the back button and actions:
  /// the UIKit shell on iOS, or the vertical bar strip on a folding window.
  static bool usesSystemRail(BuildContext context) =>
      !_DuoChrome.of(context) &&
      (NativeShell.active ||
          DuoWindowScope.of(context).edge != DuoBarEdge.none);

  @override
  Widget build(BuildContext context) {
    if (NativeShell.active) return _buildShell(context);
    final chrome = MobileChrome.instance;
    if (!chrome.enabled || _DuoChrome.of(context)) return _buildPage(context);
    // Android and other phones: the floating tab bar and now-playing bar sit
    // over the navigator, and the page keeps clear of them through its
    // bottom inset, the way the iOS shell hands UIKit's safe area on.
    final route = ModalRoute.of(context);
    chrome.markImmersive(route, extendBodyBehindAppBar);
    return ListenableBuilder(
      listenable: chrome.layout,
      builder: (context, _) {
        if (!chrome.floating) return _buildPage(context);
        final data = MediaQuery.of(context);
        if (extendBodyBehindAppBar || data.viewInsets.bottom > 0) {
          return _buildPage(context, floating: true);
        }
        final root = route == null || route.isFirst;
        final bottom = ChromeMetrics.inset(
          data.viewPadding,
          bar:
              root &&
              chrome.nowPlaying.value != null &&
              (chrome.tabs.value?.visible ?? true),
        );
        return MediaQuery(
          data: data.copyWith(
            padding: data.padding.copyWith(bottom: bottom),
            viewPadding: data.viewPadding.copyWith(bottom: bottom),
          ),
          child: Builder(
            builder: (context) => _buildPage(context, floating: true),
          ),
        );
      },
    );
  }

  Widget _buildPage(BuildContext context, {bool floating = false}) {
    final data = MediaQuery.of(context);
    final geometry = DuoWindowScope.of(context);
    final nested = _DuoChrome.of(context);
    final systemRail = usesSystemRail(context);
    final rail = !nested && (systemRail || preferSideNavigation);
    final left = systemRail && geometry.edge == DuoBarEdge.left;
    final width = rail
        ? math.max(
            DuoRail.width,
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
          DuoRailItem.fromWidget(controls!.leading!, context, leading: true)
        else if ((controls?.automaticallyImplyLeading ?? true) &&
            Navigator.of(context).canPop())
          DuoRailItem(
            icon: CupertinoIcons.chevron_back,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            leading: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        for (final action in controls?.actions ?? const <Widget>[])
          DuoRailItem.fromWidget(action, context),
        ...extraActions,
      ],
      ...navigationItems,
    ];
    // Immersive pages (player, lyrics) drop their title with the bar; others
    // keep a quiet title line in the content, the way a large title sits.
    final titleBar = systemRail && appBar != null
        ? (extendBodyBehindAppBar
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  title: appBar!.title,
                  titleTextStyle: appBar!.titleTextStyle,
                  centerTitle: appBar!.centerTitle,
                  backgroundColor: appBar!.backgroundColor,
                  foregroundColor: appBar!.foregroundColor,
                  elevation: appBar!.elevation,
                  toolbarHeight: 48,
                  bottom: appBar!.bottom,
                ))
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
        if (rail && background != null) background!,
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
              consumed: nested || rail || floating,
              child: Scaffold(
                appBar: titleBar,
                body: body,
                backgroundColor: backgroundColor,
                extendBody: extendBody,
                extendBodyBehindAppBar: extendBodyBehindAppBar,
                resizeToAvoidBottomInset: resizeToAvoidBottomInset,
                // The floating bar carries the mini player; a page's own
                // copy would only cost the body its bottom inset.
                bottomNavigationBar: floating && bottomNavigationBar is MiniPlayer
                    ? null
                    : bottomNavigationBar,
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

extension on DuoScaffold {
  /// Under the UIKit shell the page draws no bar of its own: it describes its
  /// title, actions and tabs, and the shell shows them with system controls.
  /// A page with controls the shell cannot express keeps its Flutter bar.
  Widget _buildShell(BuildContext context) {
    final nested = _DuoChrome.of(context);
    final id = NativeShell.instance.idOf(ModalRoute.of(context));
    final root = id == 0;
    _ShellSpec? describe(BuildContext context) => id == null
        ? null
        : _ShellSpec.build(
            context,
            routeId: id,
            controls: appBar ?? railAppBar,
            extraActions: extraActions,
            tabs: navigationItems,
            immersive: extendBodyBehindAppBar,
            root: root,
          );
    final spec = describe(context);
    final ownBar = spec == null || spec.chromeless;
    // A tab's root keeps the app's own masthead; the system bar above it
    // holds only actions. Pushed pages take the system title and sit below.
    final masthead = !ownBar && root && appBar?.title != null
        ? AppBar(
            automaticallyImplyLeading: false,
            title: appBar!.title,
            titleTextStyle: appBar!.titleTextStyle,
            centerTitle: appBar!.centerTitle,
            backgroundColor: appBar!.backgroundColor,
            foregroundColor: appBar!.foregroundColor,
            elevation: appBar!.elevation,
            toolbarHeight: 56,
            bottom: appBar!.bottom,
          )
        : null;
    final shell = NativeShell.instance;
    Widget child = _DuoChrome(
      consumed: true,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          shell.accessoryActive,
          shell.nowPlaying,
          shell.chromeInsets,
        ]),
        builder: (context, _) {
          // A Flutter strip that would be empty (system accessory showing, or
          // nothing playing) must not be a bottom bar: an empty bar makes the
          // Scaffold drop the body's bottom inset and lists end under the
          // tab bar.
          final strip = shell.accessoryActive.value || !shell.nowPlaying.value
              ? null
              : bottomNavigationBar;
          final scaffold = Scaffold(
            appBar: ownBar ? appBar : masthead,
            // Pushed pages sit below the system bar. A tab shell passes the
            // padding on, so the tab page inside can lay its masthead under
            // the transparent bar itself.
            body:
                !ownBar &&
                    !root &&
                    masthead == null &&
                    !extendBodyBehindAppBar &&
                    body != null
                ? SafeArea(bottom: false, child: body!)
                : body,
            backgroundColor: backgroundColor,
            extendBody: extendBody,
            extendBodyBehindAppBar: extendBodyBehindAppBar,
            resizeToAvoidBottomInset: resizeToAvoidBottomInset,
            bottomNavigationBar: strip,
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation: floatingActionButtonLocation,
          );
          if (masthead == null) return scaffold;
          // The root's masthead sits where the transparent system bar is, so
          // the inset stays the same on both sides of every push.
          final data = MediaQuery.of(context);
          final bar = shell.chromeInsets.value.top;
          return MediaQuery(
            data: data.copyWith(
              padding: data.padding.copyWith(
                top: math.max(0, data.padding.top - bar),
              ),
              viewPadding: data.viewPadding.copyWith(
                top: math.max(0, data.viewPadding.top - bar),
              ),
            ),
            child: scaffold,
          );
        },
      ),
    );
    if (background != null) {
      child = Stack(fit: StackFit.expand, children: [background!, child]);
    }
    if (spec == null) return child;
    return _ShellPageBinding(
      id: id!,
      nested: nested,
      describe: (context) => describe(context)!,
      child: child,
    );
  }
}

/// Keeps the shell's description of one page current while it is visible.
class _ShellPageBinding extends StatefulWidget {
  const _ShellPageBinding({
    required this.id,
    required this.nested,
    required this.describe,
    required this.child,
  });
  final int id;
  final bool nested;

  /// Built on every send, so a glyph rendered after the first pass is in.
  final _ShellSpec Function(BuildContext context) describe;
  final Widget child;

  @override
  State<_ShellPageBinding> createState() => _ShellPageBindingState();
}

class _ShellPageBindingState extends State<_ShellPageBinding> {
  bool _registered = false;

  @override
  Widget build(BuildContext context) {
    // Home tabs stay built when hidden; only the visible one owns the bar.
    final visible = !widget.nested || TickerMode.valuesOf(context).enabled;
    final shell = NativeShell.instance;
    if (visible) {
      final spec = widget.describe(context);
      spec.callbacks.forEach(shell.register);
      shell.updatePage(widget.id, spec.map, nested: widget.nested);
      _registered = true;
      if (spec.pending.isNotEmpty) {
        // Icons without an SF Symbol are rasterised once; redraw with them.
        Future.wait(spec.pending).then((_) {
          if (mounted) setState(() {});
        });
      }
    } else if (_registered) {
      shell.clearPage(widget.id, nested: widget.nested);
      _registered = false;
    }
    return widget.child;
  }

  @override
  void dispose() {
    if (_registered && widget.nested) {
      NativeShell.instance.clearPage(widget.id, nested: true);
    }
    super.dispose();
  }
}

/// A page as the shell understands it.
class _ShellSpec {
  _ShellSpec._(this.map, this.callbacks, this.pending, this.chromeless);

  final Map<String, Object?> map;
  final Map<String, VoidCallback> callbacks;
  final List<Future<void>> pending;

  /// Some control could not be expressed natively; Flutter keeps the bar.
  final bool chromeless;

  static _ShellSpec build(
    BuildContext context, {
    required int routeId,
    required AppBar? controls,
    required List<DuoRailItem> extraActions,
    required List<DuoRailItem> tabs,
    required bool immersive,
    bool root = false,
  }) {
    final callbacks = <String, VoidCallback>{};
    final pending = <Future<void>>[];
    var chromeless = false;

    Map<String, Object?> icon(IconData data) {
      final symbol = sfSymbol(data);
      if (symbol != null) return {'symbol': symbol};
      final glyph = ShellGlyphs.cached(data);
      if (glyph == null) pending.add(ShellGlyphs.of(data));
      return {'glyph': glyph};
    }

    Map<String, Object?>? convert(Widget widget, String id) {
      switch (widget) {
        case IconButton(icon: Icon(icon: final data?)):
          if (widget.onPressed != null) callbacks[id] = widget.onPressed!;
          return {
            'id': id,
            'title': widget.tooltip ?? '',
            'enabled': widget.onPressed != null,
            ...icon(data),
          };
        case BackButton() || CloseButton():
          callbacks[id] =
              (widget as dynamic).onPressed as VoidCallback? ??
              () => Navigator.of(context).maybePop();
          return {
            'id': id,
            'title': widget is CloseButton
                ? MaterialLocalizations.of(context).closeButtonTooltip
                : MaterialLocalizations.of(context).backButtonTooltip,
            'symbol': widget is CloseButton ? 'xmark' : 'chevron.backward',
          };
        case TextButton():
          if (widget.onPressed != null) callbacks[id] = widget.onPressed!;
          return {
            'id': id,
            'title': shellLabelOf(widget.child) ?? '',
            'enabled': widget.onPressed != null,
          };
        case PopupMenuButton():
          final entries = widget.itemBuilder(context);
          final menu = <Map<String, Object?>>[];
          for (final (j, entry) in entries.indexed) {
            if (entry is! PopupMenuItem) continue;
            final itemId = '$id-m$j';
            final value = entry.value;
            callbacks[itemId] = () {
              entry.onTap?.call();
              (widget.onSelected as dynamic)?.call(value);
            };
            menu.add({
              'id': itemId,
              'title': shellLabelOf(entry.child) ?? '',
              'enabled': entry.enabled,
              'checked': entry is CheckedPopupMenuItem && entry.checked,
            });
          }
          final menuIcon = widget.icon;
          return {
            'id': id,
            'title': widget.tooltip ?? '',
            'enabled': widget.enabled,
            'menu': menu,
            ...switch (menuIcon) {
              Icon(icon: final data?) => icon(data),
              _ => const {'symbol': 'ellipsis.circle'},
            },
          };
        default:
          return null;
      }
    }

    Map<String, Object?> railItem(DuoRailItem item, String id) {
      if (item.onPressed != null) callbacks[id] = item.onPressed!;
      return {
        'id': id,
        'title': item.label,
        'enabled': item.onPressed != null,
        ...icon(item.icon),
      };
    }

    final actions = <Map<String, Object?>>[];
    for (final (i, action) in (controls?.actions ?? const <Widget>[]).indexed) {
      final converted = convert(action, '$routeId-a$i');
      if (converted == null) {
        chromeless = true;
      } else {
        actions.add(converted);
      }
    }
    for (final (i, item) in extraActions.indexed) {
      actions.add(railItem(item, '$routeId-x$i'));
    }
    Map<String, Object?>? leading;
    if (controls?.leading case final widget?) {
      leading = convert(widget, '$routeId-l');
      if (leading == null) chromeless = true;
    }
    final map = <String, Object?>{
      'title': immersive || root ? null : shellLabelOf(controls?.title),
      'immersive': immersive,
      'chromeless': chromeless,
      'hidesBack':
          leading == null && !(controls?.automaticallyImplyLeading ?? true),
      'leading': leading,
      'actions': actions,
      // The shell's shared now-playing entries that lead to this very page.
      'hideShared': switch (ModalRoute.of(context)?.settings.name) {
        'player' => const ['shell.player.lyrics', 'shell.player.queue'],
        'lyrics' => const ['shell.player.lyrics'],
        'comments' => const ['shell.player.comments'],
        _ => const <String>[],
      },
      if (tabs.isNotEmpty) ...{
        'tabs': [
          for (final tab in tabs)
            {
              'title': tab.label,
              'badge': tab.badge,
              ...icon(tab.icon),
              if (tab.selectedIcon != null)
                'selectedSymbol': sfSymbol(tab.selectedIcon!),
            },
        ],
        'selectedTab': math.max(0, tabs.indexWhere((tab) => tab.selected)),
      },
    };
    return _ShellSpec._(map, callbacks, pending, chromeless);
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

/// The symbol the vertical bar shows for a Material icon used elsewhere in
/// the app. The bar is a system place, so it speaks the system's symbols.
IconData duoRailIcon(IconData icon) => _railIcons[icon] ?? icon;

final _railIcons = <IconData, IconData>{
  Icons.arrow_back: CupertinoIcons.chevron_back,
  Icons.arrow_back_rounded: CupertinoIcons.chevron_back,
  Icons.arrow_back_ios: CupertinoIcons.chevron_back,
  Icons.arrow_back_ios_new: CupertinoIcons.chevron_back,
  Icons.close: CupertinoIcons.xmark,
  Icons.close_rounded: CupertinoIcons.xmark,
  Icons.check: CupertinoIcons.checkmark,
  Icons.check_rounded: CupertinoIcons.checkmark,
  Icons.favorite: CupertinoIcons.heart_fill,
  Icons.favorite_border: CupertinoIcons.heart,
  Icons.playlist_add: CupertinoIcons.text_badge_plus,
  Icons.playlist_add_rounded: CupertinoIcons.text_badge_plus,
  Icons.queue_music: CupertinoIcons.music_note_list,
  Icons.queue_music_rounded: CupertinoIcons.music_note_list,
  Icons.lyrics_outlined: CupertinoIcons.text_quote,
  Icons.refresh: CupertinoIcons.arrow_clockwise,
  Icons.refresh_rounded: CupertinoIcons.arrow_clockwise,
  Icons.search: CupertinoIcons.search,
  Icons.search_rounded: CupertinoIcons.search,
  Icons.more_vert: CupertinoIcons.ellipsis,
  Icons.more_horiz: CupertinoIcons.ellipsis,
  Icons.more_horiz_rounded: CupertinoIcons.ellipsis,
  Icons.delete: CupertinoIcons.trash,
  Icons.delete_outline: CupertinoIcons.trash,
  Icons.delete_outline_rounded: CupertinoIcons.trash,
  Icons.share: CupertinoIcons.share,
  Icons.share_rounded: CupertinoIcons.share,
  Icons.edit: CupertinoIcons.pencil,
  Icons.edit_rounded: CupertinoIcons.pencil,
  Icons.sort: CupertinoIcons.arrow_up_arrow_down,
  Icons.sort_rounded: CupertinoIcons.arrow_up_arrow_down,
  Icons.swap_horiz: CupertinoIcons.arrow_right_arrow_left,
  Icons.download: CupertinoIcons.arrow_down_circle,
  Icons.download_rounded: CupertinoIcons.arrow_down_circle,
  Icons.downloading_rounded: CupertinoIcons.arrow_down_circle,
  Icons.home_outlined: CupertinoIcons.house,
  Icons.library_music_outlined: CupertinoIcons.music_albums,
  Icons.settings_outlined: CupertinoIcons.gear_alt,
  Icons.chat_bubble_outline_rounded: CupertinoIcons.chat_bubble,
  Icons.info_outline: CupertinoIcons.info,
  Icons.add: CupertinoIcons.add,
  Icons.add_rounded: CupertinoIcons.add,
  Icons.select_all: CupertinoIcons.checkmark_circle,
  Icons.folder_open: CupertinoIcons.folder,
};

class DuoRailItem {
  const DuoRailItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.onPressed,
    this.selected = false,
    this.navigation = false,
    this.leading = false,
    this.marker,
    this.custom,
    this.badge,
  });
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final VoidCallback? onPressed;

  /// A system tab badge; empty text shows a plain dot.
  final String? badge;

  /// A main tab of the app (bottom capsule), or a back / close control that
  /// stays at the very top and is the last thing to leave the bar.
  final bool selected, navigation, leading;
  final Widget? marker, custom;

  factory DuoRailItem.fromWidget(
    Widget widget,
    BuildContext context, {
    bool leading = false,
  }) {
    if (widget is IconButton) {
      final icon = widget.icon;
      return DuoRailItem(
        icon: icon is Icon
            ? duoRailIcon(icon.icon ?? CupertinoIcons.circle)
            : CupertinoIcons.ellipsis,
        label: widget.tooltip ?? '',
        leading: leading,
        onPressed: widget.onPressed,
        custom: icon is Icon ? null : widget,
      );
    }
    if (widget is BackButton) {
      return DuoRailItem(
        icon: CupertinoIcons.chevron_back,
        label: MaterialLocalizations.of(context).backButtonTooltip,
        leading: true,
        onPressed: widget.onPressed ?? () => Navigator.of(context).maybePop(),
      );
    }
    if (widget is CloseButton) {
      return DuoRailItem(
        icon: CupertinoIcons.xmark,
        label: MaterialLocalizations.of(context).closeButtonTooltip,
        leading: true,
        onPressed: widget.onPressed ?? () => Navigator.of(context).maybePop(),
      );
    }
    if (widget is TextButton) {
      return DuoRailItem(
        icon: CupertinoIcons.checkmark,
        label: widget.child is Text ? (widget.child as Text).data ?? '' : '',
        leading: leading,
        onPressed: widget.onPressed,
      );
    }
    return DuoRailItem(
      icon: CupertinoIcons.ellipsis,
      label: MaterialLocalizations.of(context).moreButtonTooltip,
      leading: leading,
      custom: widget,
    );
  }
}

/// Where each group of the bar goes, given the free stretches of the strip.
class DuoRailLayout {
  const DuoRailLayout({
    required this.leading,
    required this.actions,
    required this.overflow,
    required this.tabs,
    required this.top,
    required this.tabsTop,
    this.mergedOverflow = false,
  });

  /// The items shown in the top groups, and those pushed into the menu.
  final List<DuoRailItem> leading, actions, overflow, tabs;

  /// Where the first top group starts and where the tab capsule starts.
  final double top, tabsTop;

  /// Too short for a second capsule: the menu sits under the back button.
  final bool mergedOverflow;

  bool get isEmpty =>
      leading.isEmpty && actions.isEmpty && overflow.isEmpty && tabs.isEmpty;
}

/// The same coordinate system as UIKit, including split-view leading rails.
/// Groups skip *rectangles*, not a whole edge; the camera's column stays
/// usable below the camera.
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

  /// The system strip is this wide; the groups are capsules inside it.
  static const width = 76.0;
  static const button = 44.0, capsulePadding = 4.0, itemGap = 2.0;
  static const groupGap = 12.0;
  static const capsuleWidth = button + capsulePadding * 2;

  static double capsuleHeight(int count) => count == 0
      ? 0
      : capsulePadding * 2 + button * count + itemGap * (count - 1);

  /// The stretches of the strip free of camera, status bar and fold, from top
  /// to bottom, each tall enough for at least one button.
  static List<Rect> freeSegments(
    Rect bounds,
    List<Rect> obstructions, {
    double top = 0,
    double bottom = 0,
  }) {
    final result = <Rect>[];
    var y = bounds.top + math.max(8, top);
    final limit = bounds.bottom - math.max(8, bottom);
    final blocks =
        obstructions
            .where((r) => r.left < bounds.right && r.right > bounds.left)
            .map((r) => r.inflate(6))
            .toList()
          ..sort((a, b) => a.top.compareTo(b.top));
    for (final block in blocks) {
      if (block.bottom <= y) continue;
      if (block.top > y) {
        final end = math.min(block.top, limit);
        if (end - y >= capsuleHeight(1)) {
          result.add(Rect.fromLTRB(bounds.left, y, bounds.right, end));
        }
      }
      y = math.max(y, block.bottom);
      if (y >= limit) break;
    }
    if (limit - y >= capsuleHeight(1)) {
      result.add(Rect.fromLTRB(bounds.left, y, bounds.right, limit));
    }
    return result;
  }

  /// Back stays, tabs stay next, actions leave from the bottom up into the
  /// menu. That is the system's navigation-first compression.
  static DuoRailLayout layout(
    List<DuoRailItem> items,
    Rect bounds,
    List<Rect> obstructions, {
    double top = 0,
    double bottom = 0,
  }) {
    const none = DuoRailLayout(
      leading: [],
      actions: [],
      overflow: [],
      tabs: [],
      top: 0,
      tabsTop: 0,
    );
    final segments = freeSegments(bounds, obstructions, top: top, bottom: bottom);
    if (segments.isEmpty || items.isEmpty) return none;
    final first = segments.first, last = segments.last;
    final leading = items.where((i) => i.leading && !i.navigation).toList();
    final actions = items.where((i) => !i.leading && !i.navigation).toList();
    final tabs = items.where((i) => i.navigation).toList();

    DuoRailLayout? attempt(bool showTabs) {
      final tabsHeight = showTabs ? capsuleHeight(tabs.length) : 0.0;
      if (showTabs && tabsHeight > last.height) return null;
      var available = first.height;
      if (showTabs && identical(first, last)) {
        available -= tabsHeight + groupGap;
      }
      final hiddenTabs = !showTabs && tabs.isNotEmpty;
      var remaining = available - capsuleHeight(leading.length);
      if (remaining < 0) return null;
      final needsGroupGap =
          leading.isNotEmpty && (actions.isNotEmpty || hiddenTabs);
      if (needsGroupGap) remaining -= groupGap;
      // 8 + 44n + 2(n - 1) <= remaining
      final capacity = remaining < capsuleHeight(1)
          ? 0
          : ((remaining - capsulePadding * 2 + itemGap) / (button + itemGap))
                .floor();
      final overflow = capacity < actions.length || hiddenTabs;
      var merged = false;
      if (overflow && capacity == 0) {
        // No room for a second capsule under the camera: the menu joins the
        // back button rather than everything leaving the bar.
        if (leading.isEmpty || capsuleHeight(leading.length + 1) > available) {
          return null;
        }
        merged = true;
      }
      final shown = overflow ? math.max(0, capacity - 1) : actions.length;
      return DuoRailLayout(
        leading: leading,
        actions: actions.take(shown).toList(),
        overflow: [
          ...actions.skip(shown),
          if (hiddenTabs) ...tabs,
        ],
        tabs: showTabs ? tabs : const [],
        top: first.top - bounds.top,
        tabsTop: last.bottom - tabsHeight - bounds.top,
        mergedOverflow: merged,
      );
    }

    return attempt(tabs.isNotEmpty) ??
        attempt(false) ??
        // Not even back and a menu fit: offer everything through one menu.
        (first.height >= capsuleHeight(1)
            ? DuoRailLayout(
                leading: const [],
                actions: const [],
                overflow: items,
                tabs: const [],
                top: first.top - bounds.top,
                tabsTop: 0,
              )
            : none);
  }

  @override
  Widget build(BuildContext context) {
    final plan = layout(items, bounds, obstructions, top: top, bottom: bottom);
    if (plan.isEmpty) return const SizedBox.shrink();
    final strings = MaterialLocalizations.of(context);
    final left = (bounds.width - capsuleWidth) / 2;
    final groups = <Widget>[];
    final menu = plan.overflow.isEmpty
        ? null
        : _RailOverflow(items: plan.overflow, label: strings.moreButtonTooltip);
    var y = plan.top;
    if (plan.leading.isNotEmpty) {
      groups.add(
        Positioned(
          left: left,
          top: y,
          child: _RailCapsule(
            children: [
              for (final item in plan.leading) _RailButton(item),
              if (plan.mergedOverflow && menu != null) menu,
            ],
          ),
        ),
      );
      y += capsuleHeight(plan.leading.length) + groupGap;
    }
    if (plan.actions.isNotEmpty || (menu != null && !plan.mergedOverflow)) {
      groups.add(
        Positioned(
          left: left,
          top: y,
          child: _RailCapsule(
            children: [
              for (final item in plan.actions) _RailButton(item),
              if (menu != null && !plan.mergedOverflow) menu,
            ],
          ),
        ),
      );
    }
    if (plan.tabs.isNotEmpty) {
      groups.add(
        Positioned(
          left: left,
          top: plan.tabsTop,
          child: _RailCapsule(
            key: const ValueKey('duo-rail-tabs'),
            blur: true,
            children: [for (final item in plan.tabs) _RailButton(item)],
          ),
        ),
      );
    }
    return Material(
      key: const ValueKey('duo-system-rail'),
      type: MaterialType.transparency,
      child: Stack(clipBehavior: Clip.none, children: groups),
    );
  }
}

/// One piece of glass holding a group: a circle for one item, a pill for more.
class _RailCapsule extends StatelessWidget {
  const _RailCapsule({super.key, required this.children, this.blur = false});
  final List<Widget> children;
  final bool blur;

  @override
  Widget build(BuildContext context) => GlassSurface(
    level: GlassLevel.thin,
    blur: blur,
    shadow: false,
    borderRadius: BorderRadius.circular(DuoRail.capsuleWidth / 2),
    padding: const EdgeInsets.all(DuoRail.capsulePadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: DuoRail.itemGap),
          child,
        ],
      ],
    ),
  );
}

class _RailButton extends StatelessWidget {
  const _RailButton(this.item);
  final DuoRailItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = item.onPressed != null || item.custom != null;
    final selected = item.selected;
    Widget icon = Icon(
      selected ? (item.selectedIcon ?? item.icon) : item.icon,
      size: 22,
      color: selected
          ? colors.onPrimaryContainer
          : colors.onSurface.withValues(alpha: enabled ? 1 : .38),
    );
    if (item.marker != null) {
      icon = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          icon,
          Positioned(top: -5, right: -7, child: item.marker!),
        ],
      );
    }
    Widget body = SizedBox.square(
      dimension: DuoRail.button,
      child: Center(
        child: item.custom != null && item.onPressed == null
            ? item.custom
            : icon,
      ),
    );
    if (selected) {
      body = GlassSurface(
        level: GlassLevel.thick,
        blur: false,
        shadow: false,
        tint: colors.primaryContainer,
        borderRadius: BorderRadius.circular(DuoRail.button / 2),
        child: body,
      );
    }
    if (item.custom != null && item.onPressed == null) return body;
    return Semantics(
      label: item.label,
      button: true,
      enabled: item.onPressed != null,
      selected: selected,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: Pressable(onTap: item.onPressed, child: body),
      ),
    );
  }
}

class _RailOverflow extends StatelessWidget {
  const _RailOverflow({required this.items, required this.label});
  final List<DuoRailItem> items;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      child: MusicPopupMenuButton<int>(
        key: const ValueKey('duo-rail-overflow'),
        tooltip: label,
        onSelected: (index) => items[index].onPressed?.call(),
        itemBuilder: (context) => [
          for (final (i, item) in items.indexed)
            PopupMenuItem(
              value: i,
              enabled: item.onPressed != null,
              child: item.onPressed == null && item.custom != null
                  ? item.custom!
                  : Row(
                      children: [
                        Icon(
                          item.selected
                              ? (item.selectedIcon ?? item.icon)
                              : item.icon,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: Text(item.label)),
                        if (item.selected) ...[
                          const SizedBox(width: 12),
                          Icon(
                            CupertinoIcons.checkmark,
                            size: 16,
                            color: colors.primary,
                          ),
                        ],
                      ],
                    ),
            ),
        ],
        child: SizedBox.square(
          dimension: DuoRail.button,
          child: Icon(
            CupertinoIcons.ellipsis,
            size: 22,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
