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
- 2026-06-24 产品反馈该 Android release 包播放后系统播控中心没有出现，`v1.0.0` 发布状态降为 blocked。随后通过 `46ce92d` / `v1.0.0-hotfix.1` 修复 release 资源裁剪导致的 CustomAction 图标缺失问题，小米 10 Pro 开发验证和小米 17 Pro 产品验收均通过。

## 1.0.0 Blocker

| Request | 问题 | Owner | 状态 | 验收 |
| --- | --- | --- | --- | --- |
| AM-20260624-ANDROID-RELEASE-MEDIA-CONTROL | Android release 包播放后系统播控中心消失 | android | accepted_pushed_verified | `46ce92d` / `v1.0.0-hotfix.1` 已推送；小米 10 Pro 和小米 17 Pro 验证通过，四槽为收藏、上一首、播放/暂停、下一首且可用 |

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
- Feature Count: 3

| Request | 功能 | Owner | Work Branch | 状态 | Commit | Release |
| --- | --- | --- | --- | --- | --- | --- |
| AM-20260624-002 | 播放状态持久化，ohos 并行实现，Android 协助复核 | ohos | `lane/ohos` | merged | `98d64a1`/`473ac61`/`9cbde92` | 1.0.1 |
| AM-20260624-001 | 歌词/封面稳定加载 pipeline，Android 主责，iOS 验证支持 | android | `feature/1.0.1/AM-20260624-001-metadata-pipeline` | assigned | pending | 1.0.1 |
| AM-20260624-003 | 底部播放状态栏和播放详情页左右滑动切歌 | android | `feature/1.0.1/AM-20260624-003-swipe-to-skip` | assigned | pending | 1.0.1 |

## 并行队列

- AM-20260624-ANDROID-RELEASE-MEDIA-CONTROL：1.0.0 blocker 已通过 `46ce92d` / `v1.0.0-hotfix.1` 修复并完成产品验收；Android lane 只需做归属复核和知识沉淀检查，不阻塞 1.0.1 开工。
- AM-20260624-002：ohos lane 在 `/Users/huangqi/AIHome/projects/ai_music_ohos` / `lane/ohos` 开发公共 Dart 播放状态持久化；禁止触碰 `android/`、Android release 播控热修文件和 metadata pipeline。
- AM-20260624-001：android lane 在 `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260624-001` / `feature/1.0.1/AM-20260624-001-metadata-pipeline` 开发 metadata pipeline；禁止混入旧 `/Users/huangqi/AIHome/projects/ai_music_android` 脏现场和 AM-002 播放状态持久化。
- AM-20260624-003：android lane 后续在独立 worktree/branch 开发底部播放状态栏和播放详情页滑动切歌；禁止混入 AM-001 metadata pipeline、AM-002 播放状态持久化或 Android release 播控 hotfix。
- iOS lane：等待 Android metadata pipeline review accepted 后做 provider/ATS/file URI/锁屏封面等平台风险验证；未收到 handoff 前不改公共 Dart。
- UI lane：做页面现状巡检和 UI 建议，不进入自动 review，不直接改业务代码。
