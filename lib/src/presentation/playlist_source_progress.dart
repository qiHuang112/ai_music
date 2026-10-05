import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import 'app_localizations.dart';

class PlaylistSourceProgress extends StatelessWidget {
  const PlaylistSourceProgress({
    super.key,
    required this.controller,
    required this.playlistId,
  });
  final MusicController controller;
  final String playlistId;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.playlistSourceProgress,
    builder: (context, statuses, _) {
      final status = statuses[playlistId];
      if (status == null || (!status.matching && status.failed == 0)) {
        return const SizedBox.shrink();
      }
      final remaining = status.failed + status.total - status.completed;
      final zh = AppStringsScope.of(context).isZh;
      return Padding(
        key: const Key('playlist-source-matching-progress'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    status.matching
                        ? (zh
                              ? '正在匹配音源 ${status.completed}/${status.total} 首'
                              : 'Matching sources ${status.completed}/${status.total}')
                        : (zh
                              ? '有 $remaining 首暂未匹配到音源'
                              : '$remaining songs have no source yet'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!status.matching)
                  TextButton(
                    onPressed: () =>
                        controller.matchPlaylistSources(playlistId),
                    child: Text(zh ? '重试' : 'Retry'),
                  ),
              ],
            ),
            if (status.matching)
              LinearProgressIndicator(
                minHeight: 3,
                value: status.total == 0 ? 0 : status.completed / status.total,
              ),
          ],
        ),
      );
    },
  );
}
