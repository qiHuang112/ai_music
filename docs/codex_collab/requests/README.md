# 任务单

每个任务单使用一个 Markdown 文件，命名格式：

```text
AM-YYYYMMDD-NNN-short-title.md
```

示例：

```text
AM-20260621-001-harmony-media-session.md
```

## 状态值

- `proposed`：任务已记录，但还没分配。
- `assigned`：已确定负责人 lane 和验收标准。
- `in_progress`：负责人 lane 正在处理。
- `self_tested`：owner 已完成自动化和产品主路径自测，正在整理 review 证据。
- `review_requested`：已通过 review gate，等待规格符合性和代码质量 review。
- `review`：实现已完成，等待 review。
- `changes_requested`：架构师 review 后发现问题，已分发给对应 lane 修复。
- `accepted`：架构师或指定 reviewer 已验收。
- `accepted_pending_merge`：架构师 review accepted 且 owner 自测通过，等待架构师合入目标分支。
- `pushed`：已由架构师按闭环规则推送到远端，并同步 product 验证最新包。
- `blocked`：需要用户输入或外部状态变化。

## 模板

```text
# AM-YYYYMMDD-NNN 中文短标题

Status: proposed
Owner Lane: android|ios|ohos|architect
Source Thread: <thread-id>
Target Version: <x.y.z>
Base Branch: release/<x.y.z>
Work Branch: feature/<x.y.z>/AM-YYYYMMDD-NNN-short-title
Project Path: /Users/huangqi/AIHome/projects/ai_music_<lane_or_request>
Merge Branch: release/<x.y.z>
Created: YYYY-MM-DD
Updated: YYYY-MM-DD
Workflow: superpowers-v1
Work Type: feature|bugfix|refactor|research|process|release
Risk Level: P0|P1|P2|P3
User Visible: yes|no
Design Doc: docs/superpowers/specs/YYYY-MM-DD-short-title-design.md
Implementation Plan: docs/superpowers/plans/YYYY-MM-DD-short-title.md
Required Skills: brainstorming, writing-plans, test-driven-development
TDD Mode: required|exception|not_applicable
TDD Exception: none|<例外原因>
TDD Exception Review: not_applicable|pending|accepted
Baseline Commit: <7-40 位 commit SHA>
Head Commit: pending|<7-40 位 commit SHA>
Root Cause Evidence: pending|not_applicable|<Bug 根因摘要或证据路径>
Research Evidence: pending|not_applicable|<研究脚本和证据路径>
Red Evidence: pending|not_applicable|<失败测试命令和预期失败>
Green Evidence: pending|not_applicable|<通过测试命令和结果>
Targeted Tests: pending|<命令和结果>
Self Test Evidence: pending|<owner 自测动作和结果>
Product Main Path Evidence: pending|not_applicable|<入口到结果证据>
Baseline Freshness Evidence: pending|<merge-base/fetch/rebase 证据>
Scope Diff Evidence: pending|<diff 文件范围>
Spec Review Result: pending|accepted|changes_requested|blocked
Code Quality Review Result: pending|accepted|changes_requested|blocked
Full Verification Evidence: pending|<完整验证命令和结果>
Blocking Findings: none|<P0/P1/P2 finding>
Merge Evidence: pending|<merge commit 和分支>
Push Evidence: pending|<远端分支和 commit>
Product Notification Evidence: pending|<product thread 通知定位>
Knowledge Evidence: pending|not_applicable|<知识沉淀路径>

## 目标
- <一句话说明目标>

## 范围
- 包含：<路径或行为>
- 不包含：<路径或行为>

## 验收标准
- <可测试的结果>

## 消息记录
- YYYY-MM-DD HH:MM type=<task|status|review_request|review_result|handoff|blocker> lane=<lane> summary=<中文摘要>

## 相关提交
- <commit-sha> <提交标题>

## 版本与发布
- Target Version: <x.y.z>
- Release Tag: <pending|vX.Y.Z|vX.Y.Z-rc.N>
- Android APK: <pending|build/release/...apk>
- Push Status: <not_ready|accepted_pending_push|pushed>

## Review 结果
- Reviewer Lane: architect|android|ios|ohos|none
- Result: pending|accepted|changes_requested|blocked
- Android Findings: <无问题或中文摘要>
- iOS Findings: <无问题或中文摘要>
- HarmonyOS Findings: <无问题或中文摘要>
- Architect Findings: <无问题或中文摘要>
- Notes: <中文 review 摘要和分发结果>
```

## 工程目录规则

- 新任务必须填写 `Project Path`，不再使用 `Worktree Path`。
- `Project Path` 必须指向独立仓库克隆或独立工程目录，不能指向 `/Users/huangqi/AIHome/worktrees/`。
- 开工、review、合入前必须先整合最新 `origin/main` 或目标 release 已合入内容，并在回传里写当前 `HEAD` 和基线 commit。
- 旧任务若仍有 `Worktree Path`，只能作为历史兼容或取补丁来源；合入前必须在最新主线独立工程中重放最小改动。

## Superpowers 门禁

- 2026-07-11 及以后新建任务必须填写模板中的 Superpowers 字段。
- `design`：要求设计文档、风险、用户可感知性和所需 skills。
- `start`：要求实施计划、独立工程、基线 commit 和 TDD 模式。
- `review`：要求 HEAD、RED/GREEN 或已批准例外、根因/研究证据、targeted tests、自测、主路径、基线和 scope diff。
- `merge`：要求规格符合性和代码质量双 review accepted、完整验证和无 blocking finding。
- `close`：要求 merge、push、Product 通知和知识沉淀证据。

运行方式：

```bash
python3 docs/codex_collab/tools/team_ops.py validate-workflow \
  docs/codex_collab/requests/AM-YYYYMMDD-NNN-short-title.md \
  --gate design|start|review|merge|close
```
