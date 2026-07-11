# AM-20260711-003 Library First 移动端 UI 实现

Status: pushed
Owner Lane: android
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Product Return Thread: 019f4ed4-106e-7860-875d-a32f81629e4e
Target Version: 1.1.0
Base Branch: release/1.1.0
Work Branch: feature/1.1.0/AM-20260711-003-library-first-ui
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-003
Merge Branch: release/1.1.0
Created: 2026-07-11
Updated: 2026-07-11
Workflow: superpowers-v1
Work Type: feature
Risk Level: P1
User Visible: yes
Design Doc: docs/superpowers/specs/2026-07-11-am-20260711-003-library-first-mobile-ui-implementation.md
Implementation Plan: docs/superpowers/plans/2026-07-11-am003-library-first-ui.md
Required Skills: using-superpowers, ai-music-team-ops, brainstorming, writing-plans, test-driven-development, product-design:image-to-code, verification-before-completion
TDD Mode: required
TDD Exception: not_applicable
TDD Exception Review: not_applicable
Baseline Commit: aef2bf3c79623581b897d815315248fb15724d10
Head Commit: edd10b83d6bcc777fea993c4e2708d2bafdd1ca0
Root Cause Evidence: not_applicable
Research Evidence: docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md; docs/codex_collab/knowledge/ui/2026-07-11-am003-library-first-page-spec.md
Red Evidence: Task 2 RED tests added in `test/widget_test.dart` and `test/player_page_test.dart`; targeted RED commands failed as expected: home hierarchy missing `继续播放`; search rows missing `可下载` status chip; player page missing `当前队列` entry/sheet.
Green Evidence: Task 2/early Task 3 GREEN implemented: Home adds `继续播放` card before local assets/discovery; search rows add status chips for downloadable/unavailable candidates while keeping preview absent; Player adds distinct `当前队列` entry and queue sheet with count/current row; mini player exposes the same queue sheet without opening player; mini player title/cover area is now a real button hit target and clears focus before opening player detail; mini player sits above the gesture edge with fixed bottom gap.
Targeted Tests: `flutter test --no-pub test/widget_test.dart --plain-name 'library first home prioritizes local assets and continuing playback'` passed; `flutter test --no-pub test/widget_test.dart --plain-name 'search result rows expose status chips and keep unavailable rows actionless'` passed; `flutter test --no-pub test/player_page_test.dart --plain-name 'current queue entry opens queue sheet instead of playlist sheet'` passed; `flutter test --no-pub test/widget_test.dart --plain-name 'mini player exposes current queue without opening player'` passed; `flutter test --no-pub test/widget_test.dart --plain-name 'mini player keeps controls above gesture safe area'` passed; `flutter test --no-pub test/widget_test.dart --plain-name 'mini player title exposes a button hit target'` RED/GREEN passed; `flutter test --no-pub test/widget_test.dart --plain-name 'mini player title clears focus and opens player detail'` passed; `flutter test --no-pub test/widget_test.dart --plain-name 'mini player queue clears focus and opens app queue sheet'` passed; `flutter test --no-pub test/widget_test.dart --plain-name 'download manager cached rows expose cached status chip'` RED/GREEN passed; `flutter test --no-pub test/widget_test.dart --plain-name 'settings pages persist language theme and music source'` RED/GREEN passed after hiding old/preview/Kuwo sources from the user-facing source selector; targeted `flutter analyze --no-pub lib/src/presentation/music_home_page.dart test/widget_test.dart` passed after mini player fix; earlier targeted `flutter analyze --no-pub lib/src/presentation/app_localizations.dart lib/src/presentation/download_manager_page.dart lib/src/presentation/music_home_page.dart lib/src/presentation/player_page.dart lib/src/presentation/settings_page.dart test/widget_test.dart test/player_page_test.dart` passed; `git diff --check` passed. Full `test/widget_test.dart test/player_page_test.dart` attempt was stopped after an existing `lyrics scroll does not seek but tapping a line seeks` test did not complete, unrelated to this slice.
Self Test Evidence: Latest WIP debug APK built and installed on Xiaomi 10 Pro `192.168.31.76:41563`; sha256 `18e98b42e335fdc90b397d0af5d7e1386da5a32fdac6bdc11bc622dcb43ad4b8`, `versionCode=1`, `versionName=1.0.0`, `lastUpdateTime=2026-07-11 20:30:27`; input method remains `com.baidu.input_mi/.ImeService`. Evidence captured in `/Users/huangqi/AIHome/output/AM-20260711-003-designqa-final-20260711-195825-xiaomi10/`: home and settings/source selector show only `歌曲海 / gequhai.com`; search `外婆` via system Baidu 9-key candidate returns `歌海 / 外婆 / 周杰伦 - MP3 / 可下载` with no `PREVIEW/试听/30s/网盘/夸克`; tapping play yields `first_byte_ms=1653 < download_complete_ms=6077`, media session `state=3`, formal cache `周杰伦-外婆-74d0f9f4e3.mp3`, `.lrc`, and `_cache_index.json` with `source_gequhai/direct_audio/canCacheAudio=true/clientReady=true`; mini player safe-area evidence `44-home-after-final-install.xml` shows title button bounds `[44,2104][530,2247]` and controls above bottom edge; `45-current-queue-sheet-fixed.xml` shows `当前队列` app bottom sheet with `1 首` and no keyboard/clipboard; `46-player-detail-from-mini-title-fixed.xml` shows tapping mini title opens `正在播放` detail with `外婆/周杰伦` and lyrics block; `47-hotlist-detail-no-overflow-fixed.xml` shows hotlist detail rows and `47-hotlist-no-overflow-logcat.txt` contains no RenderFlex/Flutter overflow error.
Product Main Path Evidence: selected image `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`; Android baseline screenshots `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`; OHOS screenshots `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/screenshots`; OHOS Library First notes `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/library-first-ohos-implementation-notes.md`; OHOS AM-003 review checklist `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/am-20260711-003-ohos-cross-platform-review-checklist.md`; WIP Android screenshots `/Users/huangqi/AIHome/output/AM-20260711-003-designqa-wip-20260711-194305-xiaomi10/screens/`, including `AM-20260711-003_library-first_android_xiaomi10_home_initial_wip.png` and `AM-20260711-003_library-first_android_xiaomi10_settings_source_gequhai_only_wip.png`.
Baseline Freshness Evidence: implementation project `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003` fetched and rebased AM-003 workflow commits onto `origin/release/1.1.0=aef2bf3c79623581b897d815315248fb15724d10`; branch upstream updated to `origin/release/1.1.0`.
Scope Diff Evidence: `git diff --name-status origin/release/1.1.0..HEAD` shows AM-003 docs/spec/request/plan plus Flutter presentation/test files only: `docs/codex_collab/knowledge/qa-researcher/*`, `docs/codex_collab/knowledge/ui/*`, `docs/codex_collab/requests/AM-20260711-003-*`, `docs/superpowers/plans/2026-07-11-am003-library-first-ui.md`, `docs/superpowers/specs/2026-07-11-am-20260711-003-library-first-mobile-ui-implementation.md`, `lib/src/presentation/app_localizations.dart`, `download_manager_page.dart`, `music_home_page.dart`, `player_page.dart`, `settings_page.dart`, `test/player_page_test.dart`, `test/widget_test.dart`; no screenshot/build artifacts staged.
Spec Review Result: accepted
Code Quality Review Result: accepted
Full Verification Evidence: Architect review accepted after UI P1 re-review accepted. Fresh verification: `flutter test --no-pub test/widget_test.dart --name "mini player|library first|search result rows|download manager cached|settings pages"` = 12 passed; `flutter test --no-pub test/player_page_test.dart --name "current queue entry opens queue sheet instead of playlist sheet"` = 1 passed; `flutter analyze --no-pub lib/src/presentation/app_localizations.dart lib/src/presentation/download_manager_page.dart lib/src/presentation/music_home_page.dart lib/src/presentation/player_page.dart lib/src/presentation/settings_page.dart test/widget_test.dart test/player_page_test.dart` = no issues; scoped `git diff --check` clean. Xiaomi 10 Pro evidence path `/Users/huangqi/AIHome/output/AM-20260711-003-designqa-final-20260711-195825-xiaomi10/` covers full-audio search/play/cache, no PREVIEW, Gequhai-only settings, mini player safe area, player detail lyrics, current queue sheet, and hotlist no overflow.
Blocking Findings: none
Merge Evidence: release/1.1.0 merge commit d0fa9b26029eaca595d28a59ace377eb2a562c44 merged feature/1.1.0/AM-20260711-003-library-first-ui into release/1.1.0.
Push Evidence: `git push origin release/1.1.0` succeeded; remote branch advanced from `aef2bf3` to `f1e6ea3` after AM-003 merge evidence commit.
Push Status: pushed
Product Notification Evidence: architect final response to product/android/ui includes target branch, merge commit, pushed release HEAD, APK sha, installation state, tests, and evidence paths.
Knowledge Evidence: docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md

## 目标

将 Product 默认选定的 `Library First / 我的音乐与继续播放优先` 方向落地为 AI Music 1.1.0 移动端 Flutter UI，实现首页、搜索下载、播放详情/队列、歌单/下载管理/设置的统一视觉和主路径体验。

## 范围

- 包含：公共 Flutter UI、必要 controller/presentation state wiring、当前队列入口、跨页面 mini player、完整音频边下边播时收藏/加歌单入口、热榜 overflow 修复、搜索键盘和结果层级、下载管理/设置/歌单列表视觉统一、截图验收矩阵。
- 包含：UI lane 输出页面级实现规范；Android owner 实现公共 Dart/Flutter UI；OHOS owner 复核安全区、系统手势、字体缩放、foreground-only 和启动首帧风险；QA researcher 按矩阵做截图验收。
- 不包含：恢复 preview 作为完成路径、把不可下载源伪装成完整音频、改变 1.0.2 已验收的歌源/缓存安全闸口、选定方向之外的第二套视觉系统。

## 验收标准

- design/start gate 通过后才能进入代码实现。
- UI lane 先输出页面级实现规范，必须引用选定图和真实截图；Android 不在规范前抢写大改 UI。
- Android 必须按 TDD 提交：先补 widget/controller golden-adjacent 或截图主路径测试，再实现。
- 小米 10 Pro 真机主路径必须覆盖：首页、搜索 `一丝不挂`/`稻香` 并点击播放、不可下载样例原因展示且无 PREVIEW、播放详情、当前队列入口/sheet、下载管理、设置、收藏/歌单、热榜详情无 overflow、完整音频边下边播收藏/加歌单入口。
- OHOS 必须按 `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/am-20260711-003-ohos-cross-platform-review-checklist.md` 复核：SafeArea、系统手势区、48px 触控、大字号、键盘、跨页 mini player、当前队列入口、长列表/sheet、foreground-only、启动首帧风险，并回传 HAP 路径、sha256、source commit、是否清数据、目标设备、截图目录、操作路径和 pass/fail/blocker。
- QA 必须按 `docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md` 作为 design-qa gate 回传：矩阵路径、截图命名规则、包 SHA、设备、操作路径、截图/录屏/日志路径、每项 pass/fail/blocker 和失败升级规则。
- Product 体验包只接受完整音频路径；preview、网盘、HTML、防护页仍不得作为完成路径或正式缓存。

## 分工

- UI owner: 输出页面级实现规范、tokens、组件结构和截图标注；不直接修改业务代码，除非 architect 后续明确 handoff。
- Android owner: 公共 Flutter UI 实现、widget/controller 测试、Android debug APK、小米 10 Pro 主路径自测。
- OHOS owner: 跨端约束复核，提供 HAP/截图或约束清单，确认设计没有假设不存在的平台能力。
- QA researcher: 建立并执行截图验收矩阵，记录失败升级规则。
- Architect: review gate、scope diff、防回退、合入/推送/体验包判断。

## 消息记录

- 2026-07-11 type=task lane=product summary=Product 默认选择第 1 张 `Library First / 我的音乐与继续播放优先` 作为 1.1.0 UI 实现基准，生成图路径 `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`。
- 2026-07-11 type=status lane=architect summary=Architect 创建 AM-20260711-003 实现 request，独立 Project Path 为 `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`，基线 `origin/release/1.0.2=b306932d03e1eedbe96fd50dafe0f95805b0eab4`，实现分支 `feature/1.1.0/AM-20260711-003-library-first-ui`。
- 2026-07-11 type=status lane=qa-researcher summary=QA researcher 已更新 Library First 验收矩阵，作为本实现 request 的 design-qa gate 和后续截图验收输入。
- 2026-07-11 type=status lane=architect summary=Architect 已将 QA 矩阵设为 AM-003 design-qa gate：后续 Android/OHOS review_request 必须回传矩阵路径、截图命名规则、包 SHA、设备、操作路径、截图/录屏/日志路径和 pass/fail/blocker 证据；缺任一关键字段按 changes_requested 处理。
- 2026-07-11 type=status lane=ohos summary=OHOS 已提供 Library First 跨端实现注意清单 `library-first-ohos-implementation-notes.md`；UI 规范和 Android 实现必须标注并处理 SafeArea/insets、跨页 mini player、搜索键盘、48px 触控、大字号、当前队列入口、播放详情层级、长列表/sheet、foreground-only 和启动首帧风险。
- 2026-07-11 type=status lane=architect summary=Architect 已将 AM-003 request/spec/plan、`team_ops.py`、UI audit 和 QA 矩阵同步到独立 Project Path `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`；该路径本地 `validate-request` 和 `validate-workflow --gate start` 均为 OK。UI 页面级实现规范仍是 Android 开工前置，目标路径为 `docs/codex_collab/knowledge/ui/2026-07-11-am003-library-first-page-spec.md`。
- 2026-07-11 type=status lane=ohos summary=OHOS 已输出 AM-003 Library First 跨端实现复核清单 `am-20260711-003-ohos-cross-platform-review-checklist.md`；Architect 将其纳入 review/验收 gate。UI 页面级 spec 必须标注 safe area、键盘态、mini player 固定规则、当前队列入口、sheet 高度、48px 触控、大字号策略和暗色首帧预期；Android 实现不得写死 Android 状态栏/键盘/导航栏高度；后续 HAP 验收必须回传 HAP 路径、sha256、source commit、是否清数据、目标设备和截图 pass/fail/blocker。
- 2026-07-11 type=status lane=architect summary=Architect 已补齐 Android start gate 需要的短路径兼容 request `docs/codex_collab/requests/AM-20260711-003-library-first-ui.md`，内容与 canonical `AM-20260711-003-library-first-mobile-ui-implementation.md` 保持一致；Android 可用任一路径运行 `validate-request` 和 `validate-workflow --gate start`。
- 2026-07-11 type=status lane=ui summary=UI 已完成页面级实现规范 `docs/codex_collab/knowledge/ui/2026-07-11-am003-library-first-page-spec.md`，覆盖 Home/Search/Player/Queue/Library/Download/Settings、tokens、状态 chip、48px 触控、Android/OHOS safe area、键盘常驻、mini player、长文本、热榜无 Flutter layout overflow 和 QA 截图命名。
- 2026-07-11 type=status lane=architect summary=Architect 已将 UI page spec 同步进 AM-003 Project Path，并给出 scope 裁决：新增真实当前队列 bottom sheet 属于 AM-003；热榜红色竖条按图片水印/素材质量处理，不按 Flutter overflow 定性，但实现仍需防 layout overflow；状态 chip 映射按 UI spec 执行；标题取舍为首页/主入口用 `音乐`，搜索页和搜索输入聚焦态用 `搜音乐`。
- 2026-07-11 type=status lane=architect summary=Architect 已整理 AM-003 product 路由：当前 product 回传入口为 `019f4ed4-106e-7860-875d-a32f81629e4e`；旧 `Source Thread: 019ee910-8747-71e3-9293-720273f9e61f` 仅保留为历史来源/归档引用，不作为当前推进投递目标。
- 2026-07-11 type=task lane=product summary=Product 确认当前安装的 AM-003 WIP 包核心链路不可用，搜索、下载、边下边播不能验收；AM-003 已标记 `blocked_on_core_source`，等待 AM-20260711-004 恢复歌曲海完整资源主链路后再继续 UI 实现和体验包。
- 2026-07-11 type=status lane=product summary=AM-004 已进入 review 且小米 10 Pro 已安装 self_tested 包；AM-003 不继续空等，恢复 Library First 实现准备和计划对齐，但最终打包、自测、截图/录屏和 review_request 等 AM-004 architect accepted/merged 基线后执行。
- 2026-07-11 type=status lane=android summary=AM-004 三方 review 已 accepted，但 AM-003 Project Path fetch 后 `origin/release/1.0.2` 仍为 `b306932`，`origin/main` 为 `7ef2430`，尚未包含 AM-004 业务提交；AM-003 继续准备不依赖合入的 TDD/UI 清单，构建 APK 和小米 10 Pro 主路径自测等待 architect 合入 AM-004 后的 release 基线。
- 2026-07-11 type=blocker lane=android summary=收到 AM-004 已合入 `release/1.1.0@aef2bf3` 的回传后，AM-003 Project Path 执行 `git fetch origin`、显式 fetch `release/1.1.0`、`git ls-remote origin` 均确认当前 remote 只暴露 `main=7ef2430` 和 `release/1.0.2=b306932`；AM-003 无法同步到 `aef2bf3`，不能进入基于 AM-004 的构建和真机自测。
- 2026-07-11 type=status lane=product/ui summary=Product/UI 复核远端后确认 `release/1.1.0` 已可 fetch；Android 在 AM-003 Project Path 重新 fetch 成功，`origin/release/1.1.0=aef2bf3c79623581b897d815315248fb15724d10`，并将 AM-003 workflow commits rebase 到该基线，继续保留 Library First WIP。
- 2026-07-11 type=review_result lane=ui summary=UI 复验 AM-003 mini player P1 与热榜无 overflow 补充证据 accepted；范围为 mini player safe area、标题点击进入播放详情、右侧当前队列打开 AI Music bottom sheet、热榜详情无 Flutter overflow。证据为 `44/45/46/47` fixed 截图/XML/logcat；剩余无阻塞 P1/P2，红色竖向素材水印按 P3 观感建议记录。
- 2026-07-11 type=review_result lane=architect summary=Architect 双 review accepted。Spec Review Result: accepted，Library First 首页层级、搜索完整音频状态、无 PREVIEW、播放详情歌词、当前队列 sheet、mini player safe area、热榜无 overflow 和歌曲海唯一源证据通过。Code Quality Review Result: accepted，diff 限 Flutter presentation/tests/docs，targeted widget/player tests、局部 analyze 和 scoped diff-check 通过，无阻塞 finding。

## 相关提交

- pending
- Project Path sync commit pending in `feature/1.1.0/AM-20260711-003-library-first-ui`.

## 版本与发布

- Target Version: 1.1.0
- Release Tag: not_applicable
- Android APK: WIP debug `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003/build/app/outputs/flutter-apk/app-debug.apk`, sha256 `c605edf0b662ddf14240f7bb9d065c5a95b90e3e1245e3bd0dc388e6b7c85ace`
- Push Status: not_ready

## Review 结果

- Reviewer Lane: architect
- Result: accepted
- Android Findings: none
- iOS Findings: not_applicable
- HarmonyOS Findings: not_applicable_for_android_review; OHOS owner should re-verify after HAP is built from accepted UI baseline.
- Architect Findings: none
- Notes: 本 request 是 AM-20260711-002 设计选择后的实现拆分；AM-20260711-002 保持设计/audit canonical 角色。P3：热榜图片左侧红色竖向素材水印记录为观感建议，不阻塞合入。
