# AM-20260711-002 Mobile UI Product Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于 AI Music 当前真实移动端 App 页面完成 Product Design 审计，并生成恰好 3 套独立移动端视觉方向供 Product 选择。

**Architecture:** Architect 只建立 request、设计规格、计划和跨 lane 门禁；Android 提供真实页面证据，UI 执行 audit/ideate，OHOS 和 QA researcher 提供跨端与验收矩阵。Product 选择视觉方向前不进入 Flutter UI 实现。

**Tech Stack:** AI Music Flutter App、Android 小米 10 Pro 截图与日志、Product Design audit/ideate、AI Music `team_ops.py` workflow gate、Markdown 协同账本。

## Global Constraints

- Target Version: 1.1.0。
- Audit baseline: `origin/release/1.0.2=b306932d03e1eedbe96fd50dafe0f95805b0eab4`。
- Architect-confirmed AM-017 APK: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017_android_source/build/app/outputs/flutter-apk/app-debug.apk`，sha256 `4eebeed8803576266d0e2456e47a0fb11a083eaff58284d3ec4d85a7852b068a`。
- Android screenshot APK: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-016/build/app/outputs/flutter-apk/app-debug.apk`，sha256 `ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3`。
- Product Design 必须先审计真实页面，再生成恰好 3 套独立视觉方向。
- 选定方向前不允许开发 lane 修改 UI 代码。
- 1.0.2 既有搜索、完整音频播放、下载缓存、歌词封面、热榜和歌单功能不因本任务阻塞。
- Preview、网盘、不可下载源不能作为完整播放或下载完成路径。
- Android 曾创建的同 requestId 截图采集 request/design/plan 已并入本 canonical plan 的 Task 2；它不是第二个 AM-20260711-002 request。
- Product 静态审计 P1 事实必须进入 1.1.0 设计约束：当前播放队列没有可见 UI 入口；mini player 在下载管理、设置、排序编辑等页面中断；完整音频边下边播时丢失收藏与加歌单入口。选定视觉方向前只做设计约束和 handoff，不派 UI 代码。
- 跨端硬约束必须进入 1.1.0 设计和 QA：横滑切歌避开系统边缘返回区；48px 最小触控目标；搜索提交后处理键盘与焦点；大字号下不依赖固定卡高；歌单选择 sheet 与下载长列表可滚动；SafeArea/系统手势区不能写死；OHOS foreground-only 与启动窗白色/暗色首帧不一致列为平台风险。
- UI 真实截图 audit 已并入 `docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md`。当前状态允许 Product 基于 Library First、Now Playing Hero、Discovery Mix 三套提示词生成恰好 3 张图并选择方向；选定前仍不派 UI 实现代码。
- Audit evidence debt：Android b306932 已包含 AM-010 `_HotlistItemTile` leading `height: 32` 修复，但当前热榜详情截图仍显示 overflow debug 条，后续由 Android/android-discovery 复现或补无 overflow 截图；真正队列 sheet 截图缺失不阻塞 ideation，但 image-to-code/开发 handoff 前必须由 Android 补采或确认当前无可达队列 UI。

---

### Task 1: 建立 request、设计规格和启动门禁

**Files:**
- Create: `docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md`
- Create: `docs/superpowers/specs/2026-07-11-am-20260711-002-mobile-ui-redesign-product-design.md`
- Create: `docs/superpowers/plans/2026-07-11-am-20260711-002-mobile-ui-redesign-product-design.md`

**Interfaces:**
- Consumes: Product 的 AM-20260711-002 指令、`origin/release/1.0.2` 当前基线、`team_ops.py` workflow gate。
- Produces: 可分派给 android/ui/ohos/qa-researcher 的 request、设计规格和实施计划。

- [ ] **Step 1: 确认基线 commit**

Run:

```bash
git fetch origin
git rev-parse origin/release/1.0.2
```

Expected: 输出 `b306932d03e1eedbe96fd50dafe0f95805b0eab4` 或更新后的 release/1.0.2 commit；若输出不同，更新 request 的 `Baseline Commit` 和设计规格中的审计基线。

- [ ] **Step 2: 写入 request/design/plan**

Use the three files listed above. Request status starts as `assigned` so `validate-workflow --gate start` can verify Project Path, plan, baseline and workflow fields.

- [ ] **Step 3: 运行设计和开工门禁**

Run:

```bash
python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md --gate design
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md --gate start
```

Expected: all commands print `OK`.

- [ ] **Step 4: 提交前范围检查**

Run:

```bash
git diff --name-status -- docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md docs/superpowers/specs/2026-07-11-am-20260711-002-mobile-ui-redesign-product-design.md docs/superpowers/plans/2026-07-11-am-20260711-002-mobile-ui-redesign-product-design.md
```

Expected: only AM-20260711-002 canonical request/design/plan and linked QA matrix appear.

### Task 2: Android 提供真实页面审计包

**Files:**
- Create: `docs/codex_collab/knowledge/android/2026-07-11-am-002-mobile-ui-current-screens.md`
- Evidence folder: `/tmp/am002-mobile-ui-audit/android/`

**Interfaces:**
- Consumes: release/1.0.2 debug or beta APK installed on 小米 10 Pro, current Product main paths.
- Produces: UI lane 可直接审计的 screenshot packet and device evidence.

- [ ] **Step 1: 记录包和设备**

Android message must include package path, APK sha256, `dumpsys package` versionCode/versionName/lastUpdateTime, device serial, and source commit. The required source commit is `b306932d03e1eedbe96fd50dafe0f95805b0eab4` or a newer `origin/release/1.0.2`; 32d183c evidence is not accepted for this audit.

- [ ] **Step 2: 捕获首页发现与我的音乐**

Capture:

```text
/tmp/am002-mobile-ui-audit/android/01-home-discover.png
/tmp/am002-mobile-ui-audit/android/02-home-my-music.png
```

Evidence must include whether hotlist, favorites, custom playlist and cached songs are visible.

- [ ] **Step 3: 捕获搜索下载路径**

Actions:

```text
搜索 一丝不挂
搜索 稻香
搜索 浮夸
```

Capture:

```text
/tmp/am002-mobile-ui-audit/android/03-search-yisibugua.png
/tmp/am002-mobile-ui-audit/android/04-search-daoxiang.png
/tmp/am002-mobile-ui-audit/android/05-search-fail-closed.png
```

Expected: complete audio rows are distinguishable when available; unavailable rows show reason; no `试听/PREVIEW/30s` completion path.

- [ ] **Step 4: 捕获播放详情与当前队列**

Actions:

```text
播放 一丝不挂
打开播放详情
打开当前队列
```

Capture:

```text
/tmp/am002-mobile-ui-audit/android/06-player-detail.png
/tmp/am002-mobile-ui-audit/android/07-current-queue.png
```

Expected: media session state=3 and metadata match the displayed song.

- [ ] **Step 4a: 捕获队列入口与跨页 mini player**

Capture or mark blocker:

```text
/tmp/am002-mobile-ui-audit/android/07a-queue-entry.png
/tmp/am002-mobile-ui-audit/android/07b-download-manager-mini-player.png
/tmp/am002-mobile-ui-audit/android/07c-settings-mini-player.png
/tmp/am002-mobile-ui-audit/android/07d-sort-edit-mini-player.png
```

Expected: evidence explicitly shows whether the current queue has a visible entry and whether mini player persists across download manager, settings and sort/edit screens.

- [ ] **Step 5: 捕获歌单管理**

Capture:

```text
/tmp/am002-mobile-ui-audit/android/08-playlists.png
/tmp/am002-mobile-ui-audit/android/09-playlist-detail.png
/tmp/am002-mobile-ui-audit/android/10-hotlist-add-feedback.png
```

Expected: custom playlist, hotlist playlist, add feedback and item states are visible or named as blockers.

- [ ] **Step 6: 捕获完整音频边播的收藏与加歌单入口**

Actions:

```text
搜索并播放 一丝不挂 或 稻香
在完整音频边下边播状态打开播放详情
检查收藏入口和加入歌单入口
```

Capture:

```text
/tmp/am002-mobile-ui-audit/android/11-full-audio-streaming-favorite-entry.png
/tmp/am002-mobile-ui-audit/android/12-full-audio-streaming-add-playlist-entry.png
```

Expected: if either entry is missing, record it as a design constraint rather than a development task.

### Task 3: UI 执行 Product Design audit

**Files:**
- Create: `docs/codex_collab/knowledge/ui/2026-07-11-am-002-mobile-ui-product-design-audit.md`
- Evidence folder: `/tmp/am002-mobile-ui-audit/ui/`

**Interfaces:**
- Consumes: Android screenshot packet and design spec.
- Produces: Product Design audit report with screenshot-tied findings.

- [ ] **Step 1: 检查截图可用性**

Reject any screenshot that is blank, locked, loading, cropped, or from a mismatched package. Record rejected files and replacement request in the UI report.

- [ ] **Step 2: 按四条路径写 step list**

Audit report must list:

```text
1. 首页发现与我的音乐
2. 搜索下载
3. 播放详情与当前队列
4. 歌单管理
```

Each step includes health, UX issue, visual hierarchy issue, accessibility risk, and evidence limit.

Audit must explicitly include the Product P1 static facts:

```text
1. 当前播放队列没有可见 UI 入口。
2. mini player 在下载管理、设置、排序编辑等页面中断。
3. 完整音频边下边播时收藏与加歌单入口缺失。
```

Audit must also check the cross-platform constraints: edge-swipe conflict, 48px touch target, keyboard dismissal after search submit, dynamic text without fixed card height, scrollable playlist sheet/download list, SafeArea/system gesture insets, and OHOS foreground-only/startup first-frame risk.

- [ ] **Step 3: 输出 Product Design audit 结论**

Expected report sections:

```text
Overall Verdict
Screenshots Reviewed
Highest-impact Findings
Accessibility Risks
Evidence Limits
Recommendations for Ideation
```

No finding may rely on memory or old screenshots.

### Task 4: OHOS 补跨端约束

**Files:**
- Create: `docs/codex_collab/knowledge/ohos/2026-07-11-am-002-mobile-ui-cross-platform-constraints.md`

**Interfaces:**
- Consumes: design spec and Android screenshot packet.
- Produces: HarmonyOS constraints for UI ideation and later implementation.

- [ ] **Step 1: 检查 HarmonyOS 宿主限制**

OHOS lane records safe area, status/navigation bar behavior, system font differences, ArkTS/HAP shell limitations, AVSession/notification constraints, and any Flutter rendering risks.

OHOS must specifically classify:

```text
foreground-only playback and lifecycle limits
white launch screen vs dark first-frame inconsistency
system gesture edge region
safe area/status/navigation bar insets
dynamic font and large text scaling
scrollable sheet/list behavior
```

- [ ] **Step 2: 标注跨端不可承诺项**

Examples:

```text
Android-only gesture
HarmonyOS unavailable platform affordance
OS-level playback control outside Flutter UI
```

Expected: every constraint says whether it blocks ideation, affects implementation, or only affects QA.

### Task 5: UI 生成恰好 3 套视觉方向

**Files:**
- Create: `docs/codex_collab/knowledge/ui/2026-07-11-am-002-mobile-ui-three-directions.md`
- Evidence folder: `/tmp/am002-mobile-ui-ideation/`

**Interfaces:**
- Consumes: UI audit report, Android screenshots, OHOS constraints, Product brief.
- Produces: exactly three independent Product Design visual directions for Product selection.

- [ ] **Step 1: 准备 ImageGen 输入**

Attach accepted screenshots from Task 2 and design constraints from Tasks 3 and 4. Use mobile dimensions `390 x 844` in every prompt.

- [ ] **Step 2: 生成三套独立方向**

Generate exactly three independent images. Directions must differ in information hierarchy, navigation model, playback/search prominence, or visual system. Do not generate multiple ideas in a single image.

- [ ] **Step 3: 停止等待 Product 选择**

UI final message must ask Product to choose `1`, `2`, or `3`, or give refinement feedback. UI must not start implementation or code edits.

- [ ] **Step 4: 归档方向说明**

Record for each displayed direction:

```text
Displayed option number
Image path or generated image reference
Primary screen focus
Main tradeoff
Implementation risk
```

### Task 6: QA researcher 建立截图验收矩阵

**Files:**
- Create/Use: `docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`

**Interfaces:**
- Consumes: design spec, audit report, three visual directions.
- Produces: later implementation review can reuse the screenshot matrix.

- [ ] **Step 1: 定义验收设备和页面矩阵**

Matrix rows must include 小米 10 Pro development validation and 小米 17 Pro product acceptance. Columns must include home, search, player detail, queue, playlist list, playlist detail, unavailable source, download/cache state. The current matrix file is `docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`.

- [ ] **Step 2: 定义 pass/fail/blocker**

Failure categories:

```text
P0: 主路径不可操作或完整播放/下载入口消失
P1: 选定视觉方向关键结构未实现
P2: 状态或文案误导
P3: 视觉细节偏差
```

- [ ] **Step 3: 回传 QA evidence gate**

QA researcher message must include matrix path, required screenshots, expected actions, log or media-session requirements where applicable, and failure escalation rule.

### Task 7: Architect 收口设计阶段并拆后续实现

**Files:**
- Modify: `docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md`

**Interfaces:**
- Consumes: Android screenshots, UI audit, OHOS constraints, three directions, QA matrix, Product selection.
- Produces: accepted design phase and a separate implementation request after Product chooses a direction.

- [ ] **Step 1: 验证所有 handoff 证据**

Run:

```bash
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-002-mobile-ui-redesign-product-design.md --gate review
```

Expected: `OK` after evidence fields are updated.

- [ ] **Step 2: Product 选择后创建实现 request**

Create a new implementation request for 1.1.0 UI work. Its scope must name the selected option number, source screenshots, exact screens to implement, target branch, Project Path, tests, screenshot QA matrix and rollback strategy.

The implementation request must carry the Product P1 handoff items: current queue entry, persistent mini player across management/settings/edit pages, and favorite/add-playlist entry during full-audio streaming. It must also name the cross-platform constraints and owners: public Dart for shared UI behavior and OHOS owner for foreground-only, startup first-frame, safe-area and system gesture verification.

- [ ] **Step 3: 禁止选定前开发合入**

If any lane sends UI implementation before Product selection, Architect returns `changes_requested` with reason: `AM-20260711-002 visual direction not selected`.
