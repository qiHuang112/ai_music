import 'package:ai_music/src/playback/playback_index_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual target is not kept when target is already current index', () {
    final tracker = PlaybackIndexTracker()
      ..markPublished(0)
      ..markManualTarget(currentIndex: 0, targetIndex: 0);

    expect(tracker.manualTargetIndex, isNull);
    expect(
      tracker.handleIndexChanged(1, shuffleModeEnabled: true, itemCount: 3),
      PlaybackIndexChangeAction.redirectAutomaticShuffle,
    );
  });

  test('stale manual target clears and allows automatic shuffle redirect', () {
    final tracker = PlaybackIndexTracker()
      ..markPublished(0)
      ..markManualTarget(currentIndex: 0, targetIndex: 2);

    expect(
      tracker.handleIndexChanged(1, shuffleModeEnabled: true, itemCount: 3),
      PlaybackIndexChangeAction.redirectAutomaticShuffle,
    );
    expect(tracker.manualTargetIndex, isNull);
  });

  test('matching manual target publishes without shuffle redirect', () {
    final tracker = PlaybackIndexTracker()
      ..markPublished(0)
      ..markManualTarget(currentIndex: 0, targetIndex: 2);

    expect(
      tracker.handleIndexChanged(2, shuffleModeEnabled: true, itemCount: 3),
      PlaybackIndexChangeAction.publish,
    );
    expect(tracker.manualTargetIndex, isNull);
  });
}
