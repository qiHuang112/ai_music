import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_playlists.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';

Future<MusicPlaylist?> showCreatePlaylistDialog(
  BuildContext context,
  MusicController controller, {
  Track? initialTrack,
}) async {
  final name = await _playlistNameDialog(
    context,
    title: AppStringsScope.of(context).newPlaylist,
    actionLabel: AppStringsScope.of(context).create,
  );
  if (name == null) {
    return null;
  }
  final playlist = await controller.createPlaylist(name);
  if (playlist != null && initialTrack != null) {
    await controller.addTrackToPlaylist(playlist, initialTrack);
  }
  return playlist;
}

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  MusicController controller,
  Track track,
) {
  final parentContext = context;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final strings = AppStringsScope.of(parentContext);
      final playlists = controller.customPlaylists;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(strings.newPlaylist),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Future<void>.delayed(Duration.zero);
                if (!parentContext.mounted) {
                  return;
                }
                await showCreatePlaylistDialog(
                  parentContext,
                  controller,
                  initialTrack: track,
                );
              },
            ),
            if (playlists.isEmpty)
              ListTile(
                title: Text(strings.noCustomPlaylistsYet),
                subtitle: Text(strings.createOneToGroup),
              )
            else
              for (final playlist in playlists)
                ListTile(
                  leading: Icon(
                    controller.isInPlaylist(playlist, track)
                        ? Icons.check
                        : Icons.queue_music,
                  ),
                  title: Text(playlist.name),
                  subtitle: Text(
                    controller.isInPlaylist(playlist, track)
                        ? strings.alreadyAdded
                        : strings.addToThisPlaylist,
                  ),
                  enabled: !controller.isInPlaylist(playlist, track),
                  onTap: () async {
                    await controller.addTrackToPlaylist(playlist, track);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

Future<String?> playlistNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
}) {
  return _playlistNameDialog(
    context,
    title: title,
    actionLabel: actionLabel,
    initialValue: initialValue,
  );
}

Future<String?> _playlistNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return _PlaylistNameDialog(
        title: title,
        actionLabel: actionLabel,
        initialValue: initialValue,
      );
    },
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.title,
    required this.actionLabel,
    required this.initialValue,
  });

  final String title;
  final String actionLabel;
  final String initialValue;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: AppStringsScope.of(context).playlistName,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStringsScope.of(context).cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }

  void _submit() {
    final value = _controller.text;
    Navigator.of(context).pop(value);
  }
}
