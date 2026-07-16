# AM-005 Search Library and Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make search responsive, turn validated paginated results into a dynamically growing lazy playback library, stabilize streaming lyrics, and remove the player stop button.

**Architecture:** Gequhai search emits parsed candidates immediately and validates them with a bounded worker pool. `SearchPlaybackSession` owns candidate ordering and mode-aware transitions while `MusicAudioHandler` delegates virtual-queue operations to the controller and keeps only the current real source loaded. Streaming metadata is bound before player loading and refreshed from the promoted cache with generation checks.

**Tech Stack:** Dart, Flutter, audio_service, just_audio, flutter_test.

## Global Constraints

- Full-audio validation remains fail closed; invalid candidates never become playable or enter formal cache.
- Validation concurrency is at most 3.
- Search library pagination appends dynamically and does not pre-download unplayed songs.
- Only the lead may stage, commit, merge, or push. This plan performs no Git submission actions.
- Final Android validation uses Xiaomi Mi 10 Pro and restores Sogou IME.

---

### Task 1: Responsive Progressive Search

**Files:**
- Modify: `lib/src/data/resolver_http_client.dart`
- Modify: `lib/src/data/resolver_models.dart`
- Modify: `lib/src/data/gequhai_player_audio_resolver.dart`
- Modify: `lib/src/application/music_controller.dart`
- Modify: `lib/src/presentation/music_home_page.dart`
- Modify: `lib/src/presentation/app_localizations.dart`
- Test: `test/music_resolver_test.dart`
- Test: `test/music_controller_test.dart`
- Test: `test/widget_test.dart`
- Create: `test/resolver_http_client_test.dart`

**Interfaces:**
- `MusicSearchCandidate.isValidating` and `isClientReady` expose typed UI state derived from candidate evidence.
- `GequhaiPlayerAudioResolver.searchPageProgressively` emits parsed `validating` candidates first, then ordered snapshots as up to three validations complete.
- `HttpMusicResolverClient` accepts explicit connect/response timeout and GET-attempt limits; defaults no longer perform three 12-second interactive GET attempts.

- [ ] Write failing resolver tests proving raw candidates emit before validation completes, no more than three validations run concurrently, failures disappear, and final order matches search order.
- [ ] Run `flutter test --no-pub test/music_resolver_test.dart` and confirm the new tests fail on serial validation.
- [ ] Implement a three-worker ordered validation pool with generation cancellation and prepared-resolution reuse.
- [ ] Write failing HTTP client tests proving the configured short connect timeout performs only the configured attempt count.
- [ ] Implement explicit timeout/attempt policy and response-body timeout without changing Range fail-closed behavior.
- [ ] Write failing controller/widget tests for visible disabled `validating` rows that become playable when ready.
- [ ] Implement candidate state getters, controller visibility rules, localized `校验中`, and disabled row actions.
- [ ] Run the four matching test files and keep all existing progressive/pagination tests green.

### Task 2: Dynamic Lazy Search Playback Library

**Files:**
- Create: `lib/src/application/search_playback_session.dart`
- Modify: `lib/src/application/music_controller.dart`
- Modify: `lib/src/application/playback_use_case.dart`
- Modify: `lib/src/playback/music_audio_handler.dart`
- Modify: `lib/src/presentation/player_page.dart`
- Create: `test/search_playback_session_test.dart`
- Modify: `test/music_controller_test.dart`
- Modify: `test/music_audio_handler_test.dart`
- Modify: `test/player_page_test.dart`

**Interfaces:**
- `SearchPlaybackSession.append`, `select`, `next(mode, automatic)`, and `previous(mode)` manage a generation-bound candidate library and stable shuffle order.
- `MusicAudioHandler.onSkipToNextRequested`, `onSkipToPreviousRequested`, `onSkipToQueueItemRequested`, and `onPlaybackCompleted` return `true` when the virtual queue handled the command.
- `MusicAudioHandler.publishDisplayQueue(items, currentIndex)` publishes the full search library while the real player holds only the current source.
- `PlaybackUseCase.applyPlaybackMode(mode, managedQueue: true)` reports the selected mode but keeps the one-source player loop disabled so completion reaches the controller.

- [ ] Write pure RED tests for sequential end, loop-all wrap, repeat-one automatic replay, manual next, stable shuffle, previous, and dynamic append.
- [ ] Implement `SearchPlaybackSession` minimally and make the pure tests green.
- [ ] Write audio-handler RED tests for delegated next/previous/item/completion and display queue index preservation.
- [ ] Implement handler delegation, managed queue mode, and display queue publishing without regressing normal cached queues.
- [ ] Write controller RED tests proving clicking a search result activates all ready candidates, page 2 appends, queue selection lazily resolves only the selected song, and library playback clears the search session.
- [ ] Refactor `playCandidate` into public session activation and private lazy candidate playback; republish the display queue after each real source load.
- [ ] Route player buttons, notifications, automatic completion, and queue-sheet item taps through the same session transitions.
- [ ] Run session, handler, controller, and player tests.

### Task 3: Streaming Lyrics and Player Controls

**Files:**
- Modify: `lib/src/application/music_controller.dart`
- Modify: `lib/src/presentation/player_page.dart`
- Modify: `test/music_controller_test.dart`
- Modify: `test/player_page_test.dart`

**Interfaces:**
- The active streaming binding stores media ID, candidate key, playback generation, and resolved metadata until promotion or track change.
- Promotion refresh applies metadata only when the binding is still current.

- [ ] Write RED tests proving resolved lyrics are visible before player load completes, a lyric-less stream receives fallback lyrics after promotion, and stale prior-track metadata is ignored.
- [ ] Move resolved metadata binding before `playFuture` and preserve a streaming-current association independent of `cachedTracks` IDs.
- [ ] After promotion, load metadata from the formal cache and atomically update the current stream binding when its generation still matches.
- [ ] Write a widget RED test asserting no Stop tooltip/icon exists on both player detail variants.
- [ ] Remove the visible stop control while retaining the controller/handler stop API for lifecycle cleanup.
- [ ] Run controller and player tests.

### Task 4: Verification and Device Handoff

**Files:**
- Update evidence under: `evidence/qa-am005-final/20260716-search-library-lyrics/`

- [ ] Run targeted resolver, HTTP, controller, handler, session, player, progressive cache, and widget tests.
- [ ] Run `flutter analyze --no-pub` and `git diff --check`.
- [ ] Build `flutter build apk --debug --no-pub`, record APK SHA-256, and install with `adb install -r` on Xiaomi Mi 10 Pro.
- [ ] Verify first candidate timing, page 2 dynamic queue growth, queue item lazy playback, current playback mode, no eager downloads, lyrics before/after promotion, and seek playback.
- [ ] Scan logcat for HTTP timeout amplification, proxy errors, stale metadata, and playback source errors.
- [ ] Restore `com.sohu.inputmethod.sogou.xiaomi/.SogouIME`, disable ADB Keyboard, and leave the real keyboard visible.
- [ ] Report HEAD, APK SHA, tests/analyze/diff-check, device evidence, risks, and next action without staging, committing, or pushing.
