# AM-005 Streaming Search and Seek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make validated Gequhai results appear progressively with automatic pagination, reuse prepared media resolution, and keep incomplete progressive streams seekable and recoverable.

**Architecture:** Extend the existing progressive resolver contract with page metadata and a load-more entry point. Keep the formal cache as one contiguous byte-zero download, but proxy uncached seek ranges directly from the validated upstream. Preserve the existing controller and list UI while adding explicit pagination state and a single-attempt player reload after source errors.

**Tech Stack:** Dart, Flutter, `dart:io` HTTP proxy, `just_audio`, `audio_service`, Flutter test.

## Global Constraints

- Only validated complete audio may be visible.
- Failed search, playback, or Range requests must not create formal cache entries.
- Gequhai candidate validation remains serial within a page.
- Pages load on demand; do not prefetch every provider page.
- Preserve unrelated dirty worktree changes.
- Do not stage, commit, or push from the developer role.
- Install the debug APK to Xiaomi 10 Pro with user data preserved after verification.

---

### Task 1: Seekable Progressive Proxy

**Files:**
- Modify: `lib/src/data/progressive_audio_cache.dart:554`
- Modify: `test/progressive_audio_cache_test.dart:12`

**Interfaces:**
- Consumes: `ProgressiveAudioSession.handle(HttpRequest)` and the existing contiguous part file.
- Produces: strict initial 206 validation and direct upstream Range pass-through when `range.start > downloadedBytes`.

- [ ] **Step 1: Write failing proxy tests**

Add tests whose real HTTP source records Range/full requests:

```dart
test('valid initial 206 stays on the ranged upstream response', () async {
  // Request bytes 0-1023 through the proxy.
  expect(source.rangeRequests, 1);
  expect(source.fullRequests, 0);
});

test('far seek proxies an aligned upstream range before background catches up', () async {
  // Keep the byte-zero download slow, then request bytes 65536-66559.
  expect(response.statusCode, HttpStatus.partialContent);
  expect(response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 65536-66559/${source.bytes.length}');
  expect(await response.expand((chunk) => chunk).toList(),
      source.bytes.sublist(65536, 66560));
});
```

- [ ] **Step 2: Run RED tests**

Run:

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/progressive_audio_cache_test.dart --plain-name 'valid initial 206 stays on the ranged upstream response' --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true
/Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/progressive_audio_cache_test.dart --plain-name 'far seek proxies an aligned upstream range before background catches up' --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true
```

Expected: the first fails because the valid 206 regex falls back to full GET; the second fails with timeout or no exact upstream seek Range.

- [ ] **Step 3: Implement strict Range pass-through**

Correct the raw regular expression to `r'^bytes\s+0-\d+/(\d+)$'`. Before `_waitForBytes`, route an ahead-of-prefix range to a helper that requests the exact upstream bytes, requires aligned HTTP 206/audio/positive total, copies safe headers, and pipes the response without writing to `partFile`.

- [ ] **Step 4: Run GREEN and regression tests**

Run the two named tests and the complete `test/progressive_audio_cache_test.dart`; expect all tests to pass.

- [ ] **Step 5: Record uncommitted checkpoint**

Run `git diff --check -- lib/src/data/progressive_audio_cache.dart test/progressive_audio_cache_test.dart`. Do not stage or commit.

### Task 2: Progressive Gequhai Pages and Prepared Resolution

**Files:**
- Modify: `lib/src/data/resolver_models.dart:457`
- Modify: `lib/src/data/gequhai_player_audio_resolver.dart:22`
- Modify: `lib/src/data/music_resolver.dart:28`
- Modify: `test/music_resolver_test.dart:549`

**Interfaces:**
- Consumes: `MusicSearchProgress`, `GequhaiPlayerAudioResolver.resolve`, existing fail-closed parsing.
- Produces: `MusicSearchProgress.page`, `hasNextPage`, and `searchPageProgressively(query, source, page:)` through a new `PaginatedProgressiveMusicResolver` contract.

- [ ] **Step 1: Write failing resolver tests**

Cover page URL/number, parsed next-page link, per-candidate emissions, and network reuse:

```dart
expect(requestedSearchUris, [
  Uri.parse('https://www.gequhai.com/s/%E5%91%A8%E6%9D%B0%E4%BC%A6?page=2'),
]);
expect(progress.first.candidates, hasLength(1));
expect(progress.first.isComplete, isFalse);
expect(progress.last.hasNextPage, isTrue);
expect((await resolver.resolve(progress.first.candidates.single)).url, audioUrl);
expect(detailRequestCount, 1);
```

- [ ] **Step 2: Run RED tests**

Run each new `music_resolver_test.dart` plain-name test. Expect compilation failures for missing pagination fields/interface, then expected behavior failures after test scaffolding compiles.

- [ ] **Step 3: Implement page progress and one-shot prepared values**

Add immutable page metadata to progress. Parse `?page=N` next links. Validate rows serially and emit after each success. Key prepared values by source/platform/id, clear them on a new page-1 search session, and consume them in `resolve` before calling the fresh network chain.

- [ ] **Step 4: Run GREEN and resolver regression tests**

Run all new named tests followed by `flutter test --no-pub test/music_resolver_test.dart --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true`; expect all tests to pass.

- [ ] **Step 5: Record uncommitted checkpoint**

Run `git diff --check` for the four task files. Do not stage or commit.

### Task 3: Controller and Automatic Pagination UI

**Files:**
- Modify: `lib/src/application/music_controller.dart:396`
- Modify: `lib/src/presentation/music_home_page.dart:337`
- Modify: `test/music_controller_test.dart:623`
- Modify: `test/widget_test.dart:690`

**Interfaces:**
- Consumes: `PaginatedProgressiveMusicResolver.searchPageProgressively` and page metadata.
- Produces: `loadMoreSearchResults()`, `retrySearchPage()`, `isLoadingMoreSearch`, and `hasMoreSearchResults`.

- [ ] **Step 1: Write failing controller and widget tests**

```dart
expect(controller.candidates.map((item) => item.id), ['page-1']);
expect(controller.hasMoreSearchResults, isTrue);
await controller.loadMoreSearchResults();
expect(controller.candidates.map((item) => item.id), ['page-1', 'page-2']);
expect(resolver.requestedPages, [1, 2]);
```

Add a widget test that scrolls the result list to the bottom and verifies page 2 is requested once while page-1 rows remain interactive.

- [ ] **Step 2: Run RED tests**

Run the named controller and widget tests. Expect failures for missing pagination state and load-more behavior.

- [ ] **Step 3: Implement merged page state and scroll trigger**

Keep page 1 `isSearching` separate from load-more state, merge stable candidate identities, preserve rows on later-page errors, and use a list `ScrollController` threshold to invoke load more once. Route the existing refresh icon to retry the failed current page when page-1 results already exist.

- [ ] **Step 4: Run GREEN and UI regressions**

Run new named tests, then `test/music_controller_test.dart` and `test/widget_test.dart`; expect all tests to pass.

- [ ] **Step 5: Record uncommitted checkpoint**

Run `git diff --check` for controller/UI files. Do not stage or commit.

### Task 4: Player Error Reload and End-to-End Verification

**Files:**
- Modify: `lib/src/playback/music_audio_handler.dart:28`
- Modify: `test/music_audio_handler_test.dart:5`
- Verify: all files changed by Tasks 1-3

**Interfaces:**
- Consumes: current `_items`, queue index, player position, and playback-event errors.
- Produces: user-triggered single reload for `play()` and `seek()` after a player source error.

- [ ] **Step 1: Write a failing recovery test**

Inject or expose the existing player dependency through a minimal testable adapter, then assert that one source error causes the next play/seek to reload once at the requested position and that a second failure does not loop.

- [ ] **Step 2: Run RED recovery test**

Run the named `music_audio_handler_test.dart` test; expect failure because errors are not recorded and `play()` directly delegates to the player.

- [ ] **Step 3: Implement user-triggered one-shot reload**

Record playback-event errors without automatic retries. On the next user play or seek, reload the current queue item at the last/requested position, clear the recovery marker after the attempt, and preserve audio-service queue/media state.

- [ ] **Step 4: Run complete verification**

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/progressive_audio_cache_test.dart test/music_resolver_test.dart test/music_controller_test.dart test/music_audio_handler_test.dart test/widget_test.dart --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true
/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze --no-pub
git diff --check
```

Expected: all tests pass, analyze reports no issues, and diff check is clean.

- [ ] **Step 5: Build, preserve-data install, and verify Xiaomi 10 Pro**

Build `app-debug.apk`, compute SHA-256, install with `adb install -r`, then verify progressive search timing, automatic page 2, far-forward seek, backward seek, play recovery, media-session playing state, aligned 206 logs, and absence of local HTTP 504. Leave the app at the search entry with the Xiaomi system keyboard enabled. Do not stage or commit.
