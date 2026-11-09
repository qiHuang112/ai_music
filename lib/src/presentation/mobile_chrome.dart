import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoModalPopupRoute;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../application/music_controller.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'design/controls.dart';
import 'design/glass_surface.dart';
import 'desktop_scope.dart';
import 'music_thumbnail.dart';
import 'native_shell.dart';
import 'design/app_icons.dart';

/// What the floating tab bar shows. Published by the home page.
@immutable
class MobileTabs {
  const MobileTabs({
    required this.labels,
    required this.index,
    required this.floating,
    this.visible = true,
    this.downloading = false,
    this.updateBadge = false,
  });

  final List<String> labels;
  final int index;

  /// False while a wide window navigates from a side rail instead.
  final bool floating;

  /// False while the home search field is being typed into.
  final bool visible;
  final bool downloading, updateBadge;

  @override
  bool operator ==(Object other) =>
      other is MobileTabs &&
      listEquals(other.labels, labels) &&
      other.index == index &&
      other.floating == floating &&
      other.visible == visible &&
      other.downloading == downloading &&
      other.updateBadge == updateBadge;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(labels),
    index,
    floating,
    visible,
    downloading,
    updateBadge,
  );
}

/// The page on top of the root navigator, as far as the bars care.
@immutable
class ChromeRoute {
  const ChromeRoute({
    this.root = true,
    this.immersive = false,
    this.modal = false,
  });

  /// A tab's own page, not something pushed over it.
  final bool root;

  /// Player and lyrics: the bars step aside.
  final bool immersive;

  /// A sheet or dialog is up.
  final bool modal;

  @override
  bool operator ==(Object other) =>
      other is ChromeRoute &&
      other.root == root &&
      other.immersive == immersive &&
      other.modal == modal;

  @override
  int get hashCode => Object.hash(root, immersive, modal);
}

/// Geometry shared by the bars and the pages laid out around them. The
/// numbers follow the iOS shell: the system tab bar capsule, and the 56 pt
/// now-playing bar 12 pt above it, edge to edge with the capsule.
abstract final class ChromeMetrics {
  static const tabHeight = 62.0;
  static const barHeight = 56.0;
  static const gap = 12.0;
  static const side = 21.0;
  static const maxWidth = 520.0;

  /// The capsule floats just above the gesture area, never on it.
  static double bottomMargin(EdgeInsets viewPadding) =>
      math.max(12.0, viewPadding.bottom);

  static Rect tabRect(Size size, EdgeInsets viewPadding) {
    final room = size.width - viewPadding.left - viewPadding.right;
    final width = math.max(0.0, math.min(room - side * 2, maxWidth));
    final left = viewPadding.left + (room - width) / 2;
    final bottom = size.height - bottomMargin(viewPadding);
    return Rect.fromLTRB(left, bottom - tabHeight, left + width, bottom);
  }

  static Rect barRect(Size size, EdgeInsets viewPadding) {
    final tabs = tabRect(size, viewPadding);
    return Rect.fromLTWH(
      tabs.left,
      tabs.top - gap - barHeight,
      tabs.width,
      barHeight,
    );
  }

  /// The bottom inset a page keeps clear: up to the tab bar, and past the
  /// now-playing bar as well where that shows.
  static double inset(EdgeInsets viewPadding, {required bool bar}) =>
      bottomMargin(viewPadding) + tabHeight + (bar ? gap + barHeight + gap : 0);
}

/// The Flutter counterpart of the iOS shell's chrome, for Android and other
/// phones without UIKit: a floating glass tab bar that stays over pushed
/// pages, and the now-playing bar above it on the tabs' own pages. Both sit
/// over the root navigator, so they hold still while pages slide beneath.
class MobileChrome extends NavigatorObserver {
  MobileChrome._();

  static final MobileChrome instance = MobileChrome._();

  /// Phones where Flutter draws this chrome itself.
  static bool get supported =>
      !kIsWeb &&
      !NativeShell.active &&
      !isMacMusicDesktop &&
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => false,
        _ => true,
      };

  /// Set once at start-up. Off in tests that pump pages on their own, where
  /// the home page keeps its inline bars.
  bool enabled = false;

  final ValueNotifier<MobileTabs?> tabs = ValueNotifier(null);
  final ValueNotifier<ChromeRoute> top = ValueNotifier(const ChromeRoute());
  final ValueNotifier<MediaItem?> nowPlaying = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<bool> favorite = ValueNotifier(false);

  late final Listenable layout = Listenable.merge([tabs, top, nowPlaying]);

  /// Whether pages currently lay out around the floating bars.
  bool get floating => enabled && (tabs.value?.floating ?? false);

  ValueChanged<int>? onTabSelected;
  VoidCallback? onOpenPlayer;
  VoidCallback? onOpenQueue;

  MusicController? _controller;
  MusicController? get controller => _controller;
  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<PlaybackState>? _stateSub;

  void attachPlayback(MusicController controller) {
    if (!enabled || identical(_controller, controller)) return;
    _controller?.removeListener(_onControllerChanged);
    unawaited(_itemSub?.cancel());
    unawaited(_stateSub?.cancel());
    _controller = controller;
    nowPlaying.value = controller.audioHandler.mediaItem.value;
    playing.value = controller.audioHandler.playbackState.value.playing;
    _itemSub = controller.mediaItemStream.listen(
      (item) => nowPlaying.value = item,
    );
    _stateSub = controller.playbackStateStream.listen(
      (state) => playing.value = state.playing,
    );
    controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  void _onControllerChanged() {
    final controller = _controller;
    final track = controller?.currentTrack;
    final liked = track != null && controller!.isFavorite(track);
    if (liked != favorite.value) _defer(() => favorite.value = liked);
  }

  void toggleFavorite() {
    final track = _controller?.currentTrack;
    if (track != null) unawaited(_controller!.toggleFavorite(track));
  }

  MobileTabs? _wantedTabs;

  /// Called from the home page's build; applied after the frame.
  void publishTabs(MobileTabs value) {
    if (_wantedTabs == value) return;
    _wantedTabs = value;
    _defer(() => tabs.value = _wantedTabs);
  }

  /// A tab tapped over a pushed page goes back to that tab's own page first,
  /// as the system tab bar does on iOS.
  void selectTab(int index) {
    final nav = navigator;
    if (nav != null && nav.canPop()) nav.popUntil((route) => route.isFirst);
    onTabSelected?.call(index);
  }

  // ---- Routes -------------------------------------------------------------

  final List<Route<dynamic>> _stack = [];
  final Expando<bool> _immersive = Expando<bool>('chrome-immersive');
  ChromeRoute? _wantedTop;

  /// Pages say whether they are immersive as they build.
  void markImmersive(Route<dynamic>? route, bool value) {
    if (route == null || (_immersive[route] ?? false) == value) return;
    _immersive[route] = value;
    _refresh();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _refresh();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _refresh();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _refresh();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute != null && index >= 0) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    } else if (index >= 0) {
      _stack.removeAt(index);
    }
    _refresh();
  }

  static bool _isModal(Route<dynamic> route) =>
      route is ModalBottomSheetRoute ||
      route is RawDialogRoute ||
      route is CupertinoModalPopupRoute;

  void _refresh() {
    var modal = false;
    Route<dynamic>? page;
    for (final route in _stack.reversed) {
      if (route is PageRoute) {
        page = route;
        break;
      }
      if (_isModal(route)) modal = true;
    }
    final next = ChromeRoute(
      root: page == null || identical(page, _stack.firstOrNull),
      immersive: page != null && (_immersive[page] ?? false),
      modal: modal,
    );
    if (next == _wantedTop) return;
    _wantedTop = next;
    _defer(() => top.value = _wantedTop!);
  }

  /// Navigator callbacks and page builds happen mid-frame; listeners are
  /// told once it is done.
  static void _defer(VoidCallback apply) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }
}

/// Draws the floating bars over the root navigator. Lives in the app builder.
class MobileChromeOverlay extends StatelessWidget {
  const MobileChromeOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = MobileChrome.instance;
    if (!chrome.enabled) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: chrome.layout,
      builder: (context, _) {
        final tabs = chrome.tabs.value;
        if (tabs == null || !tabs.floating) return const SizedBox.shrink();
        final media = MediaQuery.of(context);
        final route = chrome.top.value;
        final keyboard = media.viewInsets.bottom > 0;
        final showTabs =
            tabs.visible && !keyboard && !route.immersive && !route.modal;
        final showBar =
            showTabs && route.root && chrome.nowPlaying.value != null;
        return Stack(
          children: [
            _ChromeSlot(
              rect: ChromeMetrics.barRect(media.size, media.viewPadding),
              shown: showBar,
              child: _NowPlayingBar(chrome: chrome),
            ),
            _ChromeSlot(
              rect: ChromeMetrics.tabRect(media.size, media.viewPadding),
              shown: showTabs,
              child: _FloatingTabBar(tabs: tabs, onSelected: chrome.selectTab),
            ),
          ],
        );
      },
    );
  }
}

/// Slides a bar a little down and fades it when it steps aside.
class _ChromeSlot extends StatelessWidget {
  const _ChromeSlot({
    required this.rect,
    required this.shown,
    required this.child,
  });

  final Rect rect;
  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeSemantics(
          excluding: !shown,
          child: AnimatedSlide(
            offset: shown ? Offset.zero : const Offset(0, .6),
            duration: MusicMotion.base,
            curve: shown ? MusicMotion.emphasized : Curves.easeInCubic,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: MusicMotion.base,
              curve: Curves.easeOut,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass capsule of four tabs, icon over label. The current one sits on a
/// darker pill lit in the accent. Like the iOS tab bar, the pill can be
/// picked up and slid: it lifts under the finger, follows it, lights each tab
/// it crosses, and springs onto the nearest tab when let go. A tap glides it
/// there on the same spring.
class _FloatingTabBar extends StatefulWidget {
  const _FloatingTabBar({required this.tabs, required this.onSelected});

  final MobileTabs tabs;
  final ValueChanged<int> onSelected;

  static const _icons = [
    CupertinoIcons.house,
    CupertinoIcons.music_note_list,
    CupertinoIcons.arrow_down_circle,
    CupertinoIcons.gear_alt,
  ];
  static const _selectedIcons = [
    CupertinoIcons.house_fill,
    CupertinoIcons.music_note_list,
    CupertinoIcons.arrow_down_circle_fill,
    CupertinoIcons.gear_alt_fill,
  ];

  @override
  State<_FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<_FloatingTabBar>
    with TickerProviderStateMixin {
  static const _inset = 4.0;

  /// Where the pill is, in tabs: 0 is the first, 1.5 halfway to the third.
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.tabs.index.toDouble(),
  );

  /// 0 resting, 1 held under the finger.
  late final AnimationController _lift = AnimationController.unbounded(
    vsync: this,
  );

  bool _dragging = false;
  int _hovered = -1;

  int get _count => widget.tabs.labels.length;

  @override
  void didUpdateWidget(_FloatingTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.tabs.index != widget.tabs.index) {
      _glideTo(widget.tabs.index, 0);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _lift.dispose();
    _stretch.dispose();
    super.dispose();
  }

  /// How hard the finger pulls the capsule, -1 (left) to 1 (right): its
  /// speed while sliding, or how far past the last tab it is dragged.
  late final AnimationController _stretch = AnimationController.unbounded(
    vsync: this,
  );
  Duration? _lastMove;

  void _glideTo(int index, double velocity) => _position.animateWith(
    SpringSimulation(_pillSpring, _position.value, index.toDouble(), velocity),
  );

  // A little give, so the pill lands rather than stops.
  static const _pillSpring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 26,
  );

  // The capsule wobbles back like jelly.
  static const _jelly = SpringDescription(mass: 1, stiffness: 300, damping: 14);

  void _setLift(double target) => _lift.animateWith(
    SpringSimulation(MusicMotion.snappy, _lift.value, target, 0),
  );

  double _rawTabAt(double dx, double width) => (dx - _inset) / width - .5;

  /// Past either end the pill gives only a little, like a rubber band.
  double _tabAt(double dx, double width) {
    final raw = _rawTabAt(dx, width);
    final last = (_count - 1).toDouble();
    if (raw < 0) return -_rubber(-raw);
    if (raw > last) return last + _rubber(raw - last);
    return raw;
  }

  static double _rubber(double over) => .35 * (1 - 1 / (1 + over));

  void _follow(DragUpdateDetails details, double width) {
    _position.value = _tabAt(details.localPosition.dx, width);
    // Pulled past the end: the capsule stretches that way.
    final raw = _rawTabAt(details.localPosition.dx, width);
    final past = raw < 0 ? raw : (raw > _count - 1 ? raw - (_count - 1) : 0.0);
    // Otherwise it leans with the finger's speed, smoothed.
    final time = details.sourceTimeStamp;
    var speed = 0.0;
    if (time != null && _lastMove != null && time > _lastMove!) {
      final seconds = (time - _lastMove!).inMicroseconds / 1e6;
      speed = details.delta.dx / seconds / 2400;
    }
    _lastMove = time;
    final target = (past != 0 ? past * 1.4 : speed).clamp(-1.0, 1.0);
    _stretch.value += (target - _stretch.value) * .35;
    final over = _position.value.round().clamp(0, _count - 1);
    if (over != _hovered) {
      _hovered = over;
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _start(DragStartDetails details, double width) {
    _dragging = true;
    _lastMove = details.sourceTimeStamp;
    _hovered = _position.value.round();
    _setLift(1);
    // The pill comes to the finger rather than jumping there.
    _position.animateWith(
      SpringSimulation(
        MusicMotion.snappy,
        _position.value,
        _tabAt(details.localPosition.dx, width),
        0,
      ),
    );
  }

  void _end(double velocityPx, double width) {
    if (!_dragging) return;
    _dragging = false;
    _lastMove = null;
    _setLift(0);
    _stretch.animateWith(SpringSimulation(_jelly, _stretch.value, 0, 0));
    final velocity = velocityPx / width;
    // A flick carries a little further, never past a neighbor.
    final target = (_position.value + (velocity * .12).clamp(-.6, .6))
        .round()
        .clamp(0, _count - 1);
    _glideTo(target, velocity);
    if (target != widget.tabs.index) widget.onSelected(target);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final outer = Theme.of(context).colorScheme;
    final glass = MusicTokens.of(context).glass;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final width = (size.width - _inset * 2) / _count;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _start(d, width),
          onHorizontalDragUpdate: (d) => _follow(d, width),
          onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0, width),
          onHorizontalDragCancel: () => _end(0, width),
          child: AnimatedBuilder(
            animation: Listenable.merge([_position, _lift, _stretch]),
            builder: (context, _) {
              final at = _position.value;
              final lift = _lift.value;
              final held = lift.clamp(0.0, 1.0);
              final pull = _stretch.value.clamp(-1.0, 1.0);
              final pill = Rect.fromLTWH(
                _inset + width * at,
                _inset,
                width,
                size.height - _inset * 2,
              );
              // Held, the lens swells past the capsule.
              final lens = Rect.fromCenter(
                center: pill.center,
                width: pill.width * (1 + .16 * lift),
                height: pill.height * (1 + .30 * lift),
              );
              final bar = Material(
                key: const ValueKey('floating-tab-bar'),
                type: MaterialType.transparency,
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(
                    ChromeMetrics.tabHeight / 2,
                  ),
                  child: Builder(
                    builder: (context) {
                      // Inside the surface: the metal skin relights its
                      // display.
                      final colors = Theme.of(context).colorScheme;
                      return Stack(
                        children: [
                          Positioned.fromRect(
                            rect: pill,
                            child: Opacity(
                              // The resting pill gives way to the lens.
                              opacity: 1 - held,
                              child: DecoratedBox(
                                key: const ValueKey('floating-tab-pill'),
                                decoration: BoxDecoration(
                                  color: dark
                                      ? Colors.black.withValues(alpha: .26)
                                      : colors.onSurface.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(
                                    pill.height / 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _row(colors, at, keyed: true),
                        ],
                      );
                    },
                  ),
                ),
              );
              // The capsule swells a touch while held and leans the way it
              // is pulled, anchored on the far side, then wobbles back.
              final sx = 1 + .03 * lift + .035 * pull.abs();
              final sy = 1 + .02 * lift - .03 * pull.abs();
              return Transform(
                alignment: Alignment(-pull.sign * .8, 0),
                transform: Matrix4.diagonal3Values(sx, sy, 1),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: bar),
                    if (held > .01)
                      Positioned.fromRect(
                        rect: lens,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            // Text styles come from a Material, as in the bar.
                            child: Material(
                              type: MaterialType.transparency,
                              child: _lens(
                                lens,
                                size,
                                at,
                                lift,
                                held,
                                outer,
                                glass,
                                dark,
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
      },
    );
  }

  /// The held pill as a glass lens: a magnified copy of the tabs under it,
  /// a bright rim and top sheen, and a shadow that grows as it lifts.
  Widget _lens(
    Rect lens,
    Size bar,
    double at,
    double lift,
    double held,
    ColorScheme colors,
    Color glass,
    bool dark,
  ) {
    final radius = BorderRadius.circular(lens.height / 2);
    final zoom = 1 + .22 * lift;
    final center = lens.center;
    return Opacity(
      key: const ValueKey('floating-tab-lens'),
      opacity: held,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .38 : .20),
              blurRadius: 10 + 14 * held,
              spreadRadius: 1.5 * held,
              offset: Offset(0, 3 + 5 * held),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Clear glass over the capsule: hides the flat tabs below.
              ColoredBox(color: glass.withValues(alpha: .94)),
              Positioned(
                left: -lens.left,
                top: -lens.top,
                width: bar.width,
                height: bar.height,
                child: Transform(
                  transform: Matrix4.identity()
                    ..translateByDouble(center.dx, center.dy, 0, 1)
                    ..scaleByDouble(zoom, zoom, 1, 1)
                    ..translateByDouble(-center.dx, -center.dy, 0, 1),
                  child: _row(colors, at, keyed: false),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: dark ? .20 : .45),
                      Colors.white.withValues(alpha: 0),
                      colors.primary.withValues(alpha: .06),
                    ],
                    stops: const [0, .5, 1],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: dark ? .34 : .7),
                    width: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ColorScheme colors, double at, {required bool keyed}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _inset),
    child: Row(
      children: [
        for (var i = 0; i < _count; i++)
          Expanded(child: _tab(colors, i, at, keyed: keyed)),
      ],
    ),
  );

  Widget _tab(ColorScheme colors, int i, double at, {required bool keyed}) {
    final tabs = widget.tabs;
    // The accent follows the pill: full on the tab it covers, fading as it
    // slides off, so the light travels with it.
    final lit = (1 - (at - i).abs()).clamp(0.0, 1.0);
    final selected = i == tabs.index;
    return _TabButton(
      key: keyed ? ValueKey('floating-tab-$i') : null,
      label: tabs.labels[i],
      icon: lit > .5
          ? _FloatingTabBar._selectedIcons[i %
                _FloatingTabBar._selectedIcons.length]
          : _FloatingTabBar._icons[i % _FloatingTabBar._icons.length],
      selected: selected,
      color: Color.lerp(colors.onSurface, colors.primary, lit)!,
      marker: switch (i) {
        2 when tabs.downloading => SizedBox.square(
          dimension: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: colors.primary,
          ),
        ),
        3 when tabs.updateBadge => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colors.error,
            shape: BoxShape.circle,
          ),
        ),
        _ => null,
      },
      onTap: () => widget.onSelected(i),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
    this.marker,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget? marker;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        pressedScale: .9,
        onTap: onTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 27,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 25, color: color),
                    if (marker != null)
                      Positioned(right: -10, top: 0, child: marker!),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.2),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The now-playing bar of the iOS shell: cover, "song - artist", then play
/// and the queue, the same on every width (songs change by swiping). Pressing
/// it lights it faintly; dragging sideways carries the song away and brings
/// the next one in.
class _NowPlayingBar extends StatefulWidget {
  const _NowPlayingBar({required this.chrome});

  final MobileChrome chrome;

  @override
  State<_NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<_NowPlayingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  double _drag = 0;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _settle() => _slide.animateWith(
    SpringSimulation(MusicMotion.snappy, _slide.value, 0, 0),
  );

  void _onDragEnd(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final direction = _drag <= -56 || velocity <= -400
        ? -1
        : (_drag >= 56 || velocity >= 400 ? 1 : 0);
    _drag = 0;
    final controller = widget.chrome.controller;
    if (direction == 0 || controller == null) {
      _settle();
      return;
    }
    unawaited(direction < 0 ? controller.next() : controller.previous());
    _slide
        .animateTo(
          direction * width,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeIn,
        )
        .then((_) {
          if (!mounted) return;
          _slide.value = -direction * width * .5;
          _settle();
        });
  }

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome;
    return ListenableBuilder(
      listenable: Listenable.merge([
        chrome.nowPlaying,
        chrome.playing,
        chrome.favorite,
      ]),
      builder: (context, _) {
        final item = chrome.nowPlaying.value;
        final controller = chrome.controller;
        if (item == null || controller == null) return const SizedBox.shrink();
        final strings = AppStringsScope.of(context);
        final playing = chrome.playing.value;
        final artist = item.artist ?? '';
        return Listener(
          onPointerDown: (_) => _press(true),
          onPointerUp: (_) => _press(false),
          onPointerCancel: (_) => _press(false),
          child: _PressHighlight(
            pressed: _pressed,
            child: Material(
              type: MaterialType.transparency,
              child: GlassSurface(
                borderRadius: BorderRadius.circular(
                  ChromeMetrics.barHeight / 2,
                ),
                child: Builder(
                  builder: (context) {
                    final colors = Theme.of(context).colorScheme;
                    return LayoutBuilder(
                      builder: (context, box) => GestureDetector(
                        key: const ValueKey('floating-now-playing'),
                        behavior: HitTestBehavior.opaque,
                        onTap: chrome.onOpenPlayer,
                        onHorizontalDragStart: (_) {
                          _drag = 0;
                          _slide.stop();
                        },
                        onHorizontalDragUpdate: (details) {
                          _drag += details.delta.dx;
                          _slide.value = _drag * .6;
                        },
                        onHorizontalDragEnd: (details) =>
                            _onDragEnd(details, box.maxWidth),
                        onHorizontalDragCancel: () {
                          _drag = 0;
                          _settle();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 9, right: 6),
                          child: Row(
                            children: [
                              // Only the song moves with the finger; the
                              // buttons hold still at the bar's end.
                              Expanded(
                                child: ClipRect(
                                  child: AnimatedBuilder(
                                    animation: _slide,
                                    builder: (context, child) {
                                      final travel =
                                          (_slide.value.abs() / box.maxWidth)
                                              .clamp(0.0, 1.0);
                                      return Transform.translate(
                                        offset: Offset(_slide.value, 0),
                                        child: Opacity(
                                          opacity: (1 - travel * 1.6).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        MusicThumbnail(
                                          uri:
                                              item.artUri ??
                                              controller.currentArtworkUri,
                                          label: item.title,
                                          size: 38,
                                          radius: 8,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            artist.isEmpty
                                                ? item.title
                                                : '${item.title} - $artist',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textScaler: MediaQuery.textScalerOf(
                                              context,
                                            ).clamp(maxScaleFactor: 1.3),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: colors.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _BarButton(
                                key: const ValueKey(
                                  'floating-now-playing-toggle',
                                ),
                                icon: playing ? AppIcons.pause : AppIcons.play,
                                size: 32,
                                label: playing ? strings.pause : strings.play,
                                onTap: () =>
                                    unawaited(controller.togglePlayPause()),
                              ),
                              _BarButton(
                                key: const ValueKey(
                                  'floating-now-playing-queue',
                                ),
                                icon: CupertinoIcons.list_bullet,
                                size: 27,
                                label: strings.isZh ? '当前队列' : 'Play queue',
                                onTap: () => chrome.onOpenQueue?.call(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A faint wash over the bar while a finger is on it. The bar keeps its
/// size: a springy shrink read as the bar shaking.
class _PressHighlight extends StatelessWidget {
  const _PressHighlight({required this.pressed, required this.child});

  final bool pressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: pressed ? 1 : 0,
              duration: Duration(milliseconds: pressed ? 80 : 250),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(
                    ChromeMetrics.barHeight / 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.icon,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        pressedScale: .82,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: ChromeMetrics.barHeight,
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
