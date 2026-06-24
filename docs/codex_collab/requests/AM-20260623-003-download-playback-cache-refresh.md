# AM-20260623-003 HarmonyOS 下载后播放与串歌排查

Status: in_progress_fix
Owner Lane: ohos
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.1
Created: 2026-06-23
Updated: 2026-06-24

## 当前阻塞

产品澄清：多首下载后逐个点击播放，实际播放歌曲和点击行对不上的 P1 发生在 HarmonyOS，Android 没有问题。此前把该 P1 派给 android 主责属于定责错误，现改为 ohos 主责。

AM-20260623-003 当前不得 accepted，不得合入 `release/main`，不得进入 tag/release 构建。最新证据显示本轮 P1 可优先按 HarmonyOS vendored plugin 修复：native 侧沿用了旧 `MediaSource` 队列，`loadAssent()` index 越界时又没有把 load failure 可靠回给 Dart，导致 UI/AVSession metadata 已更新但 AVPlayer 未加载目标 source。

## 当前执行指令

ohos lane 现在进入修复阶段，不再停留在定位阶段。直接在 `/Users/huangqi/AIHome/projects/ai_music_ohos` 的 `lane/ohos` 分支处理：

1. `third_party/just_audio_harmonyos/ohos/src/main/ets/AudioPlayer.ets`
   - full `load` 前清空或强制刷新 `mediaSources`。
   - 目标是避免 `AudioPlayer.getAudioSource()` 复用旧 root/children，确保 native `songList` 与 just_audio 本次 load 的队列一致。
2. `third_party/just_audio_harmonyos/ohos/src/main/ets/MediaAvPlayer.ets`
   - `loadAssent()` 遇到 index 越界、source 不存在或 load 失败时，通过现有错误通道可靠回传 Dart。
   - 不能只 sync error 后静默 return，不能让 UI/AVSession metadata 看起来已经切歌成功但 AVPlayer 停在旧 source、stopped 或 released。

修复后必须重新构建 signed HAP 并安装到 `192.168.31.53:10178`，复测产品复现路径：先播放 3 首自建歌单 `qi`，再搜索/下载/逐个播放多首 `yellow`，至少覆盖 3 首不同歌曲。review_request 需要附上构建命令、安装结果、截图/metadata/hilog/AudioPolicyService 关键摘要。

## HarmonyOS 必修验收

- 在鸿蒙测试机上覆盖至少 3 首不同歌曲：下载完成后逐个点击播放，点击行、Dart `mediaItem`、AVSession metadata、ArkTS 当前 source/path/fd、AVPlayer 实际播放源必须完全一致。
- 必须提供鸿蒙测试机复现/修复证据，包括点击前后 Dart/ArkTS 日志、`hidumper -s AVSessionService` metadata、AVPlayer source/path/fd/index 关键字段。
- 重点排查 `just_audio_harmonyos` 本地 fd/data source、AVPlayer source、预加载播放器升格、AVSession metadata 与 Dart mediaItem 是否错位。
- 必修平台修复：`AudioPlayer.getAudioSource()` / full `load` 前必须清空或强制刷新 `mediaSources`，避免复用旧 root/children 和旧 native `songList`。
- 必修平台修复：`MediaAvPlayer.loadAssent()` 遇到 index 越界、source 不存在或 load 失败时，必须把失败可靠回传给 Dart，不能只 sync error 后静默 return，不能让 UI/AVSession metadata 看起来已经切歌成功。
- 如果修复在 `third_party/just_audio_harmonyos` 或 AVPlayer 预加载链路，需补最小 ArkTS/HarmonyOS 验证日志，并沉淀到 `docs/codex_collab/knowledge/ohos/`。
- 验收前仍需确认 `AudioPolicyService -a '-v'` 中 MUSIC 音量非 0 且未 mute，避免设备静音误判。

## 排查重点

- `MediaAvPlayer.ets` / `AudioPlayer.ets` 内部 `musicIndex`、assetId、file path、fd、AVPlayer state 回调是否对应同一首歌。
- 本地文件 `file://` / sandbox path 到 AVPlayer source 的转换是否复用旧 source。
- 预加载播放器升格时 `currentPlayer` / `nextPlayer`、source、index、metadata 是否同步切换。
- AVSession metadata 是否只更新了标题/封面，但 AVPlayer 实际 source 仍停留在上一首。
- Dart `MediaItem` 与 ArkTS 播放源不一致时，优先记录两端 id/title/artist/path/source 对照日志。

## Android 协助边界

- Android 公共 Dart 队列/index 修复先不作为本轮 P1 主线；除非 ohos 修复 `mediaSources` 刷新和 load failure 回传后仍能复现，才再拉 android 协助。
- Android 已有公共 Dart 防串歌修复可作为后续安全加固：候选缓存命中更严格、cacheId 包含 artist/title、搜索结果播放按可见 candidates 构建队列，并补至少 3 首不同歌曲逐个播放不串歌测试。
- Android 仍负责 AM-20260623-003 的 P2：下载按钮即时出现、搜索结果当前播放态、已有封面不重复拉取。

## 工程与分支

- ohos lane 工程：`/Users/huangqi/AIHome/projects/ai_music_ohos`
- ohos 分支：`lane/ohos`
- ohos 可写范围：`third_party/just_audio_harmonyos/**`、`ohos/**`、`docs/codex_collab/knowledge/ohos/**`；如需改公共 Dart，先回报架构师确认。
- android lane 工程：`/Users/huangqi/AIHome/projects/ai_music_android`
- android 分支：`lane/android`
- android 可写范围：公共 Dart 播放/缓存/metadata/UI 测试相关文件；不改 `ohos/**` 和 `third_party/just_audio_harmonyos/**`。
- integration 工程只做架构师合入和出包，不在 integration 里直接修业务。

## 消息记录

- 2026-06-24 type=correction lane=product status=blocker summary=产品澄清串歌发生在 HarmonyOS，Android 没有问题；串歌 P1 主 owner 改为 ohos lane，android 只保留协助角色。
- 2026-06-24 type=blocker lane=ohos status=blocked summary=ohos lane 在 `192.168.31.53:10178` 复现核心链路：下载 `yellow` 搜索结果第 2/3/4 条后，点击第 3 条 `Yellow / 酷玩乐队`，Flutter UI 和 AVSession metadata 都显示酷玩乐队，但原生没有进入 `prepared/playing/play succeeded`，`AudioPolicyService` 显示 AudioRenderer `rendererState=5`，日志出现 `MediaAvPlayer current musicIndex 2`，对应 `loadAssent()` index 越界分支。证据在 `/tmp/ai_music_ohos_am003串歌/search_yellow_track3_kuwan/`。
- 2026-06-24 type=status lane=ohos status=in_progress summary=进一步定位为 HarmonyOS vendored plugin 缓存旧 `MediaSource` 队列：先播放 3 首自建歌单 `qi`，再搜索下载/播放多首 `yellow` 后，native duration 对上旧队列里的 `浮夸`/`Midnight City`；第 3/4 条进入 `loadAssent()` index 越界。修复优先放在 `AudioPlayer.ets` full `load` 清空/刷新 `mediaSources`，以及 `MediaAvPlayer.loadAssent()` 越界可靠回传 Dart。
