enum PlaybackIndexChangeAction { publish, ignore, redirectAutomaticShuffle }

class PlaybackIndexTracker {
  int? lastIndex;
  int? manualTargetIndex;
  int? pendingShuffleRedirectIndex;

  void reset() {
    lastIndex = null;
    manualTargetIndex = null;
    pendingShuffleRedirectIndex = null;
  }

  void markPublished(int? index) {
    lastIndex = index;
  }

  void markManualTarget({
    required int? currentIndex,
    required int targetIndex,
  }) {
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
      return PlaybackIndexChangeAction.ignore;
    }

    if (manualTargetIndex != null) {
      if (index == manualTargetIndex) {
        manualTargetIndex = null;
        return PlaybackIndexChangeAction.publish;
      }
      manualTargetIndex = null;
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
