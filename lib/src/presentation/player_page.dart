import 'app_theme.dart';
import 'playback_queue.dart';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/song_comments.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
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
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          MusicUi.pagePadding,
                          12,
                          MusicUi.pagePadding,
                          32,
                        ),
                        children: [
                          _Artwork(
                            uri: item.artUri ?? controller.currentArtworkUri,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 18),
                          _LyricsPreview(controller: controller),
                          const SizedBox(height: 18),
                          _PositionSlider(
                            key: ValueKey('player-position-${item.id}'),
                            trackId: item.id,
                            controller: controller,
                            duration: duration,
                            bufferedPosition: state.bufferedPosition,
                          ),
                          const SizedBox(height: 16),
                          _PlaybackControls(
                            controller: controller,
                            playing: state.playing,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            children: [
                              if (currentTrack != null &&
                                  controller.canSwitchSongSource(currentTrack))
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
                                      original: controller.originalSongForTrack(
                                        currentTrack,
                                      ),
                                      candidate: controller.selectedSongSource(
                                        currentTrack,
                                      ),
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
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final artUri = uri;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).height * .34).clamp(
            180.0,
            MusicUi.playerCoverMaxWidth,
          ),
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(MusicUi.radius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MusicUi.radius),
              child: artUri == null
                  ? Icon(Icons.album, size: 108, color: colors.primary)
                  : Image(
                      image: _imageProvider(artUri),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) {
                        return Icon(
                          Icons.album,
                          size: 108,
                          color: colors.primary,
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  ImageProvider _imageProvider(Uri uri) {
    if (uri.isScheme('file')) {
      return FileImage(File(uri.toFilePath()));
    }
    return NetworkImage(uri.toString());
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
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
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
              builder: (context, progress, _) => Slider(
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
  const _PlaybackControls({required this.controller, required this.playing});

  final MusicController controller;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: _modeTooltip(strings, controller.playbackMode),
          onPressed: controller.cyclePlaybackMode,
          icon: Icon(_modeIcon(controller.playbackMode)),
        ),
        IconButton(
          tooltip: strings.previous,
          iconSize: 32,
          onPressed: controller.previous,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          tooltip: playing ? strings.pause : strings.play,
          iconSize: 40,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            minimumSize: const Size(64, 64),
          ),
          onPressed: controller.togglePlayPause,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: strings.next,
          iconSize: 32,
          onPressed: controller.next,
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          key: const ValueKey('player-queue'),
          tooltip: strings.isZh ? '当前队列' : 'Play queue',
          onPressed: () => showPlaybackQueue(context, controller),
          icon: const Icon(Icons.queue_music_rounded),
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
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(MusicUi.radius),
        ),
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
