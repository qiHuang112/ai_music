import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/music_controller.dart';
import '../data/json_file_store.dart';
import '../data/music_playlists.dart';
import '../data/song_comments.dart';
import '../platform/app_storage.dart';
import 'app_localizations.dart';
import 'app_popup_menu.dart';
import 'app_theme.dart';
import 'design/glass_surface.dart';
import 'design/vinyl_disc.dart';
import 'desktop_scope.dart';
import 'initial_song_scroll.dart';
import 'music_thumbnail.dart';
import 'mini_player.dart';
import 'playback_queue.dart';
import 'player_page.dart';
import 'playlist_actions.dart';
import 'song_actions.dart';
import 'song_comments_page.dart';

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
    this.persistWindowState = true,
  });

  final MusicController controller;
  final Widget home, library, downloads, settings;
  final Widget Function(String id) playlistBuilder;
  final VoidCallback focusSearch;
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
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
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
    final value = _detail?.name;
    _saveTail = _saveTail.then((_) async {
      try {
        await const JsonFileStore().write(file, {'detail': value});
      } catch (_) {}
    });
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
    if (command && key == LogicalKeyboardKey.keyK) {
      _openSearch();
    } else if (command && key == LogicalKeyboardKey.comma) {
      selectSection('settings');
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
    final colors = Theme.of(context).colorScheme;
    return DesktopMusicScope(
      openPlayer: _openPlayer,
      openDetail: _showDetail,
      selection: _selection,
      locate: _locate,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Scaffold(
          // The backdrop fills the native titlebar; interactive content stays
          // below its traffic lights. Fullscreen reports a zero inset.
          body: Padding(
            padding: EdgeInsets.only(top: _titlebarInset),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
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
                              children: [
                                SizedBox(width: 190, child: _sidebar(strings)),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final docked =
                                          constraints.maxWidth >= 800;
                                      final content = IndexedStack(
                                        index: sections.indexOf(_section),
                                        children: [
                                          for (final section in sections)
                                            TickerMode(
                                              enabled: section == _section,
                                              child: Semantics(
                                                container: true,
                                                child: Navigator(
                                                  key: _navigators[section],
                                                  pages: [
                                                    MaterialPage<void>(
                                                      key: ValueKey(section),
                                                      child: _root(section),
                                                    ),
                                                  ],
                                                  onDidRemovePage: (_) {},
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                      final panel = _detail == null
                                          ? const SizedBox.shrink()
                                          : _details(_detail!, close: true);
                                      if (docked) {
                                        return Row(
                                          children: [
                                            Expanded(child: content),
                                            AnimatedContainer(
                                              duration: _motion(context, 180),
                                              width: _detail == null ? 0 : 300,
                                              clipBehavior: Clip.hardEdge,
                                              decoration: const BoxDecoration(),
                                              child: OverflowBox(
                                                alignment: Alignment.topRight,
                                                minWidth: 300,
                                                maxWidth: 300,
                                                child: panel,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      return Stack(
                                        children: [
                                          Positioned.fill(child: content),
                                          if (_detail != null)
                                            Positioned(
                                              top: 0,
                                              bottom: 0,
                                              right: 0,
                                              width: 300,
                                              child: Material(
                                                elevation: 8,
                                                color: colors.surface,
                                                child: panel,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: _motion(context, 220),
                          child: _player
                              ? DesktopNowPlaying(
                                  key: const ValueKey('desktop-now-playing'),
                                  controller: controller,
                                  onClose: () =>
                                      setState(() => _player = false),
                                  detail: _details(_playerDetail, close: false),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  DesktopPlaybackBar(
                    controller: controller,
                    onOpenPlayer: _openPlayer,
                    onOpenOrigin: _openOrigin,
                    onDetail: _showDetail,
                    detail: _player ? _playerDetail : _detail,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebar(AppStrings strings) {
    Widget entry(String id, String title, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selected: _section == id,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, size: 19),
        minLeadingWidth: 20,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => selectSection(id),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(23, 22, 20, 20),
          child: Text('来听', style: MusicType.masthead(context, size: 26)),
        ),
        entry('home', strings.isZh ? '首页' : 'Home', Icons.home_outlined),
        entry(
          'library',
          strings.isZh ? '音乐库' : 'Library',
          Icons.library_music_outlined,
        ),
        entry(
          'playlist:$favoritePlaylistId',
          strings.isZh ? '我的收藏' : 'Favorites',
          Icons.favorite_border,
        ),
        entry(
          'downloads',
          strings.isZh ? '下载' : 'Downloads',
          Icons.download_outlined,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(23, 16, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.isZh ? '我的歌单' : 'Playlists',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                tooltip: strings.newPlaylist,
                icon: const Icon(Icons.add, size: 19),
                onPressed: () => showCreatePlaylistDialog(context, controller),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final playlist in controller.frequentlyUsedPlaylists)
                entry(
                  'playlist:${playlist.id}',
                  playlist.name,
                  Icons.queue_music,
                ),
            ],
          ),
        ),
        entry('settings', strings.settings, Icons.settings_outlined),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _details(DesktopDetail detail, {required bool close}) {
    final zh = AppStringsScope.of(context).isZh;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
          child: Row(
            children: [
              for (final value in DesktopDetail.values)
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      if (value == detail) return;
                      _showDetail(value);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: detail == value
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(_detailLabel(value, zh)),
                  ),
                ),
              if (close)
                IconButton(
                  tooltip: zh ? '收起面板' : 'Close panel',
                  onPressed: _closeDetail,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (detail) {
            DesktopDetail.lyrics => PlayerLyricsPanel(controller: controller),
            DesktopDetail.comments => _comments(),
            DesktopDetail.queue => DesktopPlaybackQueue(controller: controller),
          },
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
  });
  final MusicController controller;
  final VoidCallback onOpenPlayer, onOpenOrigin;
  final ValueChanged<DesktopDetail> onDetail;
  final DesktopDetail? detail;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.mediaItemStream,
    initialData: controller.audioHandler.mediaItem.value,
    builder: (context, itemSnapshot) {
      final item = itemSnapshot.data;
      if (item == null) return const SizedBox.shrink();
      final strings = AppStringsScope.of(context);
      return StreamBuilder<PlaybackState>(
        stream: controller.playbackStateStream,
        initialData: controller.audioHandler.playbackState.value,
        builder: (context, snapshot) {
          final state = snapshot.data ?? PlaybackState();
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(MusicUi.glassRadius),
              child: Builder(
                builder: (context) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            InkWell(
                              onTap: onOpenPlayer,
                              child: SizedBox.square(
                                dimension: 52,
                                child: MiniPlaybackProgress(
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
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: onOpenPlayer,
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ),
                                  Text(
                                    item.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  InkWell(
                                    onTap: onOpenOrigin,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${strings.isZh ? '来自' : 'From'}：${controller.playbackOriginName ?? (strings.isZh ? '当前队列' : 'Queue')}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                DesktopPlaybackModeButton(
                                  controller: controller,
                                ),
                                IconButton(
                                  tooltip: strings.isZh ? '上一首' : 'Previous',
                                  onPressed: controller.previous,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                ),
                                DesktopPlayButton(
                                  playing: state.playing,
                                  onPressed: controller.togglePlayPause,
                                  tooltip: state.playing
                                      ? strings.pause
                                      : strings.play,
                                ),
                                IconButton(
                                  tooltip: strings.isZh ? '下一首' : 'Next',
                                  onPressed: controller.next,
                                  icon: const Icon(Icons.skip_next_rounded),
                                ),
                              ],
                            ),
                            PlayerPositionSlider(
                              key: ValueKey(item.id),
                              controller: controller,
                              trackId: item.id,
                              duration: item.duration ?? Duration.zero,
                              bufferedPosition: state.bufferedPosition,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 182,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                for (final value in DesktopDetail.values)
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(42, 34),
                                        backgroundColor: detail == value
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.secondaryContainer
                                            : null,
                                      ),
                                      onPressed: () => onDetail(value),
                                      child: Text(
                                        _detailLabel(value, strings.isZh),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            StreamBuilder<double>(
                              stream: controller.audioHandler.volumeStream,
                              initialData: controller.audioHandler.volume,
                              builder: (context, volume) => Row(
                                children: [
                                  const Icon(
                                    Icons.volume_up_outlined,
                                    size: 18,
                                  ),
                                  Expanded(
                                    child: DesktopSliderOverlay(
                                      child: Slider(
                                        value: (volume.data ?? 1).clamp(0, 1),
                                        onChanged:
                                            controller.audioHandler.setVolume,
                                        semanticFormatterCallback: (v) =>
                                            '${(v * 100).round()}%',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
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
    return StreamBuilder<List<MediaItem>>(
      stream: controller.audioHandler.queue,
      initialData: controller.audioHandler.queue.value,
      builder: (context, queue) => StreamBuilder<MediaItem?>(
        stream: controller.mediaItemStream,
        initialData: controller.audioHandler.mediaItem.value,
        builder: (context, current) {
          final items = queue.data ?? const <MediaItem>[];
          return Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${strings.isZh ? '当前队列' : 'Queue'} · ${items.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: strings.isZh ? '定位当前歌曲' : 'Locate current song',
                    onPressed: () => setState(() => _locate++),
                    icon: const Icon(Icons.my_location, size: 18),
                  ),
                ],
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
                          builder: (tap, selected) => ListTile(
                            dense: true,
                            selected: selected,
                            contentPadding: const EdgeInsets.only(
                              left: 12,
                              right: 4,
                            ),
                            leading: InkWell(
                              onTap: () => _play(item.id),
                              child: _pending == item.id
                                  ? const SizedBox.square(
                                      dimension: 34,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : MusicThumbnail(
                                      uri: item.artUri,
                                      size: 34,
                                      label: item.title,
                                    ),
                            ),
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: tap,
                            trailing: MusicPopupMenuButton<String>(
                              key: menu,
                              tooltip: strings.more,
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'play',
                                  child: Text(strings.play),
                                ),
                                if (track != null)
                                  PopupMenuItem(
                                    value: 'add',
                                    child: Text(strings.addToPlaylist),
                                  ),
                                if (track != null)
                                  PopupMenuItem(
                                    value: 'share',
                                    child: Text(strings.isZh ? '分享' : 'Share'),
                                  ),
                                if (!active)
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text(
                                      strings.isZh ? '从队列移除' : 'Remove',
                                    ),
                                  ),
                              ],
                              onSelected: (action) async {
                                switch (action) {
                                  case 'play':
                                    await _play(item.id);
                                  case 'add':
                                    if (track != null && context.mounted) {
                                      await showAddToPlaylistSheet(
                                        context,
                                        controller,
                                        track,
                                      );
                                    }
                                  case 'share':
                                    if (track != null && context.mounted) {
                                      await shareSong(
                                        context,
                                        controller,
                                        track,
                                      );
                                    }
                                  case 'remove':
                                    await controller.removeQueueItems([
                                      item.id,
                                    ]);
                                }
                              },
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
    );
  }
}
