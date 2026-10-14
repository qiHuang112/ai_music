import 'dart:async';
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
import 'song_comments_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentTrack = controller.currentTrack;
        final strings = AppStringsScope.of(context);
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(strings.nowPlaying),
            actions: [
              if (currentTrack != null) ...[
                IconButton(
                  tooltip: controller.isFavorite(currentTrack)
                      ? strings.removeFromFavorites
                      : strings.addToFavorites,
                  onPressed: () => controller.toggleFavorite(currentTrack),
                  icon: Icon(
                    controller.isFavorite(currentTrack)
                        ? Icons.favorite
                        : Icons.favorite_border,
                  ),
                ),
                IconButton(
                  tooltip: strings.addToPlaylist,
                  onPressed: () =>
                      showAddToPlaylistSheet(context, controller, currentTrack),
                  icon: const Icon(Icons.playlist_add),
                ),
              ],
            ],
          ),
          body: _PlayerBackdrop(
            controller: controller,
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
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            MusicUi.pagePadding,
                            4,
                            MusicUi.pagePadding,
                            12,
                          ),
                          children: [
                            _Artwork(
                              uri: item.artUri ?? controller.currentArtworkUri,
                              controller: controller,
                              playing: state.playing,
                              cueing: _cueing,
                              swipe: _disc,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: MusicType.masthead(context, size: 26),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            _LyricsPreview(controller: controller),
                            const SizedBox(height: 8),
                            _PositionSlider(
                              key: ValueKey('player-position-${item.id}'),
                              trackId: item.id,
                              controller: controller,
                              duration: duration,
                              bufferedPosition: state.bufferedPosition,
                            ),
                            const SizedBox(height: 10),
                            _PlaybackControls(
                              controller: controller,
                              playing: state.playing || _cueing,
                              onToggle: () => _togglePlayPause(state.playing),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              children: [
                                if (currentTrack != null &&
                                    controller.canSwitchSongSource(
                                      currentTrack,
                                    ))
                                  TextButton.icon(
                                    key: const Key('player-switch-source'),
                                    onPressed: () => showSongSourcePicker(
                                      context,
                                      controller,
                                      currentTrack,
                                    ),
                                    icon: const Icon(Icons.swap_horiz),
                                    label: Text(
                                      strings.isZh ? '切换来源' : 'Choose source',
                                    ),
                                  ),
                                if (currentTrack != null)
                                  TextButton.icon(
                                    key: const ValueKey('player-comments'),
                                    onPressed: () {
                                      final query = SongCommentQuery.fromTrack(
                                        currentTrack,
                                        original: controller
                                            .originalSongForTrack(currentTrack),
                                        candidate: controller
                                            .selectedSongSource(currentTrack),
                                        lyrics: controller.currentLyrics,
                                      );
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              SongCommentsPage(query: query),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                    ),
                                    label: Text(
                                      strings.isZh ? '歌曲热评' : 'Song comments',
                                    ),
                                  ),
                              ],
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
    required this.swipe,
  });

  final Uri? uri;
  final MusicController controller;
  final bool playing, cueing;
  final _DiscSwipe swipe;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artUri = uri;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(child: Icon(Icons.album, size: 44, color: colors.primary)),
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
          maxWidth: (MediaQuery.sizeOf(context).height * .35).clamp(
            180.0,
            MusicUi.playerCoverMaxWidth,
          ),
        ),
        child: _DiscCarousel(
          swipe: swipe,
          neighbor: _neighborLabel,
          // The arm does not follow the song: the position updates several
          // times a second, and redrawing the deck for each kept the phone
          // busy for as long as music played.
          builder: (context, swiping) => Turntable(
            playing: playing,
            // The arm lifts off while the record is being changed.
            armDown: (playing || cueing) && !swiping,
            label: label,
          ),
        ),
      ),
    );
  }

  /// The cover of the song before (-1) or after (1) this one in the queue,
  /// for the record that slides in. Unknown in shuffle: the label is blank.
  Widget? _neighborLabel(int step) {
    if (controller.playbackMode == PlaybackMode.shuffle) return null;
    final queue = controller.audioHandler.queue.value;
    final id = controller.audioHandler.mediaItem.value?.id;
    final index = queue.indexWhere((item) => item.id == id);
    if (index < 0 || queue.length < 2) return null;
    final art = queue[(index + step) % queue.length].artUri;
    return art == null
        ? null
        : Image(
            image: artworkImageProvider(art),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
  }
}

/// What the finger is doing to the record, passed from the page's swipe area
/// to the deck.
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
  final Widget? Function(int step) neighbor;
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
                child: Turntable(
                  playing: false,
                  armDown: false,
                  label: widget.neighbor(step),
                ),
              ),
            Transform.translate(offset: Offset(x, 0), child: deck),
          ],
        );
      },
      child: deck,
    );
  }
}

ImageProvider artworkImageProvider(Uri uri) => uri.isScheme('file')
    ? FileImage(File(uri.toFilePath()))
    : NetworkImage(uri.toString());

/// Lights the page from the playing cover and keeps that light while the
/// next cover loads.
class _PlayerBackdrop extends StatefulWidget {
  const _PlayerBackdrop({required this.controller, required this.child});

  final MusicController controller;
  final Widget child;

  @override
  State<_PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<_PlayerBackdrop> {
  Uri? _uri;
  ArtworkPalette? _palette;

  Future<void> _read(Uri? uri) async {
    if (uri == _uri) return;
    _uri = uri;
    final palette = uri == null
        ? null
        : await ArtworkPalette.of(artworkImageProvider(uri));
    if (mounted && uri == _uri) setState(() => _palette = palette);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
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
            child: _SwipeDownToClose(child: widget.child),
          ),
        );
      },
    );
  }
}

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
        return Scaffold(
          extendBodyBehindAppBar: true,
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
                        ? Icons.favorite
                        : Icons.favorite_border,
                  ),
                ),
                IconButton(
                  tooltip: strings.addToPlaylist,
                  onPressed: () =>
                      showAddToPlaylistSheet(context, controller, currentTrack),
                  icon: const Icon(Icons.playlist_add),
                ),
              ],
            ],
          ),
          body: _PlayerBackdrop(
            controller: controller,
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
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
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
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                              child: _PositionSlider(
                                key: ValueKey('lyrics-position-${item.id}'),
                                trackId: item.id,
                                controller: controller,
                                duration: duration,
                                bufferedPosition: state.bufferedPosition,
                              ),
                            ),
                            _PlaybackControls(
                              controller: controller,
                              playing: state.playing,
                            ),
                            const SizedBox(height: 12),
                          ],
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

class _PositionSlider extends StatefulWidget {
  const _PositionSlider({
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
  State<_PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<_PositionSlider> {
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
    // Scales down as one piece on narrow phones instead of overflowing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassIconButton(
            blur: false,
            tooltip: _modeTooltip(strings, controller.playbackMode),
            onPressed: controller.cyclePlaybackMode,
            icon: _modeIcon(controller.playbackMode),
          ),
          const SizedBox(width: 12),
          GlassIconButton(
            blur: false,
            tooltip: strings.previous,
            size: 54,
            onPressed: controller.previous,
            icon: Icons.skip_previous_rounded,
          ),
          const SizedBox(width: 16),
          PlayPauseButton(
            playing: playing,
            tooltip: playing ? strings.pause : strings.play,
            onPressed: onToggle ?? controller.togglePlayPause,
          ),
          const SizedBox(width: 16),
          GlassIconButton(
            blur: false,
            tooltip: strings.next,
            size: 54,
            onPressed: controller.next,
            icon: Icons.skip_next_rounded,
          ),
          const SizedBox(width: 12),
          GlassIconButton(
            blur: false,
            key: const ValueKey('player-queue'),
            tooltip: strings.isZh ? '当前队列' : 'Play queue',
            onPressed: () => showPlaybackQueue(context, controller),
            icon: Icons.queue_music_rounded,
          ),
        ],
      ),
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
        MaterialPageRoute(
          builder: (context) => _LyricsDetailPage(controller: controller),
        ),
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: _LyricsPreviewContent(controller: controller),
      ),
    );
  }
}

class _LyricsPreviewContent extends StatelessWidget {
  const _LyricsPreviewContent({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lyrics = controller.currentLyrics;
    if (controller.isLoadingMetadata && lyrics.isEmpty) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.controller.metadataError ?? strings.noLyrics,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
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
              : const Icon(Icons.refresh),
          label: Text(loading ? strings.fetchingLyrics : strings.retryLyrics),
        ),
      ],
    );
  }

  void _scheduleAutoRecover() {
    final trackId = widget.controller.currentTrack?.id;
    if (trackId == null ||
        _autoRequestedTrackId == trackId ||
        widget.controller.currentLyrics.isNotEmpty ||
        widget.controller.isLoadingMetadata) {
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

  final _scrollController = ScrollController();
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
    if (controller.isLoadingMetadata && lyrics.isEmpty) {
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
            builder: (context, snapshot) {
              _resetFollowStateIfLyricsChanged(lyrics);
              final position = snapshot.data ?? Duration.zero;
              final activeIndex = _activeLyricIndex(lyrics, position);
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

  void _resetFollowStateIfLyricsChanged(List<LyricLine> lyrics) {
    if (!identical(_followLyrics, lyrics)) {
      _followLyrics = lyrics;
      _followState.reset();
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
    PlaybackMode.sequential => Icons.playlist_play,
    PlaybackMode.repeatOne => Icons.repeat_one,
    PlaybackMode.shuffle => Icons.shuffle,
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
