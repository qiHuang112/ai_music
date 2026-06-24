# 版本账本

这个文件由 product lane 负责维护版本视角，架构师和各开发 lane 在任务状态变化时补充事实依据。目标是随时能回答：每个版本新增了多少功能、包含哪些 request、当前验收和推送状态如何、对应 tag 和 Android release 包在哪里。

## 规则

- 当前冻结版本不再接收新增功能，只接收已登记任务、bugfix 和验收修复。
- 新增功能默认进入下一版本，除非 product lane 明确要求插入当前版本并写明原因。
- `accepted_pending_merge` 表示 review accepted 且 owner 自测通过，等待架构师合入目标分支。
- 架构师确认提交范围、测试和 review 结论后，可以直接合入并推送；推送后同步 product 验证最新包。
- 需要发版时，由 reviewer/architect 打 tag、基于 tag 构建 Android release 包，成功后再 push release 分支、main 和 tag。

## 1.0.0

- Status: release_ready
- Branch: `release/1.0.0`
- Release Tag: pending `v1.0.0`
- Android APK: pending final tag build
- Frozen At: 2026-06-22
- Feature Count: 2

| Request | 功能 | Owner | Work Branch | 状态 | Commit | Release |
| --- | --- | --- | --- | --- | --- | --- |
| AM-20260622-002 | 安卓播控收藏、随机短听跳过和收藏进度条回归修复 | android | main 迁移前已完成 | pushed/accepted | `74b8bea` | pending |
| AM-20260622-003 | 恢复 FLAC 源、Auto 双源搜索、搜索展示优化、歌词封面基础恢复 | android | `lane/integration` 验收后合入 `main` | accepted | `71a51bd` | pending `v1.0.0` |

## Worktree 状态

| 用途 | Branch | Worktree Path | 状态 |
| --- | --- | --- | --- |
| 1.0.0 收口 | `release/1.0.0` | `/Users/huangqi/AIHome/worktrees/ai_music/release-1.0.0` | ready |
| 1.0.1 集成 | `release/1.0.1` | `/Users/huangqi/AIHome/worktrees/ai_music/release-1.0.1` | ready |
| AM-20260622-003 开发 | `feature/1.0.0/AM-20260622-003-restore-flac-source` | `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003` | ready |

## 发布注意事项

- 本地 fetch tags 时发现远端已有同名 tag `v1.0.0-android-arm64` 且与本地 tag 不一致；不得强行覆盖。
- 1.0.0 正式发布前，架构师需要确认 tag 命名策略，优先使用 `v1.0.0` 或 `v1.0.0-rc.N`，避免复用冲突 tag。

## 1.0.1

- Status: planned
- Branch: `release/1.0.1`
- Release Tag: pending
- Android APK: pending
- Frozen At: pending
- Feature Count: 0

| Request | 功能 | Owner | Work Branch | 状态 | Commit | Release |
| --- | --- | --- | --- | --- | --- | --- |
