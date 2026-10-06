enum PlaybackIndexChangeAction { publish, ignore, redirectAutomaticShuffle }

class PlaybackIndexTracker {
  int? lastIndex;
  int? manualTargetIndex;
  int? _manualOriginIndex;
  int? pendingShuffleRedirectIndex;

  void reset() {
    lastIndex = null;
    manualTargetIndex = null;
    _manualOriginIndex = null;
    pendingShuffleRedirectIndex = null;
  }

  void markPublished(int? index) {
    lastIndex = index;
  }

  void markManualTarget({
    required int? currentIndex,
    required int targetIndex,
  }) {
    pendingShuffleRedirectIndex = null;
    _manualOriginIndex = currentIndex;
    manualTargetIndex = currentIndex == targetIndex ? null : targetIndex;
  }

  void markPendingShuffleRedirect(int index) {
    pendingShuffleRedirectIndex = index;
  }

  PlaybackIndexChangeAction handleIndexChanged(
    int index, {
    required bool shuffleModeEnabled,
    required int itemCount,
  }) {
    if (pendingShuffleRedirectIndex != null) {
      if (index == pendingShuffleRedirectIndex) {
        pendingShuffleRedirectIndex = null;
        return PlaybackIndexChangeAction.publish;
      }
      // Native may still be on the intermediate source or skip an unavailable
      // target. Metadata must always describe the source actually producing
      // audio, even while a shuffle seek is pending.
      if (index != lastIndex) pendingShuffleRedirectIndex = null;
      return PlaybackIndexChangeAction.publish;
    }

    if (manualTargetIndex != null) {
      if (index == manualTargetIndex) {
        manualTargetIndex = null;
        return PlaybackIndexChangeAction.publish;
      }
      if (index != _manualOriginIndex) manualTargetIndex = null;
      return PlaybackIndexChangeAction.publish;
    }

    if (shuffleModeEnabled &&
        itemCount > 1 &&
        lastIndex != null &&
        lastIndex != index) {
      return PlaybackIndexChangeAction.redirectAutomaticShuffle;
    }

    return PlaybackIndexChangeAction.publish;
  }
}
