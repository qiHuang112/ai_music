# AM-20260711-003 Library First 移动端 UI 实现

Status: assigned
Owner Lane: android
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Target Version: 1.1.0
Base Branch: release/1.0.2
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
Implementation Plan: docs/superpowers/plans/2026-07-11-am-20260711-003-library-first-mobile-ui-implementation.md
Required Skills: using-superpowers, ai-music-team-ops, brainstorming, writing-plans, test-driven-development, product-design:image-to-code, verification-before-completion
TDD Mode: required
TDD Exception: not_applicable
TDD Exception Review: not_applicable
Baseline Commit: b306932d03e1eedbe96fd50dafe0f95805b0eab4
Head Commit: pending
Root Cause Evidence: not_applicable
Research Evidence: docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md
Red Evidence: pending
Green Evidence: pending
Targeted Tests: pending
Self Test Evidence: pending
Product Main Path Evidence: selected image `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`; Android baseline screenshots `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`; OHOS screenshots `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/screenshots`; OHOS Library First notes `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/library-first-ohos-implementation-notes.md`
Baseline Freshness Evidence: implementation project `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003` is checked out at `origin/release/1.0.2=b306932d03e1eedbe96fd50dafe0f95805b0eab4` on `feature/1.1.0/AM-20260711-003-library-first-ui`
Scope Diff Evidence: pending
Spec Review Result: pending
Code Quality Review Result: pending
Full Verification Evidence: pending
Blocking Findings: none at assignment; selected visual direction and current screenshots are available. UI page-level implementation spec is required before Android starts code.
Merge Evidence: pending
Push Evidence: pending
Product Notification Evidence: pending
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
- OHOS 必须复核：SafeArea、系统手势区、48px 触控、大字号、键盘、foreground-only、启动首帧风险。
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

## 相关提交

- pending

## 版本与发布

- Target Version: 1.1.0
- Release Tag: not_applicable
- Android APK: pending
- Push Status: not_ready

## Review 结果

- Reviewer Lane: pending
- Result: pending
- Android Findings: pending
- iOS Findings: not_applicable
- HarmonyOS Findings: pending
- Architect Findings: pending
- Notes: 本 request 是 AM-20260711-002 设计选择后的实现拆分；AM-20260711-002 保持设计/audit canonical 角色。
