import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../application/music_controller.dart';
import '../domain/music_models.dart';
import 'app_theme.dart';
import 'playback_queue.dart';
import 'app_localizations.dart';
import 'playlist_actions.dart';
import 'swipe_to_skip.dart';
import 'song_source_page.dart';
import 'song_comments_page.dart';
import '../data/song_comments.dart';

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

  @override
  void initState() {
    super.initState();
    controller.loadMetadataForCurrentTrack();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentTrack = controller.currentTrack;
        final strings = AppStringsScope.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(strings.nowPlaying),
            actions: [
              if (currentTrack != null) ...[
                if (controller.canSwitchSongSource(currentTrack))
                  IconButton(
                    key: const Key('player-switch-source'),
                    tooltip: strings.isZh ? '切换来源' : 'Choose source',
                    onPressed: () =>
                        showSongSourcePicker(context, controller, currentTrack),
                    icon: const Icon(Icons.swap_horiz),
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
          body: SafeArea(
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
                      child: _PlayerLayout(
                        controller: controller,
                        item: item,
                        state: state,
                        duration: duration,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PlayerLayout extends StatelessWidget {
  const _PlayerLayout({
    required this.controller,
    required this.item,
    required this.state,
    required this.duration,
  });

  final MusicController controller;
  final MediaItem item;
  final PlaybackState state;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 680 &&
            constraints.maxWidth > constraints.maxHeight;
        final contentWidth = math.min(
          constraints.maxWidth - MusicUi.pagePadding * 2,
          wide ? 960.0 : 480.0,
        );
        final coverSize = math.min(
          contentWidth,
          wide ? 180.0 : MusicUi.playerCoverMaxWidth,
        );
        final track = controller.currentTrack;
        final actions = track == null
            ? const SizedBox.shrink()
            : _PlayerSongActions(controller: controller, track: track);
        final heading = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              item.artist ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _LyricsPreview(controller: controller),
            if (wide) ...[const SizedBox(height: 12), actions],
          ],
        );
        final artwork = _Artwork(
          uri: item.artUri ?? controller.currentArtworkUri,
          size: coverSize,
        );
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const Key('player-song-content'),
                padding: const EdgeInsets.symmetric(
                  horizontal: MusicUi.pagePadding,
                  vertical: 16,
                ),
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              artwork,
                              const SizedBox(width: 32),
                              Expanded(child: heading),
                            ],
                          )
                        : Column(
                            children: [
                              artwork,
                              const SizedBox(height: 18),
                              heading,
                            ],
                          ),
                  ),
                ),
              ),
            ),
            Padding(
              key: const Key('player-bottom-controls'),
              padding: const EdgeInsets.fromLTRB(
                MusicUi.pagePadding,
                0,
                MusicUi.pagePadding,
                8,
              ),
              child: Center(
                child: SizedBox(
                  width: math.min(contentWidth, 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!wide && track != null) ...[
                        actions,
                        const SizedBox(height: 24),
                      ],
                      _PositionSlider(
                        key: ValueKey('player-position-${item.id}'),
                        trackId: item.id,
                        controller: controller,
                        duration: duration,
                        bufferedPosition: state.bufferedPosition,
                      ),
                      const SizedBox(height: 8),
                      _PlaybackControls(
                        controller: controller,
                        playing: state.playing,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayerSongActions extends StatelessWidget {
  const _PlayerSongActions({required this.controller, required this.track});

  final MusicController controller;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const Key('player-favorite'),
            tooltip: controller.isFavorite(track)
                ? strings.removeFromFavorites
                : strings.addToFavorites,
            onPressed: () => controller.toggleFavorite(track),
            icon: Icon(
              controller.isFavorite(track)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
          IconButton(
            key: const ValueKey('player-comments'),
            tooltip: strings.isZh ? '歌曲热评' : 'Song comments',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SongCommentsPage(
                  query: SongCommentQuery.fromTrack(
                    track,
                    original: controller.originalSongForTrack(track),
                    candidate: controller.selectedSongSource(track),
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.uri, required this.size});

  final Uri? uri;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artUri = uri;
    final fallback = Center(
      child: Icon(
        Icons.album_outlined,
        size: size * .36,
        color: colors.primary,
      ),
    );
    return Center(
      child: SizedBox.square(
        key: const ValueKey('player-artwork'),
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(MusicUi.radius),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: .10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MusicUi.radius),
            child: artUri == null
                ? fallback
                : Image(
                    image: artUri.isScheme('file')
                        ? FileImage(File(artUri.toFilePath()))
                        : NetworkImage(artUri.toString()),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
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
          appBar: AppBar(
            title: Text(
              strings.lyrics,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            centerTitle: true,
            actions: [
              if (currentTrack != null) ...[
                IconButton(
                  tooltip: controller.isFavorite(currentTrack)
                      ? strings.removeFromFavorites
                      : strings.addToFavorites,
                  onPressed: () => controller.toggleFavorite(currentTrack),
                  icon: Icon(
                    controller.isFavorite(currentTrack)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
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
          body: SafeArea(
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
                      child: _LyricsLayout(
                        controller: controller,
                        item: item,
                        state: state,
                        duration: duration,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LyricsLayout extends StatelessWidget {
  const _LyricsLayout({
    required this.controller,
    required this.item,
    required this.state,
    required this.duration,
  });
  final MusicController controller;
  final MediaItem item;
  final PlaybackState state;
  final Duration duration;
  @override
  Widget build(BuildContext context) => MusicPageBackdrop(
    child: Column(
      children: [
        Expanded(
          child: _LyricsPanel(
            key: ValueKey('lyrics-panel-${item.id}'),
            controller: controller,
            fillsAvailable: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: _TransportSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PositionSlider(
                  key: ValueKey('lyrics-position-${item.id}'),
                  trackId: item.id,
                  controller: controller,
                  duration: duration,
                  bufferedPosition: state.bufferedPosition,
                ),
                const SizedBox(height: 8),
                _PlaybackControls(
                  controller: controller,
                  playing: state.playing,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _TransportSurface extends StatelessWidget {
  const _TransportSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('player-transport-surface'),
      padding: dark
          ? const EdgeInsets.fromLTRB(10, 5, 10, 14)
          : const EdgeInsets.only(bottom: 4),
      decoration: dark
          ? BoxDecoration(
              gradient: MusicUi.playerGradient(context),
              border: Border.all(color: MusicUi.playerBorder(context)),
              borderRadius: BorderRadius.circular(26),
            )
          : null,
      child: child,
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
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: SizedBox(
                  height: 48,
                  child: Slider(
                    padding: EdgeInsets.zero,
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    _formatDuration(widget.duration),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
    this.compact = false,
  });

  final MusicController controller;
  final bool playing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final playSize = compact
        ? (Theme.of(context).brightness == Brightness.dark ? 58.0 : 62.0)
        : 64.0;
    final secondaryStyle = IconButton.styleFrom(
      minimumSize: const Size(44, 48),
      padding: const EdgeInsets.all(6),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              style: secondaryStyle,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: _modeTooltip(strings, controller.playbackMode),
              onPressed: controller.cyclePlaybackMode,
              icon: Icon(_modeIcon(controller.playbackMode)),
            ),
            IconButton(
              style: secondaryStyle,
              tooltip: strings.previous,
              iconSize: 32,
              onPressed: controller.previous,
              icon: const Icon(Icons.skip_previous),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: MusicUi.accentGradient(context),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .18),
                    blurRadius: 22,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: IconButton(
                tooltip: playing ? strings.pause : strings.play,
                iconSize: 32,
                style: IconButton.styleFrom(
                  foregroundColor: colors.onPrimaryContainer,
                  fixedSize: Size.square(playSize),
                ),
                onPressed: controller.togglePlayPause,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
            ),
            IconButton(
              style: secondaryStyle,
              tooltip: strings.next,
              iconSize: 32,
              onPressed: controller.next,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              key: const ValueKey('playback-queue'),
              style: secondaryStyle,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: strings.isZh ? '当前队列' : 'Play queue',
              onPressed: () => showPlaybackQueue(context, controller),
              icon: const Icon(Icons.queue_music_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(MusicUi.radius),
        ),
        child: Row(
          children: [
            Expanded(child: _LyricsPreviewContent(controller: controller)),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
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
                    color: row.active
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    fontWeight: row.active ? FontWeight.w700 : FontWeight.w400,
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
  final _scrollController = ScrollController();
  final _followState = LyricFollowState();
  bool _userScrolling = false;
  int _followGeneration = 0;
  List<LyricLine>? _followLyrics;
  _LyricGeometry? _geometry;
  bool _hasFollowed = false;

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
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _MissingLyricsContent(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleLarge!.copyWith(
      fontSize: 17,
      height: 1.6,
      fontWeight: FontWeight.w400,
    );
    if (!_hasTimedLyrics(lyrics)) {
      return _wrapContent(
        ListView.builder(
          key: const ValueKey('lyrics-list'),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          itemCount: lyrics.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              lyrics[index].text,
              textAlign: TextAlign.center,
              style: textStyle.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      );
    }

    return _wrapContent(
      LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          final locale = Localizations.maybeLocaleOf(context);
          final width = math.max(1.0, constraints.maxWidth - 48);
          if (_geometry == null ||
              !_geometry!.matches(
                lyrics,
                width,
                textStyle,
                scaler,
                direction,
                locale,
              )) {
            _geometry = _LyricGeometry(
              lyrics,
              width,
              textStyle,
              scaler,
              direction,
              locale,
            );
            _followState.reset();
          }
          final geometry = _geometry!;
          return StreamBuilder<Duration>(
            stream: widget.positionStream ?? controller.positionStream,
            initialData: controller.audioHandler.currentPosition,
            builder: (context, snapshot) {
              _resetFollowStateIfLyricsChanged(lyrics);
              final position = snapshot.data ?? Duration.zero;
              final activeIndex = _activeLyricIndex(lyrics, position);
              _maybeFollow(activeIndex, geometry);
              return Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      // Programmatic follow animations must not enter browse mode.
                      final userScroll =
                          (notification is ScrollStartNotification &&
                              notification.dragDetails != null) ||
                          (notification is UserScrollNotification &&
                              notification.direction != ScrollDirection.idle);
                      if (userScroll && !_userScrolling) {
                        _followGeneration++;
                        setState(() => _userScrolling = true);
                        _followState.reset();
                      }
                      if (notification is ScrollEndNotification &&
                          _userScrolling) {
                        _scheduleFollowResume();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      key: const ValueKey('lyrics-list'),
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        vertical: constraints.maxHeight / 2,
                      ),
                      itemExtentBuilder: (index, _) => geometry.heights[index],
                      itemCount: lyrics.length,
                      itemBuilder: (context, index) {
                        final line = lyrics[index];
                        final active = index == activeIndex;
                        final distance = (index - activeIndex).abs();
                        return Semantics(
                          selected: active,
                          child: InkWell(
                            onTap: () {
                              _resumeFollowing();
                              controller.seekToLyricLine(line);
                            },
                            child: DecoratedBox(
                              decoration:
                                  active && theme.brightness == Brightness.dark
                                  ? BoxDecoration(
                                      gradient: RadialGradient(
                                        radius: 1,
                                        colors: [
                                          theme.colorScheme.primary.withValues(
                                            alpha: .08,
                                          ),
                                          theme.colorScheme.primary.withValues(
                                            alpha: 0,
                                          ),
                                        ],
                                      ),
                                    )
                                  : const BoxDecoration(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Text(
                                    line.text,
                                    textAlign: TextAlign.center,
                                    style: textStyle.copyWith(
                                      color: active
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant
                                                .withValues(
                                                  alpha: distance > 2
                                                      ? .58
                                                      : distance > 1
                                                      ? .78
                                                      : 1,
                                                ),
                                      fontSize: active ? 18 : 17,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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
    final content = Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: MusicUi.readingMaxWidth),
        child: child,
      ),
    );
    return widget.fillsAvailable
        ? content
        : SizedBox(height: 280, child: content);
  }

  void _maybeFollow(int activeIndex, _LyricGeometry geometry) {
    if (_userScrolling || activeIndex < 0) return;
    final target = geometry.centers[activeIndex];
    if (!_followState.shouldFollow(activeIndex, target)) return;
    final generation = _followGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _userScrolling ||
          generation != _followGeneration ||
          !_scrollController.hasClients) {
        return;
      }
      final offset = target.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (!_hasFollowed || MediaQuery.disableAnimationsOf(context)) {
        _hasFollowed = true;
        _scrollController.jumpTo(offset);
      } else {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resetFollowStateIfLyricsChanged(List<LyricLine> lyrics) {
    if (!identical(_followLyrics, lyrics)) {
      _followLyrics = lyrics;
      _hasFollowed = false;
      _followState.reset();
      _followGeneration++;
      _userScrolling = false;
    }
  }

  void _resumeFollowing() {
    _followGeneration++;
    setState(() {
      _followState.reset();
      _userScrolling = false;
    });
  }

  void _scheduleFollowResume() {
    final generation = ++_followGeneration;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && generation == _followGeneration) _resumeFollowing();
    });
  }
}

// Cache measured row geometry across position ticks. Wrapping and text scaling
// change each row's center, so both auto-follow and browsing use the same offsets.
class _LyricGeometry {
  _LyricGeometry(
    this.lyrics,
    this.width,
    this.style,
    this.scaler,
    this.direction,
    this.locale,
  ) {
    final painter = TextPainter(
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    );
    var top = 0.0;
    for (final line in lyrics) {
      painter.text = TextSpan(
        text: line.text,
        style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      );
      painter.layout(maxWidth: width);
      final height = math.max(52.0, painter.height.ceilToDouble() + 24);
      heights.add(height);
      centers.add(top + height / 2);
      top += height;
    }
    painter.dispose();
  }

  final List<LyricLine> lyrics;
  final double width;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  final heights = <double>[];
  final centers = <double>[];

  bool matches(
    List<LyricLine> next,
    double nextWidth,
    TextStyle nextStyle,
    TextScaler nextScaler,
    TextDirection nextDirection,
    Locale? nextLocale,
  ) =>
      identical(lyrics, next) &&
      width == nextWidth &&
      style == nextStyle &&
      scaler == nextScaler &&
      direction == nextDirection &&
      locale == nextLocale;

  int nearest(double offset) {
    var low = 0;
    var high = centers.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (centers[mid] < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 && offset - centers[low - 1] < centers[low] - offset) {
      return low - 1;
    }
    return low;
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
