import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../downloads/presentation/cache_status_indicator.dart';
import '../../player/application/player_controller.dart';
import '../application/library_controller.dart';
import '../domain/track.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Music'),
        actions: [
          IconButton(
            tooltip: '导入曲库',
            onPressed: () => ref
                .read(libraryControllerProvider.notifier)
                .importFromSources(),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: library.when(
          loading: () => const _LoadingLibrary(),
          error: (error, stackTrace) => _LibraryError(message: '$error'),
          data: (state) => _LibraryContent(state: state),
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _LibraryContent extends ConsumerWidget {
  const _LibraryContent({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.tracks.isEmpty) {
      return _EmptyLibrary(errorMessage: state.errorMessage);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LibrarySummary(state: state),
        if (state.errorMessage != null)
          _InlineNotice(message: state.errorMessage!),
        Expanded(
          child: ListView.separated(
            itemCount: state.tracks.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final track = state.tracks[index];
              final progress = state.downloadProgress[track.id];
              return _TrackTile(track: track, index: index, progress: progress);
            },
          ),
        ),
      ],
    );
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.progress,
  });

  final Track track;
  final int index;
  final double? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: SizedBox.square(
        dimension: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        track.displaySubtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: CacheStatusIndicator(
        track: track,
        progress: progress,
        onCachePressed: progress == null
            ? () =>
                  ref.read(libraryControllerProvider.notifier).cacheTrack(track)
            : null,
      ),
      onTap: () async {
        try {
          await ref.read(playerControllerProvider).playTrack(track);
        } catch (error) {
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('播放失败：$error')));
        }
      },
    );
  }
}

class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final source = state.lastSourceUri?.host ?? '本地沙盒';
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(label: '曲库', value: '${state.tracks.length}'),
          ),
          Expanded(
            child: _SummaryMetric(label: '已缓存', value: '${state.cachedCount}'),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '音源',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  state.isImporting ? '导入中' : source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (mediaItem == null) {
      return const SizedBox.shrink();
    }

    final playback = ref.watch(playbackStateProvider).value;
    final isPlaying = playback?.playing ?? false;

    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 6,
        child: InkWell(
          onTap: () => context.go('/player'),
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.album_rounded, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mediaItem.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        mediaItem.artist ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isPlaying ? '暂停' : '播放',
                  onPressed: () =>
                      ref.read(playerControllerProvider).togglePlayPause(),
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 34,
                  ),
                ),
                IconButton(
                  tooltip: '下一首',
                  onPressed: () => ref.read(playerControllerProvider).next(),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.errorContainer,
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class _EmptyLibrary extends ConsumerWidget {
  const _EmptyLibrary({this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 54),
            const SizedBox(height: 16),
            Text(errorMessage ?? '还没有导入曲库', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref
                  .read(libraryControllerProvider.notifier)
                  .importFromSources(),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('导入本地音源'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryError extends ConsumerWidget {
  const _LibraryError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 54),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref
                  .read(libraryControllerProvider.notifier)
                  .importFromSources(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingLibrary extends StatelessWidget {
  const _LoadingLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
