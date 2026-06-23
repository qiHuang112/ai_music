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
Worktree Path: /Users/huangqi/AIHome/worktrees/ai_music/<lane>-AM-YYYYMMDD-NNN
Merge Branch: release/<x.y.z>
Created: YYYY-MM-DD
Updated: YYYY-MM-DD

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
