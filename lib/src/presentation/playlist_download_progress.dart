import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_playlists.dart';
import 'app_localizations.dart';

class PlaylistDownloadProgressView extends StatelessWidget {
  const PlaylistDownloadProgressView({
    super.key,
    required this.controller,
    required this.playlist,
  });

  final MusicController controller;
  final MusicPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final progress = controller.playlistDownloadProgress(playlist);
    if (progress == null) return const SizedBox.shrink();
    final strings = AppStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.playlistDownloadProgress(
            controller.cachedCountForPlaylist(playlist),
            progress.total,
            progress.processed,
          ),
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          key: ValueKey('playlist-progress-${playlist.id}'),
          value: progress.fraction,
        ),
      ],
    );
  }
}
