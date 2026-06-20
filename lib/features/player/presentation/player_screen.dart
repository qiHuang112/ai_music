import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/player_controller.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    final playback = ref.watch(playbackStateProvider).value;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value ?? Duration.zero;
    final isPlaying = playback?.playing ?? false;
    final repeatOne = playback?.repeatMode == AudioServiceRepeatMode.one;

    return Scaffold(
      appBar: AppBar(title: const Text('正在播放')),
      body: SafeArea(
        child: mediaItem == null
            ? const _NoTrack()
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              size: 96,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      mediaItem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mediaItem.artist ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SeekSection(position: position, duration: duration),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '单曲循环',
                          onPressed: () => ref
                              .read(playerControllerProvider)
                              .toggleRepeatOne(),
                          icon: Icon(
                            repeatOne
                                ? Icons.repeat_one_on_rounded
                                : Icons.repeat_one_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '上一首',
                          onPressed: () =>
                              ref.read(playerControllerProvider).previous(),
                          icon: const Icon(Icons.skip_previous_rounded),
                          iconSize: 36,
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: isPlaying ? '暂停' : '播放',
                          onPressed: () => ref
                              .read(playerControllerProvider)
                              .togglePlayPause(),
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          iconSize: 40,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '下一首',
                          onPressed: () =>
                              ref.read(playerControllerProvider).next(),
                          icon: const Icon(Icons.skip_next_rounded),
                          iconSize: 36,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '顺序播放',
                          onPressed: repeatOne
                              ? () => ref
                                    .read(playerControllerProvider)
                                    .toggleRepeatOne()
                              : null,
                          icon: const Icon(Icons.repeat_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SeekSection extends ConsumerWidget {
  const _SeekSection({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalMs = math.max(duration.inMilliseconds, 1);
    final currentMs = position.inMilliseconds.clamp(0, totalMs);

    return Column(
      children: [
        Slider(
          min: 0,
          max: totalMs.toDouble(),
          value: currentMs.toDouble(),
          onChanged: (_) {},
          onChangeEnd: (value) => ref
              .read(playerControllerProvider)
              .seek(Duration(milliseconds: value.round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position)),
              Text(_formatDuration(duration)),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoTrack extends StatelessWidget {
  const _NoTrack();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('从曲库选择一首歌开始播放'));
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString();
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours <= 0) {
    return '$minutes:$seconds';
  }
  return '$hours:${minutes.padLeft(2, '0')}:$seconds';
}
