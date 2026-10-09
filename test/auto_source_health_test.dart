import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/data/auto_source_health.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = MusicDataSource.buguyy;
  const failure = HttpException('HTTP 503');

  test('working search cannot hide repeated resolve or media failures', () {
    for (final operation in [
      AutoSourceOperation.resolve,
      AutoSourceOperation.media,
    ]) {
      final health = AutoSourceHealth();
      for (var i = 0; i < 3; i++) {
        health.recordSuccess(source);
        health.recordFailure(source, failure, operation: operation);
      }
      expect(health.isAvailable(source), isFalse);
    }
  });

  test(
    'successful operations reset consecutive failures before degradation',
    () {
      final health = AutoSourceHealth();
      health.recordFailure(source, failure);
      health.recordFailure(source, failure);
      expect(health.isAvailable(source), isTrue);
      health.recordSuccess(source);
      health.recordFailure(source, failure);
      health.recordFailure(source, failure);
      expect(health.isAvailable(source), isTrue);
      health.recordFailure(source, failure);
      expect(health.availableSources, [MusicDataSource.flac]);
      expect(health.degradationReason(source), contains('3'));
      expect(AutoSourceHealth().isAvailable(source), isTrue);
    },
  );

  test(
    'missing music, unsupported audio and cancellation do not disable source',
    () {
      final health = AutoSourceHealth();
      final errors = [
        StateError('No URL returned'),
        StateError('No downloadable quality found'),
        StateError('请求已过期'),
        const UnsupportedEncryptedAudioException(),
        const HttpException('HTTP 404'),
        const HttpException('HTTP 416'),
        const HttpException('Audio returned 404'),
        const HttpException('Audio returned 416'),
        StateError('Download cancelled'),
        StateError('用户取消'),
      ];
      for (var round = 0; round < 4; round++) {
        for (final error in errors) {
          health.recordFailure(source, error);
        }
      }
      expect(health.isAvailable(source), isTrue);
    },
  );

  test('late and manual successes cannot reopen a degraded circuit', () async {
    final health = AutoSourceHealth();
    final response = Completer<String>();
    final pending = health.run(source, () => response.future, automatic: true);
    for (var i = 0; i < 3; i++) {
      health.recordFailure(source, failure);
    }
    response.complete('late success');
    expect(await pending, 'late success');
    expect(health.isAvailable(source), isFalse);
    expect(
      await health.run(source, () async => 'manual test', automatic: false),
      'manual test',
    );
    expect(health.isAvailable(source), isFalse);
    await expectLater(
      health.run(
        source,
        () async => fail('disabled source requested'),
        automatic: true,
      ),
      throwsA(isA<AutoSourceUnavailableException>()),
    );
  });

  test(
    'queued searches stop at degradation before their HTTP request starts',
    () async {
      final health = AutoSourceHealth();
      final gate = Completer<void>();
      var calls = 0;
      var active = 0;
      var peak = 0;
      final outcomes = [
        for (var i = 0; i < 20; i++)
          health
              .run<void>(source, () async {
                calls++;
                active++;
                if (active > peak) peak = active;
                await gate.future;
                active--;
                throw failure;
              }, automatic: true)
              .then<Object?>((_) => null, onError: (Object e) => e),
      ];
      expect(calls, 2);
      gate.complete();
      final results = await Future.wait(outcomes);
      expect(peak, 2);
      expect(calls, inInclusiveRange(3, 4));
      expect(
        results.whereType<AutoSourceUnavailableException>(),
        hasLength(20 - calls),
      );
      expect(health.isAvailable(source), isFalse);
    },
  );

  test(
    'queued work wakes on circuit opening even while active requests hang',
    () async {
      final health = AutoSourceHealth();
      final gate = Completer<void>();
      final active = [
        for (var i = 0; i < 2; i++)
          health.run(source, () => gate.future, automatic: true),
      ];
      final queued = health.run(
        source,
        () async => fail('queued request started'),
        automatic: true,
      );
      final checked = expectLater(
        queued,
        throwsA(isA<AutoSourceUnavailableException>()),
      );
      for (var i = 0; i < 3; i++) {
        health.recordFailure(source, failure);
      }
      await checked.timeout(const Duration(seconds: 1));
      gate.complete();
      await Future.wait(active);
      expect(health.isAvailable(source), isFalse);
    },
  );

  test('cancelled operation does not count its late network failure', () async {
    final health = AutoSourceHealth();
    var cancelled = false;
    final gate = Completer<void>();
    final pending = health.run(
      source,
      () async {
        await gate.future;
        throw failure;
      },
      automatic: true,
      isCancelled: () => cancelled,
    );
    final checked = expectLater(pending, throwsA(isA<HttpException>()));
    cancelled = true;
    gate.complete();
    await checked;
    health.recordFailure(source, failure);
    health.recordFailure(source, failure);
    expect(health.isAvailable(source), isTrue);
  });

  test(
    'cancelled queued search releases its place to the next live search',
    () async {
      final health = AutoSourceHealth(maxConcurrentPerSource: 1);
      final gate = Completer<void>();
      final first = health.run(source, () => gate.future, automatic: true);
      var cancelled = false;
      final second = health.run(
        source,
        () async => fail('cancelled queued search started'),
        automatic: true,
        isCancelled: () => cancelled,
      );
      final checked = expectLater(second, throwsA(isA<StateError>()));
      final third = health.run(source, () async => 'next', automatic: true);
      cancelled = true;
      gate.complete();
      await first;
      await checked;
      expect(await third.timeout(const Duration(seconds: 1)), 'next');
    },
  );
}
