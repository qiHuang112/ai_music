import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../application/song_cache_progress.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'design/controls.dart';
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

  // Editing: rows picked for a batch removal, and the order shown while a
  // move is still on its way to the player.
  bool _selecting = false;
  final _picked = <String>{};
  List<MediaItem>? _moving;

  Future<void> _edit(Future<void> Function() edit) async {
    try {
      await edit();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _moving = null);
    }
  }

  Future<void> _remove(Iterable<String> ids) =>
      _edit(() => widget.controller.removeQueueItems(ids));

  Future<void> _clear(List<MediaItem> items, String? currentId) async {
    final strings = AppStringsScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.isZh ? '清空队列？' : 'Clear the queue?'),
        content: Text(
          strings.isZh
              ? '正在播放的这首会保留，其余歌曲从队列中移除。歌单和已下载的文件不受影响。'
              : 'The song that is playing stays; the rest leave the queue. '
                    'Playlists and downloads are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.isZh ? '清空' : 'Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _remove([
      for (final item in items)
        if (item.id != currentId) item.id,
    ]);
  }

  void _reorder(List<MediaItem> items, int from, int to) {
    if (to > from) to -= 1;
    if (from == to) return;
    final item = items[from];
    setState(() => _moving = [...items]..insert(to, items.removeAt(from)));
    _edit(() => widget.controller.moveQueueItem(item.id, to));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      // Full screen: the queue is a place to browse, not a peek.
      height: MediaQuery.sizeOf(context).height,
      child: SafeArea(
        top: false,
        child: StreamBuilder<List<MediaItem>>(
          stream: controller.audioHandler.queue,
          initialData: controller.audioHandler.queue.value,
          builder: (context, snapshot) {
            final items = _moving ?? snapshot.data ?? const <MediaItem>[];
            return StreamBuilder<MediaItem?>(
              stream: controller.mediaItemStream,
              initialData: controller.audioHandler.mediaItem.value,
              builder: (context, current) {
                final currentId = current.data?.id;
                final editable = items.length > 1;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: MusicUi.pagePadding,
                        end: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selecting
                                  ? (strings.isZh
                                        ? '已选 ${_picked.length} 首'
                                        : '${_picked.length} selected')
                                  : (strings.isZh
                                        ? '当前队列 · ${items.length}'
                                        : 'Play queue · ${items.length}'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (_selecting) ...[
                            IconButton(
                              key: const ValueKey('queue-remove-selected'),
                              tooltip: strings.isZh
                                  ? '移除所选'
                                  : 'Remove selected',
                              onPressed: _picked.isEmpty
                                  ? null
                                  : () {
                                      final ids = _picked.toList();
                                      setState(() {
                                        _picked.clear();
                                        _selecting = false;
                                      });
                                      _remove(ids);
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _picked.clear();
                                _selecting = false;
                              }),
                              child: Text(strings.isZh ? '完成' : 'Done'),
                            ),
                          ] else ...[
                            IconButton(
                              key: const ValueKey('queue-select'),
                              tooltip: strings.isZh ? '批量操作' : 'Select',
                              onPressed: editable
                                  ? () => setState(() => _selecting = true)
                                  : null,
                              icon: const Icon(Icons.checklist_rounded),
                            ),
                            IconButton(
                              key: const ValueKey('queue-clear'),
                              tooltip: strings.isZh ? '清空队列' : 'Clear queue',
                              onPressed: editable
                                  ? () => _clear(items, currentId)
                                  : null,
                              icon: const Icon(Icons.delete_sweep_outlined),
                            ),
                            IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
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
                          : ReorderableListView.builder(
                              buildDefaultDragHandles: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              itemCount: items.length,
                              // flutter_ohos does not support onReorderItem
                              // yet.
                              // ignore: deprecated_member_use
                              onReorder: (from, to) =>
                                  _reorder(items, from, to),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final active = currentId == item.id;
                                final picked = _picked.contains(item.id);
                                void toggle() => setState(() {
                                  picked
                                      ? _picked.remove(item.id)
                                      : _picked.add(item.id);
                                });
                                return ListTile(
                                  key: ValueKey('queue-item-${item.id}'),
                                  selected: active,
                                  selectedTileColor: colors.secondaryContainer,
                                  contentPadding:
                                      const EdgeInsetsDirectional.only(
                                        start: 12,
                                        end: 4,
                                      ),
                                  leading: _selecting
                                      // The playing song cannot be removed.
                                      ? Checkbox(
                                          value: picked,
                                          onChanged: active
                                              ? null
                                              : (_) => toggle(),
                                        )
                                      : _QueueCover(
                                          controller: controller,
                                          item: item,
                                          active: active,
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
                                      ? const Padding(
                                          padding: EdgeInsets.all(14),
                                          child: SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : active || _selecting
                                      ? null
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: strings.isZh
                                                  ? '从队列移除'
                                                  : 'Remove from queue',
                                              onPressed: () =>
                                                  _remove([item.id]),
                                              icon: Icon(
                                                Icons.close_rounded,
                                                size: 20,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: Tooltip(
                                                message: strings.dragToReorder,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Icon(
                                                    Icons.drag_handle_rounded,
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                  onTap: _selecting
                                      ? (active ? null : toggle)
                                      : () => _select(item.id),
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
      ),
    );
  }
}

/// A queue row's cover. On the song that is playing it carries the same level
/// meter as the song lists: moving while it plays, resting when paused.
class _QueueCover extends StatelessWidget {
  const _QueueCover({
    required this.controller,
    required this.item,
    required this.active,
  });

  final MusicController controller;
  final MediaItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final cover = MusicThumbnail(uri: item.artUri, size: size);
    if (!active) return cover;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          cover,
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: StreamBuilder<PlaybackState>(
                stream: controller.playbackStateStream,
                initialData: controller.audioHandler.playbackState.value,
                builder: (context, state) => EqualizerBars(
                  playing: state.data?.playing ?? false,
                  size: 18,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
              ),
            ),
          ),
        ],
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
    this.child,
  });
  final MusicController controller;
  final MediaItem item;
  final PlaybackState state;

  /// What the ring goes around: the mini player's record.
  final Widget? child;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    key: ValueKey(item.id),
    stream: controller.positionStream,
    initialData: controller.audioHandler.currentPosition,
    builder: (context, position) => ValueListenableBuilder<SongCacheProgress>(
      valueListenable: controller.cacheProgressForId(item.id),
      builder: (context, cache, _) {
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
        return ProgressRing(
          key: const ValueKey('mini-playback-progress'),
          played: played,
          buffered: buffered,
          child: child,
        );
      },
    ),
  );
}

/// Playback progress drawn around its child as a ring: it starts at twelve
/// o'clock and runs clockwise, with the buffered part faint behind it.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.played,
    required this.buffered,
    this.child,
    this.stroke = 3,
    this.gap = 2,
  });

  /// Both run from 0 to 1.
  final double played, buffered;
  final Widget? child;
  final double stroke, gap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RingPainter(
            played: played,
            buffered: buffered,
            stroke: stroke,
            rail: colors.onSurface,
            from: colors.primary,
            to: colors.primaryContainer,
          ),
          child: Padding(padding: EdgeInsets.all(stroke + gap), child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.played,
    required this.buffered,
    required this.stroke,
    required this.rail,
    required this.from,
    required this.to,
  });

  final double played, buffered, stroke;
  final Color rail, from, to;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    const top = -math.pi / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      center,
      radius,
      line..color = rail.withValues(alpha: .12),
    );
    if (buffered > 0) {
      canvas.drawArc(
        bounds,
        top,
        2 * math.pi * buffered,
        false,
        line..color = rail.withValues(alpha: .22),
      );
    }
    if (played > 0) {
      canvas.drawArc(
        bounds,
        top,
        2 * math.pi * played,
        false,
        line
          ..color = to
          ..shader = SweepGradient(
            colors: [from, to],
            transform: const GradientRotation(top),
          ).createShader(bounds),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.stroke != stroke ||
      old.rail != rail ||
      old.from != from ||
      old.to != to;
}
