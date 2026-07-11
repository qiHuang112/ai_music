# AM-20260711-003 Library First Mobile UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the selected Library First mobile UI direction for AI Music 1.1.0 without regressing complete-audio search, playback, download, cache, lyrics, cover, queue, favorites, or playlist flows.

**Architecture:** UI lane first converts the selected image and audit into a page-level implementation spec. Android then implements shared Flutter presentation changes in small TDD slices while preserving resolver/cache/controller gates. OHOS and QA validate cross-platform constraints and screenshot evidence before architect merge.

**Tech Stack:** Flutter, Dart, Material 3, AI Music presentation/application layers, Android Xiaomi 10 Pro device evidence, OHOS HAP evidence, `team_ops.py` superpowers workflow gates.

## Global Constraints

- Target Version: 1.1.0.
- Base Branch: `release/1.0.2`.
- Baseline Commit: `b306932d03e1eedbe96fd50dafe0f95805b0eab4`.
- Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`.
- Work Branch: `feature/1.1.0/AM-20260711-003-library-first-ui`.
- Selected Image: `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`.
- Product Design Audit: `docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md`.
- QA Matrix: `docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`.
- OHOS Library First Notes: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/library-first-ohos-implementation-notes.md`.
- OHOS AM-003 Review Checklist: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/am-20260711-003-ohos-cross-platform-review-checklist.md`.
- Preview,网盘,HTML,防护页和不可下载源不能作为完整播放或下载完成路径。
- Android code work starts only after UI lane provides a page-level implementation spec.
- Every user-visible code slice must include RED/GREEN evidence or an approved TDD exception.
- Main-path self-test evidence is mandatory before review: search, tap play, download/cache, player, queue, playlists, hotlist, settings.
- UI spec and Android implementation must not hard-code Android status bar, keyboard or navigation bar heights; use safe area/insets and scrollable layouts that also pass OHOS constraints.

---

### Task 1: UI 页面级实现规范

**Files:**
- Create: `docs/codex_collab/knowledge/ui/2026-07-11-am003-library-first-page-spec.md`
- Modify: `docs/codex_collab/requests/AM-20260711-003-library-first-mobile-ui-implementation.md`

**Interfaces:**
- Consumes: selected image, UI audit, Android screenshots, OHOS screenshots, QA matrix.
- Produces: page-level component, token and state spec consumed by Android implementation.

- [ ] **Step 1: Define page inventory**

Write the spec with these exact sections:

```markdown
## Page Inventory

- Home: search, local assets, saved hotlist playlist, discovery card, mini player.
- Search: keyboard state, full-audio rows, cached rows, unavailable rows, no preview.
- Player: cover, lyrics, progress, controls, favorite, add playlist, current queue.
- Current Queue: entry point, sheet/list, current item, next items, queue source.
- Library: favorites, custom playlists, hotlist playlist, add-to-playlist sheet.
- Download Manager: active task, cached tracks, failed tasks, mini player continuity.
- Settings: source status groups, disabled product sources, no misleading selectability.
```

- [ ] **Step 2: Define tokens**

Add a `Tokens` section naming colors, spacing, shape and text scale. Required values:

```text
surface base: dark green-black
primary: teal family, close to #7DDAD1
discovery accent: warm gold family, close to #E7C56A
corner radius: 12-16 for major cards, 8 or less for compact controls
minimum touch target: 48px
```

- [ ] **Step 3: Define acceptance annotations**

For each page, include:

```markdown
- Source screenshot(s):
- Selected image influence:
- Required state(s):
- Must not regress:
- QA screenshot name(s):
```

- [ ] **Step 3a: Add OHOS implementation notes**

Copy these requirements into the page spec:

```text
safe area/insets annotated per page
keyboard-visible search result behavior
mini player persistence rule
current queue entry location and semantics
48px minimum touch target
large-font/long-text behavior
scroll strategy for queue, playlist sheet, download manager and settings
foreground-only and startup first-frame risk notes
```

- [ ] **Step 4: Validate handoff message**

Run:

```bash
python3 docs/codex_collab/tools/team_ops.py validate-message --request-file docs/codex_collab/requests/AM-20260711-003-library-first-mobile-ui-implementation.md --file /tmp/am003-ui-handoff.txt
```

Expected: `OK`.

### Task 2: Android scaffolds UI tests before implementation

**Files:**
- Modify: `test/widget_test.dart`
- Modify: `test/player_page_test.dart`
- Modify: `test/music_controller_test.dart`

**Interfaces:**
- Consumes: UI page spec from Task 1.
- Produces: failing tests that describe the new UI gates.

- [ ] **Step 1: Add home hierarchy test**

Add a widget test named:

```dart
testWidgets('library first home prioritizes local assets and continuing playback', (tester) async {
  // Build the home page with cached tracks, a hotlist playlist and an active current track.
  // Expect the local library section before hotlist discovery.
  // Expect a continuing playback or mini player affordance.
});
```

Run:

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/widget_test.dart --plain-name 'library first home prioritizes local assets and continuing playback'
```

Expected: FAIL before implementation.

- [ ] **Step 2: Add search result action hierarchy test**

Add a widget/controller test proving:

```text
source_kuwo_full_audio or cached rows expose play/download actions
BuguYY/FLAC unavailable rows show reason text and no download action
PREVIEW/30s text is absent
```

Run the targeted test and record the failing output.

- [ ] **Step 3: Add current queue entry test**

Add a player page widget test proving the current queue entry opens a queue sheet/list, not the add-to-playlist sheet.

Run the targeted test and record the failing output.

### Task 3: Implement Library First shared Flutter UI

**Files:**
- Modify: `lib/src/presentation/music_home_page.dart`
- Modify: `lib/src/presentation/player_page.dart`
- Modify: `lib/src/presentation/download_manager_page.dart`
- Modify: `lib/src/presentation/settings_page.dart`
- Modify as needed: `lib/src/application/music_controller.dart`
- Modify as needed: `lib/src/presentation/app_localizations.dart`

**Interfaces:**
- Consumes: failing tests from Task 2 and page spec from Task 1.
- Produces: updated shared Flutter UI preserving existing playback/download/cache gates.

- [ ] **Step 1: Implement home hierarchy**

Implement the Library First home ordering:

```text
search
continuing playback or mini player context
local assets
saved hotlist playlist
hotlist discovery
```

Run the home hierarchy test until it passes.

- [ ] **Step 2: Implement search result rows**

Search rows must use:

```text
title line
artist/source/quality line
status chip
separate play/download action slots
```

Unavailable rows keep the reason visible but expose no download action. Preview rows remain hidden or blocked.

- [ ] **Step 3: Implement current queue entry**

Add a distinct current queue entry in the player surface. It must not share icon, tooltip or action semantics with add-to-playlist.

- [ ] **Step 4: Keep mini player persistent**

Ensure mini player remains visible or explicitly available on:

```text
home
download manager
settings
playlist detail
sort/edit mode, unless edit dirty state requires a guarded confirm
```

- [ ] **Step 5: Preserve streaming actions**

In complete-audio streaming states, favorite and add-to-playlist remain visible. Do not gate these actions on completed cache adoption.

### Task 4: Hotlist overflow and management surfaces

**Files:**
- Modify: `lib/src/presentation/music_home_page.dart`
- Modify: `lib/src/presentation/download_manager_page.dart`
- Modify: `lib/src/presentation/settings_page.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: current b306932 overflow screenshot finding.
- Produces: no-overflow hotlist detail and consistent management page patterns.

- [ ] **Step 1: Reproduce or confirm hotlist overflow**

Use widget layout constraints or a Xiaomi 10 Pro screenshot to reproduce the hotlist detail overflow. If not reproducible, record a fresh no-overflow screenshot as evidence.

- [ ] **Step 2: Add hotlist layout test**

Add a widget test that pumps the hotlist detail with ranked artwork and verifies no Flutter overflow error is thrown.

- [ ] **Step 3: Normalize management rows**

Download manager and settings source rows should use consistent status chips and avoid long gray explanatory paragraphs as primary state.

### Task 5: OHOS and QA evidence

**Files:**
- Modify: `docs/codex_collab/requests/AM-20260711-003-library-first-mobile-ui-implementation.md`
- External evidence: OHOS screenshot directory and QA screenshot matrix output.

**Interfaces:**
- Consumes: Android implementation APK and UI page spec.
- Produces: cross-platform review evidence.

- [ ] **Step 1: OHOS constraints review**

OHOS owner verifies:

```text
safe areas
system gesture zones
48px controls
large font behavior
keyboard behavior
foreground-only assumptions
startup first-frame risk
```

OHOS review evidence must follow `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/am-20260711-003-ohos-cross-platform-review-checklist.md` and include:

```text
HAP path and sha256
source commit / branch
whether app data was cleared
HDC target, device model and OS
screenshot directory
operation path list
pass/fail/blocker table
key screenshots: home, search_keyboard, search_results, mini_player, player_lyrics, queue, favorites_or_playlist, downloads, settings
blocker owner and required decision when blocked
```

- [ ] **Step 2: QA matrix execution**

QA captures or reviews:

```text
home
search and play
unavailable result
player and queue
download manager
settings source list
hotlist detail
playlist/favorite
```

- [ ] **Step 2a: Attach required matrix metadata**

Android and OHOS review requests must include:

```text
QA matrix path: docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md
screenshot naming rule
package path and sha256
device model and device id
operation path for each screenshot or recording
screenshot/recording/log directory
pass/fail/blocker result for each required matrix row
failure escalation rule for any blocker
```

- [ ] **Step 3: Record pass/fail/blocker**

Use failure categories:

```text
P0: main path broken
P1: selected Library First structure missing
P2: misleading state or action
P3: visual polish issue
```

### Task 6: Review, merge and notification

**Files:**
- Modify: `docs/codex_collab/requests/AM-20260711-003-library-first-mobile-ui-implementation.md`

**Interfaces:**
- Consumes: Android HEAD, tests, analyze, APK, device screenshots, OHOS review, QA matrix.
- Produces: accepted/changes_requested review and merge decision.

- [ ] **Step 1: Review gate**

Run:

```bash
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-003-library-first-mobile-ui-implementation.md --gate review
```

Expected: `OK` only after Head Commit, Targeted Tests, Scope Diff Evidence, Self Test Evidence, Spec Review Result and Code Quality Review Result are filled.

- [ ] **Step 2: Required verification**

Android owner must report:

```text
flutter test targeted suite
flutter analyze --no-pub
git diff --check
debug APK path and sha256
Xiaomi 10 Pro screenshot directory
media_session evidence for search -> tap play
cache evidence proving only complete audio is cached
QA matrix path, screenshot naming rule, package sha, device, operation path and pass/fail/blocker summary
```

- [ ] **Step 3: Merge gate**

After accepted review, run:

```bash
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-003-library-first-mobile-ui-implementation.md --gate merge
```

Expected: `OK`.

- [ ] **Step 4: Product notification**

Send a validated message to Product with:

```text
HEAD
merge commit
target branch
push result
APK path and sha
whether Xiaomi 17 Pro install is ready
remaining P3 polish, if any
```
