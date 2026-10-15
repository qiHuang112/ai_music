import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'design/controls.dart';
import 'design/glass_surface.dart';
import 'design/vinyl_disc.dart';
import 'music_thumbnail.dart';
import 'playback_queue.dart';
import 'player_page.dart';
import 'swipe_to_skip.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItemStream,
      initialData: controller.audioHandler.mediaItem.value,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<PlaybackState>(
          stream: controller.playbackStateStream,
          initialData: controller.audioHandler.playbackState.value,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data ?? PlaybackState();
            final strings = AppStringsScope.of(context);
            const height = 54.0;
            final radius = BorderRadius.circular(height / 2);
            return SafeArea(
              top: false,
              child: Padding(
                padding: MusicUi.miniPlayerInsets,
                // A glass pill: the record fills its left end, then the song
                // on one line, then the lit play button.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassSurface(
                      borderRadius: radius,
                      child: Builder(
                        builder: (context) {
                          // Resolve colors inside the surface: silver provides
                          // a light-on-dark theme for its display window.
                          final text = Theme.of(context).textTheme;
                          final colors = Theme.of(context).colorScheme;
                          return Material(
                            key: const ValueKey('mini-player-card'),
                            type: MaterialType.transparency,
                            borderRadius: radius,
                            clipBehavior: Clip.antiAlias,
                            child: SwipeToSkip(
                              key: const ValueKey('mini-player-swipe-area'),
                              onNext: controller.next,
                              onPrevious: controller.previous,
                              child: GestureDetector(
                                // Swipe up for the queue; sideways changes the song.
                                onVerticalDragEnd: (details) {
                                  if ((details.primaryVelocity ?? 0) < -120) {
                                    showPlaybackQueue(context, controller);
                                  }
                                },
                                child: InkWell(
                                  onTap: () => _openPlayer(context),
                                  child: MediaQuery.withClampedTextScaling(
                                    maxScaleFactor: 1.4,
                                    child: SizedBox(
                                      height: height,
                                      child: Stack(
                                        children: [
                                          // A short line inside the top edge: the bar pulls up into the queue.
                                          Align(
                                            alignment: Alignment.topCenter,
                                            child: Container(
                                              key: const ValueKey(
                                                'mini-player-grabber',
                                              ),
                                              margin: const EdgeInsets.only(
                                                top: 5,
                                              ),
                                              width: 22,
                                              height: 3,
                                              decoration: BoxDecoration(
                                                color: colors.onSurface
                                                    .withValues(alpha: .24),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              // Its rim is the progress: from twelve
                                              // o'clock, clockwise.
                                              SizedBox.square(
                                                dimension: height,
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
                                                      size: 30,
                                                      radius: 0,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Flexible(
                                                      flex: 3,
                                                      child: Text(
                                                        item.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: text.titleMedium,
                                                      ),
                                                    ),
                                                    if ((item.artist ?? '')
                                                        .isNotEmpty)
                                                      Flexible(
                                                        flex: 2,
                                                        child: Text(
                                                          ' - ${item.artist}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: text.bodyLarge
                                                              ?.copyWith(
                                                                color: colors
                                                                    .onSurfaceVariant,
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // By night the lit button; by day a quiet outlined one.
                                              if (Theme.of(
                                                    context,
                                                  ).brightness ==
                                                  Brightness.dark) ...[
                                                PlayPauseButton(
                                                  key: const ValueKey(
                                                    'mini-player-play',
                                                  ),
                                                  playing: state.playing,
                                                  size: 42,
                                                  tooltip: state.playing
                                                      ? strings.pause
                                                      : strings.play,
                                                  onPressed: controller
                                                      .togglePlayPause,
                                                ),
                                                const SizedBox(width: 3),
                                              ] else
                                                _OutlinedPlayButton(
                                                  key: const ValueKey(
                                                    'mini-player-play',
                                                  ),
                                                  playing: state.playing,
                                                  tooltip: state.playing
                                                      ? strings.pause
                                                      : strings.play,
                                                  onPressed: controller
                                                      .togglePlayPause,
                                                ),
                                              const SizedBox(width: 6),
                                            ],
                                          ),
                                        ],
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPlayer(BuildContext context) {
    // The player rises from the bar it was opened from.
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        settings: const RouteSettings(name: 'player'),
        transitionDuration: MusicMotion.slow,
        reverseTransitionDuration: MusicMotion.base,
        pageBuilder: (context, _, _) => PlayerPage(controller: controller),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(
              parent: animation,
              curve: MusicMotion.emphasized,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _OutlinedPlayButton extends StatelessWidget {
  const _OutlinedPlayButton({
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
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: Pressable(
          pressedScale: .88,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 1.6,
                  color: colors.onSurface.withValues(alpha: .55),
                ),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 22,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
