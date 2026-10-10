import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
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
            final colors = Theme.of(context).colorScheme;
            const radius = BorderRadius.all(
              Radius.circular(MusicUi.miniPlayerRadius),
            );
            return SafeArea(
              top: false,
              child: Padding(
                padding: MusicUi.miniPlayerInsets,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: .10),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    key: const ValueKey('mini-player-card'),
                    color: colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: radius,
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors.surfaceContainerLow,
                            colors.secondaryContainer,
                          ],
                          begin: AlignmentDirectional.topStart,
                          end: AlignmentDirectional.bottomEnd,
                        ),
                      ),
                      child: SwipeToSkip(
                        key: const ValueKey('mini-player-swipe-area'),
                        onNext: controller.next,
                        onPrevious: controller.previous,
                        child: InkWell(
                          onTap: () => _openPlayer(context),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  8,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    MusicThumbnail(
                                      uri: item.artUri,
                                      size: 48,
                                      radius: 14,
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
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          Text(
                                            item.artist ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox.square(
                                      dimension: 48,
                                      child: Center(
                                        child: IconButton.filled(
                                          key: const ValueKey(
                                            'mini-player-play',
                                          ),
                                          tooltip: state.playing
                                              ? strings.pause
                                              : strings.play,
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                colors.primaryContainer,
                                            foregroundColor:
                                                colors.onPrimaryContainer,
                                            minimumSize: const Size.square(44),
                                            padding: const EdgeInsets.all(10),
                                          ),
                                          onPressed: controller.togglePlayPause,
                                          icon: Icon(
                                            state.playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: strings.next,
                                      onPressed: controller.next,
                                      icon: const Icon(Icons.skip_next_rounded),
                                    ),
                                    IconButton(
                                      key: const ValueKey('mini-player-queue'),
                                      tooltip: strings.isZh
                                          ? '当前队列'
                                          : 'Play queue',
                                      onPressed: () => showPlaybackQueue(
                                        context,
                                        controller,
                                      ),
                                      icon: const Icon(
                                        Icons.queue_music_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  70,
                                  0,
                                  16,
                                  12,
                                ),
                                child: MiniPlaybackProgress(
                                  controller: controller,
                                  item: item,
                                  state: state,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Future<void> _openPlayer(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => PlayerPage(controller: controller),
      ),
    );
  }
}
