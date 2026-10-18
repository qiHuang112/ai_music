import 'dart:async';

import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_resolver.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'file_sharing.dart';

/// Keep the current source visible without adding icons to the menu.
class SongSourceMenuLabel extends StatelessWidget {
  const SongSourceMenuLabel({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Text(strings.isZh ? '切换来源（$source）' : 'Switch source ($source)');
  }
}

Future<void> shareSong(
  BuildContext context,
  MusicController controller,
  Track track, {
  MusicSearchCandidate? candidate,
}) async {
  final strings = AppStringsScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  DialogRoute<void>? progress;
  var cancelled = false;
  VoidCallback? cancelWork;
  void closeProgress() {
    final route = progress;
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
    progress = null;
  }

  try {
    var file = await controller.cachedFileForSharing(
      track,
      candidate: candidate,
    );
    if (!context.mounted) return;
    if (file == null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      progress = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              cancelled = true;
              cancelWork?.call();
              closeProgress();
            }
          },
          child: AlertDialog(
            title: Text(strings.isZh ? '正在准备分享…' : 'Preparing to share…'),
            content: const LinearProgressIndicator(),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  cancelWork?.call();
                  closeProgress();
                },
                child: Text(strings.cancel),
              ),
            ],
          ),
        ),
      );
      unawaited(navigator.push(progress!));
      file = await controller.prepareTrackForSharing(
        track,
        candidate: candidate,
        isCancelled: () => cancelled || !context.mounted,
        onCancelReady: (cancel) {
          cancelWork = cancel;
          if (cancelled) cancel();
        },
      );
    }
    closeProgress();
    if (cancelled || !context.mounted) return;
    await FileSharing.share(
      file.path,
      name: [
        track.title,
        track.artist,
      ].where((s) => s.trim().isNotEmpty).join(' - '),
      chooserTitle: strings.isZh ? '分享音频' : 'Share audio',
    );
  } catch (error) {
    closeProgress();
    if (!cancelled && context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.isZh ? '分享失败，请重试' : 'Unable to share. Please retry.',
          ),
        ),
      );
    }
  }
}
