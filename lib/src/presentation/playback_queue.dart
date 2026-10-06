import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../application/song_cache_progress.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'music_thumbnail.dart';

Future<void> showPlaybackQueue(
  BuildContext context,
  MusicController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => PlaybackQueue(controller: controller),
);

/// Live queue: audio-service publishes appends and source replacements here.
class PlaybackQueue extends StatefulWidget {
  const PlaybackQueue({super.key, required this.controller});
  final MusicController controller;

  @override
  State<PlaybackQueue> createState() => _PlaybackQueueState();
}

class _PlaybackQueueState extends State<PlaybackQueue> {
  String? _pending;
  String? _error;
  int _request = 0;
  late final StreamSubscription<PlaybackState> _errors;

  @override
  void initState() {
    super.initState();
    _errors = widget.controller.playbackStateStream.listen((state) {
      if (mounted &&
          state.processingState == AudioProcessingState.error &&
          (_pending == null ||
              widget.controller.audioHandler.mediaItem.value?.id == _pending)) {
        setState(() => _error = state.errorMessage ?? 'Playback failed');
      }
    });
  }

  @override
  void dispose() {
    unawaited(_errors.cancel());
    super.dispose();
  }

  Future<void> _select(String id) async {
    if (_pending == id) return;
    final request = ++_request;
    setState(() {
      _pending = id;
      _error = null;
    });
    try {
      await widget.controller.playQueueItem(id);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && request == _request) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: SafeArea(
        top: false,
        child: StreamBuilder<List<MediaItem>>(
          stream: controller.audioHandler.queue,
          initialData: controller.audioHandler.queue.value,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <MediaItem>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: MusicUi.horizontalInsets,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.isZh
                              ? '当前队列 · ${items.length}'
                              : 'Play queue · ${items.length}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: MusicUi.horizontalInsets,
                    child: Text(
                      strings.playTrackFailed(_error!),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(child: Text(strings.nothingPlaying))
                      : StreamBuilder<MediaItem?>(
                          stream: controller.mediaItemStream,
                          initialData: controller.audioHandler.mediaItem.value,
                          builder: (context, current) => ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final active = current.data?.id == item.id;
                              return ListTile(
                                key: ValueKey('queue-item-${item.id}'),
                                selected: active,
                                selectedTileColor: colors.secondaryContainer,
                                leading: MusicThumbnail(
                                  uri: item.artUri,
                                  size: 44,
                                ),
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  item.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: _pending == item.id
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : active
                                    ? Icon(
                                        Icons.equalizer_rounded,
                                        color: colors.primary,
                                      )
                                    : null,
                                onTap: () => _select(item.id),
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

/// The high-frequency stream rebuilds only this inset progress area.
class MiniPlaybackProgress extends StatelessWidget {
  const MiniPlaybackProgress({
    super.key,
    required this.controller,
    required this.item,
    required this.state,
  });
  final MusicController controller;
  final MediaItem item;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    key: ValueKey(item.id),
    stream: controller.positionStream,
    initialData: controller.audioHandler.currentPosition,
    builder: (context, position) => ValueListenableBuilder<SongCacheProgress>(
      valueListenable: controller.cacheProgressForId(item.id),
      builder: (context, cache, _) {
        final colors = Theme.of(context).colorScheme;
        final duration = item.duration?.inMilliseconds ?? 0;
        final played = duration <= 0
            ? 0.0
            : ((position.data?.inMilliseconds ?? 0) / duration).clamp(0.0, 1.0);
        final buffered = duration <= 0
            ? 0.0
            : cache.offline
            ? 1.0
            : (state.bufferedPosition.inMilliseconds / duration).clamp(
                0.0,
                1.0,
              );
        return ExcludeSemantics(
          child: SizedBox(
            key: const ValueKey('mini-playback-progress'),
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    key: const ValueKey('mini-buffered-progress'),
                    widthFactor: buffered,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.onSurface.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    key: const ValueKey('mini-played-progress'),
                    widthFactor: played,
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Center(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colors.primary,
                                    colors.primaryContainer,
                                  ],
                                  begin: AlignmentDirectional.centerStart,
                                  end: AlignmentDirectional.centerEnd,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          if (played > 0)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Container(
                                key: const ValueKey('mini-playback-head'),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.primaryContainer.withValues(
                                        alpha: .35,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
