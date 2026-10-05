import 'dart:async';
import 'package:ai_music/src/application/playback_cache_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'same window does not repeat downloads and one failure does not block others',
    () async {
      final ids = <String>[];
      final prefetch = PlaybackCachePrefetch(
        startDelay: Duration.zero,
        prepare: (id, token) async {
          ids.add(id);
          if (id == 'bad') throw StateError('Unavailable');
        },
      );
      prefetch.activate(['1', 'bad', '3', '4', '5']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      prefetch.activate(['1', 'bad', '3', '4', '5']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ids, ['1', 'bad', '3', '4', '5']);
      await prefetch.cancel();
    },
  );

  test(
    'replacement window waits for cancellation before writing another song',
    () async {
      final ids = <String>[];
      final firstStarted = Completer<void>();
      final firstStopped = Completer<void>();
      final release = Completer<void>();
      final prefetch = PlaybackCachePrefetch(
        startDelay: Duration.zero,
        prepare: (id, token) async {
          ids.add(id);
          if (id == 'old') {
            firstStarted.complete();
            try {
              await token.wait(release.future);
            } finally {
              firstStopped.complete();
            }
          } else {
            expect(firstStopped.isCompleted, isTrue);
          }
        },
      );
      prefetch.activate(['old', 'never']);
      await firstStarted.future;
      prefetch.activate(['new', 'following']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ids, ['old', 'new', 'following']);
      await prefetch.cancel();
      release.complete();
    },
  );

  test('pause cancels delayed work and resumes with a fresh window', () async {
    final ids = <String>[];
    final prefetch = PlaybackCachePrefetch(
      startDelay: const Duration(milliseconds: 20),
      prepare: (id, token) async => ids.add(id),
    );
    prefetch.activate(['not-started']);
    await prefetch.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ids, isEmpty);
    prefetch.activate(['resumed']);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ids, ['resumed']);
    await prefetch.cancel();
  });
}
