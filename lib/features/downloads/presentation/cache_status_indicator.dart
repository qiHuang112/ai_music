import 'package:flutter/material.dart';

import '../../library/domain/track.dart';

class CacheStatusIndicator extends StatelessWidget {
  const CacheStatusIndicator({
    super.key,
    required this.track,
    required this.progress,
    required this.onCachePressed,
  });

  final Track track;
  final double? progress;
  final VoidCallback? onCachePressed;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    if (value != null) {
      return SizedBox.square(
        dimension: 40,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: value <= 0 ? null : value,
          ),
        ),
      );
    }

    if (track.isCached) {
      return Icon(
        Icons.offline_pin_rounded,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (track.cacheState == TrackCacheState.failed) {
      return IconButton(
        tooltip: '重新缓存',
        onPressed: onCachePressed,
        icon: const Icon(Icons.error_outline_rounded),
      );
    }

    return IconButton(
      tooltip: '缓存到沙盒',
      onPressed: onCachePressed,
      icon: const Icon(Icons.download_for_offline_outlined),
    );
  }
}
