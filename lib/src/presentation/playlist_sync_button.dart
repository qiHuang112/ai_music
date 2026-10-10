import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import '../data/music_playlists.dart';
import 'app_localizations.dart';

class PlaylistSyncButton extends StatefulWidget {
  const PlaylistSyncButton({
    super.key,
    required this.controller,
    required this.playlist,
  });
  final MusicController controller;
  final MusicPlaylist playlist;
  @override
  State<PlaylistSyncButton> createState() => _PlaylistSyncButtonState();
}

class _PlaylistSyncButtonState extends State<PlaylistSyncButton> {
  bool _syncing = false;
  Future<void> _sync() async {
    if (_syncing) return;
    final zh = AppStringsScope.of(context).isZh;
    setState(() => _syncing = true);
    try {
      final unavailable = await widget.controller.syncOnlinePlaylist(
        widget.playlist,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              unavailable > 0
                  ? (zh
                        ? '已同步可读取歌曲，另 $unavailable 首暂无法读取，原有歌曲保留'
                        : 'Available songs synchronized; local songs retained.')
                  : (zh ? '已同步最新歌单内容' : 'Playlist synchronized'),
            ),
          ),
        );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(zh ? '同步失败，请重试' : 'Sync failed. Retry.')),
          );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('my-playlist-sync'),
    tooltip: AppStringsScope.of(context).isZh ? '同步最新内容' : 'Sync playlist',
    onPressed: _syncing ? null : _sync,
    icon: _syncing
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.sync),
  );
}
