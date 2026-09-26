import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/prefetch_retry.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delay ladder honors floors and longer server Retry-After', () {
    const policy = PrefetchRetryPolicy();
    expect(
      [for (var i = 0; i < 6; i++) policy.delay(i)],
      [
        const Duration(seconds: 5),
        const Duration(seconds: 15),
        const Duration(seconds: 30),
        const Duration(seconds: 60),
        const Duration(seconds: 60),
        const Duration(seconds: 60),
      ],
    );
    expect(
      policy.delay(0, retryAfter: const Duration(seconds: 90)),
      const Duration(seconds: 90),
    );
  });

  test('expired 403 and truncated transfers retry, invalid audio does not', () {
    expect(
      classifyAudioPrefetchFailure(
        const HttpException('download HTTP 403'),
      ).definitive,
      isFalse,
    );
    expect(
      classifyAudioPrefetchFailure(
        const AudioTruncatedException('download ended early'),
      ).definitive,
      isFalse,
    );
    expect(
      classifyAudioPrefetchFailure(
        const AudioValidationException('download returned text/html'),
      ).definitive,
      isTrue,
    );
  });

  test(
    'offline waits and reconnect triggers one deduplicated attempt',
    () async {
      var calls = 0;
      final retry = NextTrackPrefetch(
        prepare: (_) async {
          calls += 1;
        },
        classify: (_) => const PrefetchFailure(),
      );
      retry.setOnline(false);
      retry.activate('next');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      retry.setOnline(true);
      retry.setOnline(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      retry.cancel();
    },
  );

  test('queue change cancels scheduled retry', () async {
    final scheduled = <Duration>[];
    final pending = <_FakeTimer>[];
    final calls = <String>[];
    final retry = NextTrackPrefetch(
      prepare: (track) async {
        calls.add(track);
        if (track == 'old') throw StateError('timeout');
      },
      classify: (_) => const PrefetchFailure(),
      jitterMs: () => 0,
      schedule: (duration, action) {
        scheduled.add(duration);
        final timer = _FakeTimer(action);
        pending.add(timer);
        return timer;
      },
    );
    retry.activate('old');
    await Future<void>.delayed(Duration.zero);
    expect(scheduled, [const Duration(seconds: 5)]);
    retry.activate('new');
    pending.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['old', 'new']);
    retry.cancel();
  });

  test(
    'new queue never prepares concurrently with canceled old work',
    () async {
      final oldDone = Completer<void>();
      final started = <String>[];
      final canceled = <String>[];
      final retry = NextTrackPrefetch(
        prepare: (track) async {
          started.add(track);
          if (track == 'old') await oldDone.future;
        },
        classify: (_) => const PrefetchFailure(),
        onCancel: canceled.add,
      );
      retry.activate('old');
      await Future<void>.delayed(Duration.zero);
      retry.activate('new');
      expect(canceled, ['old']);
      expect(started, ['old']);
      oldDone.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(started, ['old', 'new']);
      retry.cancel();
    },
  );

  test('expired 403 re-enters preparation after bounded backoff', () async {
    final pending = <_FakeTimer>[];
    var resolutions = 0;
    final retry = NextTrackPrefetch(
      prepare: (_) async {
        resolutions += 1;
        if (resolutions == 1) {
          throw const HttpException('download HTTP 403');
        }
      },
      classify: classifyAudioPrefetchFailure,
      jitterMs: () => 0,
      schedule: (_, action) {
        final timer = _FakeTimer(action);
        pending.add(timer);
        return timer;
      },
    );
    retry.activate('expiring-link');
    await Future<void>.delayed(Duration.zero);
    expect(resolutions, 1);
    expect(pending, hasLength(1));
    pending.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(resolutions, 2);
    expect(retry.trackId, isNull);
  });

  test('reconnect cannot bypass Retry-After deadline', () async {
    final now = DateTime(2026);
    var clock = now;
    final pending = <_FakeTimer>[];
    final scheduled = <Duration>[];
    var attempts = 0;
    final retry = NextTrackPrefetch(
      prepare: (_) async {
        attempts += 1;
        throw StateError('rate limited');
      },
      classify: (_) => const PrefetchFailure(retryAfter: Duration(seconds: 90)),
      now: () => clock,
      jitterMs: () => 0,
      schedule: (duration, action) {
        scheduled.add(duration);
        final timer = _FakeTimer(action);
        pending.add(timer);
        return timer;
      },
    );
    retry.activate('next');
    await Future<void>.delayed(Duration.zero);
    expect(scheduled, [const Duration(seconds: 90)]);
    retry.setOnline(false);
    clock = now.add(const Duration(seconds: 10));
    retry.setOnline(true);
    expect(attempts, 1);
    expect(scheduled.last, const Duration(seconds: 80));
    retry.cancel();
    pending.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);
  });

  test(
    'definitive failure moves to the following eligible track once',
    () async {
      final calls = <String>[];
      final retry = NextTrackPrefetch(
        prepare: (track) async {
          calls.add(track);
          if (track == 'invalid') throw const FormatException('not audio');
        },
        classify: (_) => const PrefetchFailure(definitive: true),
        nextAfterDefinitive: (failed) =>
            failed == 'invalid' ? 'following' : null,
      );

      retry.activate('invalid');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['invalid', 'following']);
      expect(retry.trackId, isNull);
      retry.cancel();
    },
  );
}

class _FakeTimer implements Timer {
  _FakeTimer(this._action);

  final void Function() _action;
  bool _active = true;

  void fire() {
    if (_active) _action();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
