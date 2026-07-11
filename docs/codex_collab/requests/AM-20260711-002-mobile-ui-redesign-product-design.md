# AM-20260711-002 Product Design 重做 AI Music 移动端 UI

Status: in_progress
Owner Lane: architect
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Target Version: 1.1.0
Base Branch: release/1.0.2
Work Branch: design/1.1.0/AM-20260711-002-mobile-ui-redesign-product-design
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-002
Merge Branch: main
Created: 2026-07-11
Updated: 2026-07-11
Workflow: superpowers-v1
Work Type: research
Risk Level: P1
User Visible: yes
Design Doc: docs/superpowers/specs/2026-07-11-am-20260711-002-mobile-ui-redesign-product-design.md
Implementation Plan: docs/superpowers/plans/2026-07-11-am-20260711-002-mobile-ui-redesign-product-design.md
Required Skills: using-superpowers, ai-music-team-ops, product-design:audit, product-design:ideate, writing-plans, verification-before-completion
TDD Mode: not_applicable
TDD Exception: not_applicable
TDD Exception Review: not_applicable
Baseline Commit: b306932d03e1eedbe96fd50dafe0f95805b0eab4
Head Commit: 5a90105581d0904fdaf6fd6c88b11e873769a4fa
Root Cause Evidence: not_applicable
Research Evidence: docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md
Red Evidence: not_applicable
Green Evidence: not_applicable
Targeted Tests: process/research design task: validate-request OK; validate-workflow --gate start OK; validate-workflow --gate review OK after filling design evidence, scope diff and self-test evidence; no app code targeted tests required for AM-20260711-002 because implementation moved to AM-20260711-003
Self Test Evidence: UI lane 已基于 Android b306932 小米 10 Pro 当前截图和 OHOS 真机截图完成四条路径 Product Design audit；本轮未生成新图、未改业务代码；三套 390x844 ImageGen 提示词为 Library First、Now Playing Hero、Discovery Mix
Product Main Path Evidence: Android 当前截图目录 `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`；OHOS 当前截图目录 `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/screenshots`；OHOS 约束清单 `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/ohos-platform-constraints.md`
Baseline Freshness Evidence: origin/release/1.0.2=b306932d03e1eedbe96fd50dafe0f95805b0eab4 作为真实页面审计基线；Android 截图采集包为同 commit debug APK sha256=ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3；Product 已检查首页、搜索、下载管理、播放/歌词、歌单 sheet 等关键截图有效
Scope Diff Evidence: design-only scope; diff limited to AM-20260711-002 canonical request/design/plan/knowledge and AM-20260711-003 request/design/plan handoff docs, no Flutter app source changes
Spec Review Result: accepted; selected Library First direction, Android/OHOS screenshots, UI audit, QA matrix and implementation handoff are recorded
Code Quality Review Result: accepted; ledger/docs-only update, no business code or UI implementation changes in AM-20260711-002
Full Verification Evidence: validate-request OK; validate-workflow --gate start OK; validate-workflow --gate review OK; AM-20260711-003 design/start gate OK
Blocking Findings: none for Product ideation; Android/OHOS current screenshots and UI audit are available. Current audit findings are design/implementation handoff constraints, not blockers to Product generating exactly three direction images.
Merge Evidence: pending
Push Evidence: pending
Product Notification Evidence: pending
Knowledge Evidence: docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md

## 目标

使用 Product Design 重做 AI Music 移动端 UI 的设计阶段：先基于最新真实页面做 audit，再生成恰好 3 套独立视觉方向供 Product 选择。

## 范围

- 包含：当前完整 App 的真实页面审计、三套移动端视觉方向、跨端约束、截图验收矩阵和后续实现 handoff。
- 覆盖路径：首页发现与我的音乐、搜索下载、播放详情与当前队列、歌单管理。
- 不包含：选定视觉方向前的 Flutter UI 代码实现、1.0.2 功能收口变更、预览音频作为完成路径。
- Android 曾创建的 `AM-20260711-002-android-current-product-screenshots.md` 只作为本 canonical request 的截图采集子证据清单，不再作为第二个 AM-20260711-002 request 口径流转。

## 验收标准

- design/start gate 通过。
- Android 提供基于 `origin/release/1.0.2` 的小米 10 Pro 真实页面截图、包 SHA、设备和主路径动作证据。
- UI 基于本轮截图完成 Product Design audit。
- UI 生成恰好 3 套独立视觉方向，并在 Product 选择前停止。
- OHOS 提供跨端限制，QA researcher 提供截图验收矩阵。
- Product 未选择视觉方向前，不允许开发 lane 直接修改或合入 UI 代码。
- 三个 Product P1 事实必须进入 audit、三套方向和后续实现 handoff：当前播放队列无 UI 入口、mini player 跨下载管理/设置/排序编辑中断、完整音频边下边播缺收藏和加歌单入口。
- 跨端硬约束必须进入 audit、三套方向和 QA：边缘返回区避让、48px 触控目标、搜索提交键盘处理、大字号非固定卡高、歌单 sheet/下载长列表滚动、SafeArea/系统手势区不写死、OHOS foreground-only 与启动首帧风险。

## 消息记录

- 2026-07-11 type=task lane=architect summary=Product 要求使用 Product Design 重做 AI Music 移动端 UI，先审计真实页面，再生成三套视觉方向，选定前不开发。
- 2026-07-11 type=status lane=qa-researcher summary=QA researcher 已完成 UI Product Design 回归矩阵，覆盖截图路径矩阵、状态覆盖表、截图操作步骤、视觉证据模板、pass/fail/blocker 标准和后续 design-qa 对比要求。
- 2026-07-11 type=status lane=architect summary=AM-017 已推送到 origin/release/1.0.2=b306932，并产出 debug APK sha256 4eebeed8803576266d0e2456e47a0fb11a083eaff58284d3ec4d85a7852b068a；AM-002 审计基线改用该最新 1.0.2 包。
- 2026-07-11 type=status lane=architect summary=Android 截图采集并入本 canonical request/design/plan，作为子证据而不是第二个 AM-20260711-002 request；Android 后续只回传截图目录、包 SHA、设备和逐页操作路径。
- 2026-07-11 type=blocker lane=android summary=Android 已基于 b306932 在 `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-016` 重建 debug APK，sha256 ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3；小米 10 Pro 无线调试不可达，阻塞安装和逐页截图采集。
- 2026-07-11 type=blocker lane=ohos summary=OHOS 已确认 HAP `/Users/huangqi/AIHome/projects/ai_music_ohos/build/ohos/hap/entry-default-signed.hap` sha256 9065d4d37c10c37be845f7c1c0a3561593f15234cf4a46535da2e1772f856abb，但无线 HDC 无 connect-key target，阻塞真机截图。
- 2026-07-11 type=status lane=architect summary=Product 静态审计 P1 已写入 canonical design/plan/QA：当前播放队列无入口、mini player 跨页中断、完整音频边播缺收藏/加歌单；选定视觉方向前只作为设计约束，不派 UI 代码。
- 2026-07-11 type=status lane=architect summary=跨端硬约束已写入 canonical design/plan/QA：边缘返回区、48px 触控、搜索键盘、大字号、滚动 sheet/长列表、SafeArea/系统手势区和 OHOS foreground-only/启动首帧风险；分别标公共 Dart 与 OHOS owner。
- 2026-07-11 type=blocker lane=ohos summary=OHOS 二次排查确认 Mac 到 `192.168.31.53:6666` 端口可达、`hdc tconn` 为 Connect OK、client/server 版本均为 3.2.0c、server log 显示 RSA 授权成功；但设备握手返回空 `connectKey`、`devname=localhost` 后 `CMD_KERNEL_CHANNEL_CLOSE`，所以 install/shell/uitest 仍不可执行。下一步需要设备侧关闭再开启无线调试和调试授权，必要时重新配对或重启手机端调试服务。
- 2026-07-11 type=blocker lane=ohos summary=OHOS 按 Product 确认地址 `192.168.31.53:6666` 完成新会话复连验证：`hdc kill -r` 成功，`hdc tconn 192.168.31.53:6666` 返回 Connect OK，但 `hdc list targets -v` 仍为 `[Empty]`，`hdc shell echo ok` 返回 `[Fail]ExecuteCommand need connect-key? please confirm a device by help info`。按约定停止重复探测；截图仍 blocked，最新证据追加到 `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/manifest.md`。
- 2026-07-11 type=status lane=architect summary=AM-002 设备截图 blocker 已解除：Android b306932 / 小米 10 Pro 当前截图在 `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`，包 sha256 `ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3`；OHOS HAP 真机截图在 `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/`，约束清单为 `ohos-platform-constraints.md`。Product 已检查首页、搜索、下载管理、播放/歌词、歌单 sheet 等关键图有效；UI 正在基于当前证据重做 audit 和三套视觉提示词。
- 2026-07-11 type=review_result lane=android summary=Architect 复核 Android b306932 / 小米 10 Pro 截图包 accepted as UI audit input：`summary.md` 记录设备、包、安装、media session 和已知限制；截图目录包含首页、搜索、下载管理、缓存播放、mini player、播放详情/歌词、队列相关误触/限制、收藏、热榜、设置、音乐源等 20 个文件。中文搜索干净结果页、下载中瞬间态和独立队列 sheet 未完全捕获，作为 UI audit evidence limits 记录，不阻塞 UI 进入 audit/ideate。
- 2026-07-11 type=status lane=ui summary=UI 已基于 Android b306932 小米 10 Pro 当前截图和 OHOS 真机截图完成真实截图 Product Design audit，文档已并入 canonical path `docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md`；本轮未生成新图、未改业务代码；三套 390x844 ImageGen 提示词为 Library First、Now Playing Hero、Discovery Mix。
- 2026-07-11 type=review_result lane=architect summary=Spec Review Result: accepted，UI audit 已并入 canonical path，Product 可基于文档中三套提示词独立生成恰好 3 张图并选择方向；Code Quality Review Result: accepted，本轮仅账本和设计文档更新，无 UI 代码改动。`release/1.0.2@b306932` 代码包含 AM-010 `_HotlistItemTile` leading `height: 32` 修复，因此当前热榜详情 overflow 截图按“仍需 Android/android-discovery 复现或补无 overflow 截图”的 P1 视觉证据项处理；真正队列 sheet 截图缺失不阻塞 ideation，但在 image-to-code/开发 handoff 前 Android 需补采真正队列入口/sheet 或确认当前版本无可达队列 UI；键盘常驻搜索层级不足归 public Dart/UI implementation，进入 1.1.0 设计约束。
- 2026-07-11 type=status lane=product summary=Product 默认采用三张方向图中的第 1 张 `Library First / 我的音乐与继续播放优先` 作为后续实现基准，不再等待额外选择；对应生成图路径为 `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`。下一步由 architect 拆 1.1.0 UI implementation request，UI 输出页面级实现规范，Android/OHOS/QA 按约束分头落地与验收。
- 2026-07-11 type=status lane=architect summary=Architect 已基于 Product 选定的 Library First 方向拆出 1.1.0 UI implementation request `AM-20260711-003`，独立 Project Path `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`，实现分支 `feature/1.1.0/AM-20260711-003-library-first-ui`，基线 `origin/release/1.0.2=b306932d03e1eedbe96fd50dafe0f95805b0eab4`。AM-002 继续作为 design/audit canonical，AM-003 承接实现、测试、OHOS 约束复核和 QA 截图验收。
- 2026-07-11 type=status lane=qa-researcher summary=QA researcher 已更新 Library First 验收矩阵，覆盖首页、搜索、下载缓存、mini player、播放详情、队列、收藏歌单、热榜、设置、Android/OHOS 截图证据和 pass/fail/blocker 标准；该矩阵作为 AM-20260711-002 design-qa gate 和 AM-20260711-003 QA 验收输入。
- 2026-07-11 type=status lane=ohos summary=OHOS 已基于已选 Library First 方向补完跨端实现注意清单，路径 `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/library-first-ohos-implementation-notes.md`；公共 Flutter 必须处理 SafeArea/insets、跨页 mini player、搜索键盘、48px 触控、大字号、当前队列入口、播放详情层级和长列表/sheet，OHOS 后续按 foreground-only 与启动首帧风险验收。

## 相关提交

- pending
- 609bcc78ae8da55a7253af9bb9d35eeee3946711 recorded UI audit review; follow-up AM-20260711-003 created in this update.

## 版本与发布

- Target Version: 1.1.0
- Release Tag: not_applicable
- Android APK: not_applicable
- Push Status: not_ready

## Review 结果

- Reviewer Lane: pending
- Result: pending
- Android Findings: pending
- iOS Findings: not_applicable
- HarmonyOS Findings: pending
- Architect Findings: accepted_for_product_ideation；P1/P2 owner 已记录，Product 选定视觉方向前不派 UI 代码
- Notes: 设计阶段 canonical 账本已建立；Android/OHOS 当前截图和 UI audit 已可用，Product 已选择 Library First；实现阶段由 AM-20260711-003 承接，本任务不改业务代码。
