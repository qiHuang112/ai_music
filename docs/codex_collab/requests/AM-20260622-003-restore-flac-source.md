# AM-20260622-003 恢复 FLAC 资源源

- Request: AM-20260622-003
- Owner lane: android
- Architect lane: architect
- Product lane: product
- Status: accepted
- Target Version: 1.0.0
- Base Branch: main
- Work Branch: lane/integration
- Worktree Path: /Users/huangqi/AIHome/projects/ai_music_integration
- Merge Branch: main
- Created: 2026-06-22
- Updated: 2026-06-24

## 背景

产品要求在 AM-20260622-002 闭环后，把此前因服务不可用而下线的 `flac.music.hi.cn` 资源源重新加入 AI Music 资源库。当前线上主要使用布谷歪歪，本任务不能破坏布谷歪歪搜索、解析和下载路径。

## 验收口径

- 设置页恢复 `Auto`、`BuguYY`、`FLAC` 三种资源源入口。
- `BuguYY` 单源模式只走布谷歪歪，不被 FLAC 异常拖慢或拖垮。
- `FLAC` 单源模式能走现有 `FlacResolver` / `ChallengeClient` / `MusicDataSource.flac` 链路。
- `Auto` 模式为 BuguYY 和 FLAC 双源并搜：先返回的一路先展示，另一路返回后稳定合并，不能空白等待两个源都返回。
- 搜索结果左侧展示候选真实来源：BuguYY 显示“布谷”，FLAC 显示 `FLAC`；副标题不重复来源，不展示平台字段。
- 副标题收敛为作者、专辑、最多一组格式与大小；FLAC 来源如果左侧已有 `FLAC` 标记，副标题不再重复 `FLAC` 文案。
- FLAC 候选和 resolve 需要解析封面和歌词字段；下载/历史缓存刷新时可补歌词和封面，但不能重新下载音频。
- 播放页“暂无歌词”时自动尝试恢复一次，并提供“重新获取歌词”入口；手动重试绕过 miss TTL。
- 暂停状态下，用户点击搜索结果播放、上一首、下一首或队列跳转等明确播放动作，新歌应自动开始播放。
- 下载完成后搜索结果播放按钮应立即出现，metadata 补全和完整缓存刷新不得阻塞 UI。
- 已有封面的缓存歌曲播放时复用现有 metadata，不重复走网络封面 provider。
- 搜索结果中当前播放的缓存歌曲应有明确播放态反馈，不能让用户误判没有播放。
- 下载和 resolve 必须继续按候选真实 `source` 分派，不把 `auto` 候选传入 resolve。
- 下载和 resolve 必须继续按候选真实 `source` 分派，不把 `auto` 候选传入 resolve。
- 失败降级、设置持久化和历史配置读取需要有测试覆盖。
- 核心真机验收用例：搜索《黑夜传说》。该歌布谷YY没有，`flac.music.hi.cn` 有；多源搜索必须能在布谷YY无结果时展示 FLAC 源结果。
- 日志要能证明请求过程和结果来源，包括 BuguYY 无结果、FLAC fallback 被触发、最终候选标记为 FLAC。
- 下载/播放链路不能影响现有 BuguYY 搜索、解析、下载和播放。

## 当前状态

2026-06-22 产品补充核心验收用例：搜索《黑夜传说》。android lane 后续实现和 review_request 必须提供真机或模拟器上的 ADB 自测流程与日志摘要，证明 Auto 模式在 BuguYY 无结果时能展示 FLAC 结果。

2026-06-22 版本/worktree 规则落地后，本任务分配到独立 worktree：`/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003`，分支为 `feature/1.0.0/AM-20260622-003-restore-flac-source`。android lane 后续不得在主目录 `/Users/huangqi/AIHome/ai_music` 继续开发 AM-003。

2026-06-24 产品确认小米 17 Pro 上的 latest integration Android 包体验 OK，允许合并。架构师复审后将 integration staged 业务改动整理为提交 `71a51bd` 并合入 `main`。本提交覆盖 Auto 双源渐进搜索、搜索展示收敛、FLAC 歌词/封面字段解析、历史缓存 metadata 恢复、播放页重试入口、下载后缓存状态即时刷新、已有封面不重复拉取和暂停切歌自动播放。验证通过 `flutter analyze --no-pub`、`flutter test --no-pub` 121 项；基于 integration 验收包安装到小米 17 Pro `192.168.31.190:45075`，产品反馈 OK。

## Review 要求

- review 时不能只看 Dart 单测；必须看 ADB 驱动搜索《黑夜传说》的真机或模拟器证据。
- 日志摘要至少说明：当前 source 设置、搜索关键词、BuguYY 结果数量、FLAC fallback 是否触发、最终候选来源展示、下载/播放是否成功或失败原因。
- android lane 需要把 ADB 自测方法沉淀到 `docs/codex_collab/knowledge/android/`，方便后续新成员复用。
- AM-20260622-002 的播放体验 blocker 仍需优先闭环；如果两个任务并行，提交和推送必须拆开，不能混入彼此改动。
- 设备使用必须遵守分层规则：小米 10 Pro 或其它开发测试设备用于 android lane 自测；小米 17 Pro 只用于 product lane / 主管验收，未经 product lane 明确许可不能安装或自测。
