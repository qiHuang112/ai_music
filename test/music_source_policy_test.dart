import 'dart:async';
import 'package:ai_music/src/data/auto_source_health.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/provider_request_scheduler.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('limited category remains last even with a higher numeric priority', () {
    const catalog = MusicSourceCatalog([
      MusicSourcePolicy(
        source: MusicDataSource.twentyFourBit,
        access: MusicSourceAccess.limitedFallback,
        priority: 1,
      ),
      MusicSourcePolicy(
        source: MusicDataSource.flac,
        access: MusicSourceAccess.direct,
        priority: 90,
      ),
      MusicSourcePolicy(
        source: MusicDataSource.buguyy,
        access: MusicSourceAccess.direct,
        priority: 100,
      ),
    ]);
    expect(catalog.autoSources(), [
      MusicDataSource.flac,
      MusicDataSource.buguyy,
      MusicDataSource.twentyFourBit,
    ]);
    expect(catalog.manualSources(), [
      MusicDataSource.flac,
      MusicDataSource.buguyy,
    ]);
    expect(catalog.sourcesBefore(MusicDataSource.twentyFourBit), [
      MusicDataSource.flac,
      MusicDataSource.buguyy,
    ]);
  });
  test(
    'authorization gates requests and Auto without pretending a quota failure',
    () async {
      const catalog = MusicSourceCatalog([
        MusicSourcePolicy(
          source: MusicDataSource.buguyy,
          access: MusicSourceAccess.authorizationRequired,
          priority: 1,
        ),
      ]);
      var authorized = false, calls = 0;
      final health = AutoSourceHealth(
        catalog: catalog,
        isAuthorized: (_) => authorized,
      );
      expect(health.availableSources, isEmpty);
      await expectLater(
        health.run(MusicDataSource.buguyy, () async {
          calls++;
        }, automatic: false),
        throwsStateError,
      );
      expect(calls, 0);
      authorized = true;
      await health.run(MusicDataSource.buguyy, () async {
        calls++;
      }, automatic: true);
      expect(
        health.availability(MusicDataSource.buguyy),
        MusicSourceAvailability.available,
      );
      authorized = false;
      expect(health.availableSources, isEmpty);
      expect(
        health.availability(MusicDataSource.buguyy),
        MusicSourceAvailability.authorizationRequired,
      );
    },
  );
  test(
    'network reset discards late failures and cancels old queued work',
    () async {
      final health = AutoSourceHealth(
        failureThreshold: 1,
        maxConcurrentPerSource: 1,
      );
      final gate = Completer<void>();
      final active = health.run(MusicDataSource.flac, () async {
        await gate.future;
        throw StateError('HTTP 429');
      }, automatic: true);
      final activeChecked = expectLater(active, throwsStateError);
      final queued = health.run(
        MusicDataSource.flac,
        () async => fail('old queued request started'),
        automatic: true,
      );
      final queuedChecked = expectLater(queued, throwsStateError);
      health.reset(MusicDataSource.flac);
      gate.complete();
      await Future.wait([activeChecked, queuedChecked]);
      await health.run(MusicDataSource.flac, () async {}, automatic: true);
      expect(
        health.availability(MusicDataSource.flac),
        MusicSourceAvailability.available,
      );
      expect(health.isAvailable(MusicDataSource.flac), true);
    },
  );
  test(
    'new host reuses configured limits without scheduler source branches',
    () async {
      const catalog = MusicSourceCatalog([
        MusicSourcePolicy(
          source: MusicDataSource.flac,
          access: MusicSourceAccess.direct,
          priority: 1,
          requestHosts: ['new.test'],
          requestLimits: MusicSourceRequestLimits(
            spacing: Duration.zero,
            maxConcurrent: 1,
          ),
        ),
      ]);
      final scheduler = ProviderRequestScheduler(catalog: catalog);
      final release = Completer<void>();
      var started = 0;
      final uri = Uri.parse('https://new.test/api');
      Future<ResolverHttpResponse> action() async {
        started++;
        await release.future;
        return ResolverHttpResponse(statusCode: 200, body: '{}', finalUrl: uri);
      }

      final jobs = [scheduler.run(uri, action), scheduler.run(uri, action)];
      expect(started, 1);
      release.complete();
      await Future.wait(jobs);
      expect(started, 2);
    },
  );
  test(
    'unverified and future authorization classifications are not UI statuses',
    () {
      const strings = AppStrings(AppLanguage.zh);
      expect(
        strings.sourceAvailabilityLabel(MusicSourceAvailability.unknown),
        isNull,
      );
      expect(
        strings.sourceAvailabilityLabel(MusicSourceAvailability.checking),
        isNull,
      );
      expect(
        strings.sourceAvailabilityLabel(
          MusicSourceAvailability.authorizationRequired,
        ),
        isNull,
      );
      expect(
        strings.sourceAvailabilityLabel(MusicSourceAvailability.quotaExhausted),
        '额度已耗尽',
      );
    },
  );
}
