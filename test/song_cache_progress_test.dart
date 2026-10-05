import 'package:ai_music/src/application/song_cache_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'byte events update only their song and deduplicate unchanged values',
    () {
      final progress = SongCacheProgressController();
      addTearDown(progress.dispose);
      final song = progress.listenable('flac|123');
      final unrelated = progress.listenable('buguyy|123');
      var changes = 0;
      var otherChanges = 0;
      song.addListener(() => changes++);
      unrelated.addListener(() => otherChanges++);
      for (var i = 0; i <= 100; i++) {
        progress.streaming('flac|123', bytes: i, total: 200, active: true);
      }
      expect(song.value.fraction, .5);
      expect(song.value.offline, false);
      expect(changes, 101);
      expect(otherChanges, 0);
      progress.streaming('flac|123', bytes: 100, total: 200, active: true);
      expect(changes, 101);
      progress.stopStreaming('flac|123');
      expect(song.value.active, false);
      expect(song.value.fraction, .5);
    },
  );

  test(
    'complete validation, upgrade, cancellation and clearing stay distinct',
    () {
      final progress = SongCacheProgressController();
      addTearDown(progress.dispose);
      final song = progress.listenable('song');
      progress.streaming('song', bytes: 200, total: 200, active: true);
      expect(song.value.offline, false);
      progress.removePartial('song');
      progress.completeKeys({'song'});
      expect(song.value, const SongCacheProgress(fraction: 1, offline: true));
      progress.download('song', active: true, bytes: 40, total: 200);
      expect(song.value.fraction, .2);
      expect(song.value.offline, true);
      progress.download('song', active: false);
      expect(song.value.fraction, 1);
      progress.completeKeys({});
      expect(song.value.fraction, 0);
      expect(song.value.offline, false);
    },
  );

  test(
    'restores persisted parts, protects writers and removes evicted parts',
    () {
      final progress = SongCacheProgressController();
      addTearDown(progress.dispose);
      final writing = progress.listenable('writing');
      final paused = progress.listenable('paused');
      progress.streaming('writing', bytes: 80, total: 100, active: true);
      progress.replaceInactiveParts({
        'writing': (bytes: 10, total: 100),
        'paused': (bytes: 25, total: 100),
      });
      expect(writing.value.fraction, .8);
      expect(paused.value.fraction, .25);
      expect(paused.value.active, false);
      progress.replaceInactiveParts({});
      expect(paused.value.fraction, 0);
      expect(writing.value.active, true);
      progress.clearParts();
      expect(writing.value.fraction, 0);
    },
  );

  test(
    'unknown lengths are indeterminate and oversized reports are clamped',
    () {
      final progress = SongCacheProgressController();
      addTearDown(progress.dispose);
      final song = progress.listenable('song');
      progress.streaming('song', bytes: 5, active: true);
      expect(song.value.fraction, null);
      progress.streaming('song', bytes: 500, total: 100, active: true);
      expect(song.value.fraction, 1);
      progress.streaming('song', bytes: -5, total: 100, active: true);
      expect(song.value.fraction, 0);
    },
  );
}
