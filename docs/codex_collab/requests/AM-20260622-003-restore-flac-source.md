# AM-20260622-003 恢复 FLAC 资源源

- Request: AM-20260622-003
- Owner lane: android
- Architect lane: architect
- Product lane: product
- Status: assigned
- Target Version: 1.0.0
- Base Branch: release/1.0.0
- Work Branch: feature/1.0.0/AM-20260622-003-restore-flac-source
- Worktree Path: /Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003
- Merge Branch: release/1.0.0
- Created: 2026-06-22
- Updated: 2026-06-22

## 背景

产品要求在 AM-20260622-002 闭环后，把此前因服务不可用而下线的 `flac.music.hi.cn` 资源源重新加入 AI Music 资源库。当前线上主要使用布谷歪歪，本任务不能破坏布谷歪歪搜索、解析和下载路径。

## 验收口径

- 设置页恢复 `Auto`、`BuguYY`、`FLAC` 三种资源源入口。
- `BuguYY` 单源模式只走布谷歪歪，不被 FLAC 异常拖慢或拖垮。
- `FLAC` 单源模式能走现有 `FlacResolver` / `ChallengeClient` / `MusicDataSource.flac` 链路。
- `Auto` 模式沿用旧语义：先尝试布谷歪歪；布谷歪歪为空或失败时再 fallback 到 FLAC。
- 搜索结果要清楚展示候选真实来源，避免用户分不清来自 BuguYY 还是 FLAC。
- 下载和 resolve 必须继续按候选真实 `source` 分派，不把 `auto` 候选传入 resolve。
- 失败降级、设置持久化和历史配置读取需要有测试覆盖。
- 核心真机验收用例：搜索《黑夜传说》。该歌布谷YY没有，`flac.music.hi.cn` 有；多源搜索必须能在布谷YY无结果时展示 FLAC 源结果。
- 日志要能证明请求过程和结果来源，包括 BuguYY 无结果、FLAC fallback 被触发、最终候选标记为 FLAC。
- 下载/播放链路不能影响现有 BuguYY 搜索、解析、下载和播放。

## 当前状态

2026-06-22 产品补充核心验收用例：搜索《黑夜传说》。android lane 后续实现和 review_request 必须提供真机或模拟器上的 ADB 自测流程与日志摘要，证明 Auto 模式在 BuguYY 无结果时能展示 FLAC 结果。

2026-06-22 版本/worktree 规则落地后，本任务分配到独立 worktree：`/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003`，分支为 `feature/1.0.0/AM-20260622-003-restore-flac-source`。android lane 后续不得在主目录 `/Users/huangqi/AIHome/ai_music` 继续开发 AM-003。

## Review 要求

- review 时不能只看 Dart 单测；必须看 ADB 驱动搜索《黑夜传说》的真机或模拟器证据。
- 日志摘要至少说明：当前 source 设置、搜索关键词、BuguYY 结果数量、FLAC fallback 是否触发、最终候选来源展示、下载/播放是否成功或失败原因。
- android lane 需要把 ADB 自测方法沉淀到 `docs/codex_collab/knowledge/android/`，方便后续新成员复用。
- AM-20260622-002 的播放体验 blocker 仍需优先闭环；如果两个任务并行，提交和推送必须拆开，不能混入彼此改动。
- 设备使用必须遵守分层规则：小米 10 Pro 或其它开发测试设备用于 android lane 自测；小米 17 Pro 只用于 product lane / 主管验收，未经 product lane 明确许可不能安装或自测。
