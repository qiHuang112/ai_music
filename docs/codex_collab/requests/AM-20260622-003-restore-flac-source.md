# AM-20260622-003 恢复 FLAC 资源源

- Request: AM-20260622-003
- Owner lane: android
- Architect lane: architect
- Product lane: product
- Status: changes_requested
- Target Version: 1.0.0
- Base Branch: release/1.0.0
- Work Branch: feature/1.0.0/AM-20260622-003-restore-flac-source
- Worktree Path: /Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003
- Merge Branch: release/1.0.0
- Created: 2026-06-22
- Updated: 2026-06-23

## 背景

产品要求在 Android 播控 AM-20260622-002 收敛后，把此前下线的 `flac.music.hi.cn` 资源源恢复到 AI Music。当前布谷歪歪链路不能被破坏。

## 验收口径

- 设置页恢复 `Auto`、`BuguYY`、`FLAC` 三种资源源入口。
- `BuguYY` 单源模式只走布谷歪歪，不受 FLAC 异常影响。
- `FLAC` 单源模式走现有 `FlacResolver`、`ChallengeClient`、`MusicDataSource.flac` 链路。
- `Auto` 模式必须同时搜索 BuguYY 和 FLAC 两个源；不能只在 BuguYY 无结果时才 fallback FLAC。
- `Auto` 模式设置页文案必须是双源并搜口径，不能继续写“先搜布谷歪歪，没有结果或失败时再搜 FLAC”。
- 搜索结果左侧来源标记必须清楚：BuguYY 显示“布谷”，FLAC 显示 `FLAC`；不能把 BuguYY 简写成“YY”。
- 搜索结果副标题不能再重复显示搜索源名称，来源只放左侧标记；副标题保留歌手、专辑、平台、音质、时长等有区分度的信息。
- 下载和 resolve 按候选真实 `source` 分派，不能把 `auto` 候选传入 resolve。
- FLAC 源歌曲必须尽量补齐真实封面和歌词；如果源站确实没有封面或歌词，需要有明确降级和日志说明，不能静默变成“无封面/无歌词”体验。
- FLAC 下载、resolve 和历史缓存刷新都必须能补歌词；历史缓存不能因为已有音频文件就跳过歌词刷新。
- 播放页出现“暂无歌词”时，需要自动尝试恢复歌词，并提供“重新获取歌词”按钮；手动重试必须绕过 miss TTL，不能重新下载音频。
- 核心真机验收用例必须输入中文 `黑夜传说`，用于验证布谷歪歪无结果时 FLAC 能返回并展示。
- 日志摘要至少说明当前 source 设置、搜索关键词、BuguYY 结果数量、FLAC 结果数量、最终候选来源展示、封面/歌词解析状态、下载/播放是否成功或失败原因。

## 设备边界

- 小米 10 Pro 或其它明确分配的设备用于 android lane 开发自测。
- 小米 17 Pro 只用于 product lane / 主管验收，未经 product lane 明确许可不能安装或自测。

## Review 要求

- 不能只看 Dart 单测；需要提供 ADB 驱动搜索 `黑夜传说` 的真机或模拟器证据。
- 需要把 ADB 模拟操作和自测流程沉淀到 `docs/codex_collab/knowledge/android/`。
- 本任务提交和 AM-20260622-002 必须拆开，不能混入彼此改动。

## Review 结果

2026-06-23 架构师复审 accepted。实现恢复 `Auto`、`BuguYY`、`FLAC` 三源入口，设置存储真实保存/读取 `MusicDataSource`，默认 `Auto`；`Auto` 仍按旧脚本语义先查 BuguYY，空或失败后 fallback FLAC；候选副标题展示真实来源，resolve/download 仍按候选具体 `source` 分派。`dart:developer` resolver 日志只记录 query、source、count 和 candidate source，适合作为开发/验收日志；`HttpMusicResolverClient` 的 3 次瞬时重试限定在 `TimeoutException`、`SocketException`、`HandshakeException`、`HttpException`，用于抵御 FLAC 站点偶发 handshake/socket/timeout 抖动，未改变 HTTP 状态码处理语义。android lane 已提供小米 10 Pro 真机证据：`黑夜传说` 在 Auto 下 BuguYY count=0 后 fallback FLAC count=40，候选、下载缓存和播放 media session 均显示 FLAC/黑夜传说链路成功，且未使用小米 17 Pro。

本地复核：架构师运行 `flutter test test/resolver_http_client_test.dart test/music_settings_test.dart test/music_resolver_test.dart test/widget_test.dart` 通过，`git diff --check` 通过。提交前请只 stage AM-003 相关业务、测试、任务单和 Android 知识库文件；不要混入其它 worktree 或主目录改动。

2026-06-23 产品复核新增验收点后，上一条 accepted 结论撤回，状态改为 changes_requested。AM-003 可以作为 1.0.0 阶段性版本继续推进，但 accepted 前必须补齐两个必修项：第一，`Auto` 不再是 BuguYY 空或失败才 fallback FLAC，而是同时搜索 BuguYY 和 FLAC 两个源，并在结果中保留真实来源；第二，解决 FLAC 源歌曲没有封面和歌词的问题，至少要做到能从 FLAC 搜索/解析结果、源站返回或可复用接口中提取封面与歌词，缺失时有明确降级和日志。android lane 修复后需要重新提供 `黑夜传说` 真机证据，日志中必须能看到 BuguYY 和 FLAC 都参与搜索，以及候选/下载/播放后的封面和歌词状态。

2026-06-23 本轮 android lane 回改方向：`Auto` 改为并发搜索 BuguYY 与 FLAC，单源失败不会吞掉另一源的可用结果，最终按候选评分合并并保留真实 `source`；FLAC 候选映射补充识别 `pic_url`、`cover_url`、`album_pic` 等封面字段，resolve 阶段也会优先使用 `getUrl` 返回的封面字段；歌词解析扩展到 `lyrics`、`lyricText`、`lrcContent`、`content` 等字段，下载完成后主动触发 metadata 管线，优先写入源站歌词和旁路 `.lrc`，再由已有 BuguYY/LRC API 兜底。自测文档已更新为双源并搜口径，后续真机日志需要覆盖 `黑夜传说` 和一个双源都有结果的关键词。

2026-06-23 小米 10 Pro 开发机复验：debug 包安装到 `192.168.31.76:41325` 后，使用系统输入法候选实际输入中文 `黑夜传说`。logcat 记录：`search query="黑夜传说" source=auto`、`auto buguyy count=0`、`auto flac count=40`、`auto merged buguyy=0 flac=40 count=40`、`candidateSources=flac`；UI 列表展示 FLAC / kuwo 候选，第一条旧缓存可直接播放。再输入中文 `晴天`，logcat 记录：`auto buguyy count=30`、`auto flac count=35`、`auto merged count=65`、`candidateSources=flac,buguyy`；UI 顶部展示 FLAC 候选，继续滚动后可见 BuguYY 候选，来源标识清楚。小米 10 Pro 上旧版 FLAC《黑夜传说》缓存索引原本 `coverUrl` 为空、metadata 为空；本轮补充了已缓存候选播放前的轻量 resolve 刷新，若搜索候选已带封面而旧缓存缺封面，会只更新缓存索引和 metadata，不重新下载音频。

2026-06-23 架构师复审 changes_requested。Auto 双源并搜、单源失败降级、真实来源展示和 FLAC 字段扩展方向通过；本地运行 `flutter test test/music_resolver_test.dart test/music_controller_test.dart test/resolver_http_client_test.dart test/music_settings_test.dart test/widget_test.dart` 通过。但旧缓存 metadata 刷新条件过窄：当前只在“旧缓存无封面且搜索候选自带封面”时 resolve，因此如果搜索候选没封面但 `getUrl` 能返回封面，或旧缓存已有封面但缺歌词，就不会进入新解析链路，仍可能留下产品反馈的“FLAC 无封面/无歌词”体验。android lane 需要把刷新条件改为“缓存缺封面或缺歌词时都允许轻量 resolve”，并补测试覆盖：候选无封面但 `getUrl` 返回封面、旧缓存已有封面但无歌词时 resolve 后补歌词；仍不得重新下载音频。

2026-06-23 产品补充最终 review gate。AM-003 下次复审必须同时检查 UI 和播放页体验：Auto 设置文案必须改为双源并搜；搜索结果左侧来源标记中 BuguYY 显示“布谷”、FLAC 显示 `FLAC`；副标题不能再显示搜索源名称；FLAC 下载、resolve、历史缓存刷新必须能补歌词；播放页“暂无歌词”需要自动尝试恢复并提供“重新获取歌词”按钮，手动重试绕过 miss TTL 且不重新下载音频。accepted 后进入 1.0.0 阶段版本流程，但推送 release/main/tag 和构建发布包前必须先同步 product 确认。

2026-06-23 架构师复审仍为 changes_requested。Auto 双源并搜、来源标记、Auto 文案、副标题移除 source、播放页“重新获取歌词”和手动绕过 miss TTL 方向均已覆盖；本地运行 `flutter test test/music_controller_test.dart test/music_resolver_test.dart test/player_page_test.dart test/widget_test.dart test/resolver_http_client_test.dart` 通过，`git diff --check` 通过。但上轮明确要求的旧缓存封面边界仍未闭合：`_refreshCachedCandidateMetadata()` 仍要求搜索候选自带封面才会为缺封面的缓存触发 resolve，因此“搜索候选无封面但 `getUrl`/resolve 返回封面”的历史缓存仍不会补封面。android lane 需要去掉这个候选封面前置条件，只要缓存缺封面或缺歌词就允许轻量 resolve，并补测试覆盖“候选无封面但 resolve 返回封面，缓存索引被更新，且不重新下载音频”。
