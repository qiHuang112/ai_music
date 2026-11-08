import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../application/song_cache_progress.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'desktop_home.dart';
import 'desktop_ui.dart';
import 'desktop_window.dart';
import 'music_thumbnail.dart';
import 'player_page.dart';
import 'design/app_icons.dart';

/// The Mac mini player, a copy of NetEase Cloud Music's. One window, two
/// heights (drag its bottom edge, and it snaps to the nearer):
///
/// * the strip, 336×52: × and □ stacked at the left, the cover, the song and
///   a progress hairline; under the pointer the song gives way to previous,
///   play and next. Like, bin, 词 and volume sit on the right.
/// * the square, 336×336: only the lyrics, or only the cover (词 switches),
///   until the pointer arrives; then a bar fades in at the top with the song
///   and at the foot with the controls and the progress.
///
/// The cover folds the square into the strip and opens the strip into the
/// square. × hides the window and music plays on; □ brings the full window
/// back. "…", or a right click anywhere, opens the song's menu. Dragging
/// anywhere that is not a control moves the window.
class DesktopMiniPlayer extends StatefulWidget {
  const DesktopMiniPlayer({
    super.key,
    required this.controller,
    required this.lyrics,
    required this.onLyricsButton,
    required this.onToggleShape,
    required this.onExpand,
    required this.onMenu,
  });

  final MusicController controller;

  /// What the square shows: the lyrics, or the cover.
  final bool lyrics;

  /// 词: opens the strip into the square with lyrics, or switches the
  /// square between lyrics and cover.
  final VoidCallback onLyricsButton;
  final VoidCallback onToggleShape, onExpand;

  /// Opens the song's menu at a point in the window.
  final ValueChanged<Offset> onMenu;

  @override
  State<DesktopMiniPlayer> createState() => _DesktopMiniPlayerState();
}

class _DesktopMiniPlayerState extends State<DesktopMiniPlayer> {
  bool _hovered = false, _volume = false;

  MusicController get controller => widget.controller;

  /// The bin: takes the playing song out of the queue and plays the next.
  Future<void> _removeCurrent(String id) async {
    if (controller.audioHandler.queue.value.length <= 1) return;
    await controller.next();
    await controller.removeQueueItems([id]);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.mediaItemStream,
    initialData: controller.audioHandler.mediaItem.value,
    builder: (context, media) => StreamBuilder<PlaybackState>(
      stream: controller.playbackStateStream,
      initialData: controller.audioHandler.playbackState.value,
      builder: (context, playback) {
        final item = media.data;
        final state = playback.data ?? PlaybackState();
        return DesktopNativeTooltips(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapUp: (details) =>
                widget.onMenu(details.globalPosition),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() {
                _hovered = false;
                _volume = false;
              }),
              child: Material(
                type: MaterialType.transparency,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxHeight >= 150
                      ? _square(context, item, state)
                      : _strip(context, item, state),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  /// The bars' and the strip's own color: the skin's glass, nearly solid.
  Color _bar(BuildContext context, double alpha) =>
      MusicTokens.of(context).glass.withValues(alpha: alpha);

  /// × above □ at the left edge, as NetEase stacks them.
  Widget _windowButtons(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TinyButton(
          key: const ValueKey('mini-close'),
          icon: AppIcons.close,
          tooltip: zh ? '关闭窗口（继续播放）' : 'Close (keeps playing)',
          onPressed: DesktopWindow.close,
        ),
        const SizedBox(height: 2),
        _TinyButton(
          key: const ValueKey('mini-expand'),
          icon: AppIcons.square,
          tooltip: zh ? '回到完整窗口（Esc）' : 'Full window (Esc)',
          onPressed: widget.onExpand,
        ),
      ],
    );
  }

  Widget _cover(
    BuildContext context,
    MediaItem? item,
    double size, {
    bool framed = false,
  }) {
    final zh = AppStringsScope.of(context).isZh;
    final square = framed;
    final thumbnail = MusicThumbnail(
      uri: item?.artUri ?? controller.currentArtworkUri,
      label: item?.title ?? '',
      size: size,
      radius: 3,
    );
    final label = square
        ? (zh ? '收起为迷你条' : 'Fold into the strip')
        : (zh ? '展开' : 'Open out');
    return DesktopTooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        onTap: widget.onToggleShape,
        child: DesktopHover(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const ValueKey('mini-cover'),
            onTap: widget.onToggleShape,
            child: AnimatedScale(
              scale: hovered ? 1.05 : 1,
              duration: DesktopUi.hover,
              child: framed
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: thumbnail,
                    )
                  : thumbnail,
            ),
          ),
        ),
      ),
    );
  }

  Widget _titles(BuildContext context, MediaItem? item, {bool center = false}) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final detail = [
      if ((item?.artist ?? '').isNotEmpty) item!.artist!,
      if ((item?.album ?? '').isNotEmpty) item!.album!,
    ].join(' -- ');
    return Column(
      key: const ValueKey('mini-titles'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          item?.title ?? strings.nothingPlaying,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5,
            height: 1.2,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              color: DesktopUi.muted(context),
            ),
          ),
      ],
    );
  }

  /// Previous, play and next, at NetEase's spacing.
  Widget _transport(BuildContext context, PlaybackState state) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('mini-transport'),
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopToolButton(
          icon: AppIcons.previous,
          tooltip: strings.isZh ? '上一首' : 'Previous',
          size: 26,
          iconSize: 21,
          color: colors.primary,
          onPressed: controller.previous,
        ),
        const SizedBox(width: 13),
        _PlayDot(
          key: const ValueKey('mini-play'),
          playing: state.playing,
          tooltip: state.playing ? strings.pause : strings.play,
          onPressed: controller.togglePlayPause,
        ),
        const SizedBox(width: 10),
        DesktopToolButton(
          icon: AppIcons.next,
          tooltip: strings.isZh ? '下一首' : 'Next',
          size: 26,
          iconSize: 21,
          color: colors.primary,
          onPressed: controller.next,
        ),
      ],
    );
  }

  /// Like, bin, 词 and volume, 30pt apart, in both shapes.
  Widget _actions(
    BuildContext context,
    MediaItem? item, {
    bool square = false,
  }) {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final colors = Theme.of(context).colorScheme;
    final track = controller.currentTrack;
    final favorite = track != null && controller.isFavorite(track);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopToolButton(
          icon: favorite ? AppIcons.heartFill : AppIcons.heart,
          tooltip: favorite
              ? strings.removeFromFavorites
              : strings.addToFavorites,
          color: favorite ? colors.primary : null,
          size: 30,
          iconSize: 20,
          onPressed: track == null
              ? null
              : () => controller.toggleFavorite(track),
        ),
        DesktopToolButton(
          key: const ValueKey('mini-remove'),
          icon: AppIcons.delete,
          tooltip: zh ? '从播放队列移除' : 'Remove from queue',
          size: 30,
          iconSize: 20,
          onPressed: item == null
              ? null
              : () => unawaited(_removeCurrent(item.id)),
        ),
        _LyricsToggle(
          // Lit while the square shows the lyrics.
          on: square && widget.lyrics,
          tooltip: !square
              ? (zh ? '展开歌词' : 'Show lyrics')
              : widget.lyrics
              ? (zh ? '显示封面' : 'Show cover')
              : (zh ? '显示歌词' : 'Show lyrics'),
          onPressed: widget.onLyricsButton,
        ),
        DesktopToolButton(
          key: const ValueKey('mini-volume'),
          icon: AppIcons.volumeLow,
          tooltip: zh ? '音量' : 'Volume',
          active: _volume,
          size: 30,
          iconSize: 21,
          onPressed: () => setState(() => _volume = !_volume),
        ),
      ],
    );
  }

  Widget _volumeSlider(BuildContext context) => StreamBuilder<double>(
    key: const ValueKey('mini-volume-slider'),
    stream: controller.audioHandler.volumeStream,
    initialData: controller.audioHandler.volume,
    builder: (context, volume) {
      final level = (volume.data ?? 1).clamp(0.0, 1.0).toDouble();
      return Row(
        children: [
          Icon(
            level == 0 ? AppIcons.volumeOff : AppIcons.volumeHigh,
            size: 16,
            color: DesktopUi.muted(context),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DesktopScrubber(
              value: level,
              semanticLabel: AppStringsScope.of(context).isZh ? '音量' : 'Volume',
              onChanged: controller.audioHandler.setVolume,
              onChangeEnd: controller.audioHandler.setVolume,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 26,
            child: Text(
              '${(level * 100).round()}',
              style: MusicType.readout(context, size: 11),
            ),
          ),
        ],
      );
    },
  );

  Widget _progress(MediaItem? item, PlaybackState state) => item == null
      ? const SizedBox.shrink()
      : _MiniProgress(
          key: ValueKey(item.id),
          controller: controller,
          trackId: item.id,
          duration: item.duration ?? Duration.zero,
          bufferedPosition: state.bufferedPosition,
        );

  Widget _strip(BuildContext context, MediaItem? item, PlaybackState state) {
    final middle = _volume
        ? Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: _volumeSlider(context),
          )
        : _hovered
        ? Padding(
            padding: const EdgeInsets.only(left: 18),
            child: _transport(context, state),
          )
        : _titles(context, item);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: _bar(context, .78)),
        const DesktopWindowDragArea(),
        Positioned(left: 4, top: 6, child: _windowButtons(context)),
        Positioned(left: 23, top: 8, child: _cover(context, item, 36)),
        Positioned(
          left: 66,
          right: 132,
          top: 3,
          height: 40,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: Align(
              key: ValueKey(
                _volume
                    ? 'v'
                    : _hovered
                    ? 'h'
                    : 't',
              ),
              alignment: Alignment.centerLeft,
              child: middle,
            ),
          ),
        ),
        Positioned(
          right: 5,
          top: 4,
          height: 36,
          child: _actions(context, item),
        ),
        Positioned(
          left: 64,
          right: 12,
          top: 39,
          height: 10,
          child: _progress(item, state),
        ),
      ],
    );
  }

  Widget _square(BuildContext context, MediaItem? item, PlaybackState state) {
    final zh = AppStringsScope.of(context).isZh;
    final uri = item?.artUri ?? controller.currentArtworkUri;
    final showBars = _hovered || _volume;
    return Stack(
      fit: StackFit.expand,
      children: [
        // What the square shows while the pointer is away.
        if (widget.lyrics) ...[
          if (uri != null) DesktopArtworkGlow(uri: uri),
          ColoredBox(color: _bar(context, .45)),
        ] else
          uri == null
              ? ColoredBox(color: _bar(context, .9))
              : Image(
                  image: artworkImageProvider(uri),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: _bar(context, .9)),
                ),
        const DesktopWindowDragArea(),
        if (widget.lyrics)
          Positioned.fill(child: _MiniLyrics(controller: controller)),
        // The bars fade in with the pointer.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 46,
          child: _Fade(
            visible: showBars,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: _bar(context, .88)),
                const DesktopWindowDragArea(),
                Positioned(left: 4, top: 3, child: _windowButtons(context)),
                Positioned(
                  left: 44,
                  right: 44,
                  top: 6,
                  child: _titles(context, item, center: true),
                ),
                Positioned(
                  right: 8,
                  top: 9,
                  child: Builder(
                    builder: (context) => DesktopToolButton(
                      key: const ValueKey('mini-more'),
                      icon: AppIcons.more,
                      tooltip: zh ? '更多' : 'More',
                      size: 26,
                      iconSize: 19,
                      onPressed: () {
                        final box = context.findRenderObject()! as RenderBox;
                        widget.onMenu(
                          box.localToGlobal(Offset(0, box.size.height + 4)),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 56,
          child: _Fade(
            visible: showBars,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: _bar(context, .88)),
                const DesktopWindowDragArea(),
                Positioned(
                  left: 23,
                  top: 6,
                  child: _cover(context, item, 36, framed: true),
                ),
                Positioned(
                  left: 84,
                  right: 128,
                  top: 6,
                  height: 36,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _volume
                        ? _volumeSlider(context)
                        : _transport(context, state),
                  ),
                ),
                Positioned(
                  right: 5,
                  top: 9,
                  height: 30,
                  child: _actions(context, item, square: true),
                ),
                Positioned(
                  left: 72,
                  right: 8,
                  bottom: 1,
                  height: 10,
                  child: _progress(item, state),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades the square's bars in and out with the pointer; hidden, they take
/// no clicks.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: child,
    ),
  );
}

/// The mini player's own × and □: small and quiet until pointed at.
class _TinyButton extends StatelessWidget {
  const _TinyButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DesktopTooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      onTap: onPressed,
      child: DesktopHover(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 14,
            child: Icon(
              icon,
              size: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: hovered ? .95 : .55),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The round play button in the skin's lit color.
class _PlayDot extends StatelessWidget {
  const _PlayDot({
    super.key,
    required this.playing,
    required this.tooltip,
    required this.onPressed,
  });

  final bool playing;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DesktopTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: DesktopHover(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: DesktopUi.hover,
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  colors.primary,
                  Colors.white,
                  hovered ? .12 : 0,
                ),
              ),
              child: ExcludeSemantics(
                child: Icon(
                  playing ? AppIcons.pause : AppIcons.play,
                  size: 20,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "词": lit while the lyrics are open.
class _LyricsToggle extends StatelessWidget {
  const _LyricsToggle({
    required this.on,
    required this.tooltip,
    required this.onPressed,
  });

  final bool on;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    final colors = Theme.of(context).colorScheme;
    return DesktopTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: on,
        child: DesktopHover(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const ValueKey('mini-lyrics'),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 30,
              child: Center(
                child: Text(
                  zh ? '词' : 'Ly',
                  style: TextStyle(
                    fontSize: zh ? 17 : 13,
                    fontWeight: FontWeight.w500,
                    color: on
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: hovered ? 1 : .78),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline of the song's progress across the mini player's foot.
class _MiniProgress extends StatefulWidget {
  const _MiniProgress({
    super.key,
    required this.controller,
    required this.trackId,
    required this.duration,
    required this.bufferedPosition,
  });

  final MusicController controller;
  final String trackId;
  final Duration duration, bufferedPosition;

  @override
  State<_MiniProgress> createState() => _MiniProgressState();
}

class _MiniProgressState extends State<_MiniProgress> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    return StreamBuilder<Duration>(
      stream: widget.controller.positionStream,
      initialData: widget.controller.audioHandler.currentPosition,
      builder: (context, snapshot) {
        final played = total <= 0
            ? 0.0
            : (snapshot.data ?? Duration.zero).inMilliseconds / total;
        return Center(
          child: SizedBox(
            height: 10,
            child: DesktopScrubber(
              value: (_drag ?? played).clamp(0.0, 1.0).toDouble(),
              buffered: total <= 0
                  ? 0
                  : widget.bufferedPosition.inMilliseconds / total,
              semanticLabel: AppStringsScope.of(context).isZh
                  ? '播放进度'
                  : 'Position',
              onChanged: total <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: total <= 0
                  ? null
                  : (v) {
                      setState(() => _drag = null);
                      widget.controller.seek(
                        Duration(milliseconds: (v * total).round()),
                      );
                    },
            ),
          ),
        );
      },
    );
  }
}

/// The square mini player's lyrics: the sung line bright and centred, the
/// rest dim, following the song.
class _MiniLyrics extends StatefulWidget {
  const _MiniLyrics({required this.controller});

  final MusicController controller;

  @override
  State<_MiniLyrics> createState() => _MiniLyricsState();
}

class _MiniLyricsState extends State<_MiniLyrics> {
  static const _line = 30.0;
  final _scroll = ScrollController();
  int _shown = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index, double viewport) {
    if (index == _shown) return;
    _shown = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (index * _line - (viewport - _line) / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final lyrics = controller.currentLyrics;
    final colors = Theme.of(context).colorScheme;
    if (lyrics.isEmpty) {
      return Center(
        child: Text(
          controller.isLoadingMetadata
              ? (AppStringsScope.of(context).isZh
                    ? '正在加载歌词…'
                    : 'Loading lyrics…')
              : AppStringsScope.of(context).noLyrics,
          style: TextStyle(fontSize: 13, color: DesktopUi.muted(context)),
        ),
      );
    }
    final timed = lyrics.any((line) => line.time > Duration.zero);
    return LayoutBuilder(
      builder: (context, constraints) => StreamBuilder<Duration>(
        stream: controller.positionStream,
        initialData: controller.audioHandler.currentPosition,
        builder: (context, snapshot) {
          var active = -1;
          if (timed) {
            final position = snapshot.data ?? Duration.zero;
            for (var i = 0; i < lyrics.length; i++) {
              if (lyrics[i].time <= position) {
                active = i;
              } else {
                break;
              }
            }
            _follow(active.clamp(0, lyrics.length - 1), constraints.maxHeight);
          }
          return ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0, .18, .82, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.symmetric(
                vertical: (constraints.maxHeight - _line) / 2,
                horizontal: 20,
              ),
              itemExtent: _line,
              itemCount: lyrics.length,
              itemBuilder: (context, index) => Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: index == active ? 15 : 14,
                    height: 1.2,
                    fontWeight: index == active
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: index == active
                        ? colors.onSurface
                        : colors.onSurface.withValues(alpha: .42),
                  ),
                  child: Text(
                    lyrics[index].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The song's position: elapsed time, the hairline, and its length.
class DesktopProgress extends StatefulWidget {
  const DesktopProgress({
    super.key,
    required this.controller,
    required this.trackId,
    required this.duration,
    required this.bufferedPosition,
    this.compact = false,
  });

  final MusicController controller;
  final String trackId;
  final Duration duration, bufferedPosition;

  /// The mini player's smaller figures.
  final bool compact;

  @override
  State<DesktopProgress> createState() => _DesktopProgressState();
}

class _DesktopProgressState extends State<DesktopProgress> {
  double? _drag;

  static String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    return StreamBuilder<Duration>(
      stream: widget.controller.positionStream,
      initialData: widget.controller.audioHandler.currentPosition,
      builder: (context, snapshot) => ValueListenableBuilder<SongCacheProgress>(
        valueListenable: widget.controller.cacheProgressForId(widget.trackId),
        builder: (context, cache, _) {
          final played = total <= 0
              ? 0.0
              : (snapshot.data ?? Duration.zero).inMilliseconds / total;
          final value = (_drag ?? played).clamp(0.0, 1.0).toDouble();
          final buffered = total <= 0
              ? 0.0
              : cache.offline
              ? 1.0
              : widget.bufferedPosition.inMilliseconds / total;
          final readout = MusicType.readout(
            context,
            size: widget.compact ? 10 : 11,
          );
          return Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  _clock(Duration(milliseconds: (value * total).round())),
                  textAlign: TextAlign.right,
                  style: readout,
                ),
              ),
              SizedBox(width: widget.compact ? 6 : 10),
              Expanded(
                child: DesktopScrubber(
                  value: value,
                  buffered: buffered,
                  semanticLabel: AppStringsScope.of(context).isZh
                      ? '播放进度'
                      : 'Position',
                  semanticValue: (v) =>
                      _clock(Duration(milliseconds: (v * total).round())),
                  onChanged: total <= 0
                      ? null
                      : (v) => setState(() => _drag = v),
                  onChangeEnd: total <= 0
                      ? null
                      : (v) {
                          setState(() => _drag = null);
                          widget.controller.seek(
                            Duration(milliseconds: (v * total).round()),
                          );
                        },
                ),
              ),
              SizedBox(width: widget.compact ? 6 : 10),
              SizedBox(
                width: 40,
                child: Text(_clock(widget.duration), style: readout),
              ),
            ],
          );
        },
      ),
    );
  }
}
