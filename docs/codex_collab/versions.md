# 版本账本

这个文件由 product lane 负责维护版本视角，架构师和各开发 lane 在任务状态变化时补充事实依据。目标是随时能回答：每个版本新增了多少功能、包含哪些 request、当前验收和推送状态如何、对应 tag 和 Android release 包在哪里。

## 规则

- 当前冻结版本不再接收新增功能，只接收已登记任务、bugfix 和验收修复。
- 新增功能默认进入下一版本，除非 product lane 明确要求插入当前版本并写明原因。
- `accepted_pending_merge` 表示 review accepted 且 owner 自测通过，等待架构师合入目标分支。
- 架构师确认提交范围、测试和 review 结论后，可以直接合入并推送；推送后同步 product 验证最新包。
- 需要发版时，由 reviewer/architect 打 tag、基于 tag 构建 Android release 包，成功后再 push release 分支、main 和 tag。

## 1.0.0

- Status: blocked
- Branch: `main`
- Release Tag: `v1.0.0`
- Android APK: `/Users/huangqi/AIHome/projects/ai_music_integration/build/release/ai-music-v1.0.0-android-arm64.apk`
- Android APK SHA256: `54230c472cda52da0dd56d498edb98b8335ba5da50dead02d3bcce73c7a2d4e3`
- Frozen At: 2026-06-22
- Feature Count: 2

| Request | 功能 | Owner | Work Branch | 状态 | Commit | Release |
| --- | --- | --- | --- | --- | --- | --- |
| AM-20260622-002 | 安卓播控收藏、随机短听跳过和收藏进度条回归修复 | android | main 迁移前已完成 | pushed/accepted | `74b8bea` | `v1.0.0` |
| AM-20260622-003 | 恢复 FLAC 源、Auto 双源搜索、搜索展示优化、歌词封面基础恢复 | android | `lane/integration` 验收后合入 `main` | pushed/accepted | `d032dca` | `v1.0.0` |

## 1.0.0 发布记录

- 2026-06-24 产品已在小米 17 Pro 验收 integration 包体验 OK，授权合入主线和发布 `v1.0.0`。
- 架构师将业务提交 `d032dca` 和账本提交 `2cd71ea` 推送到 `origin/main`。
- 架构师创建并推送 tag `v1.0.0`。
- 基于 `v1.0.0` 对应代码构建 Android arm64 release 包，大小约 8.86 MB。
- 已安装到产品授权的小米 17 Pro `192.168.31.190:45075`，包信息为 `com.qi.ai.music` / `versionCode=2001` / `versionName=1.0.0` / `arm64-v8a` / `lastUpdateTime=2026-06-24 22:02:10`。
- 2026-06-24 产品反馈该 Android release 包播放后系统播控中心没有出现，`v1.0.0` 发布状态降为 blocked。修复前不得继续把该包作为正式 release 交付；1.0.1 新功能暂停覆盖本 blocker。

## 1.0.0 Blocker

| Request | 问题 | Owner | 状态 | 验收 |
| --- | --- | --- | --- | --- |
| AM-20260624-ANDROID-RELEASE-MEDIA-CONTROL | Android release 包播放后系统播控中心消失 | android | urgent_p1 | release 包在小米 10 Pro 和/或小米 17 Pro 播放后系统播控中心出现，四槽为收藏、上一首、播放/暂停、下一首且可用，`dumpsys media_session`/通知/前台服务证据正常 |

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
- Branch: `main` + lane branch
- Release Tag: pending
- Android APK: pending
- Frozen At: pending
- Feature Count: 2

| Request | 功能 | Owner | Work Branch | 状态 | Commit | Release |
| --- | --- | --- | --- | --- | --- | --- |
| AM-20260624-002 | 播放状态持久化，优先开工 | android | `lane/android` | assigned | pending | 1.0.1 |
| AM-20260624-001 | 歌词/封面稳定加载 pipeline，第二优先级 | android | `lane/android` | assigned | pending | 1.0.1 |
