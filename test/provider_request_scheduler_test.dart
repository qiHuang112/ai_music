import 'dart:async';
import 'package:ai_music/src/data/provider_request_scheduler.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final flac = Uri.parse('https://flac.music.hi.cn/api');
  final buguyy = Uri.parse('https://buguyy.top/api');
  final bit24 = Uri.parse(
    'https://www.24bit.net/api/player/searchOnlineMusicTwo',
  );
  ResolverHttpResponse reply({
    int status = 200,
    String body = '{}',
    Map<String, String> headers = const {},
  }) => ResolverHttpResponse(
    statusCode: status,
    body: body,
    headers: headers,
    finalUrl: buguyy,
  );
  test(
    '24bit burst is paced and foreground precedes background backlog',
    () async {
      final scheduler = ProviderRequestScheduler(
        spacing: Duration.zero,
        sourceSpacing: const {
          MusicDataSource.twentyFourBit: Duration(milliseconds: 20),
        },
      );
      final release = Completer<void>();
      final starts = <String>[];
      final clock = Stopwatch()..start();
      final times = <int>[];
      Future<ResolverHttpResponse> action(
        String label, {
        bool hold = false,
      }) async {
        starts.add(label);
        times.add(clock.elapsedMilliseconds);
        if (hold) await release.future;
        return reply();
      }

      final first = runBackgroundProviderWork(
        () => scheduler.run(bit24, () => action('bg1', hold: true)),
      );
      final second = runBackgroundProviderWork(
        () => scheduler.run(bit24, () => action('bg2')),
      );
      await scheduler.run(bit24, () => action('user'));
      expect(starts, ['bg1', 'user']);
      expect(times[1] - times[0], greaterThanOrEqualTo(18));
      release.complete();
      await Future.wait([first, second]);
      expect(starts.last, 'bg2');
    },
  );
  test(
    '24bit cooldown stops queued burst and leaves YY and FLAC independent',
    () async {
      final scheduler = ProviderRequestScheduler(
        sourceSpacing: const {MusicDataSource.twentyFourBit: Duration.zero},
        maxConcurrent: 1,
      );
      var calls = 0;
      final release = Completer<void>();
      final first = scheduler.run(bit24, () async {
        calls++;
        await release.future;
        return reply(status: 429, headers: {'retry-after': '30'});
      });
      final a = expectLater(first, throwsA(isA<ProviderRateLimitException>()));
      final second = scheduler.run(bit24, () async {
        calls++;
        return reply();
      });
      final b = expectLater(second, throwsA(isA<ProviderRateLimitException>()));
      release.complete();
      await Future.wait([a, b]);
      expect(calls, 1);
      expect(
        (await scheduler.run(buguyy, () async => reply())).statusCode,
        200,
      );
      expect((await scheduler.run(flac, () async => reply())).statusCode, 200);
    },
  );
  test('BuguYY HTTP concurrency is two and FLAC is independent', () async {
    final gate = ProviderRequestScheduler(spacing: Duration.zero);
    final release = Completer<void>();
    var active = 0, peak = 0, started = 0;
    Future<ResolverHttpResponse> action() async {
      started++;
      active++;
      if (active > peak) peak = active;
      await release.future;
      active--;
      return reply();
    }

    final jobs = [for (var i = 0; i < 6; i++) gate.run(buguyy, action)];
    await Future<void>.delayed(Duration.zero);
    expect(started, 2);
    expect((await gate.run(flac, () => Future.value(reply()))).statusCode, 200);
    release.complete();
    await Future.wait(jobs);
    expect(peak, 2);
  });
  for (final uri in [
    flac,
    Uri.parse('https://challenge.rivers.chaitin.cn/api'),
  ]) {
    test(
      'FLAC bypasses concurrency, spacing and cooldown at ${uri.host}',
      () async {
        final gate = ProviderRequestScheduler(
          spacing: const Duration(milliseconds: 20),
          maxConcurrent: 1,
        );
        final release = Completer<void>();
        var started = 0;
        final jobs = [
          for (var i = 0; i < 6; i++)
            gate.run(uri, () async {
              started++;
              await release.future;
              return reply(status: 429, headers: {'retry-after': '30'});
            }),
        ];
        final immediatelyStarted = started;
        release.complete();
        final responses = await Future.wait(jobs);
        expect(immediatelyStarted, 6);
        expect(responses.every((response) => response.statusCode == 429), true);
        expect(
          (await gate.run(uri, () => Future.value(reply()))).statusCode,
          200,
        );
      },
    );
  }
  test(
    'background uses one slot; queued interactive work goes first',
    () async {
      final gate = ProviderRequestScheduler(spacing: Duration.zero);
      final release = Completer<void>();
      final started = <String>[];
      final first = runBackgroundProviderWork(
        () => gate.run(buguyy, () async {
          started.add('background1');
          await release.future;
          return reply();
        }),
      );
      final second = runBackgroundProviderWork(
        () => gate.run(buguyy, () async {
          started.add('background2');
          return reply();
        }),
      );
      final user = gate.run(buguyy, () async {
        started.add('user');
        return reply();
      });
      await user;
      expect(started, ['background1', 'user']);
      release.complete();
      await Future.wait([first, second]);
      expect(started.last, 'background2');
    },
  );
  test(
    'request start spacing applies even to immediately completed requests',
    () async {
      final gate = ProviderRequestScheduler(
        spacing: const Duration(milliseconds: 20),
      );
      final clock = Stopwatch()..start();
      final starts = <int>[];
      await Future.wait([
        for (var i = 0; i < 3; i++)
          gate.run(buguyy, () async {
            starts.add(clock.elapsedMilliseconds);
            return reply();
          }),
      ]);
      expect(starts[1] - starts[0], greaterThanOrEqualTo(18));
      expect(starts[2] - starts[1], greaterThanOrEqualTo(18));
    },
  );
  for (final payload in [false, true]) {
    test(
      'rate limit cooldown fails queued work without retries payload=$payload',
      () async {
        var now = DateTime(2026);
        final gate = ProviderRequestScheduler(
          spacing: Duration.zero,
          now: () => now,
          maxConcurrent: 1,
        );
        final release = Completer<void>();
        var calls = 0;
        final first = gate.run(buguyy, () async {
          calls++;
          await release.future;
          return reply(
            status: payload ? 200 : 429,
            body: payload ? '{"message":"请求过于频繁"}' : '{}',
            headers: {'retry-after': '30'},
          );
        });
        final a = expectLater(
          first,
          throwsA(isA<ProviderRateLimitException>()),
        );
        final queued = gate.run(buguyy, () async {
          calls++;
          return reply();
        });
        final b = expectLater(
          queued,
          throwsA(isA<ProviderRateLimitException>()),
        );
        release.complete();
        await Future.wait([a, b]);
        expect(calls, 1);
        await expectLater(
          gate.run(buguyy, () async {
            calls++;
            return reply();
          }),
          throwsA(isA<ProviderRateLimitException>()),
        );
        now = now.add(const Duration(seconds: 31));
        await gate.run(buguyy, () async {
          calls++;
          return reply();
        });
        expect(calls, 2);
      },
    );
  }
  test('cancelled queued request never reaches the service', () async {
    final gate = ProviderRequestScheduler(
      spacing: Duration.zero,
      maxConcurrent: 1,
    );
    final release = Completer<void>();
    var cancelled = false, calls = 0;
    final active = gate.run(buguyy, () async {
      await release.future;
      return reply();
    });
    final waiting = runZoned(
      () => gate.run(buguyy, () async {
        calls++;
        return reply();
      }),
      zoneValues: {providerCancellationKey: () => cancelled},
    );
    final check = expectLater(waiting, throwsStateError);
    cancelled = true;
    release.complete();
    await active;
    await check;
    expect(calls, 0);
  });
}
