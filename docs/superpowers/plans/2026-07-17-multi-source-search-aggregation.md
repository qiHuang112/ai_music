# AI Music Multi-Source Search Aggregation Implementation Plan

## 2026-07-17 Device Search Addendum

1. Add RED coverage proving matching complete cached tracks appear immediately for artist and artist-title queries, before remote completion, and play through the local cached path.
2. Merge cached and remote candidates conservatively by normalized title and artist while preserving distinct versions.
3. Keep initial aggregation bounded to three sequential pages/eight visible tracks; never overlap pages for one provider.
4. Record provider failure/circuit diagnostics so device evidence distinguishes timeout, 403/429, defender, and empty validated results.
5. Probe BuguYY, FLAC, and 22a5 at low frequency on the Xiaomi device. Admit none unless search plus complete direct-audio validation succeeds without bypassing security controls.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggregate strictly validated Gequhai and Kuwo full-audio results in `Auto` search, append them dynamically across pages, and keep the active search playback queue synchronized without pre-downloading unplayed songs.

**Architecture:** Add a focused data-layer coordinator that concurrently consumes the existing paginated Gequhai and Kuwo streams, keeps per-source circuit/page state, filters to client-ready full audio, and emits stable deduplicated page snapshots. `RemoteMusicResolver` delegates only its `Auto` path to this coordinator; `MusicController` and the search UI distinguish initial blocking search from background append while reusing the existing search playback session.

**Tech Stack:** Dart 3, Flutter, `dart:async`, existing `MusicSearchProgress`/resolver models, Flutter test, Android ADB/media session evidence.

## Global Constraints

- Start from a lead-provided independent Project Path whose baseline contains `origin/release/1.1.0@3e5a95f4213aa957f084d1e27e629da2c2ba0edf`.
- Do not use a Git worktree and do not modify the completed AM-20260711-005 Project Path.
- Developer must not stage, commit, merge, or push. Each task ends with a review checkpoint; the lead exclusively performs Git submission after acceptance.
- Complete local cache, `MusicDataSource.gequhai`, and `MusicDataSource.kuwoFullAudio` join the current aggregation. Other remote sources require Xiaomi reachability plus complete-audio admission evidence before joining.
- Visible results must already satisfy `directAudio`, `canCacheAudio`, `clientReady`, audio HEAD, and consistent Range 206 validation.
- PREVIEW, HTML, external-pan, challenge/defender, and low-confidence candidates remain fail closed.
- Per-source validation concurrency remains at most 2; total media-validation concurrency is at most 4.
- Initial pagination is bounded to three sequential pages/eight visible tracks per the latest device feedback. Later pagination remains user-triggered.
- Unplayed candidates must not create a progressive session, part file, or formal cache entry.
- Preserve current playback modes, dynamic search queue behavior, lyrics recovery, seek, and cache promotion behavior.
- User-approved spec: `docs/superpowers/specs/2026-07-17-multi-source-search-aggregation-design.md`.

---

## File Map

- Create `lib/src/data/multi_source_search_coordinator.dart`: source-independent concurrent merge, deduplication, page exhaustion, circuit breaker, and aggregate error behavior.
- Modify `lib/src/data/music_resolver.dart`: construct the two providers and route `Auto` pagination through the coordinator; remove the single-source short circuit.
- Modify `lib/src/application/music_controller.dart`: expose initial-versus-background search loading getters while retaining request-id cancellation and page accumulation.
- Modify `lib/src/presentation/music_home_page.dart`: show full-page/search-button loading only before first results, then use the existing list-tail progress treatment.
- Create `test/multi_source_search_coordinator_test.dart`: deterministic coordinator RED/GREEN coverage with controlled source streams and a fake clock.
- Modify `test/music_resolver_test.dart`: integration coverage for Gequhai+Kuwo page aggregation and resolver-level source failures.
- Modify `test/music_controller_test.dart`: dynamic cross-source queue growth, stale-query rejection, and no pre-download coverage.
- Modify `test/widget_test.dart`: initial loading, dynamic append, stable rows, and partial-source-failure UI coverage.

---

### Task 1: Concurrent Multi-Source Coordinator

**Files:**
- Create: `lib/src/data/multi_source_search_coordinator.dart`
- Create: `test/multi_source_search_coordinator_test.dart`

**Interfaces:**
- Consumes: `MusicDataSource`, `MusicSearchCandidate`, and `MusicSearchProgress` from `resolver_models.dart`.
- Produces: `MultiSourceSearchProvider`, `MultiSourceSearchCoordinator.searchPage`, `MultiSourceSearchFailure`, and `multiSourceCandidateKey`.

- [ ] **Step 1: Write the controlled provider harness and first failing append test**

```dart
final class _ProviderHarness {
  _ProviderHarness(this.source);

  final MusicDataSource source;
  final controllers = <int, StreamController<MusicSearchProgress>>{};
  final calls = <int>[];

  MultiSourceSearchProvider get provider => MultiSourceSearchProvider(
    source: source,
    searchPage: (query, {required page}) {
      calls.add(page);
      return (controllers[page] ??= StreamController()).stream;
    },
  );
}

test('emits first validated source then appends the second source', () async {
  final gequhai = _ProviderHarness(MusicDataSource.gequhai);
  final kuwo = _ProviderHarness(MusicDataSource.kuwoFullAudio);
  final coordinator = MultiSourceSearchCoordinator(
    providers: [gequhai.provider, kuwo.provider],
  );
  final emissions = <MusicSearchProgress>[];
  final done = coordinator.searchPage('周杰伦', page: 1).listen(emissions.add);

  kuwo.controllers[1]!.add(
    MusicSearchProgress(
      candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '晴天')],
      isComplete: true,
      hasNextPage: true,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  expect(emissions.last.candidates.map((item) => item.name), ['晴天']);

  gequhai.controllers[1]!.add(
    MusicSearchProgress(
      candidates: [_readyCandidate(MusicDataSource.gequhai, '夜曲')],
      isComplete: true,
      hasNextPage: true,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  expect(emissions.last.candidates.map((item) => item.name), ['晴天', '夜曲']);

  await gequhai.controllers[1]!.close();
  await kuwo.controllers[1]!.close();
  await done.asFuture<void>();
});
```

- [ ] **Step 2: Run the first RED test**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/multi_source_search_coordinator_test.dart --plain-name 'emits first validated source then appends the second source'
```

Expected: FAIL because `MultiSourceSearchProvider` and `MultiSourceSearchCoordinator` do not exist.

- [ ] **Step 3: Add the coordinator public API and concurrent event pump**

```dart
import 'dart:async';

import 'resolver_models.dart';

typedef SourcePageSearch = Stream<MusicSearchProgress> Function(
  String query, {
  required int page,
});

final class MultiSourceSearchProvider {
  const MultiSourceSearchProvider({
    required this.source,
    required this.searchPage,
  });

  final MusicDataSource source;
  final SourcePageSearch searchPage;
}

final class MultiSourceSearchFailure implements Exception {
  const MultiSourceSearchFailure(this.errors);

  final Map<MusicDataSource, Object> errors;

  @override
  String toString() => errors.entries
      .map((entry) => '${entry.key.storageValue}: ${entry.value}')
      .join('; ');
}

final class MultiSourceSearchCoordinator {
  MultiSourceSearchCoordinator({
    required List<MultiSourceSearchProvider> providers,
    DateTime Function()? now,
    this.circuitDuration = const Duration(minutes: 2),
  }) : _providers = List.unmodifiable(providers),
       _now = now ?? DateTime.now;

  final List<MultiSourceSearchProvider> _providers;
  final DateTime Function() _now;
  final Duration circuitDuration;
  final Map<MusicDataSource, DateTime> _retryAfter = {};
  final Map<MusicDataSource, bool> _hasNext = {};
  final Set<String> _seen = {};
  String _query = '';

  Stream<MusicSearchProgress> searchPage(
    String query, {
    required int page,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty || page < 1) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page < 1 ? 1 : page,
      );
      return;
    }
    if (_query != trimmed || page == 1) {
      _query = trimmed;
      _seen.clear();
      _hasNext
        ..clear()
        ..addEntries(_providers.map((item) => MapEntry(item.source, true)));
    }

    final active = _providers.where((provider) {
      final retryAfter = _retryAfter[provider.source];
      final circuitOpen = retryAfter != null && _now().isBefore(retryAfter);
      return !circuitOpen && (page == 1 || _hasNext[provider.source] != false);
    }).toList(growable: false);
    if (active.isEmpty) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
        hasNextPage: _hasNext.values.any((value) => value),
      );
      return;
    }

    final events = StreamController<_ProviderEvent>();
    final subscriptions = <StreamSubscription<MusicSearchProgress>>[];
    final complete = <MusicDataSource>{};
    final errors = <MusicDataSource, Object>{};
    final pageCandidates = <MusicSearchCandidate>[];

    void finish(MusicDataSource source) {
      if (!complete.add(source)) return;
      if (complete.length == active.length && !events.isClosed) {
        unawaited(events.close());
      }
    }

    for (final provider in active) {
      late final StreamSubscription<MusicSearchProgress> subscription;
      subscription = provider.searchPage(trimmed, page: page).listen(
        (progress) => events.add(_ProviderEvent.progress(provider.source, progress)),
        onError: (Object error, StackTrace stackTrace) {
          events.add(_ProviderEvent.error(provider.source, error));
          finish(provider.source);
        },
        onDone: () => finish(provider.source),
      );
      subscriptions.add(subscription);
    }

    try {
      await for (final event in events.stream) {
        final error = event.error;
        if (error != null) {
          errors[event.source] = error;
          if (_opensCircuit(error)) {
            _retryAfter[event.source] = _now().add(circuitDuration);
          }
        }
        final progress = event.progress;
        if (progress != null) {
          _hasNext[event.source] = progress.hasNextPage;
          if (progress.error != null) {
            errors[event.source] = progress.error!;
            if (_opensCircuit(progress.error!)) {
              _retryAfter[event.source] = _now().add(circuitDuration);
            }
          } else if (progress.isComplete) {
            _retryAfter.remove(event.source);
          }
          for (final candidate in progress.candidates) {
            if (!candidate.isClientReady) continue;
            if (_seen.add(multiSourceCandidateKey(candidate))) {
              pageCandidates.add(candidate);
            }
          }
          if (progress.isComplete) finish(event.source);
        }
        final allComplete = complete.length == active.length;
        yield MusicSearchProgress(
          candidates: List.unmodifiable(pageCandidates),
          isComplete: allComplete,
          page: page,
          hasNextPage: _hasNext.values.any((value) => value),
          error: allComplete && pageCandidates.isEmpty && errors.isNotEmpty
              ? MultiSourceSearchFailure(Map.unmodifiable(errors))
              : null,
        );
      }
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      if (!events.isClosed) await events.close();
    }
  }
}
```

Add the event type, circuit classifier, and conservative identity normalizer in the same file:

```dart
final class _ProviderEvent {
  const _ProviderEvent.progress(this.source, this.progress) : error = null;
  const _ProviderEvent.error(this.source, this.error) : progress = null;

  final MusicDataSource source;
  final MusicSearchProgress? progress;
  final Object? error;
}

bool _opensCircuit(Object error) {
  final failureCode = error is SourceDownloadException
      ? error.failureCode.toLowerCase()
      : '';
  const blockingCodes = {
    'provider_http_403',
    'provider_http_429',
    'security_or_defender',
    'defender_challenge',
    'security_verification',
  };
  if (blockingCodes.contains(failureCode)) return true;
  final text = error.toString().toLowerCase();
  return text.contains('http 403') ||
      text.contains('http 429') ||
      text.contains('defender') ||
      text.contains('security verification');
}

String multiSourceCandidateKey(MusicSearchCandidate candidate) {
  final title = _normalizeIdentityText(candidate.name);
  final artist = _normalizeIdentityText(candidate.artist);
  final fallback = candidate.name.trim().isEmpty
      ? _normalizeIdentityText(candidate.keyword)
      : title;
  return '$fallback\u0000$artist';
}

String _normalizeIdentityText(String value) {
  final decoded = value.replaceAllMapped(
    RegExp(r'\\+u([0-9a-fA-F]{4})'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );
  return decoded
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\u00a0&＆/,，、·•・]+'), '')
      .trim();
}
```

This intentionally preserves version words and bracketed suffixes, so original, live, DJ, and accompaniment variants do not collapse merely because punctuation differs.

- [ ] **Step 4: Add RED cases for dedup, circuit isolation, exhaustion, and aggregate failure**

Add tests with exact assertions:

```dart
expect(multiSourceCandidateKey(escapedArtist), multiSourceCandidateKey(decodedArtist));
expect(pageCandidates.map((item) => item.name), ['晴天']);
expect(gequhai.calls, [1]); // second search occurs while its circuit is open
expect(kuwo.calls, [1, 1]);
expect(exhausted.calls, [1]); // page 2 skips the exhausted source
expect(finalProgress.error, isA<MultiSourceSearchFailure>());
```

- [ ] **Step 5: Run the complete coordinator suite GREEN**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/multi_source_search_coordinator_test.dart
```

Expected: all coordinator tests pass with no pending timers or open controllers.

- [ ] **Step 6: Developer review checkpoint**

Report the new file API, RED/GREEN output, and `git diff --check` to the lead. Do not stage or commit.

---

### Task 2: Route Auto Search Through Both Validated Sources

**Files:**
- Modify: `lib/src/data/music_resolver.dart`
- Modify: `test/music_resolver_test.dart`

**Interfaces:**
- Consumes: `MultiSourceSearchCoordinator.searchPage(String, {required int page})`.
- Produces: unchanged `PaginatedProgressiveMusicResolver.searchPageProgressively` behavior for callers, now with cumulative two-source page snapshots.

- [ ] **Step 1: Write resolver integration RED tests**

Add tests that drive the existing fake HTTP client and collect every emission:

```dart
final emissions = await resolver
    .searchPageProgressively('周杰伦', MusicDataSource.auto, page: 1)
    .toList();

expect(emissions.last.isComplete, isTrue);
expect(
  emissions.last.candidates.map((item) => item.source).toSet(),
  {MusicDataSource.gequhai, MusicDataSource.kuwoFullAudio},
);
expect(emissions.last.candidates.every((item) => item.isClientReady), isTrue);
```

Add separate cases for: same title/artist from both sources deduplicates; Gequhai 429 plus Kuwo success returns Kuwo without a global error; a second same-process search skips Gequhai during cooldown; page 2 does not call an exhausted provider.

- [ ] **Step 2: Run resolver RED tests**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/music_resolver_test.dart --plain-name 'auto aggregates validated gequhai and kuwo results'
```

Expected: FAIL because current `Auto` returns immediately after the first non-empty source.

- [ ] **Step 3: Construct and delegate to the coordinator**

In `RemoteMusicResolver`:

```dart
late final MultiSourceSearchCoordinator _autoSearch;

// At the end of the constructor body, after both concrete resolvers exist:
_autoSearch = MultiSourceSearchCoordinator(
  providers: [
    MultiSourceSearchProvider(
      source: MusicDataSource.gequhai,
      searchPage: (query, {required page}) =>
          _gequhai.searchPageProgressively(query, page: page),
    ),
    MultiSourceSearchProvider(
      source: MusicDataSource.kuwoFullAudio,
      searchPage: (query, {required page}) =>
          _kuwoFullAudio.searchPageProgressively(query, page: page),
    ),
  ],
);
```

Replace `_searchAutoPageProgressively` with a direct logged delegation:

```dart
Stream<MusicSearchProgress> _searchAutoPageProgressively(
  String query, {
  required int page,
}) async* {
  _logResolver('[AI Music][resolver] search query="$query" source=auto page=$page');
  await for (final progress in _autoSearch.searchPage(query, page: page)) {
    if (progress.isComplete) {
      _logResolver(
        '[AI Music][resolver] search done query="$query" source=auto '
        'page=$page count=${progress.candidates.length} '
        'sources=${progress.candidates.map((item) => item.source.storageValue).toSet().join(",")} '
        'hasNextPage=${progress.hasNextPage}',
      );
    }
    yield progress;
  }
}
```

Remove `_activeAutoQuery`, `_activeAutoSource`, `_gequhaiRetryAfter`, and `_autoFallbackError`; their behavior is owned by the coordinator. Export the coordinator from `music_resolver.dart` only if tests or another data-layer caller need the public type.

- [ ] **Step 4: Run resolver GREEN and regression tests**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/music_resolver_test.dart
```

Expected: all resolver tests pass, including existing natural-language artist correction, prepared-resolution freshness, 403/429 failover, and pagination cases.

- [ ] **Step 5: Developer review checkpoint**

Report source request counts and final source sets for the new integration tests. Do not stage or commit.

---

### Task 3: Separate Initial Loading From Background Append

**Files:**
- Modify: `lib/src/application/music_controller.dart`
- Modify: `lib/src/presentation/music_home_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `MusicController.isInitialSearchLoading` and `MusicController.isAppendingSearchResults`.
- Consumes: existing `isSearching`, `isLoadingMoreSearch`, and `candidates` state.

- [ ] **Step 1: Write widget RED tests for first result and tail append**

Use the existing controlled paginated widget resolver. Assert:

```dart
expect(find.byType(LinearProgressIndicator), findsOneWidget);
resolver.emit([gequhaiReady], isComplete: false, hasNextPage: true);
await tester.pump();

expect(find.text('外婆'), findsOneWidget);
expect(find.byType(LinearProgressIndicator), findsNothing);
expect(find.byType(CircularProgressIndicator), findsOneWidget); // list tail only
expect(searchButton(tester).onPressed, isNotNull);
```

Then emit a Kuwo result and assert the original row remains at index 0 and the new row appears at index 1.

- [ ] **Step 2: Run widget RED test**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/widget_test.dart --plain-name 'shows first source immediately and appends the second at list tail'
```

Expected: FAIL because `isSearching` still drives the header spinner and top linear progress until both sources finish.

- [ ] **Step 3: Add derived controller loading getters**

```dart
bool get isInitialSearchLoading => isSearching && candidates.isEmpty;

bool get isAppendingSearchResults =>
    isLoadingMoreSearch || (isSearching && candidates.isNotEmpty);
```

Do not mutate `isSearching` early. It continues to protect request lifecycle and final cleanup; the new getters only define presentation behavior.

- [ ] **Step 4: Wire the search header and panel to derived states**

At the `MusicHomePage` call site:

```dart
_SearchHeader(
  controller: _searchController,
  isSearching: controller.isInitialSearchLoading,
  // existing callbacks unchanged
),
_OnlineSearchPanel(
  candidates: controller.candidates,
  isSearching: controller.isInitialSearchLoading,
  isLoadingMore: controller.isAppendingSearchResults,
  // remaining arguments unchanged
),
```

Keep the existing list-tail progress item and its stable dimensions. Do not add a new banner, source filter, or settings control.

- [ ] **Step 5: Run widget GREEN suite**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/widget_test.dart
```

Expected: all widget tests pass with no row movement and no overflow.

- [ ] **Step 6: Developer review checkpoint**

Return before/after widget assertions and a screenshot from a local debug run if available. Do not stage or commit.

---

### Task 4: Dynamic Queue, Cancellation, and No Pre-Download Guarantees

**Files:**
- Modify: `test/music_controller_test.dart`
- Modify only if RED requires it: `lib/src/application/music_controller.dart`
- Modify only if RED requires it: `lib/src/application/search_playback_session.dart`

**Interfaces:**
- Consumes: cumulative page snapshots from the resolver and existing `SearchPlaybackSession.append`.
- Produces: no new public API unless a failing test exposes an ownership defect.

- [ ] **Step 1: Add a RED test for cross-source queue growth**

```dart
await controller.search('周杰伦');
resolver.emitPage(1, [gequhaiSong], isComplete: false, hasNextPage: true);
await pumpEventQueue();
await controller.playCandidate(gequhaiSong);

resolver.emitPage(1, [gequhaiSong, kuwoSong], isComplete: true, hasNextPage: true);
await pumpEventQueue();

expect(handler.publishedQueue.map((item) => item.title), ['外婆', '晴天']);
expect(handler.mediaItem.value?.title, '外婆');
expect(streamingCache.openedCandidateIds, ['gequhai-id']);
expect(cacheStore.cachedCandidateIds, isNot(contains('kuwo-id')));
```

- [ ] **Step 2: Add stale-query and duplicate-update cases**

Assert that a late emission from query A after query B starts is ignored; a repeated cumulative snapshot does not duplicate queue items; and appending a result does not call play, seek, download, or change playback mode.

- [ ] **Step 3: Run controller RED/GREEN tests**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/music_controller_test.dart --plain-name 'dynamic multi-source results grow the active queue without pre-downloading'
/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/music_controller_test.dart test/search_playback_session_test.dart
```

Expected: if current cumulative append behavior already satisfies the contract, the new test is GREEN without production edits. If RED, make only the smallest ownership fix in `_applySearchProgress` or `SearchPlaybackSession.append`, then rerun both files.

- [ ] **Step 4: Developer review checkpoint**

Return queue titles, current media id, progressive-open calls, and formal-cache assertions. Do not stage or commit.

---

### Task 5: Full Verification, APK, and Xiaomi Device Evidence

**Files:**
- Create generated evidence under the lead-assigned request directory, outside source folders.
- Do not edit product code during this task unless a reproduced failure returns the plan to the relevant RED-GREEN task.

**Interfaces:**
- Consumes: completed Tasks 1-4.
- Produces: review-ready test, package, device, queue, Range, and cache evidence.

- [ ] **Step 1: Run the matching suite**

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test \
  test/multi_source_search_coordinator_test.dart \
  test/music_resolver_test.dart \
  test/music_controller_test.dart \
  test/search_playback_session_test.dart \
  test/progressive_audio_cache_test.dart \
  test/widget_test.dart
```

Expected: all matching tests pass.

- [ ] **Step 2: Run full verification**

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test
/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze
git diff --check
git rev-parse HEAD
git merge-base --is-ancestor 3e5a95f4213aa957f084d1e27e629da2c2ba0edf HEAD
```

Expected: full tests pass, analyze reports no issues, diff check is silent, and the baseline ancestry command exits 0.

- [ ] **Step 3: Build and preserve-install the APK**

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter build apk --debug
shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
/Users/huangqi/Library/Android/sdk/platform-tools/adb \
  -s 192.168.31.76:41563 install -r \
  build/app/outputs/flutter-apk/app-debug.apk
```

Expected: build and install succeed without clearing user data.

- [ ] **Step 4: Verify two-source search on Xiaomi Mi 10 Pro**

For each query `周杰伦`, `Angel`, and one exact song title:

1. Clear only the search UI, not app data.
2. Start logcat capture.
3. Search once and wait for the first validated row.
4. Capture the list before and after the second source appends.
5. Confirm source markers include both Gequhai and Kuwo across the loaded list.
6. Scroll near the bottom once and capture one page-growth event; do not repeatedly trigger deep pagination.
7. Confirm existing rows stay in place and media-session queue size grows after append.

- [ ] **Step 5: Verify playback, seek, and no pre-download**

Play one Gequhai result and one Kuwo result. For each source capture:

- playback starts before full download completes;
- seek forward and backward leaves media session in state 3 with position advancing;
- Range/206 evidence and full-byte promotion are consistent;
- only the played song gets a part/formal cache record;
- another visible but unplayed result has no progressive session, part file, or cache index entry;
- a failed source attempt does not erase the other source's visible results or write cache.

- [ ] **Step 6: Verify package identity and restore device state**

Pull installed `base.apk`, compare SHA-256 with the built APK, record package `lastUpdateTime`, pause playback, and confirm the default input method is the user's normal keyboard rather than ADB Keyboard.

- [ ] **Step 7: Submit developer review evidence to the lead**

Return only: conclusion, unchanged/new HEAD, baseline ancestry, matching/full test totals, analyze/diff results, APK and installed-package SHA, Xiaomi evidence directory, two-source append screenshots/logs, queue growth, no-pre-download proof, risks, and next action. Do not stage, commit, merge, or push.

---

## Plan Self-Review Results

- Spec coverage: all source scope, strict gate, concurrent append, stable ordering, deduplication, pagination, circuit isolation, queue growth, no pre-download, UI loading, and Xiaomi evidence requirements map to Tasks 1-5.
- Placeholder scan: all tasks name exact files, commands, assertions, and error behavior; no deferred implementation markers remain.
- Type consistency: `MultiSourceSearchProvider`, `MultiSourceSearchCoordinator.searchPage`, `MultiSourceSearchFailure`, `isInitialSearchLoading`, and `isAppendingSearchResults` are introduced once and used with the same signatures throughout.
- Scope check: this plan is one independently testable feature. BuguYY, FLAC, 22a5, escaped artist display cleanup, and NDK/KGP warnings remain separate follow-up work.
