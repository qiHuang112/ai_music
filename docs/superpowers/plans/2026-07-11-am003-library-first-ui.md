# AM-20260711-003 Library First UI Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to execute implementation tasks step by step. Use checkbox (`- [ ]`) syntax for progress tracking, and keep AM-004 accepted baseline as the final UI validation gate.

**Goal:** Implement the selected `Library First / 我的音乐与继续播放优先` direction across AI Music Home, Search, Player, Queue, Library, Download Manager, Settings and Hotlist while preserving complete-audio source safety.

**Architecture:** Keep existing Flutter business layers and Material 3 foundation. Introduce a consistent presentation layer language through tokens, row patterns, state chips, safe-area aware bottom surfaces, and a distinct current queue sheet. UI must consume source readiness states from existing controller/resolver models instead of inventing playback or download semantics.

**Tech Stack:** Flutter/Dart, existing AI Music controller and presentation widgets, existing widget/player tests, Xiaomi 10 Pro Android validation, OHOS screenshot/constraint validation.

## Global Constraints

- Product-selected target image is `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`.
- Canonical UI spec is `docs/codex_collab/knowledge/ui/2026-07-11-am003-library-first-page-spec.md`.
- AM-004 core source chain must be accepted/merged before final AM-003 UI package, screenshots, recordings, design-qa and review_request.
- Search results must not show PREVIEW, 30s, Quark, HTML, defender or unavailable sources as complete paths.
- Every interactive control must keep at least 48 x 48 logical px target, with safe area and keyboard behavior verified on Android and OHOS.
- AI Music uses independent Project Path `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`, not git worktree.
- Code implementation remains owned by Android unless architect explicitly hands business UI code to UI lane.

---

### Task 1: Request, Spec And Plan Gate

**Files:**
- Request: `/Users/huangqi/AIHome/ai_music/docs/codex_collab/requests/AM-20260711-003-library-first-ui.md`
- Spec: `/Users/huangqi/AIHome/ai_music/docs/codex_collab/knowledge/ui/2026-07-11-am003-library-first-page-spec.md`
- Plan: `/Users/huangqi/AIHome/ai_music/docs/superpowers/plans/2026-07-11-am003-library-first-ui.md`

**Interfaces:**
- Consumes: AM-002 audit, target image, Android/OHOS screenshots, QA matrix and Android preimplementation evidence.
- Produces: team_ops-valid request, page spec and implementation plan for Android start gate.

- [x] **Step 1: Confirm Product direction and evidence**

  Confirm Product-selected Library First target image, Android b306932 screenshots, OHOS screenshots and constraints, and AM-003 preimplementation evidence for current queue and hotlist image risk.

- [x] **Step 2: Create page-level UI spec**

  Create `2026-07-11-am003-library-first-page-spec.md` covering Home, Search, Player, Queue, Library, Download Manager, Settings, state chips, tokens, safe area, keyboard, mini player, long text and screenshot names.

- [x] **Step 3: Create formal request and implementation plan**

  Create the AM-003 request file and this implementation plan in the main collaboration ledger.

- [ ] **Step 4: Validate and notify**

  Run `team_ops.py validate-request`, `team_ops.py validate-workflow --gate start`, and `team_ops.py validate-message`; then notify product, architect and android with paths and gate results.

### Task 2: RED Tests For Library First Contracts

**Files:**
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/test/widget_test.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/test/player_page_test.dart`

**Interfaces:**
- Consumes: UI spec contract and existing widget tree.
- Produces: failing tests before implementation and stable tests after GREEN.

- [x] **Step 1: Home hierarchy RED**

  Add a failing test that requires `继续播放` above `我的音乐` and `热榜发现` when current playback exists.

- [x] **Step 2: Search result chip RED**

  Add a failing test requiring visible `可下载` and `不可下载` chips, no PREVIEW completion path, and disabled/actionless unavailable rows.

- [x] **Step 3: Current queue RED**

  Add a failing test requiring an independent `当前队列` entry and queue sheet, separate from add-to-playlist sheet.

- [x] **Step 4: Mini player queue RED**

  Add a failing test requiring mini player to expose the same current queue affordance without hijacking normal player navigation.

### Task 3: GREEN Implementation Slice

**Files:**
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/lib/src/presentation/app_localizations.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/lib/src/presentation/music_home_page.dart`
- Modify: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/lib/src/presentation/player_page.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/test/widget_test.dart`
- Test: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/test/player_page_test.dart`

**Interfaces:**
- Consumes: existing controller state, download/cache/source readiness flags and current playback queue data.
- Produces: Library First UI behaviors guarded by targeted tests.

- [x] **Step 1: Implement Home order**

  Place `继续播放` before local library assets and discovery blocks, using the selected target direction as visual reference.

- [x] **Step 2: Implement Search chips**

  Show source readiness with chip text from the spec: `可下载`, `不可下载`, `需完整音频`, `来源受限`, `已缓存`, `下载中`, `播放中`.

- [x] **Step 3: Implement Player queue entry**

  Add a dedicated `当前队列` entry and bottom sheet with current item, upcoming items, stable row heights and 48px actions.

- [x] **Step 4: Implement Mini player queue entry**

  Expose current queue from mini player while preserving tap-to-open-player behavior.

- [ ] **Step 5: Extend remaining visual surfaces**

  Apply row pattern, spacing, tokens, safe-area rules and long text behavior to Download Manager, Settings, Library/Favorites, Custom Playlist and Hotlist.

### Task 4: AM-004 Baseline Integration Gate

**Files:**
- Request dependency: `/Users/huangqi/AIHome/ai_music/docs/codex_collab/requests/AM-20260711-004-gequhai-full-source-mainline.md`
- Project: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`

**Interfaces:**
- Consumes: AM-004 accepted/merged core source baseline.
- Produces: AM-003 package eligible for final UI design-qa.

- [ ] **Step 1: Wait for accepted AM-004 baseline**

  Continue AM-003 preparation, but do not present AM-004 unaccepted package as final UI验收包.

- [ ] **Step 2: Rebase or merge accepted baseline**

  Once architect confirms AM-004 accepted/merged, align AM-003 Project Path to the accepted baseline without reverting AM-003 UI WIP.

- [ ] **Step 3: Re-run targeted tests**

  Run Home/Search/Player/mini player tests, then the expanded AM-003 UI targeted suite, `flutter analyze --no-pub`, and `git diff --check`.

### Task 5: Android And OHOS Design-QA Evidence

**Evidence:**
- Android screenshots: `/Users/huangqi/AIHome/output/AM-20260711-003-<baseline>-xiaomi10/`
- OHOS screenshots or constraints: OHOS lane evidence directory returned in review_request.
- Screenshot naming: `AM-20260711-003_library-first_<platform>_<device>_<page>_<state>_<step>.png`
- Recording naming: `AM-20260711-003_library-first_<platform>_<device>_<flow>_<step>.mp4`

**Interfaces:**
- Consumes: final AM-003 debug package and QA matrix.
- Produces: design-qa pass/fail/blocker evidence for architect/product.

- [ ] **Step 1: Capture Android key paths**

  Capture Home Library First, Search results, Search unavailable state, Download Manager, mini player safe area, Player lyrics, Current Queue sheet, Hotlist detail, Favorites/Custom Playlist and Settings.

- [ ] **Step 2: Capture recordings**

  Record Search to play, Search to download, Player to queue, mini player to queue, and Download Manager to playback flows.

- [ ] **Step 3: Capture OHOS cross-platform evidence**

  Verify safe area, keyboard, 48px touch targets, big fonts, long list/sheet behavior, mini player, foreground-only constraints and launch first frame risks.

- [ ] **Step 4: Compare against target**

  Produce a deviation list against the Library First target image and page spec. Classify P1/P2/P3 and identify whether each item blocks review.

### Task 6: Review Request And Product Handoff

**Files:**
- Request: `/Users/huangqi/AIHome/ai_music/docs/codex_collab/requests/AM-20260711-003-library-first-ui.md`
- QA matrix: `/Users/huangqi/AIHome/ai_music/docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`

**Interfaces:**
- Consumes: tests, analyze, diff-check, Android/OHOS screenshots, recordings and design-qa deviation list.
- Produces: validated `review_request` for architect/product/android with Spec Review Result and Code Quality Review Result fields ready for reviewers.

- [ ] **Step 1: Update request evidence**

  Fill final Head Commit, Targeted Tests, Self Test Evidence, Product Main Path Evidence, Scope Diff Evidence and Full Verification Evidence.

- [ ] **Step 2: Validate review gate**

  Run `team_ops.py validate-request` and `team_ops.py validate-workflow --gate review`.

- [ ] **Step 3: Send review_request**

  Notify architect, product, android, OHOS and QA with package sha, device info, screenshot directory, recording directory, operation paths, visual risks, deviation list and pass/fail/blocker judgment. Completion owners must回到 UI 线程 `019ef1d2-d6ec-79d3-9225-fb4169680228` with review conclusions and evidence paths.
