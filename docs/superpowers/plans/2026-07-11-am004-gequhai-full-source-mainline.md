# Gequhai Full Source Mainline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore AI Music search, full download, full playback, lyrics, artwork, and progressive playback using Gequhai verified full audio only.

**Architecture:** Build a strict Gequhai provider pipeline and make the UI consume only candidates that pass full-audio validation. The cache path remains fail-closed: only validated `direct_audio` may enter transient streaming or formal cache.

**Tech Stack:** Flutter/Dart, existing resolver/controller/cache layers, existing progressive streaming cache, existing widget tests, Xiaomi 10 Pro debug validation.

## Global Constraints

- Product-visible search results must only include complete playable Gequhai songs.
- No `PREVIEW`, `30s`, iTunes preview, Quark, HTML, defender page, BuguYY/FLAC non-downloadable row, or browser-only row may appear as a completion path.
- External source probing must be low-frequency and browser-faithful.
- AI Music uses independent `Project Path`, not git worktree.
- Code changes use RED-GREEN-REFACTOR with targeted tests.

---

### Task 1: Gequhai Search And Detail Parsing

**Files:**
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/music_resolver.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/resolver_models.dart`
- Create: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/gequhai_full_audio_resolver.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/test/music_resolver_test.dart`

**Interfaces:**
- Produces: `source_gequhai` candidates with `title`, `artist`, `detailUrl`, `playPageId`, and page metadata.
- Consumes: existing `MusicSearchCandidate` and `ResolvedMusic` types.

- [ ] **Step 1: Write failing search parser tests**

  Add tests that parse a fixture equivalent to `/s/外婆` and assert the exact candidate `外婆 / 周杰伦 / /play/6330` is returned, while wrong-artist rows are excluded from full playable results.

- [ ] **Step 2: Run RED**

  Run:

  ```bash
  /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/music_resolver_test.dart --plain-name 'gequhai search returns exact playable result'
  ```

  Expected: fail because the dedicated Gequhai mainline provider does not exist or does not filter candidates.

- [ ] **Step 3: Implement search and detail parsing**

  Implement `GequhaiFullAudioResolver.search(keyword)` and detail parsing for `window.play_id`, `window.mp3_title`, `window.mp3_author`, `window.mp3_cover`, `window.mp3_extra_url`, and `#content-lrc2`.

- [ ] **Step 4: Run GREEN**

  Run the same test. Expected: pass.

### Task 2: API And Media Validation Gate

**Files:**
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/gequhai_full_audio_resolver.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/resolver_models.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/test/music_resolver_test.dart`

**Interfaces:**
- Produces: `ResolvedMusic` with `urlType=directAudio`, `canCacheAudio=true`, lyrics, artwork, and SourceAttempt chain.
- Consumes: page cookie jar, `POST /api/music`, HEAD and Range media validation.

- [ ] **Step 1: Write failing API/media tests**

  Add tests for `/api/music` headers `X-Requested-With: Http` and `X-Custom-Header: Key`, merged page cookie jar, no-referer CDN HEAD/Range, positive length gate, and fail-closed non-audio responses.

- [ ] **Step 2: Run RED**

  Run:

  ```bash
  /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/music_resolver_test.dart --plain-name 'gequhai api returns validated direct audio with lyrics and cover'
  ```

  Expected: fail because the current resolver does not implement the full AM-004 gate.

- [ ] **Step 3: Implement validation**

  Implement API call, media HEAD, Range `bytes=0-8191`, positive length/total checks, and SourceAttempt failure codes `external_pan_link`, `security_or_defender`, `play_url_unavailable`, `non_audio_content`, `range_not_supported`, and `audio_validation_failed`.

- [ ] **Step 4: Run GREEN**

  Run the RED command again. Expected: pass.

### Task 3: Controller Streaming And Cache Promotion

**Files:**
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/application/music_controller.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/progressive_audio_cache.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/data/music_cache.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/test/music_controller_test.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/test/progressive_audio_cache_test.dart`

**Interfaces:**
- Consumes: validated Gequhai `ResolvedMusic`.
- Produces: transient proxy playback, first-byte logs, part-size logs, `download_complete_ms`, formal cache promotion.

- [ ] **Step 1: Write failing controller tests**

  Add tests that clicking a Gequhai candidate opens transient streaming, starts playback, leaves `downloadTasks` empty during transient playback, and promotes the complete mp3 plus lyrics/artwork metadata into formal cache.

- [ ] **Step 2: Run RED**

  Run:

  ```bash
  /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/music_controller_test.dart test/progressive_audio_cache_test.dart --plain-name 'gequhai candidate streams before complete and promotes cache'
  ```

  Expected: fail until AM-004 streaming and promotion are connected.

- [ ] **Step 3: Implement streaming path**

  Wire Gequhai validated direct audio into the existing transient Range proxy, record first-byte and part-size evidence, and call formal cache adoption only after complete download.

- [ ] **Step 4: Run GREEN**

  Run the RED command again. Expected: pass.

### Task 4: UI Full-Playable-Only Results

**Files:**
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/presentation/music_home_page.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/lib/src/presentation/app_localizations.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/test/widget_test.dart`

**Interfaces:**
- Consumes: filtered Gequhai complete candidates and structured failure summaries.
- Produces: visible rows that are all complete playable songs, with no preview or disabled source rows.

- [ ] **Step 1: Write failing widget tests**

  Add tests that assert search results do not contain `试听`, `PREVIEW`, `30s`, `不可下载`, BuguYY, FLAC, Quark, HTML, or defender rows, and that a visible result has play/download affordances.

- [ ] **Step 2: Run RED**

  Run:

  ```bash
  /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/widget_test.dart --plain-name 'search results only show complete playable gequhai songs'
  ```

  Expected: fail on current UI filtering.

- [ ] **Step 3: Implement filtering and copy**

  Filter online results to Gequhai complete candidates. If none exist, show a concise empty state explaining that no complete playable resource was found.

- [ ] **Step 4: Run GREEN**

  Run the RED command again. Expected: pass.

### Task 5: Device Self-Test And Review Handoff

**Files:**
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/docs/codex_collab/requests/AM-20260711-004-gequhai-full-source-mainline.md` if the project clone carries request docs.
- Evidence: `/tmp/am004-device-evidence/gequhai-full-source-mainline/`

**Interfaces:**
- Consumes: built debug APK and Xiaomi 10 Pro.
- Produces: review_request evidence for architect, android, android-streaming, source-researcher, and product.

- [ ] **Step 1: Run targeted suite**

  Run:

  ```bash
  /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/music_resolver_test.dart test/music_cache_test.dart test/progressive_audio_cache_test.dart test/music_controller_test.dart test/widget_test.dart
  /Users/huangqi/AIHome/tools/flutter/bin/flutter analyze --no-pub
  git diff --check origin/release/1.0.2..HEAD
  ```

  Expected: all pass.

- [ ] **Step 2: Build debug APK**

  Run:

  ```bash
  FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn /Users/huangqi/AIHome/tools/flutter/bin/flutter build apk --debug --no-pub
  shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
  ```

  Expected: APK builds and sha256 is recorded.

- [ ] **Step 3: Install and self-test on Xiaomi 10 Pro**

  Run the real product path for `外婆`, `一丝不挂`, `稻香`, `哎呀`, and one failure sample. Capture search results, media session, first-byte time, part growth, `download_complete_ms`, cache index, lyrics, artwork, and fail-closed evidence.

- [ ] **Step 4: Send review_request**

  Send a validated `review_request` with HEAD, baseline, tests, APK sha, device target, evidence directory, product main path results, and scope diff.
