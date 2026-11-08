import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/music_controller.dart';
import '../data/json_file_store.dart';
import '../data/music_playlists.dart';
import '../data/music_settings.dart';
import '../data/song_comments.dart';
import '../platform/app_storage.dart';
import 'app_localizations.dart';
import 'app_popup_menu.dart';
import 'app_theme.dart';
import 'app_update_page.dart';
import 'design/controls.dart';
import 'design/glass_surface.dart';
import 'design/vinyl_disc.dart';
import 'desktop_mini_player.dart';
import 'desktop_scope.dart';
import 'desktop_ui.dart';
import 'desktop_window.dart';
import 'initial_song_scroll.dart';
import 'music_thumbnail.dart';
import 'mini_player.dart';
import 'playback_queue.dart';
import 'player_page.dart';
import 'playlist_actions.dart';
import 'song_actions.dart';
import 'song_comments_page.dart';
import 'design/app_icons.dart';

class DesktopMusicShell extends StatefulWidget {
  const DesktopMusicShell({
    super.key,
    required this.controller,
    required this.home,
    required this.library,
    required this.downloads,
    required this.settings,
    required this.playlistBuilder,
    required this.focusSearch,
    this.searchFor,
    this.persistWindowState = true,
  });

  final MusicController controller;
  final Widget home, library, downloads, settings;
  final Widget Function(String id) playlistBuilder;
  final VoidCallback focusSearch;

  /// Searches the home page for these words, as if typed there.
  final ValueChanged<String>? searchFor;
  final bool persistWindowState;

  @override
  State<DesktopMusicShell> createState() => DesktopMusicShellState();
}

class DesktopMusicShellState extends State<DesktopMusicShell> {
  static const _navigationChannel = MethodChannel(
    'ai_music/desktop_navigation',
  );
  final _navigators = <String, GlobalKey<NavigatorState>>{};
  final _selection = ValueNotifier<String?>(null);
  final _locate = ValueNotifier<({String id, int revision})?>(null);
  String _section = 'home';
  DesktopDetail? _detail;
  DesktopDetail _playerDetail = DesktopDetail.lyrics;
  bool _player = false, _detailTouched = false;

  /// Mini player mode: whether it is the square or the strip, whether the
  /// square shows lyrics or the cover, and whether it floats over other apps.
  bool _mini = false, _miniSquare = false, _miniLyrics = true;
  bool _miniOnTop = true;
  final _observers = <String, _SectionObserver>{};
  File? _preferences;
  Future<void> _saveTail = Future.value();
  final _focus = FocusNode();
  double _titlebarInset = 32;
  Brightness? _windowBrightness;

  MusicController get controller => widget.controller;
  NavigatorState? get navigator => _navigators[_section]?.currentState;

  @override
  void initState() {
    super.initState();
    _navigators['home'] = GlobalKey<NavigatorState>();
    if (isMacMusicDesktop) {
      _navigationChannel.setMethodCallHandler((call) async {
        if (call.method == 'titlebarInset') {
          _setTitlebarInset(call.arguments);
          return;
        }
        if (call.method == 'miniShape') {
          // The window's edge was dragged and snapped to a shape.
          final square = call.arguments == true;
          if (mounted && square != _miniSquare) {
            setState(() => _miniSquare = square);
            _saveDetail();
            if (square && _miniLyrics) {
              unawaited(controller.loadMetadataForCurrentTrack());
            }
          }
          return;
        }
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        if (call.method == 'mini') {
          unawaited(toggleMini());
          return;
        }
        if (_mini) await toggleMini();
        if (call.method == 'search') _openSearch();
        if (call.method == 'settings') selectSection('settings');
      });
    }
    if (widget.persistWindowState) unawaited(_restoreDetail());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (isMacMusicDesktop && _windowBrightness != brightness) {
      _windowBrightness = brightness;
      unawaited(_syncWindowStyle(brightness));
    }
  }

  Future<void> _syncWindowStyle(Brightness brightness) async {
    try {
      final inset = await _navigationChannel.invokeMethod<num>('windowStyle', {
        'dark': brightness == Brightness.dark,
      });
      _setTitlebarInset(inset);
    } on MissingPluginException {
      // Widget tests have no native window; retain the normal titlebar spacing.
    } on PlatformException {
      // A window appearance update must not interrupt playback.
    }
  }

  void _setTitlebarInset(Object? value) {
    if (!mounted || value is! num || !value.isFinite) return;
    final inset = value.clamp(0, 80).toDouble();
    if (_titlebarInset != inset) setState(() => _titlebarInset = inset);
  }

  Future<void> _restoreDetail() async {
    try {
      final root = await getAiMusicSupportDirectory();
      final file = File('${root.path}/macos-window.json');
      final saved = await const JsonFileStore().read(file);
      if (!mounted) return;
      _preferences = file;
      if (saved is Map) {
        setState(() {
          if (saved['miniSquare'] is bool) _miniSquare = saved['miniSquare'];
          if (saved['miniLyrics'] is bool) _miniLyrics = saved['miniLyrics'];
          if (saved['miniOnTop'] is bool) _miniOnTop = saved['miniOnTop'];
        });
      }
      if (!_detailTouched && saved is Map) {
        final detail = DesktopDetail.values
            .where((d) => d.name == saved['detail'])
            .firstOrNull;
        setState(() => _detail = detail);
      } else if (_detailTouched) {
        _saveDetail();
      }
    } catch (_) {
      // A window preference never prevents access to music.
    }
  }

  void _saveDetail() {
    final file = _preferences;
    if (file == null) return;
    final value = {
      'detail': _detail?.name,
      'miniSquare': _miniSquare,
      'miniLyrics': _miniLyrics,
      'miniOnTop': _miniOnTop,
    };
    _saveTail = _saveTail.then((_) async {
      try {
        await const JsonFileStore().write(file, value);
      } catch (_) {}
    });
  }

  /// Shrinks the window into the mini player, or brings the full window
  /// back. The full layout stays built underneath, so pages keep their place.
  Future<void> toggleMini() async {
    // A tooltip left from the button that was clicked must not float over
    // the other shape.
    Tooltip.dismissAllToolTips();
    if (_mini) {
      await DesktopWindow.exitMini();
      if (mounted) setState(() => _mini = false);
      _focus.requestFocus();
      return;
    }
    if (_titlebarInset == 0 && isMacMusicDesktop) {
      // Full screen has no room for a floating window.
      return;
    }
    setState(() => _mini = true);
    _focus.requestFocus();
    if (_miniSquare && _miniLyrics) {
      unawaited(controller.loadMetadataForCurrentTrack());
    }
    await DesktopWindow.alwaysOnTop(_miniOnTop);
    await DesktopWindow.enterMini(
      _miniSquare ? DesktopWindow.miniSquare : DesktopWindow.miniStrip,
    );
  }

  void _setMiniSquare(bool square) {
    setState(() => _miniSquare = square);
    _saveDetail();
    if (square && _miniLyrics) {
      unawaited(controller.loadMetadataForCurrentTrack());
    }
    unawaited(
      DesktopWindow.resizeMini(
        square ? DesktopWindow.miniSquare : DesktopWindow.miniStrip,
        fromBottom: true,
      ),
    );
  }

  /// The song's menu in the mini player, NetEase's items where this app has
  /// the feature behind them. Items that need a page open the full window.
  Future<void> _miniMenu(Offset at) async {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final track = controller.currentTrack;
    final item = controller.audioHandler.mediaItem.value;
    final playing = controller.audioHandler.playbackState.value.playing;
    final originId = controller.playbackPlaylistId;
    final canOpenOrigin =
        originId != null &&
        (originId == favoritePlaylistId ||
            controller.allPlaylists.any((p) => p.id == originId));
    final downloaded = track != null && controller.isDownloaded(track);
    final source = track == null || downloaded
        ? null
        : controller.selectedSongSource(track);
    final artist = item?.artist ?? '';
    final album = item?.album ?? '';
    final picked = await DesktopWindow.popupMenu(at, [
      DesktopMenuItem('play', playing ? strings.pause : strings.play),
      DesktopMenuItem(
        'comments',
        zh ? '查看评论' : 'Comments',
        enabled: track != null,
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        'playlist',
        zh ? '添加到歌单' : 'Add to playlist',
        enabled: track != null,
      ),
      DesktopMenuItem(
        'download',
        downloaded ? (zh ? '已下载' : 'Downloaded') : (zh ? '下载' : 'Download'),
        enabled: source != null,
      ),
      DesktopMenuItem('share', zh ? '分享' : 'Share', enabled: track != null),
      if (artist.isNotEmpty)
        DesktopMenuItem('artist', '${zh ? '歌手：' : 'Artist: '}$artist'),
      if (album.isNotEmpty)
        DesktopMenuItem('album', '${zh ? '专辑：' : 'Album: '}$album'),
      DesktopMenuItem(
        'origin',
        '${zh ? '来自：' : 'From: '}${controller.playbackOriginName ?? (zh ? '当前队列' : 'Queue')}',
        enabled: canOpenOrigin,
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        'onTop',
        zh ? '保持在最前' : 'Float on top',
        checked: _miniOnTop,
      ),
    ]);
    if (!mounted || picked == null) return;
    switch (picked) {
      case 'play':
        controller.togglePlayPause();
      case 'comments':
        await toggleMini();
        if (!mounted) return;
        setState(() => _playerDetail = DesktopDetail.comments);
        _openPlayer();
      case 'playlist':
        await toggleMini();
        if (mounted && track != null) {
          await showAddToPlaylistSheet(context, controller, track);
        }
      case 'download':
        if (source != null) unawaited(controller.downloadCandidate(source));
      case 'share':
        await toggleMini();
        if (mounted && track != null) {
          await shareSong(context, controller, track);
        }
      case 'artist' || 'album':
        await toggleMini();
        if (!mounted) return;
        final words = picked == 'artist' ? artist : '$artist $album';
        selectSection('home');
        navigator?.popUntil((route) => route.isFirst);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.searchFor?.call(words.trim());
        });
      case 'origin':
        await toggleMini();
        if (mounted) _openOrigin();
      case 'onTop':
        _toggleMiniOnTop();
    }
  }

  /// 词: the strip opens into the square with lyrics; the square switches
  /// between lyrics and cover.
  void _miniLyricsButton() {
    if (!_miniSquare) {
      setState(() => _miniLyrics = true);
      _setMiniSquare(true);
    } else {
      setState(() => _miniLyrics = !_miniLyrics);
      _saveDetail();
    }
    if (_miniLyrics) unawaited(controller.loadMetadataForCurrentTrack());
  }

  void _toggleMiniOnTop() {
    setState(() => _miniOnTop = !_miniOnTop);
    _saveDetail();
    unawaited(DesktopWindow.alwaysOnTop(_miniOnTop));
  }

  void _back() {
    if (_player) {
      setState(() => _player = false);
    } else {
      navigator?.maybePop();
    }
  }

  void selectSection(String section) {
    // Retiring a focused navigator must not leave focus outside this shell.
    _focus.requestFocus();
    setState(() {
      _player = false;
      _section = section;
      _navigators.putIfAbsent(section, () => GlobalKey<NavigatorState>());
    });
  }

  void _showDetail(DesktopDetail detail) {
    setState(() {
      if (_player) {
        _playerDetail = detail;
      } else {
        _detail = _detail == detail ? null : detail;
        _detailTouched = true;
      }
    });
    _saveDetail();
    if (detail == DesktopDetail.lyrics) {
      unawaited(controller.loadMetadataForCurrentTrack());
    }
  }

  void _closeDetail() {
    setState(() {
      _detail = null;
      _detailTouched = true;
    });
    _saveDetail();
  }

  void _openPlayer() {
    _focus.requestFocus();
    setState(() => _player = true);
    unawaited(controller.loadMetadataForCurrentTrack());
  }

  void _openSearch() {
    selectSection('home');
    navigator?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusSearch();
    });
  }

  void _openOrigin() {
    final id = controller.playbackPlaylistId;
    if (id == null ||
        (id != favoritePlaylistId &&
            !controller.allPlaylists.any((p) => p.id == id))) {
      _showDetail(DesktopDetail.queue);
      return;
    }
    final existed = _navigators.containsKey('playlist:$id');
    selectSection('playlist:$id');
    navigator?.popUntil((route) => route.isFirst);
    if (existed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _locate.value = (
            id: id,
            revision: (_locate.value?.revision ?? 0) + 1,
          );
        }
      });
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Dialogs and overflow menus own their Escape and input handling.
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isMetaPressed;
    final editing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (command && shift && key == LogicalKeyboardKey.keyM) {
      unawaited(toggleMini());
    } else if (_mini) {
      // The mini player answers only to playback keys and Esc.
      if (key == LogicalKeyboardKey.escape) {
        unawaited(toggleMini());
      } else if (!editing && key == LogicalKeyboardKey.space) {
        controller.togglePlayPause();
      } else if (!editing && command && key == LogicalKeyboardKey.arrowRight) {
        controller.next();
      } else if (!editing && command && key == LogicalKeyboardKey.arrowLeft) {
        controller.previous();
      } else {
        return KeyEventResult.ignored;
      }
    } else if (command && key == LogicalKeyboardKey.keyK) {
      _openSearch();
    } else if (command && key == LogicalKeyboardKey.comma) {
      selectSection('settings');
    } else if (command && key == LogicalKeyboardKey.bracketLeft && !editing) {
      // ⌘[ goes back, as in Finder and Safari.
      _back();
    } else if (key == LogicalKeyboardKey.escape && !editing) {
      if (_player) {
        setState(() => _player = false);
      } else if (_detail != null) {
        _closeDetail();
      } else {
        navigator?.maybePop();
      }
    } else if (!editing && key == LogicalKeyboardKey.space) {
      controller.togglePlayPause();
    } else if (!editing && command && key == LogicalKeyboardKey.arrowRight) {
      controller.next();
    } else if (!editing && command && key == LogicalKeyboardKey.arrowLeft) {
      controller.previous();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _root(String id) => switch (id) {
    'home' => widget.home,
    'library' => widget.library,
    'downloads' => widget.downloads,
    'settings' => widget.settings,
    _ => widget.playlistBuilder(id.substring('playlist:'.length)),
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final sections = _navigators.keys.toList();
    final theme = Theme.of(context);
    return DesktopMusicScope(
      openPlayer: _openPlayer,
      openDetail: _showDetail,
      selection: _selection,
      locate: _locate,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Theme(
          data: _desktopTheme(theme),
          child: Scaffold(
            body: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // In the mini player the full window stays built, at its
                  // own size and hidden, so every page keeps its place.
                  Offstage(
                    offstage: _mini,
                    child: TickerMode(
                      enabled: !_mini,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: _mini ? 1100 : null,
                        maxWidth: _mini ? 1100 : null,
                        minHeight: _mini ? 780 : null,
                        maxHeight: _mini ? 780 : null,
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Offstage(
                                    offstage: _player,
                                    child: TickerMode(
                                      enabled: !_player,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // The sidebar floats from the window's top
                                          // edge; the traffic lights sit inside it.
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              DesktopUi.gutter,
                                              DesktopUi.gutter,
                                              0,
                                              0,
                                            ),
                                            child: SizedBox(
                                              width: DesktopUi.sidebarWidth,
                                              child: GlassSurface(
                                                level: GlassLevel.thin,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: _sidebar(strings),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                _toolbar(strings),
                                                Expanded(
                                                  child: LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final docked =
                                                          constraints
                                                              .maxWidth >=
                                                          760;
                                                      final content = IndexedStack(
                                                        index: sections.indexOf(
                                                          _section,
                                                        ),
                                                        children: [
                                                          for (final section
                                                              in sections)
                                                            TickerMode(
                                                              enabled:
                                                                  section ==
                                                                  _section,
                                                              child: Semantics(
                                                                container: true,
                                                                child: Navigator(
                                                                  key:
                                                                      _navigators[section],
                                                                  observers: [
                                                                    _observerFor(
                                                                      section,
                                                                    ),
                                                                  ],
                                                                  pages: [
                                                                    MaterialPage<
                                                                      void
                                                                    >(
                                                                      key: ValueKey(
                                                                        section,
                                                                      ),
                                                                      child: _root(
                                                                        section,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                  onDidRemovePage:
                                                                      (_) {},
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      );
                                                      final panel =
                                                          _detail == null
                                                          ? const SizedBox.shrink()
                                                          : Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    right: DesktopUi
                                                                        .gutter,
                                                                    top: 4,
                                                                  ),
                                                              child: GlassSurface(
                                                                level: GlassLevel
                                                                    .regular,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      16,
                                                                    ),
                                                                child: _details(
                                                                  _detail!,
                                                                  close: true,
                                                                ),
                                                              ),
                                                            );
                                                      if (docked) {
                                                        return Row(
                                                          children: [
                                                            Expanded(
                                                              child: content,
                                                            ),
                                                            AnimatedContainer(
                                                              duration: _motion(
                                                                context,
                                                                200,
                                                              ),
                                                              curve: MusicMotion
                                                                  .emphasized,
                                                              width:
                                                                  _detail ==
                                                                      null
                                                                  ? 0
                                                                  : DesktopUi
                                                                        .panelWidth,
                                                              clipBehavior:
                                                                  Clip.none,
                                                              decoration:
                                                                  const BoxDecoration(),
                                                              child: ClipRect(
                                                                child: OverflowBox(
                                                                  alignment:
                                                                      Alignment
                                                                          .topLeft,
                                                                  minWidth:
                                                                      DesktopUi
                                                                          .panelWidth,
                                                                  maxWidth:
                                                                      DesktopUi
                                                                          .panelWidth,
                                                                  child: panel,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        );
                                                      }
                                                      // Narrow windows lay the panel over
                                                      // the page instead of squeezing it.
                                                      return Stack(
                                                        children: [
                                                          Positioned.fill(
                                                            child: content,
                                                          ),
                                                          if (_detail != null)
                                                            Positioned(
                                                              top: 0,
                                                              bottom: 0,
                                                              right: 0,
                                                              width: DesktopUi
                                                                  .panelWidth,
                                                              child: panel,
                                                            ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: _motion(context, 240),
                                    switchInCurve: MusicMotion.emphasized,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween(
                                              begin: const Offset(0, .04),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: _player
                                        ? KeyedSubtree(
                                            key: const ValueKey(
                                              'desktop-now-playing',
                                            ),
                                            child: DesktopNowPlaying(
                                              // Clear of the traffic lights.
                                              leadingInset: _hasTrafficLights
                                                  ? 92
                                                  : 0,
                                              controller: controller,
                                              onClose: () => setState(
                                                () => _player = false,
                                              ),
                                              detail: _details(
                                                _playerDetail,
                                                close: false,
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                            DesktopPlaybackBar(
                              controller: controller,
                              onOpenPlayer: _player
                                  ? () => setState(() => _player = false)
                                  : _openPlayer,
                              onOpenOrigin: _openOrigin,
                              onDetail: _showDetail,
                              detail: _player ? _playerDetail : _detail,
                              playerOpen: _player,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_mini)
                    DesktopMiniPlayer(
                      controller: controller,
                      lyrics: _miniLyrics,
                      onLyricsButton: _miniLyricsButton,
                      onToggleShape: () => _setMiniSquare(!_miniSquare),
                      onExpand: () => unawaited(toggleMini()),
                      onMenu: (at) => unawaited(_miniMenu(at)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasTrafficLights => _titlebarInset > 0;

  /// The content's own titlebar: back on the left; skin, mini player and
  /// settings on the right, as in NetEase Cloud Music. Its empty part drags
  /// the window, and a double click fills the screen.
  Widget _toolbar(AppStrings strings) {
    final zh = strings.isZh;
    final canPop = navigator?.canPop() ?? false;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          const Positioned.fill(child: DesktopWindowDragArea()),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: Row(
              children: [
                DesktopToolButton(
                  key: const ValueKey('desktop-back'),
                  icon: AppIcons.chevronLeft,
                  tooltip: zh ? '返回（⌘[）' : 'Back (⌘[)',
                  size: 30,
                  iconSize: 22,
                  onPressed: canPop ? _back : null,
                ),
                const Spacer(),
                _SkinMenu(controller: controller),
                const SizedBox(width: 4),
                DesktopToolButton(
                  key: const ValueKey('desktop-mini-player'),
                  icon: AppIcons.miniWindow,
                  tooltip: zh ? '迷你播放器（⇧⌘M）' : 'Mini player (⇧⌘M)',
                  onPressed: controller.audioHandler.mediaItem.value == null
                      ? null
                      : () => unawaited(toggleMini()),
                ),
                const SizedBox(width: 4),
                UpdateBadge(
                  updates: controller.appUpdates,
                  child: DesktopToolButton(
                    key: const ValueKey('desktop-settings'),
                    icon: AppIcons.settings,
                    tooltip: zh ? '设置（⌘,）' : 'Settings (⌘,)',
                    active: _section == 'settings',
                    onPressed: () => selectSection('settings'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _SectionObserver _observerFor(String section) => _observers.putIfAbsent(
    section,
    () => _SectionObserver(() {
      // Pushes and pops change whether the toolbar can go back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }),
  );

  /// Pages are shared with the phone layout; on the Mac their bars, lists
  /// and scrollbars take desktop proportions.
  ThemeData _desktopTheme(ThemeData theme) {
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return theme.copyWith(
      visualDensity: VisualDensity.compact,
      appBarTheme: theme.appBarTheme.copyWith(
        toolbarHeight: 56,
        titleSpacing: 32,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actionsPadding: const EdgeInsets.only(right: 22),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          colors.onSurface.withValues(alpha: .22),
        ),
        crossAxisMargin: 3,
        mainAxisMargin: 6,
      ),
      dividerTheme: theme.dividerTheme.copyWith(
        color: colors.onSurface.withValues(alpha: dark ? .06 : .07),
        space: 1,
        thickness: .6,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: TextStyle(
          fontSize: 12,
          color: dark ? const Color(0xFF1B1B1D) : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: dark
              ? const Color(0xFFF2F2F4).withValues(alpha: .96)
              : const Color(0xFF1F1F22).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopUi.rowRadius + 2),
        ),
        selectedTileColor: DesktopUi.selectedFill(context),
      ),
    );
  }

  Widget _sidebar(AppStrings strings) {
    final zh = strings.isZh;
    final colors = Theme.of(context).colorScheme;
    Widget count(int value) => Text(
      '$value',
      style: MusicType.readout(
        context,
        size: 11,
      ).copyWith(color: DesktopUi.muted(context).withValues(alpha: .8)),
    );
    Widget entry(
      String id,
      String title, {
      IconData? icon,
      Widget? leading,
      Widget? trailing,
      Key? key,
    }) {
      final selected = _section == id;
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: DesktopRow(
          selected: selected,
          onTap: () => selectSection(id),
          child: Row(
            children: [
              leading ?? Icon(icon, size: 17, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
    }

    Widget group(String label, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: SizedBox(
        height: 20,
        child: Row(
          children: [
            Expanded(child: Text(label, style: DesktopUi.groupLabel(context))),
            ?action,
          ],
        ),
      ),
    );

    final playlists = controller.frequentlyUsedPlaylists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The traffic lights sit in this strip; like the toolbar, it drags
        // the window and zooms it on a double click.
        SizedBox(
          height: _hasTrafficLights ? 48 : 14,
          child: const DesktopWindowDragArea(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Tooltip(
            message: zh ? '搜索（⌘K）' : 'Search (⌘K)',
            waitDuration: const Duration(milliseconds: 700),
            child: DesktopRow(
              key: const ValueKey('desktop-sidebar-search'),
              onTap: _openSearch,
              height: 30,
              child: Row(
                children: [
                  Icon(
                    AppIcons.search,
                    size: 16,
                    color: DesktopUi.muted(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      zh ? '搜索' : 'Search',
                      style: TextStyle(
                        fontSize: 13,
                        color: DesktopUi.muted(context),
                      ),
                    ),
                  ),
                  const DesktopKeyCap('⌘K'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        entry('home', zh ? '首页' : 'Home', icon: AppIcons.home),
        entry('library', zh ? '音乐库' : 'Library', icon: AppIcons.library),
        group(zh ? '我的音乐' : 'Your music'),
        entry(
          'playlist:$favoritePlaylistId',
          zh ? '我的收藏' : 'Favorites',
          icon: AppIcons.heartFill,
          trailing: controller.favoriteTracks.isEmpty
              ? null
              : count(controller.favoriteTracks.length),
        ),
        entry(
          'downloads',
          zh ? '下载' : 'Downloads',
          icon: AppIcons.download,
          trailing: controller.hasActiveDownloads
              ? const SizedBox.square(
                  dimension: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : controller.cachedTracks.isEmpty
              ? null
              : count(controller.cachedTracks.length),
        ),
        group(
          zh ? '歌单' : 'Playlists',
          action: DesktopToolButton(
            icon: AppIcons.add,
            tooltip: strings.newPlaylist,
            size: 22,
            iconSize: 16,
            onPressed: () => showCreatePlaylistDialog(context, controller),
          ),
        ),
        Expanded(
          child: ShaderMask(
            // Long lists fade under the settings row instead of cutting off.
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, .9, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (final playlist in playlists)
                  entry(
                    'playlist:${playlist.id}',
                    playlist.name,
                    leading: MusicThumbnail(
                      uri: playlistArtworkUri(controller, playlist),
                      label: playlist.name,
                      size: 22,
                      radius: 5,
                    ),
                  ),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 16, 0),
                    child: Text(
                      strings.noCustomPlaylists,
                      style: TextStyle(
                        fontSize: 12,
                        color: DesktopUi.muted(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _details(DesktopDetail detail, {required bool close}) {
    final zh = AppStringsScope.of(context).isZh;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: DesktopSegmented<DesktopDetail>(
                  values: DesktopDetail.values,
                  selected: detail,
                  label: (value) => _detailLabel(value, zh),
                  onSelected: (value) {
                    if (value != detail) _showDetail(value);
                  },
                ),
              ),
              if (close) ...[
                const SizedBox(width: 6),
                DesktopToolButton(
                  icon: AppIcons.close,
                  tooltip: zh ? '收起面板' : 'Close panel',
                  size: 28,
                  iconSize: 16,
                  onPressed: _closeDetail,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: _motion(context, 160),
            child: KeyedSubtree(
              key: ValueKey(detail),
              child: switch (detail) {
                DesktopDetail.lyrics => PlayerLyricsPanel(
                  controller: controller,
                ),
                DesktopDetail.comments => _comments(),
                DesktopDetail.queue => DesktopPlaybackQueue(
                  controller: controller,
                ),
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _comments() {
    final track = controller.currentTrack;
    if (track == null) {
      return Center(child: Text(AppStringsScope.of(context).nothingPlaying));
    }
    return SongCommentsPage(
      key: ValueKey('desktop-comments-${track.id}'),
      embedded: true,
      query: SongCommentQuery.fromTrack(
        track,
        original: controller.originalSongForTrack(track),
        candidate: controller.selectedSongSource(track),
        lyrics: controller.currentLyrics,
      ),
    );
  }

  @override
  void dispose() {
    if (isMacMusicDesktop) _navigationChannel.setMethodCallHandler(null);
    _focus.dispose();
    _selection.dispose();
    _locate.dispose();
    super.dispose();
  }
}

Duration _motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

String _detailLabel(DesktopDetail value, bool zh) => switch (value) {
  DesktopDetail.lyrics => zh ? '歌词' : 'Lyrics',
  DesktopDetail.comments => zh ? '热评' : 'Comments',
  DesktopDetail.queue => zh ? '队列' : 'Queue',
};

class DesktopPlaybackBar extends StatelessWidget {
  const DesktopPlaybackBar({
    super.key,
    required this.controller,
    required this.onOpenPlayer,
    required this.onOpenOrigin,
    required this.onDetail,
    required this.detail,
    this.playerOpen = false,
  });
  final MusicController controller;
  final VoidCallback onOpenPlayer, onOpenOrigin;
  final ValueChanged<DesktopDetail> onDetail;
  final DesktopDetail? detail;
  final bool playerOpen;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.mediaItemStream,
    initialData: controller.audioHandler.mediaItem.value,
    builder: (context, itemSnapshot) {
      final item = itemSnapshot.data;
      if (item == null) return const SizedBox.shrink();
      return StreamBuilder<PlaybackState>(
        stream: controller.playbackStateStream,
        initialData: controller.audioHandler.playbackState.value,
        builder: (context, snapshot) {
          final state = snapshot.data ?? PlaybackState();
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              DesktopUi.gutter,
              DesktopUi.gutter,
              DesktopUi.gutter,
              DesktopUi.gutter,
            ),
            child: GlassSurface(
              level: GlassLevel.regular,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 72,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = (constraints.maxWidth * .28)
                        .clamp(210.0, 320.0)
                        .toDouble();
                    return Row(
                      children: [
                        SizedBox(
                          width: side,
                          child: _nowPlaying(context, item, state),
                        ),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: _transport(context, item, state),
                            ),
                          ),
                        ),
                        SizedBox(width: side, child: _extras(context)),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _nowPlaying(
    BuildContext context,
    MediaItem item,
    PlaybackState state,
  ) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final origin =
        '${strings.isZh ? '来自' : 'From'}：${controller.playbackOriginName ?? (strings.isZh ? '当前队列' : 'Queue')}';
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Row(
        children: [
          Tooltip(
            message: playerOpen
                ? (strings.isZh ? '收起播放页' : 'Close player')
                : (strings.isZh ? '打开播放页' : 'Open player'),
            waitDuration: const Duration(milliseconds: 500),
            child: DesktopHover(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: onOpenPlayer,
                child: AnimatedScale(
                  scale: hovered ? 1.06 : 1,
                  duration: DesktopUi.hover,
                  child: SizedBox.square(
                    dimension: 52,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MiniPlaybackProgress(
                          controller: controller,
                          item: item,
                          state: state,
                          child: SpinningVinyl(
                            spinning: state.playing,
                            shadow: false,
                            labelFraction: .62,
                            label: MusicThumbnail(
                              uri: item.artUri,
                              label: item.title,
                              size: 32,
                              radius: 0,
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: hovered ? 1 : 0,
                          duration: DesktopUi.hover,
                          child: Center(
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: .55),
                              ),
                              child: Icon(
                                playerOpen
                                    ? AppIcons.chevronDown
                                    : AppIcons.chevronUp,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Link(
                  text: item.title,
                  onTap: onOpenPlayer,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: DesktopUi.muted(context),
                  ),
                ),
                const SizedBox(height: 2),
                _Link(
                  text: origin,
                  onTap: onOpenOrigin,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: colors.primary.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transport(BuildContext context, MediaItem item, PlaybackState state) {
    final strings = AppStringsScope.of(context);
    final track = controller.currentTrack;
    final favorite = track != null && controller.isFavorite(track);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DesktopToolButton(
              icon: favorite ? AppIcons.heartFill : AppIcons.heart,
              tooltip: favorite
                  ? strings.removeFromFavorites
                  : strings.addToFavorites,
              active: false,
              color: favorite ? Theme.of(context).colorScheme.primary : null,
              onPressed: track == null
                  ? null
                  : () => controller.toggleFavorite(track),
            ),
            const SizedBox(width: 10),
            DesktopToolButton(
              icon: AppIcons.previous,
              tooltip: '${strings.isZh ? '上一首' : 'Previous'}  ⌘←',
              size: 36,
              iconSize: 24,
              onPressed: controller.previous,
            ),
            const SizedBox(width: 8),
            DesktopPlayButton(
              playing: state.playing,
              onPressed: controller.togglePlayPause,
              tooltip:
                  '${state.playing ? strings.pause : strings.play}  ${strings.isZh ? '空格' : 'Space'}',
            ),
            const SizedBox(width: 8),
            DesktopToolButton(
              icon: AppIcons.next,
              tooltip: '${strings.isZh ? '下一首' : 'Next'}  ⌘→',
              size: 36,
              iconSize: 24,
              onPressed: controller.next,
            ),
            const SizedBox(width: 10),
            DesktopPlaybackModeButton(controller: controller),
          ],
        ),
        const SizedBox(height: 2),
        DesktopProgress(
          key: ValueKey(item.id),
          controller: controller,
          trackId: item.id,
          duration: item.duration ?? Duration.zero,
          bufferedPosition: state.bufferedPosition,
        ),
      ],
    );
  }

  Widget _extras(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final icons = {
      DesktopDetail.lyrics: AppIcons.lyrics,
      DesktopDetail.comments: AppIcons.comments,
      DesktopDetail.queue: AppIcons.queue,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 16, left: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final value in DesktopDetail.values) ...[
            DesktopToolButton(
              icon: icons[value]!,
              tooltip: _detailLabel(value, strings.isZh),
              active: detail == value,
              onPressed: () => onDetail(value),
            ),
            const SizedBox(width: 2),
          ],
          const SizedBox(width: 10),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: StreamBuilder<double>(
                stream: controller.audioHandler.volumeStream,
                initialData: controller.audioHandler.volume,
                builder: (context, volume) {
                  final level = (volume.data ?? 1).clamp(0.0, 1.0).toDouble();
                  return Row(
                    children: [
                      Icon(
                        level == 0
                            ? AppIcons.volumeOff
                            : level < .5
                            ? AppIcons.volumeLow
                            : AppIcons.volumeHigh,
                        size: 17,
                        color: DesktopUi.muted(context),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DesktopScrubber(
                          value: level,
                          semanticLabel: strings.isZh ? '音量' : 'Volume',
                          onChanged: controller.audioHandler.setVolume,
                          onChangeEnd: controller.audioHandler.setVolume,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text that underlines under the pointer and acts on a click.
class _Link extends StatelessWidget {
  const _Link({required this.text, required this.onTap, required this.style});

  final String text;
  final VoidCallback onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => DesktopHover(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(
          decoration: hovered ? TextDecoration.underline : null,
          decorationColor: style.color,
        ),
      ),
    ),
  );
}

class DesktopPlaybackQueue extends StatefulWidget {
  const DesktopPlaybackQueue({super.key, required this.controller});
  final MusicController controller;
  @override
  State<DesktopPlaybackQueue> createState() => _DesktopPlaybackQueueState();
}

class _DesktopPlaybackQueueState extends State<DesktopPlaybackQueue> {
  int _locate = 0;
  String? _pending, _error;
  Future<void> _play(String id) async {
    setState(() {
      _pending = id;
      _error = null;
    });
    try {
      await widget.controller.playQueueItem(id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted && _pending == id) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return StreamBuilder<List<MediaItem>>(
      stream: controller.audioHandler.queue,
      initialData: controller.audioHandler.queue.value,
      builder: (context, queue) => StreamBuilder<MediaItem?>(
        stream: controller.mediaItemStream,
        initialData: controller.audioHandler.mediaItem.value,
        builder: (context, current) => StreamBuilder<bool>(
          stream: controller.playbackStateStream
              .map((state) => state.playing)
              .distinct(),
          initialData: controller.audioHandler.playbackState.value.playing,
          builder: (context, playing) {
            final items = queue.data ?? const <MediaItem>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 10, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.isZh ? '接下来播放' : 'Playing next',
                          style: DesktopUi.groupLabel(context),
                        ),
                      ),
                      Text(
                        '${items.length}',
                        style: MusicType.readout(context, size: 11),
                      ),
                      const SizedBox(width: 4),
                      DesktopToolButton(
                        icon: AppIcons.locate,
                        tooltip: strings.isZh
                            ? '定位当前歌曲'
                            : 'Locate current song',
                        size: 26,
                        iconSize: 15,
                        onPressed: () => setState(() => _locate++),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, maxLines: 3),
                  ),
                Expanded(
                  child: InitialSongScroll(
                    key: ValueKey(_locate),
                    ready: items.isNotEmpty,
                    targetIndex: items.indexWhere(
                      (item) => item.id == current.data?.id,
                    ),
                    builder: (context, scroll, anchor) => ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final active = item.id == current.data?.id;
                        final menu = GlobalKey<PopupMenuButtonState<String>>();
                        final track = controller.queueTracks
                            .where((t) => t.id == item.id)
                            .firstOrNull;
                        return anchor(
                          index,
                          item.id,
                          DesktopSongInteraction(
                            id: 'queue:${item.id}',
                            onPlay: () => _play(item.id),
                            onContextMenu: () =>
                                menu.currentState?.showButtonMenu(),
                            builder: (tap, selected) => DesktopHover(
                              builder: (context, hovered) => DesktopRow(
                                selected: selected,
                                onTap: tap,
                                height: 50,
                                padding: const EdgeInsets.only(
                                  left: 6,
                                  right: 2,
                                ),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _play(item.id),
                                      child: SizedBox.square(
                                        dimension: 36,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            MusicThumbnail(
                                              uri: item.artUri,
                                              size: 36,
                                              radius: 6,
                                              label: item.title,
                                            ),
                                            if (active ||
                                                hovered ||
                                                _pending == item.id)
                                              DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: .5),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Center(
                                                  child: _pending == item.id
                                                      ? const SizedBox.square(
                                                          dimension: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        )
                                                      : active
                                                      ? EqualizerBars(
                                                          playing:
                                                              playing.data ??
                                                              false,
                                                          size: 14,
                                                          color: colors
                                                              .primaryContainer,
                                                        )
                                                      : const Icon(
                                                          Icons
                                                              .play_arrow_rounded,
                                                          size: 18,
                                                          color: Colors.white,
                                                        ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.25,
                                              fontWeight: active
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: active
                                                  ? colors.primary
                                                  : colors.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item.artist ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              height: 1.2,
                                              color: DesktopUi.muted(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AnimatedOpacity(
                                      opacity: hovered || selected ? 1 : 0,
                                      duration: DesktopUi.hover,
                                      child: MusicPopupMenuButton<String>(
                                        key: menu,
                                        tooltip: strings.more,
                                        icon: const Icon(
                                          AppIcons.more,
                                          size: 18,
                                        ),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'play',
                                            child: Text(strings.play),
                                          ),
                                          if (track != null)
                                            PopupMenuItem(
                                              value: 'add',
                                              child: Text(
                                                strings.addToPlaylist,
                                              ),
                                            ),
                                          if (track != null)
                                            PopupMenuItem(
                                              value: 'share',
                                              child: Text(
                                                strings.isZh ? '分享' : 'Share',
                                              ),
                                            ),
                                          if (!active)
                                            PopupMenuItem(
                                              value: 'remove',
                                              child: Text(
                                                strings.isZh
                                                    ? '从队列移除'
                                                    : 'Remove',
                                              ),
                                            ),
                                        ],
                                        onSelected: (action) async {
                                          switch (action) {
                                            case 'play':
                                              await _play(item.id);
                                            case 'add':
                                              if (track != null &&
                                                  context.mounted) {
                                                await showAddToPlaylistSheet(
                                                  context,
                                                  controller,
                                                  track,
                                                );
                                              }
                                            case 'share':
                                              if (track != null &&
                                                  context.mounted) {
                                                await shareSong(
                                                  context,
                                                  controller,
                                                  track,
                                                );
                                              }
                                            case 'remove':
                                              await controller.removeQueueItems(
                                                [item.id],
                                              );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionObserver extends NavigatorObserver {
  _SectionObserver(this.onChange);

  final VoidCallback onChange;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChange();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChange();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChange();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      onChange();
}

/// The skins, one click from the toolbar. Each shows its own room color and
/// lit color.
class _SkinMenu extends StatefulWidget {
  const _SkinMenu({required this.controller});

  final MusicController controller;

  @override
  State<_SkinMenu> createState() => _SkinMenuState();
}

class _SkinMenuState extends State<_SkinMenu> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final current = widget.controller.themePreference;
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(-120, 6),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        for (final skin in AppThemePreference.values)
          MenuItemButton(
            key: ValueKey('skin-${skin.name}'),
            onPressed: () => widget.controller.saveTheme(skin),
            leadingIcon: _Swatch(palette: MusicPalette.of(skin)),
            trailingIcon: skin == current
                ? Icon(AppIcons.check, size: 16, color: colors.primary)
                : const SizedBox(width: 16),
            style: MenuItemButton.styleFrom(
              minimumSize: const Size(196, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              strings.themeName(skin),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: skin == current ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => DesktopToolButton(
        key: const ValueKey('desktop-skins'),
        icon: AppIcons.paint,
        tooltip: strings.isZh ? '换肤' : 'Skins',
        active: menu.isOpen,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});

  final MusicPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .18),
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette.background,
          palette.background,
          palette.accent,
          palette.accent,
        ],
        stops: const [0, .5, .5, 1],
      ),
    ),
  );
}
