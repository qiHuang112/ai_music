import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
import 'app_page_route.dart';
import 'app_popup_menu.dart';
import 'duo_scaffold.dart';
import 'mobile_chrome.dart';
import 'native_shell.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'app_theme.dart';
import 'playback_queue.dart';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/song_comments.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'design/ambient_backdrop.dart';
import 'design/artwork_palette.dart';
import 'design/controls.dart';
import 'design/turntable.dart';
import 'playlist_actions.dart';
import 'swipe_to_skip.dart';
import 'song_source_page.dart';
import 'song_actions.dart';
import 'desktop_scope.dart';
import 'desktop_ui.dart';
import 'desktop_window.dart';
import 'song_comments_page.dart';
import 'design/app_icons.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class LyricsPanelForTesting extends StatelessWidget {
  const LyricsPanelForTesting({
    super.key,
    required this.controller,
    this.positionStream,
  });

  final MusicController controller;
  final Stream<Duration>? positionStream;

  @override
  Widget build(BuildContext context) {
    return _LyricsPanel(
      controller: controller,
      fillsAvailable: true,
      positionStream: positionStream,
    );
  }
}

/// The existing lyrics implementation, bounded by a stable desktop panel.
class PlayerLyricsPanel extends StatelessWidget {
  const PlayerLyricsPanel({super.key, required this.controller});
  final MusicController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _LyricsPanel(
      key: ValueKey(controller.currentTrack?.id),
      controller: controller,
      fillsAvailable: true,
    ),
  );
}

/// Repositions the original deck and artwork-driven backdrop; no skin is
/// recreated or recolored for the desktop layout.
class DesktopNowPlaying extends StatefulWidget {
  const DesktopNowPlaying({
    super.key,
    required this.controller,
    required this.onClose,
    required this.detail,
    this.leadingInset = 0,
  });
  final MusicController controller;
  final VoidCallback onClose;
  final Widget detail;

  /// Room on the left of the top row for the window's traffic lights.
  final double leadingInset;
  @override
  State<DesktopNowPlaying> createState() => _DesktopNowPlayingState();
}

class _DesktopNowPlayingState extends State<DesktopNowPlaying> {
  final _disc = _DiscSwipe();
  @override
  void dispose() {
    _disc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final track = controller.currentTrack;
    return _PlayerBackdrop(
      controller: controller,
      closeOnSwipe: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(
          children: [
            // The window's titlebar while the player is open: it drags the
            // window, and the lights sit at its left.
            SizedBox(
              height: 56,
              child: Stack(
                children: [
                  const Positioned.fill(child: DesktopWindowDragArea()),
                  Padding(
                    padding: EdgeInsets.only(left: widget.leadingInset, top: 4),
                    child: Row(
                      children: [
                        DesktopToolButton(
                          icon: AppIcons.chevronDown,
                          tooltip: zh ? '收起（Esc）' : 'Close (Esc)',
                          size: 34,
                          iconSize: 24,
                          onPressed: widget.onClose,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          zh ? '正在播放' : 'NOW PLAYING',
                          style: MusicType.eyebrow(context),
                        ),
                        const Spacer(),
                        if (track != null) ...[
                          DesktopToolButton(
                            tooltip: controller.isFavorite(track)
                                ? strings.removeFromFavorites
                                : strings.addToFavorites,
                            onPressed: () => controller.toggleFavorite(track),
                            icon: controller.isFavorite(track)
                                ? AppIcons.heartFill
                                : AppIcons.heart,
                            color: controller.isFavorite(track)
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 4),
                          DesktopToolButton(
                            tooltip: strings.addToPlaylist,
                            onPressed: () => showAddToPlaylistSheet(
                              context,
                              controller,
                              track,
                            ),
                            icon: AppIcons.playlistAdd,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: StreamBuilder<MediaItem?>(
                      stream: controller.mediaItemStream,
                      initialData: controller.audioHandler.mediaItem.value,
                      builder: (context, media) => StreamBuilder<PlaybackState>(
                        stream: controller.playbackStateStream,
                        initialData:
                            controller.audioHandler.playbackState.value,
                        builder: (context, state) {
                          final item = media.data;
                          if (item == null) {
                            return Center(child: Text(strings.nothingPlaying));
                          }
                          return LayoutBuilder(
                            builder: (context, constraints) => Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _Artwork(
                                      uri:
                                          item.artUri ??
                                          controller.currentArtworkUri,
                                      controller: controller,
                                      playing: state.data?.playing ?? false,
                                      cueing: false,
                                      maxWidth: [
                                        constraints.maxWidth * .8,
                                        constraints.maxHeight - 150,
                                        440.0,
                                      ].reduce((a, b) => a < b ? a : b),
                                    ),
                                    const SizedBox(height: 22),
                                    Text(
                                      item.title,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: MusicType.masthead(
                                        context,
                                        size: 32,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      [
                                        if ((item.artist ?? '').isNotEmpty)
                                          item.artist!,
                                        if ((item.album ?? '').isNotEmpty)
                                          item.album!,
                                      ].join('  ·  '),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: DesktopUi.muted(context),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (track != null &&
                                        controller.canSwitchSongSource(track))
                                      TextButton(
                                        onPressed: () => showSongSourcePicker(
                                          context,
                                          controller,
                                          track,
                                        ),
                                        child: SongSourceMenuLabel(
                                          source: controller.songSourceLabel(
                                            track,
                                            isZh: zh,
                                          ),
                                        ),
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
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 10,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 8, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: widget.detail,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPageState extends State<PlayerPage> {
  MusicController get controller => widget.controller;

  // Set between the tap on play and the first sound: the needle goes down
  // first, then the record turns and the music starts with it.
  bool _cueing = false;
  final _disc = _DiscSwipe();
  Timer? _cue;

  void _togglePlayPause(bool playing) {
    if (playing || _cueing) {
      // Pausing, or a second tap while cueing, is immediate.
      _cue?.cancel();
      final wasCueing = _cueing;
      setState(() => _cueing = false);
      if (!wasCueing) controller.togglePlayPause();
      return;
    }
    setState(() => _cueing = true);
    // An explicit play: if the song changed meanwhile, the new one must not
    // be paused by a toggle.
    _cue = Timer(MusicMotion.toneArm, () {
      if (!mounted) return;
      setState(() => _cueing = false);
      controller.play();
    });
  }

  @override
  void dispose() {
    // Leaving mid-cue still starts the song that was asked for.
    if (_cue?.isActive ?? false) controller.play();
    _cue?.cancel();
    _disc.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Loading can notify the app-level listener synchronously. Let the route
    // finish mounting before updating metadata, and skip a route already closed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.loadMetadataForCurrentTrack();
    });
  }

  /// The record, title and artist of the song before (-1) or after (1)
  /// this one, sliding in beside the finger. Unknown in shuffle.
  Widget? _neighborSlab(BuildContext context, int step) {
    final item = _neighborItem(controller, step);
    if (item == null) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Artwork(
          uri: item.artUri,
          controller: controller,
          playing: false,
          cueing: false,
        ),
        const SizedBox(height: 18),
        _SongInfo(title: item.title, artist: item.artist ?? ''),
      ],
    );
  }

  void _openComments(BuildContext context, Track track) {
    final query = SongCommentQuery.fromTrack(
      track,
      original: controller.originalSongForTrack(track),
      candidate: controller.selectedSongSource(track),
      lyrics: controller.currentLyrics,
    );
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => SongCommentsPage(query: query)));
  }

  void _openLyrics(BuildContext context) => Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => _LyricsDetailPage(controller: controller),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentTrack = controller.currentTrack;
        final strings = AppStringsScope.of(context);
        final rail = DuoScaffold.usesSystemRail(context);
        return DuoScaffold(
          extendBodyBehindAppBar: true,
          background: _PlayerBackdrop(
            controller: controller,
            closeOnSwipe: false,
            child: const SizedBox.expand(),
          ),
          // Under the iOS shell the side rail already carries lyrics and
          // the queue for every page, and the controls row has the queue.
          extraActions: [
            if (!NativeShell.active) ...[
              DuoRailItem(
                icon: CupertinoIcons.text_quote,
                label: strings.isZh ? '完整歌词' : 'Full lyrics',
                onPressed: () => _openLyrics(context),
              ),
              DuoRailItem(
                icon: CupertinoIcons.music_note_list,
                label: strings.isZh ? '当前队列' : 'Play queue',
                onPressed: () => showPlaybackQueue(context, controller),
              ),
            ],
          ],
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            // Immersive like the iOS shell's player: back and the menu only.
            title: MobileChrome.instance.floating
                ? null
                : Text(strings.nowPlaying),
            actions: [
              // One menu instead of a row of icons: the heart sits by the
              // title, and the rarer actions wait behind the ellipsis.
              if (currentTrack != null)
                MusicPopupMenuButton<String>(
                  key: const ValueKey('player-more'),
                  tooltip: strings.more,
                  icon: const Icon(AppIcons.more),
                  onSelected: (value) => switch (value) {
                    'playlist' => showAddToPlaylistSheet(
                      context,
                      controller,
                      currentTrack,
                    ),
                    'source' => showSongSourcePicker(
                      context,
                      controller,
                      currentTrack,
                    ),
                    'comments' => _openComments(context, currentTrack),
                    _ => _openLyrics(context),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'playlist',
                      child: Text(strings.addToPlaylist),
                    ),
                    if (controller.canSwitchSongSource(currentTrack))
                      PopupMenuItem(
                        key: const Key('player-switch-source'),
                        value: 'source',
                        child: Text(strings.isZh ? '切换来源' : 'Choose source'),
                      ),
                    PopupMenuItem(
                      key: const ValueKey('player-comments'),
                      value: 'comments',
                      child: Text(strings.isZh ? '歌曲热评' : 'Song comments'),
                    ),
                    PopupMenuItem(
                      value: 'lyrics',
                      child: Text(strings.isZh ? '完整歌词' : 'Full lyrics'),
                    ),
                  ],
                ),
            ],
          ),
          body: Builder(
            builder: (bodyContext) => _PlayerBackdrop(
              controller: controller,
              paint: !rail,
              child: SafeArea(
                child: StreamBuilder<MediaItem?>(
                  stream: controller.mediaItemStream,
                  initialData: controller.audioHandler.mediaItem.value,
                  builder: (context, mediaSnapshot) {
                    final item = mediaSnapshot.data;
                    if (item == null) {
                      return Center(child: Text(strings.nothingPlaying));
                    }
                    return StreamBuilder<PlaybackState>(
                      stream: controller.playbackStateStream,
                      initialData: controller.audioHandler.playbackState.value,
                      builder: (context, stateSnapshot) {
                        final state = stateSnapshot.data ?? PlaybackState();
                        final duration = item.duration ?? Duration.zero;
                        return SwipeToSkip(
                          key: const ValueKey('player-swipe-area'),
                          onNext: controller.next,
                          onPrevious: controller.previous,
                          onDrag: _disc.drag,
                          onSettle: _disc.settle,
                          child: _AdaptivePlayerBody(
                            controller: controller,
                            swipe: _disc,
                            neighbor: _neighborSlab,
                            contentOrigin: Offset(
                              MediaQuery.paddingOf(bodyContext).left,
                              MediaQuery.paddingOf(bodyContext).top,
                            ),
                            lyrics: _LyricsPanel(
                              controller: controller,
                              fillsAvailable: true,
                            ),
                            preview: _LyricsPreview(controller: controller),
                            header: [
                              _Artwork(
                                uri:
                                    item.artUri ?? controller.currentArtworkUri,
                                maxWidth:
                                    MediaQuery.displayFeaturesOf(context).any(
                                      (f) =>
                                          f.state ==
                                              ui
                                                  .DisplayFeatureState
                                                  .postureHalfOpened &&
                                          f.bounds.width > f.bounds.height,
                                    )
                                    ? 120
                                    : null,
                                controller: controller,
                                playing: state.playing,
                                cueing: _cueing,
                              ),
                              const SizedBox(height: 18),
                              _SongInfo(
                                title: item.title,
                                artist: item.artist ?? '',
                                favorite: currentTrack == null
                                    ? null
                                    : controller.isFavorite(currentTrack),
                                onFavorite: currentTrack == null
                                    ? null
                                    : () => controller.toggleFavorite(
                                        currentTrack,
                                      ),
                              ),
                            ],
                            controls: [
                              const SizedBox(height: 8),
                              PlayerPositionSlider(
                                key: ValueKey('player-position-${item.id}'),
                                trackId: item.id,
                                controller: controller,
                                duration: duration,
                                bufferedPosition: state.bufferedPosition,
                              ),
                              const SizedBox(height: 6),
                              _PlaybackControls(
                                controller: controller,
                                playing: state.playing || _cueing,
                                onToggle: () => _togglePlayPause(state.playing),
                              ),
                            ],
                          ),
                        );
                      },
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

/// Use the safe window's available space, including after a fold or split-view
/// resize. The route and its audio controller stay mounted across both layouts.
class _AdaptivePlayerBody extends StatefulWidget {
  const _AdaptivePlayerBody({
    required this.controller,
    required this.swipe,
    required this.neighbor,
    required this.contentOrigin,
    required this.header,
    required this.controls,
    required this.preview,
    required this.lyrics,
  });

  final MusicController controller;

  /// A horizontal drag moves the whole record-and-title slab with the
  /// finger, as the next song's slides in beside it.
  final _DiscSwipe swipe;
  final Widget? Function(BuildContext context, int step) neighbor;
  final Offset contentOrigin;
  final List<Widget> header;
  final List<Widget> controls;
  final Widget preview;
  final Widget lyrics;

  @override
  State<_AdaptivePlayerBody> createState() => _AdaptivePlayerBodyState();
}

class _AdaptivePlayerBodyState extends State<_AdaptivePlayerBody> {
  bool _queue = false;

  Widget _details(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return Column(
      children: [
        // The system's sliding switch, as Music uses between lyrics and
        // up next; it reads as one control instead of two outlined buttons.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Builder(
            builder: (context) {
              final colors = Theme.of(context).colorScheme;
              Widget segment(String text) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
              return CupertinoSlidingSegmentedControl<bool>(
                key: const ValueKey('player-details-switch'),
                groupValue: _queue,
                backgroundColor: colors.onSurface.withValues(alpha: .08),
                thumbColor: colors.surface.withValues(alpha: .9),
                children: {
                  false: segment(zh ? '歌词' : 'Lyrics'),
                  true: segment(zh ? '待播' : 'Up next'),
                },
                onValueChanged: (value) =>
                    setState(() => _queue = value ?? false),
              );
            },
          ),
        ),
        Expanded(
          child: ClipRect(
            key: const ValueKey('player-expanded-lyrics'),
            child: _queue
                ? PlaybackQueue(controller: widget.controller, embedded: true)
                : widget.lyrics,
          ),
        ),
      ],
    );
  }

  /// The part of the page that changes with the song, following the finger.
  /// [height] is what the whole stack may take, for sizing the record;
  /// [fill] fixes the slab's own height so spacers inside it can spread
  /// the record, title and lyric preview over it.
  Widget _slab(List<Widget> parts, {double? height, double? fill}) {
    Widget frame(Widget child) => height == null
        ? child
        : MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: Size(MediaQuery.sizeOf(context).width, height)),
            child: child,
          );
    return _DiscCarousel(
      swipe: widget.swipe,
      neighbor: (context, step) {
        final slab = widget.neighbor(context, step);
        return slab == null
            ? null
            : frame(_SwipingScope(swiping: true, child: slab));
      },
      builder: (context, swiping) => frame(
        _SwipingScope(
          swiping: swiping,
          child: SizedBox(
            height: fill,
            child: Column(
              mainAxisSize: fill == null ? MainAxisSize.min : MainAxisSize.max,
              children: parts,
            ),
          ),
        ),
      ),
    );
  }

  Widget _deck() => ListView(
    key: const PageStorageKey('player-expanded-scroll'),
    padding: const EdgeInsets.symmetric(
      horizontal: MusicUi.pagePadding,
      vertical: 8,
    ),
    children: [_slab(widget.header), ...widget.controls],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final paneWidth = 320 * scale.clamp(1.0, 1.4);
        const gap = 24.0;
        // With the status bar in a side strip nothing sits above the record;
        // give it the breathing room a title bar used to.
        final padding = EdgeInsets.fromLTRB(
          MusicUi.pagePadding,
          MediaQuery.paddingOf(context).top < 8 ? 16 : 4,
          MusicUi.pagePadding,
          12,
        );
        final bounds = Offset.zero & constraints.biggest;
        final folds = MediaQuery.displayFeaturesOf(context)
            .where((f) => f.state == ui.DisplayFeatureState.postureHalfOpened)
            .map((f) => f.bounds.shift(-widget.contentOrigin).intersect(bounds))
            .where((r) => !r.isEmpty);
        for (final fold in folds) {
          final horizontal = fold.width > fold.height;
          final before = horizontal ? fold.top : fold.left;
          final after = horizontal
              ? constraints.maxHeight - fold.bottom
              : constraints.maxWidth - fold.right;
          // Both regions must have room for usable controls. Tiny split windows
          // fall back to a single scrollable surface on the larger side.
          final minimum = horizontal ? 160.0 : 240.0;
          if (before >= minimum && after >= minimum) {
            final details = Padding(
              padding: padding.copyWith(bottom: 0),
              child: _details(context),
            );
            return Flex(
              key: const ValueKey('player-fold-layout'),
              direction: horizontal ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: horizontal ? null : before,
                  height: horizontal ? before : null,
                  child: horizontal ? details : _deck(),
                ),
                SizedBox(
                  width: horizontal ? null : fold.width,
                  height: horizontal ? fold.height : null,
                ),
                Expanded(child: horizontal ? _deck() : details),
              ],
            );
          }
          final useBefore = before >= after;
          return Padding(
            padding: horizontal
                ? EdgeInsets.only(
                    top: useBefore ? 0 : fold.bottom,
                    bottom: useBefore ? constraints.maxHeight - fold.top : 0,
                  )
                : EdgeInsets.only(
                    left: useBefore ? 0 : fold.right,
                    right: useBefore ? constraints.maxWidth - fold.left : 0,
                  ),
            child: ListView(
              key: const PageStorageKey('player-compact-scroll'),
              padding: padding,
              children: [
                _slab([...widget.header, widget.preview]),
                ...widget.controls,
              ],
            ),
          );
        }
        if (constraints.maxWidth >= 520 && constraints.maxHeight < 480) {
          return Padding(
            key: const ValueKey('player-short-layout'),
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ListView(children: [_slab(widget.header)])),
                const SizedBox(width: 16),
                Expanded(
                  child: ListView(
                    key: const PageStorageKey('player-compact-scroll'),
                    children: [widget.preview, ...widget.controls],
                  ),
                ),
              ],
            ),
          );
        }
        final wide =
            constraints.maxWidth >= paneWidth * 2 + gap + padding.horizontal;
        if (!wide) {
          // Spread record, lyric preview and controls over a tall window
          // instead of leaving the bottom empty. The record is sized from the
          // height actually available here, not the window, so an open inner
          // display held upright still fits without scrolling.
          final available = constraints.maxHeight - padding.vertical;
          // The slider and buttons take about this much; the slab gets the
          // rest and spreads the record, title and lyric preview over it.
          // Too short for that and it falls back to its natural height.
          final controlsHeight = 140 + 24 * scale;
          final record = (available - 400).clamp(
            150.0,
            MusicUi.playerCoverMaxWidth,
          );
          final natural =
              record + 18 + 60 * scale + _lyricsPreviewHeight(context) + 80;
          final fill = available - controlsHeight >= natural
              ? available - controlsHeight
              : null;
          final gap = fill == null
              ? const SizedBox(height: 16)
              : const Spacer();
          // A minimum height, not a fill sliver: the latter measures the
          // record's intrinsic height at full width and overshoots.
          return SingleChildScrollView(
            key: const PageStorageKey('player-compact-scroll'),
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(0, available)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _slab(
                    [...widget.header, gap, widget.preview, gap],
                    height: available,
                    fill: fill,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.controls,
                  ),
                ],
              ),
            ),
          );
        }
        return Padding(
          key: const ValueKey('player-expanded-layout'),
          padding: const EdgeInsets.only(
            top: 4,
            bottom: 12,
            right: MusicUi.pagePadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _deck()),
              const SizedBox(width: gap),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom,
                  ),
                  child: _details(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The record on its deck. The cover is the label.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.uri,
    required this.controller,
    required this.playing,
    required this.cueing,
    this.maxWidth,
  });

  final Uri? uri;
  final MusicController controller;
  final bool playing, cueing;

  /// The Mac window has room for a larger deck than a phone.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artUri = uri;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(AppIcons.record, size: 44, color: colors.primary),
      ),
    );
    final label = artUri == null
        ? placeholder
        : Image(
            image: artworkImageProvider(artUri),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Sized so the whole player fits one screen without scrolling.
          // The compact player hands in the height left for the whole stack.
          // Title, lyric preview, slider, controls and their gaps take about
          // 400pt; the record gets the rest, so every window fits on one
          // screen and a tall one still shows a big record.
          maxWidth:
              maxWidth ??
              (MediaQuery.sizeOf(context).height - 400).clamp(
                150.0,
                MusicUi.playerCoverMaxWidth,
              ),
        ),
        // The arm does not follow the song: the position updates several
        // times a second, and redrawing the deck for each kept the phone
        // busy for as long as music played. It lifts off while the record is
        // being changed.
        child: Turntable(
          playing: playing,
          armDown: (playing || cueing) && !_SwipingScope.of(context),
          label: label,
        ),
      ),
    );
  }
}

/// What the finger is doing to the record, passed from the page's swipe area
/// to the deck.
/// Whether the slab is mid-swipe, for the arm that lifts while it moves.
class _SwipingScope extends InheritedWidget {
  const _SwipingScope({required this.swiping, required super.child});
  final bool swiping;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SwipingScope>()?.swiping ??
      false;
  @override
  bool updateShouldNotify(_SwipingScope oldWidget) =>
      swiping != oldWidget.swiping;
}

/// The queue item before (-1) or after (1) the playing one; null in shuffle
/// or when there is nothing else to show.
MediaItem? _neighborItem(MusicController controller, int step) {
  if (controller.playbackMode == PlaybackMode.shuffle) return null;
  final queue = controller.audioHandler.queue.value;
  final id = controller.audioHandler.mediaItem.value?.id;
  final index = queue.indexWhere((item) => item.id == id);
  if (index < 0 || queue.length < 2) return null;
  return queue[(index + step) % queue.length];
}

class _DiscSwipe extends ChangeNotifier {
  double dx = 0;
  bool dragging = false;

  /// Set for one notification when a drag ends: -1 next, 1 previous, 0 back.
  int? settled;

  void drag(double distance) {
    dx = distance;
    dragging = true;
    settled = null;
    notifyListeners();
  }

  void settle(int direction) {
    dragging = false;
    settled = direction;
    notifyListeners();
    settled = null;
  }
}

/// Changing records: the deck follows the finger, the neighbouring record
/// comes in from the side, and on release one of them takes the centre.
class _DiscCarousel extends StatefulWidget {
  const _DiscCarousel({
    required this.swipe,
    required this.neighbor,
    required this.builder,
  });

  final _DiscSwipe swipe;
  final Widget? Function(BuildContext context, int step) neighbor;
  final Widget Function(BuildContext context, bool swiping) builder;

  @override
  State<_DiscCarousel> createState() => _DiscCarouselState();
}

class _DiscCarouselState extends State<_DiscCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _x;
  bool _swiping = false;
  double _width = 400;

  @override
  void initState() {
    super.initState();
    _x = AnimationController.unbounded(vsync: this);
    widget.swipe.addListener(_follow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _width = MediaQuery.sizeOf(context).width;
  }

  Future<void> _follow() async {
    final swipe = widget.swipe;
    if (swipe.dragging) {
      _x.value = swipe.dx;
      if (!_swiping) setState(() => _swiping = true);
      return;
    }
    final direction = swipe.settled ?? 0;
    try {
      if (direction == 0) {
        await _x.animateTo(
          0,
          duration: MusicMotion.base,
          curve: MusicMotion.standard,
        );
      } else {
        // The old record leaves and the neighbour arrives at the centre,
        // where the real deck then takes its place.
        await _x.animateTo(
          direction * _width,
          duration: MusicMotion.base,
          curve: Curves.easeOutCubic,
        );
        _x.value = 0;
      }
    } on TickerCanceled {
      return;
    }
    if (mounted && !widget.swipe.dragging) setState(() => _swiping = false);
  }

  @override
  void dispose() {
    widget.swipe.removeListener(_follow);
    _x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.builder(context, _swiping);
    if (!_swiping) return deck;
    // The two neighbouring decks are built once per swipe and only moved
    // afterwards, so following the finger costs no rebuilds.
    final neighbours = {
      for (final step in const [-1, 1])
        if (widget.neighbor(context, step) case final slab?)
          step: RepaintBoundary(child: slab),
    };
    return AnimatedBuilder(
      animation: _x,
      builder: (context, deck) {
        final x = _x.value;
        final step = x < 0 ? 1 : -1;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (x != 0)
              Transform.translate(
                offset: Offset(x + step * _width, 0),
                child: neighbours[step],
              ),
            Transform.translate(offset: Offset(x, 0), child: deck),
          ],
        );
      },
      child: RepaintBoundary(child: deck),
    );
  }
}

ImageProvider artworkImageProvider(Uri uri) => uri.isScheme('file')
    ? FileImage(File(uri.toFilePath()))
    : NetworkImage(uri.toString());

/// Lights the page from the playing cover and keeps that light while the
/// next cover loads.
class _PlayerBackdrop extends StatefulWidget {
  const _PlayerBackdrop({
    required this.controller,
    required this.child,
    this.closeOnSwipe = true,
    this.paint = true,
  });

  final MusicController controller;
  final Widget child;

  /// With a system side strip the light is painted once, under the whole
  /// window, by the scaffold; the content copy then only keeps the gesture.
  final bool closeOnSwipe, paint;

  @override
  State<_PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<_PlayerBackdrop> {
  Uri? _uri;
  ArtworkPalette? _palette;

  Future<void> _read(Uri? uri) async {
    if (uri == _uri) return;
    _uri = uri;
    // This is called by the media StreamBuilder; even clearing a missing cover
    // must finish asynchronously before notifying its ancestor.
    final palette = await (uri == null
        ? Future<ArtworkPalette?>.value()
        : ArtworkPalette.of(artworkImageProvider(uri)));
    if (mounted && uri == _uri) setState(() => _palette = palette);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (!widget.paint) {
      return widget.closeOnSwipe
          ? _SwipeDownToClose(child: widget.child)
          : widget.child;
    }
    return StreamBuilder<MediaItem?>(
      stream: widget.controller.mediaItemStream,
      initialData: widget.controller.audioHandler.mediaItem.value,
      builder: (context, snapshot) {
        _read(snapshot.data?.artUri ?? widget.controller.currentArtworkUri);
        // The light wanders only while music plays; a paused page is still.
        return StreamBuilder<PlaybackState>(
          stream: widget.controller.playbackStateStream,
          initialData: widget.controller.audioHandler.playbackState.value,
          builder: (context, state) => AmbientBackdrop(
            glow: _palette?.glow(brightness),
            shade: _palette?.shade(brightness),
            drift: state.data?.playing ?? false,
            child: widget.closeOnSwipe
                ? _SwipeDownToClose(child: widget.child)
                : widget.child,
          ),
        );
      },
    );
  }
}

/// Opens the comments for the playing song from any page.
Future<void> openSongCommentsPage(
  BuildContext context,
  MusicController controller,
) {
  final track = controller.currentTrack;
  if (track == null) return Future.value();
  final query = SongCommentQuery.fromTrack(
    track,
    original: controller.originalSongForTrack(track),
    candidate: controller.selectedSongSource(track),
    lyrics: controller.currentLyrics,
  );
  return Navigator.of(context).push<void>(
    AppPageRoute<void>(builder: (_) => SongCommentsPage(query: query)),
  );
}

/// Opens the full lyrics page, from the player or straight from the
/// now-playing bar on any page.
Future<void> openLyricsPage(BuildContext context, MusicController controller) =>
    Navigator.of(context).push<void>(
      AppPageRoute(
        settings: const RouteSettings(name: 'lyrics'),
        builder: (_) => _LyricsDetailPage(controller: controller),
      ),
    );

class _LyricsDetailPage extends StatelessWidget {
  const _LyricsDetailPage({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentTrack = controller.currentTrack;
        final strings = AppStringsScope.of(context);
        final rail = DuoScaffold.usesSystemRail(context);
        return DuoScaffold(
          extraActions: [
            DuoRailItem(
              icon: CupertinoIcons.music_note_list,
              label: strings.isZh ? '当前队列' : 'Play queue',
              onPressed: () => showPlaybackQueue(context, controller),
            ),
          ],
          extendBodyBehindAppBar: true,
          background: _PlayerBackdrop(
            controller: controller,
            closeOnSwipe: false,
            child: const SizedBox.expand(),
          ),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(strings.lyrics),
            actions: [
              if (currentTrack != null) ...[
                IconButton(
                  tooltip: controller.isFavorite(currentTrack)
                      ? strings.removeFromFavorites
                      : strings.addToFavorites,
                  onPressed: () => controller.toggleFavorite(currentTrack),
                  icon: Icon(
                    controller.isFavorite(currentTrack)
                        ? AppIcons.heartFill
                        : AppIcons.heart,
                  ),
                ),
                IconButton(
                  tooltip: strings.addToPlaylist,
                  onPressed: () =>
                      showAddToPlaylistSheet(context, controller, currentTrack),
                  icon: const Icon(AppIcons.playlistAdd),
                ),
              ],
            ],
          ),
          body: _PlayerBackdrop(
            controller: controller,
            paint: !rail,
            child: SafeArea(
              child: StreamBuilder<MediaItem?>(
                stream: controller.mediaItemStream,
                initialData: controller.audioHandler.mediaItem.value,
                builder: (context, mediaSnapshot) {
                  final item = mediaSnapshot.data;
                  if (item == null) {
                    return Center(child: Text(strings.nothingPlaying));
                  }
                  return StreamBuilder<PlaybackState>(
                    stream: controller.playbackStateStream,
                    initialData: controller.audioHandler.playbackState.value,
                    builder: (context, stateSnapshot) {
                      final state = stateSnapshot.data ?? PlaybackState();
                      final duration = item.duration ?? Duration.zero;
                      return SwipeToSkip(
                        key: const ValueKey('lyrics-swipe-area'),
                        onNext: controller.next,
                        onPrevious: controller.previous,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final scale =
                                (MediaQuery.textScalerOf(context).scale(16) /
                                        16)
                                    .clamp(1.0, double.infinity);
                            // A pinned video or a split window may leave less
                            // height than the title and playback controls need.
                            // Keep a usable lyric viewport and let the whole
                            // page scroll instead of overflowing the controls.
                            return SingleChildScrollView(
                              key: const PageStorageKey('lyrics-page-scroll'),
                              child: SizedBox(
                                height: constraints.maxHeight.clamp(
                                  420 * scale,
                                  double.infinity,
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        8,
                                        24,
                                        12,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: MusicType.masthead(
                                              context,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.artist ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: _LyricsPanel(
                                        controller: controller,
                                        fillsAvailable: true,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        8,
                                        24,
                                        0,
                                      ),
                                      child: PlayerPositionSlider(
                                        key: ValueKey(
                                          'lyrics-position-${item.id}',
                                        ),
                                        trackId: item.id,
                                        controller: controller,
                                        duration: duration,
                                        bufferedPosition:
                                            state.bufferedPosition,
                                      ),
                                    ),
                                    _PlaybackControls(
                                      controller: controller,
                                      playing: state.playing,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class PlayerPositionSlider extends StatefulWidget {
  const PlayerPositionSlider({
    super.key,
    required this.controller,
    required this.trackId,
    required this.duration,
    required this.bufferedPosition,
  });

  final MusicController controller;
  final String trackId;
  final Duration duration;
  final Duration bufferedPosition;

  @override
  State<PlayerPositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PlayerPositionSlider> {
  bool _dragging = false;
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.controller.positionStream,
      initialData: widget.controller.audioHandler.currentPosition,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        final max = widget.duration.inMilliseconds.toDouble();
        final liveValue = max <= 0
            ? 0.0
            : position.inMilliseconds
                  .clamp(0, widget.duration.inMilliseconds)
                  .toDouble();
        final value = ((_dragging ? _dragValue : null) ?? liveValue)
            .clamp(0.0, max <= 0 ? 1.0 : max)
            .toDouble();
        final displayPosition = Duration(milliseconds: value.round());
        return Column(
          children: [
            ValueListenableBuilder(
              valueListenable: widget.controller.cacheProgressForId(
                widget.trackId,
              ),
              builder: (context, progress, _) => SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  thumbColor: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: DesktopSliderOverlay(
                  child: Slider(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    value: value,
                    max: max <= 0 ? 1 : max,
                    secondaryTrackValue: max <= 0
                        ? 0
                        : progress.offline
                        ? max
                        : widget.bufferedPosition.inMilliseconds
                              .clamp(0, max)
                              .toDouble(),
                    secondaryActiveColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .28),
                    inactiveColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .08),
                    onChanged: max <= 0
                        ? null
                        : (value) {
                            setState(() {
                              _dragging = true;
                              _dragValue = value;
                            });
                          },
                    onChangeStart: max <= 0
                        ? null
                        : (value) {
                            setState(() {
                              _dragging = true;
                              _dragValue = value;
                            });
                          },
                    onChangeEnd: max <= 0
                        ? null
                        : (value) {
                            setState(() {
                              _dragging = false;
                              _dragValue = null;
                            });
                            widget.controller.seek(
                              Duration(milliseconds: value.round()),
                            );
                          },
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _formatDuration(displayPosition),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MusicType.readout(context),
                  ),
                ),
                Expanded(
                  child: Text(
                    _formatDuration(widget.duration),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MusicType.readout(context),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.controller,
    required this.playing,
    this.onToggle,
  });

  final MusicController controller;
  final bool playing;

  /// Replaces the plain toggle where the deck is on screen to cue it first.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    // One row, evenly spread, the way the system's players lay it out: play
    // in the middle, skip either side, mode and queue at the ends as quiet
    // glyphs rather than a row of five rings.
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        // Narrower than the five targets (a fold pane) scales the row down
        // as one piece instead of overflowing.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: constraints.maxWidth.clamp(264.0, 380.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PlainControl(
                  tooltip: _modeTooltip(strings, controller.playbackMode),
                  onPressed: controller.cyclePlaybackMode,
                  icon: _modeIcon(controller.playbackMode),
                  size: 24,
                ),
                _PlainControl(
                  tooltip: strings.previous,
                  onPressed: controller.previous,
                  icon: AppIcons.previous,
                  size: 40,
                ),
                PlayPauseButton(
                  playing: playing,
                  tooltip: playing ? strings.pause : strings.play,
                  onPressed: onToggle ?? controller.togglePlayPause,
                  size: 72,
                ),
                _PlainControl(
                  tooltip: strings.next,
                  onPressed: controller.next,
                  icon: AppIcons.next,
                  size: 40,
                ),
                _PlainControl(
                  key: const ValueKey('player-queue'),
                  tooltip: strings.isZh ? '当前队列' : 'Play queue',
                  onPressed: () => showPlaybackQueue(context, controller),
                  icon: AppIcons.queue,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare glyph with a 48pt touch target that dips when pressed.
class _PlainControl extends StatelessWidget {
  const _PlainControl({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: Pressable(
          onTap: onPressed,
          pressedScale: .88,
          child: SizedBox.square(
            dimension: math.max(48, size + 8),
            child: Icon(
              icon,
              size: size,
              color: colors.onSurface.withValues(alpha: size < 32 ? .72 : 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title and artist, left-aligned under the record, with the heart at the
/// end of the line the way the system and QQ Music set it.
class _SongInfo extends StatelessWidget {
  const _SongInfo({
    required this.title,
    required this.artist,
    this.favorite,
    this.onFavorite,
  });

  final String title;
  final String artist;

  /// Null hides the heart but keeps its room, so neighbouring slabs line up.
  final bool? favorite;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = AppStringsScope.of(context);
    final liked = favorite ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MusicType.masthead(context, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (favorite == null)
          const SizedBox(width: 48, height: 48)
        else
          _PlainControl(
            key: const ValueKey('player-favorite'),
            tooltip: liked
                ? strings.removeFromFavorites
                : strings.addToFavorites,
            onPressed: onFavorite,
            icon: liked ? AppIcons.heartFill : AppIcons.heart,
            size: 28,
          ),
      ],
    );
  }
}

class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('lyrics-preview'),
      borderRadius: BorderRadius.circular(MusicUi.radius),
      onTap: () => Navigator.of(context).push<void>(
        AppPageRoute(
          builder: (context) => _LyricsDetailPage(controller: controller),
        ),
      ),
      child: Container(
        width: double.infinity,
        height: _lyricsPreviewHeight(context),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: _LyricsPreviewContent(controller: controller),
      ),
    );
  }
}

double _lyricsPreviewHeight(BuildContext context) {
  final style = Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 16);
  final painter = TextPainter(
    text: TextSpan(text: '歌词', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = (painter.height + 4) * 3 + 20;
  painter.dispose();
  return height < 100 ? 100 : height;
}

class _LyricsPreviewContent extends StatelessWidget {
  const _LyricsPreviewContent({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lyrics = controller.currentLyrics;
    if (controller.isLoadingMetadata &&
        lyrics.isEmpty &&
        controller.currentMetadata.lyricsStatus != LyricsStatus.notFound) {
      return const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (lyrics.isEmpty) {
      return Center(child: _MissingLyricsContent(controller: controller));
    }
    return StreamBuilder<Duration>(
      stream: controller.positionStream,
      initialData: controller.audioHandler.currentPosition,
      builder: (context, snapshot) {
        final synchronized = _hasTimedLyrics(lyrics);
        final rows = synchronized
            ? _previewLyricRows(
                lyrics,
                _activeLyricIndex(lyrics, snapshot.data ?? Duration.zero),
              )
            : [
                for (final line in lyrics.take(3))
                  _PreviewLyricRow(line: line, active: false),
              ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  row.line.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: row.active ? 16 : 14,
                    color: row.active
                        ? colors.primary
                        : colors.onSurfaceVariant.withValues(alpha: .7),
                    fontWeight: row.active ? FontWeight.w700 : FontWeight.w400,
                    shadows: row.active && MusicTokens.of(context).neon
                        ? [
                            Shadow(
                              color: colors.primaryContainer.withValues(
                                alpha: .75,
                              ),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PreviewLyricRow {
  const _PreviewLyricRow({required this.line, required this.active});

  final LyricLine line;
  final bool active;
}

class _MissingLyricsContent extends StatefulWidget {
  const _MissingLyricsContent({required this.controller});

  final MusicController controller;

  @override
  State<_MissingLyricsContent> createState() => _MissingLyricsContentState();
}

class _MissingLyricsContentState extends State<_MissingLyricsContent> {
  String? _autoRequestedTrackId;

  @override
  void didUpdateWidget(covariant _MissingLyricsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.currentTrack?.id !=
        widget.controller.currentTrack?.id) {
      _autoRequestedTrackId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAutoRecover();
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final loading = widget.controller.isLoadingMetadata;
    final failed =
        widget.controller.metadataError != null ||
        widget.controller.currentMetadata.lyricsStatus == LyricsStatus.failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          failed
              ? strings.lyricsLoadFailed
              : widget.controller.currentMetadata.lyricsStatus ==
                    LyricsStatus.unknown
              ? strings.fetchingLyrics
              : strings.noLyrics,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (failed) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading
                ? null
                : () => widget.controller.recoverMetadataForCurrentTrack(
                    bypassLyricsMiss: true,
                  ),
            icon: loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.refresh),
            label: Text(loading ? strings.fetchingLyrics : strings.retryLyrics),
          ),
        ],
      ],
    );
  }

  void _scheduleAutoRecover() {
    final trackId = widget.controller.currentTrack?.id;
    if (trackId == null ||
        _autoRequestedTrackId == trackId ||
        widget.controller.currentLyrics.isNotEmpty ||
        widget.controller.isLoadingMetadata ||
        widget.controller.metadataError != null ||
        widget.controller.currentMetadata.lyricsStatus !=
            LyricsStatus.unknown) {
      return;
    }
    _autoRequestedTrackId = trackId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.autoRecoverMetadataForCurrentTrack();
      }
    });
  }
}

List<_PreviewLyricRow> _previewLyricRows(
  List<LyricLine> lyrics,
  int activeIndex,
) {
  final safeActive = activeIndex.clamp(0, lyrics.length - 1);
  final start = (safeActive - 1).clamp(0, lyrics.length - 1);
  final end = (start + 3).clamp(0, lyrics.length);
  final adjustedStart = (end - 3).clamp(0, start);
  return [
    for (var index = adjustedStart; index < end; index += 1)
      _PreviewLyricRow(line: lyrics[index], active: index == safeActive),
  ];
}

class _LyricsPanel extends StatefulWidget {
  const _LyricsPanel({
    super.key,
    required this.controller,
    this.fillsAvailable = false,
    this.positionStream,
  });

  final MusicController controller;
  final bool fillsAvailable;
  final Stream<Duration>? positionStream;

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  static const _itemExtent = 48.0;

  var _scrollController = ScrollController();
  final _followState = LyricFollowState();
  bool _userScrolling = false;
  int? _previewIndex;
  int _followGeneration = 0;
  List<LyricLine>? _followLyrics;

  MusicController get controller => widget.controller;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = controller.currentLyrics;
    if (controller.isLoadingMetadata &&
        lyrics.isEmpty &&
        controller.currentMetadata.lyricsStatus != LyricsStatus.notFound) {
      return _wrapContent(const Center(child: CircularProgressIndicator()));
    }
    if (lyrics.isEmpty) {
      return _wrapContent(
        Center(child: _MissingLyricsContent(controller: controller)),
      );
    }
    if (!_hasTimedLyrics(lyrics)) {
      return _wrapContent(
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: lyrics.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              lyrics[index].text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return _wrapContent(
      LayoutBuilder(
        builder: (context, constraints) {
          final verticalPadding = ((constraints.maxHeight - _itemExtent) / 2)
              .clamp(0.0, 1000.0);
          return StreamBuilder<Duration>(
            stream: widget.positionStream ?? controller.positionStream,
            initialData: controller.audioHandler.currentPosition,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final activeIndex = _activeLyricIndex(lyrics, position);
              _resetFollowStateIfLyricsChanged(lyrics, activeIndex);
              if (!_userScrolling) {
                _previewIndex = activeIndex;
              }
              _maybeFollow(activeIndex);
              final previewIndex = (_previewIndex ?? activeIndex).clamp(
                0,
                lyrics.length - 1,
              );
              return Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification ||
                          notification is UserScrollNotification) {
                        _userScrolling = true;
                        _followState.reset();
                        _updatePreviewIndex(lyrics.length);
                      }
                      if (notification is ScrollEndNotification &&
                          _userScrolling) {
                        _scheduleFollowResume();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(vertical: verticalPadding),
                      itemExtent: _itemExtent,
                      itemCount: lyrics.length,
                      itemBuilder: (context, index) {
                        final line = lyrics[index];
                        final active = index == activeIndex;
                        return InkWell(
                          onTap: () {
                            _userScrolling = false;
                            _previewIndex = index;
                            _followState.reset();
                            controller.seekToLyricLine(line);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Center(
                              child: Text(
                                line.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: active
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      fontWeight: active
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _CenterLyricGuide(
                    line: lyrics[previewIndex],
                    emphasized: _userScrolling,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _wrapContent(Widget child) {
    if (widget.fillsAvailable) {
      return child;
    }
    return SizedBox(height: 280, child: child);
  }

  void _maybeFollow(int activeIndex) {
    if (_userScrolling || activeIndex < 0 || !_scrollController.hasClients) {
      return;
    }
    final target = (activeIndex * _itemExtent)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    if (!_followState.shouldFollow(activeIndex, target)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        target.clamp(0, _scrollController.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _resetFollowStateIfLyricsChanged(
    List<LyricLine> lyrics,
    int activeIndex,
  ) {
    if (!identical(_followLyrics, lyrics)) {
      _followLyrics = lyrics;
      _followState.reset();
      if (!_scrollController.hasClients) {
        _scrollController.dispose();
        _scrollController = ScrollController(
          initialScrollOffset: activeIndex * _itemExtent,
        );
      }
    }
  }

  void _updatePreviewIndex(int lyricsLength) {
    if (!_scrollController.hasClients) {
      return;
    }
    final next = (_scrollController.offset / _itemExtent).round().clamp(
      0,
      lyricsLength - 1,
    );
    if (_previewIndex != next && mounted) {
      setState(() {
        _previewIndex = next;
      });
    }
  }

  void _scheduleFollowResume() {
    final generation = ++_followGeneration;
    // 手动滚动只浏览歌词和中线时间；短暂空闲后再恢复随播放进度自动跟随。
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && generation == _followGeneration) {
        setState(() {
          _followState.reset();
          _userScrolling = false;
        });
      }
    });
  }
}

class LyricFollowState {
  int? _lastIndex;
  double? _lastTargetOffset;

  bool shouldFollow(int index, double targetOffset) {
    // positionStream 更新很密；同一句同一偏移不重复 animate，避免歌词页抖动。
    final sameIndex = _lastIndex == index;
    final sameTarget =
        _lastTargetOffset != null &&
        (targetOffset - _lastTargetOffset!).abs() < 1;
    if (sameIndex && sameTarget) {
      return false;
    }
    _lastIndex = index;
    _lastTargetOffset = targetOffset;
    return true;
  }

  void reset() {
    _lastIndex = null;
    _lastTargetOffset = null;
  }
}

class _CenterLyricGuide extends StatelessWidget {
  const _CenterLyricGuide({required this.line, required this.emphasized});

  final LyricLine line;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lineAlpha = emphasized ? 0.74 : 0.22;
    final chipAlpha = emphasized ? 0.92 : 0.52;
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Divider(color: colors.primary.withValues(alpha: lineAlpha)),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(right: 18),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: chipAlpha),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _formatDuration(line.time),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onPrimaryContainer.withValues(
                    alpha: emphasized ? 1 : 0.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _activeLyricIndex(List<LyricLine> lyrics, Duration position) {
  var active = 0;
  for (var index = 0; index < lyrics.length; index += 1) {
    if (lyrics[index].time <= position) {
      active = index;
    } else {
      break;
    }
  }
  return active;
}

bool _hasTimedLyrics(List<LyricLine> lyrics) =>
    lyrics.any((line) => line.time > Duration.zero);

IconData _modeIcon(PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.sequential => AppIcons.sequential,
    PlaybackMode.repeatOne => AppIcons.repeatOne,
    PlaybackMode.shuffle => AppIcons.shuffle,
  };
}

String _modeTooltip(AppStrings strings, PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.sequential => strings.modeSequential,
    PlaybackMode.repeatOne => strings.modeRepeatOne,
    PlaybackMode.shuffle => strings.modeShuffle,
  };
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = value.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

/// Pulling the page down from its top closes it, as it rose from the mini
/// player. Sideways swipes stay with song skipping.
class _SwipeDownToClose extends StatefulWidget {
  const _SwipeDownToClose({required this.child});

  final Widget child;

  @override
  State<_SwipeDownToClose> createState() => _SwipeDownToCloseState();
}

class _SwipeDownToCloseState extends State<_SwipeDownToClose> {
  Offset? _down;
  DateTime? _at;
  bool _atTop = true;

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollNotification>(
    onNotification: (n) {
      if (n.metrics.axis == Axis.vertical) _atTop = n.metrics.extentBefore <= 0;
      return false;
    },
    child: Listener(
      onPointerDown: (event) {
        _down = _atTop ? event.position : null;
        _at = DateTime.now();
      },
      onPointerCancel: (_) => _down = null,
      onPointerUp: (event) {
        final down = _down;
        _down = null;
        if (down == null || !_atTop) return;
        final delta = event.position - down;
        final quick =
            DateTime.now().difference(_at!) < const Duration(milliseconds: 600);
        if (delta.dy > 90 && delta.dy > delta.dx.abs() * 2 && quick) {
          Navigator.of(context).maybePop();
        }
      },
      child: Stack(
        children: [
          widget.child,
          // The left edge is the system's way back; it takes a sideways
          // drag before song skipping can.
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 22,
            child: GestureDetector(
              key: const ValueKey('player-edge-back'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) >= 0) {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class DesktopPlaybackModeButton extends StatelessWidget {
  const DesktopPlaybackModeButton({super.key, required this.controller});
  final MusicController controller;
  @override
  Widget build(BuildContext context) => DesktopToolButton(
    tooltip: _modeTooltip(AppStringsScope.of(context), controller.playbackMode),
    onPressed: controller.cyclePlaybackMode,
    icon: _modeIcon(controller.playbackMode),
    active: controller.playbackMode != PlaybackMode.sequential,
  );
}
