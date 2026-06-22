# AM-20260621-003 鸿蒙播控中心修复

Status: pushed
Owner Lane: ohos
Source Thread: 当前 Codex 对话
Created: 2026-06-21
Updated: 2026-06-22

## 目标
- 修复 AI Music HarmonyOS 播控中心链路已接通但体验不可用的问题，让系统播控中心能正确展示并控制当前歌曲。

## 范围
- 包含：HarmonyOS 宿主、ArkTS、AVSession、AVPlayer 状态同步、鸿蒙音频插件、HAP 构建验证、鸿蒙知识沉淀。
- 不包含：公共 Dart 播放业务、Android、iOS，除非排查证明 Flutter 公共层传参缺失。

## 验收标准
- 暂停后能从鸿蒙播控中心重新启动播放。
- 播控中心显示当前歌曲封面。
- 播控中心显示当前歌名和歌唱者。
- 播控中心的单曲循环、列表播放等播放模式状态，必须与应用内当前状态一致；不能出现应用里已切换但系统播控仍显示旧状态。
- 播控中心的点赞/收藏状态必须与应用内收藏状态一致；系统播控里切换点赞后，应用内收藏状态也要同步，反向也一样。
- 播控中心封面不能写死为应用 icon；系统展示用图必须按当前播放歌曲的真实封面更新。当前歌曲没有封面时，才允许使用明确的默认降级图。
- 播控中心的切歌模式与点赞能力有明确实现或降级策略；如果 HarmonyOS API 不支持某项能力，要在任务记录和知识库里写明原因。
- 修复后鸿蒙 lane 主动请求架构师 review，默认走 `ohos -> architect review -> ohos` 闭环。

## 消息记录
- 2026-06-21 type=task lane=ohos summary=用户反馈鸿蒙播控中心链路已实现但存在暂停后无法恢复、缺封面、缺歌名/歌手、切歌模式和点赞未实现等问题。
- 2026-06-21 type=task lane=architect summary=请求架构师调度并 review 鸿蒙播控中心修复；本任务不默认分发给 Android 或 iOS。
- 2026-06-21 type=task lane=architect summary=架构师确认本任务默认只分发给 ohos lane；要求先读 `harmonyos-development` skill 和鸿蒙知识库，按暂停恢复、metadata/封面、命令能力边界、状态同步四条线逐项排查。
- 2026-06-21 type=review_result lane=ohos status=changes_requested summary=`4664d87` 方向正确但仍有 4 个 P2，需要修复 metadata 异步错配、系统播放模式不回写应用状态、点赞状态不闭环、固定应用 icon 不满足真实封面要求后重提 review。
- 2026-06-21 type=task lane=ohos summary=用户追加反馈：单曲循环/列表播放状态、点赞/收藏状态与应用内不一致；封面不能写死成 icon，系统播控展示图要按当前播放音乐封面动态更新。
- 2026-06-21 type=task lane=architect summary=请求架构师把新增状态一致性和动态封面要求纳入 AM-20260621-003 review；仍默认只回鸿蒙 lane，不通知 Android/iOS，除非有公共 Dart 证据。
- 2026-06-21 type=review_request lane=ohos summary=ohos lane 提交 `8f0e779`：移除后台长时任务残留；metadata 增加曲目快照校验；封面优先抽取当前音频内嵌图并失败才降级默认图；未接公共 Dart 回写前不注册系统 `setLoopMode`/`toggleFavorite`。
- 2026-06-21 type=review_result lane=ohos status=accepted summary=架构师 review `8f0e779` 通过；此前 4 个 P2 均已闭合或降级为不展示系统入口。当前只涉及鸿蒙，不通知 Android/iOS。
- 2026-06-21 type=demo_ready lane=product status=ready_to_try summary=鸿蒙播控中心边界收紧版可体验：播放中心仅展示能真实闭环的 play/pause/上一首/下一首/seek 和 App -> AVSession 播放模式状态；封面优先显示音频内嵌封面，无封面才默认图；系统 loop/favorite 按钮暂不展示。体验包已由 ohos lane 安装到 `192.168.31.53:10178` 并启动。
- 2026-06-21 type=review_result lane=ohos status=changes_requested summary=产品验收未通过：暂停后系统播控图标状态未变化且无法从系统播控恢复播放；点赞按钮此前可用但当前不可点击；左侧播放模式切换按钮当前不可点击；封面仍未按当前播放音乐替换。当前不能算产品可验收版本。
- 2026-06-21 type=task lane=architect status=changes_requested summary=请求架构师重新审视 `8f0e779` 的 accepted 边界：如果系统 loop/favorite 按钮无法闭环，应隐藏或禁用到不展示，不应保留不可点击坏入口；如果产品要求必须可点，需要判断是否 handoff 公共 Dart/插件协议。
- 2026-06-21 type=review_request lane=ohos status=ready_for_review summary=ohos lane 继续修复产品验收失败点：play/pause 先发布目标态并驱动 AVPlayer；移除 `loopMode/isFavorite` 发布和系统回调；新增 HarmonyOS-only 私有 MethodChannel 同步 Dart `MediaItem.id/title/artist/artUri/duration` 给 AVSession metadata；封面优先使用 `artUri`，失败再抽取内嵌封面或默认图。
- 2026-06-21 type=review_result lane=ohos status=accepted summary=架构师 review 通过：HarmonyOS-only Dart bridge 有平台保护，未改变 Android/iOS；AVSession play/pause 目标态同步方向正确；`AVMetadata.mediaImage` 当前 SDK 支持 `PixelMap|string`；隐藏 loop/favorite 能力符合不能留下不可点击入口的验收边界。
- 2026-06-21 type=handoff lane=android status=assigned summary=当前 main 的公共 Flutter UI 使用 `ReorderableListView.builder(onReorderItem:)`，`flutter_ohos` 不支持，导致未打临时补丁时 HAP 构建在 FlutterTask 阶段失败；这属于公共 Dart/跨端兼容问题，需要 android lane 在 AM-004 或后续公共 UI 修复里处理。
- 2026-06-21 type=demo_ready lane=product status=ready_to_try_limited summary=架构师 review 已 accepted，可让产品验收鸿蒙播控中心修复；ohos lane 已用临时兼容公共 UI 的方式构建 signed HAP 并安装到 `192.168.31.53:10178`。已知限制：当前 main 未临时补丁时 HAP 构建仍被公共 UI `onReorderItem` 兼容问题挡住，需 android lane 修复后才能从 HEAD 稳定出包。
- 2026-06-21 type=review_result lane=ohos status=changes_requested summary=产品截图验收未通过：封面已经能显示当前歌曲，但系统播控底部按钮仍有问题；中间暂停按钮显示为暂停图标但点击无法暂停，左侧播放模式按钮灰色不亮且不可点击，右侧点赞按钮灰色不亮且不可点击。此前“loop/favorite 不应再露出不可点击坏入口”的 accepted 边界没有满足。
- 2026-06-21 type=task lane=architect status=changes_requested summary=请求架构师重新 review 最新体验包：封面进步可保留，但 AVSession 控制按钮能力未闭环；特别是 center pause 命令、left loop mode、right favorite 的注册/禁用/隐藏策略与产品验收不一致。
- 2026-06-21 type=review_request lane=ohos status=ready_for_review summary=ohos lane 提交 `b106d33`：系统 pause 先同步 `AVPlaybackState.PAUSE` 再 await `AVPlayer.pause()`；恢复发布 `loopMode/isFavorite` 并注册 `setLoopMode/setTargetLoopMode/toggleFavorite`；系统播放模式和收藏命令通过 HarmonyOS-only 私有 MethodChannel 回到 Dart `MusicController`，复用真实播放模式和收藏持久化状态。
- 2026-06-21 type=review_result lane=ohos status=accepted summary=架构师 review `b106d33` 通过：底部三类按钮已从“灰色不可点”改为真实闭环；公共 Dart 改动均由 `isOpenHarmonyPlatform` 和私有 channel 限定在 HarmonyOS；不通知 iOS。提交 trailer 需在推送前从 `Reviewed-by-lane: none` 改为 `Reviewed-by-lane: architect`。
- 2026-06-21 type=demo_ready lane=product status=ready_to_try summary=鸿蒙播控中心按钮闭环版可验收：封面/歌名/歌手继续保留；系统 pause/play、播放模式、点赞按钮均应可见可用并回写 App 状态。signed HAP 已由 ohos lane 安装到 `192.168.31.53:10178`；需要产品手动播放后逐项点 pause/loop/favorite 验证。
- 2026-06-21 type=reference lane=ohos status=noted summary=按产品要求已定位付华丽播控中心参考实现：`/Users/huangqi/AIProjects/notes-ai/work/harmony/content/鸿蒙播控中心最简接入逻辑.md`、`/Users/huangqi/AIProjects/eastmoney-harmony/features/launcher/src/main/ets/common/utils/AvSessionController.ets`，重点参考提交包括 `b89c0dd035`、`0b587d1997`、`369f5f6eb1`，以及后续一批播放/暂停状态修复提交。
- 2026-06-21 type=demo_ready lane=product status=ready_to_try summary=ohos lane 提交最终可验版本 `b66594f` 并安装到无线 HDC 设备 `192.168.31.53:10178`：系统 pause 走 AVSession 回调并 await `AVPlayer.pause()`；播放模式发布 `loopMode` 并回写 App；点赞发布 `isFavorite` 并回写 App；封面、标题、歌手继续使用当前 Dart `MediaItem` 同步到 AVSession。产品仍需真机手点 pause/play、播放模式、点赞、封面随歌曲变化后再最终验收。
- 2026-06-21 type=product_feedback lane=ohos status=changes_requested summary=产品复测 `b66594f` 未通过：点击系统播控 pause 后歌曲实际暂停，但播控中心仍显示正在播放状态，导致后续无法从系统播控恢复播放；左侧播放模式按钮点击也没有生效。ohos lane 必须对照付华丽/符华利在 `AIProjects/eastmoney-harmony` 的 AVSession 实现重新研究状态闭环。
- 2026-06-21 type=review_request lane=ohos status=review summary=ohos lane 提交 `52bee7d`：系统 play/pause 回到 HarmonyOS-only Dart `MusicAudioHandler.play()/pause()`；暂停态 `AVPlaybackState.speed` 保持当前倍率；系统 `setLoopMode` 点击按 AI Music 顺序推进；移除当前 SDK 无效的 `setTargetLoopMode` 注册。已构建 signed HAP、无线 HDC 安装，并提供 `show_controller_info` 中 pause/play/loop/favorite 后关键字段。
- 2026-06-21 type=review_result lane=ohos status=accepted summary=架构师复审 `52bee7d` 通过：前一版 pause 后系统仍显示 playing 的根因已通过业务入口闭环和 paused speed 修正覆盖；播放模式点击不生效已改为按应用按钮语义推进；未发现需要 Android/iOS 处理的问题。commit trailer 已修正为 `Reviewed-by-lane: architect`。
- 2026-06-21 type=demo_ready lane=product status=ready_to_try summary=`52bee7d` 可进入产品真机复测：请播放歌曲后在系统播控中心逐项验证 pause/play 状态、播放模式切换、点赞收藏、封面/标题/歌手。ohos lane 已安装到 `192.168.31.53:10178`。
- 2026-06-22 type=status lane=ohos status=ready_to_try summary=ohos lane 将上一版 accepted 提交整理为最终 SHA `52bee7d8a8700b28310dfc856fc0cbf1e01a3716`，代码内容与已 review 的鸿蒙播控中心状态闭环版本一致，仅把 commit trailer 修正为 `Reviewed-by-lane: architect`；`git show --stat HEAD` 仍为 4 个鸿蒙相关文件，未混入其它 lane 的 `music_home_page.dart` / `widget_test.dart`。
- 2026-06-22 type=status lane=architect status=pushed summary=产品已确认鸿蒙播控中心功能体验 OK；最终提交 `52bee7d8a8700b28310dfc856fc0cbf1e01a3716` 已推送到远端 `origin/main`，`git ls-remote origin refs/heads/main` 已确认远端 main 指向同一 SHA。AM-003 按 pushed/accepted 归档。

## 架构师调度要求

- ohos lane 开始前必须先读取：
  - `/Users/huangqi/.codex/skills/harmonyos-development/SKILL.md`
  - `docs/codex_collab/knowledge/ohos/README.md`
  - `docs/codex_collab/knowledge/architect/2026-06-21-ohos-avsession-minimal-review.md`
- 禁止再次大范围重写 `MediaAvPlayer` 播放加载链路；每次改动必须围绕一个可验证问题。
- 暂停恢复优先级最高：先确认 `session.on('play')`、`session.on('pause')`、`AVPlayer` paused/prepared 状态、`isPlaying` 标记和 `AVPlaybackState` 是否一致。
- metadata/封面必须分开验证：先让 `title/artist` 稳定显示，再接 `mediaImage`；封面 URI 或 PixelMap 不可靠时必须记录降级策略。
- 封面不能写死为应用 icon：优先使用当前歌曲真实封面更新 AVSession metadata；只有歌曲确实没有封面或解析失败时，才使用默认图，并把降级原因写入知识库。
- 播放模式和点赞状态必须以应用当前状态为准做双向同步：应用内切换后要刷新系统播控状态；系统播控触发后要回写到应用侧状态。不能只改图标展示，不改真实业务状态。
- 切歌模式和点赞属于系统播控能力边界：如果 AVSession API 支持就实现最小映射；如果当前 API/插件无法可靠支持，应禁用或不注册对应命令，并在知识库记录原因。
- 所有修复必须用 `hidumper -s AVSessionService` 和真机手动播放验证，HDC 自动点击只能作为辅助。
- 如果排查发现 Dart `MediaItem`/`AudioSource.tag` 没有传到鸿蒙原生层，再把具体证据交给 architect 判定是否 handoff 给 android；没有证据前不通知 Android/iOS。

## 相关提交
- `4664d87` 补齐鸿蒙播控中心元数据和控制状态：changes_requested。
- `8f0e779` 收紧鸿蒙播控中心状态边界：产品验收后降为 changes_requested。
- `b106d33` 修复鸿蒙播控中心按钮闭环：临时 SHA，后续已整理为最终提交。
- `b66594f` 修复鸿蒙播控中心按钮闭环：产品复测 changes_requested，已安装到 `192.168.31.53:10178`，问题是系统播控状态没有跟随真实暂停态更新，播放模式点击不生效。
- `52bee7d` 修复鸿蒙播控中心状态闭环：架构师 review accepted，产品体验确认 OK，已推送到远端 `origin/main`；由上一版 accepted 提交整理 trailer 后得到，代码内容不变。

## 付华丽参考实现
- 最小接入文档：`/Users/huangqi/AIProjects/notes-ai/work/harmony/content/鸿蒙播控中心最简接入逻辑.md`
- 参考工程：`/Users/huangqi/AIProjects/eastmoney-harmony`
- 核心文件：`features/launcher/src/main/ets/common/utils/AvSessionController.ets`
- 相关文件：`features/launcher/src/main/ets/components/audio/AudioPlayManager.ets`、`features/launcher/src/main/ets/components/audio/AudioPlayer.ets`
- 重点提交：`b89c0dd035` 后台播放与 AVSession 最小链路、`0b587d1997` 播控中心相关修复、`369f5f6eb1` 语音播放 UI 适配，后续 `2026-01-29` 至 `2026-01-30` 多个提交集中处理暂停、恢复、状态错乱和断网后的播放状态问题。
- 可复用经验：系统播控按钮的注册、状态发布和真实播放器动作必须同源闭环；暂不支持的命令不要露出不可点击或点击无效的入口。
- 本轮必须重点对照：
  - `session.on('pause')` 收到系统命令后，是否先驱动真实播放器暂停，再把 `AVPlaybackState.PLAYBACK_STATE_PAUSE` 稳定发布到 AVSession。
  - `AVPlayer` 自身 state change、time update、position timer 或 Dart bridge 回写是否又把暂停态覆盖回 playing。
  - `session.on('play')` 是否能在系统播控仍处于 paused 状态时反向恢复播放器，并同步 `PLAYBACK_STATE_PLAY`。
  - `setLoopMode` / `setTargetLoopMode` 是否真的收到系统回调，播放模式枚举映射是否正确，Dart 回写完成后是否重新发布 AVSession loopMode。
  - 每次宣称 ready 前，必须附 `hidumper -s AVSessionService -a '-show_session_info'` 和 `show_controller_info` 在点击前后的关键字段变化。

## Review 结果
- Reviewer Lane: architect
- Result: accepted
- Android Findings: 不涉及
- iOS Findings: 不涉及
- HarmonyOS Findings:
  - 已闭合：`setAVMetadata()` 现在在异步封面读取前快照 `musicIndex/songItem/avMetadata/lifecycleGeneration`，返回后确认仍是同一曲目再发布，避免快速切歌 metadata 错配。
  - 已闭合：封面不再固定写应用 icon，优先用临时 `AVMetadataExtractor.fetchAlbumCover()` 从当前音频文件抽内嵌封面；独立 fd/extractor 在 finally 中释放，失败才降级默认图。
  - 已闭合：未接公共 Dart 回写前不注册系统 `setLoopMode`，只保留 App -> AVSession 的 loopMode 展示同步，避免系统按钮改变 App 不知道的原生临时模式。
  - 已闭合：未接公共 Dart 收藏/持久化前不注册系统 `toggleFavorite`，避免系统点赞状态和 App 收藏状态不一致。
  - 已闭合：系统 play/pause 回调先向 AVSession 发布目标播放/暂停态，再驱动 `AVPlayer.play()`/`pause()`，能避免按钮图标停在旧状态和暂停后无法恢复播放。
  - 已闭合：新增 `com.qi.ai_music.ohos_media_controls` 私有通道，Dart 侧只在 `isOpenHarmonyPlatform` 下同步当前 `MediaItem`，不会影响 Android/iOS；原生 metadata 优先使用 Dart 的真实 title/artist/artUri/duration。
  - 已确认：当前 DevEco SDK 的 `AVMetadata.mediaImage` 类型为 `image.PixelMap | string`，因此 `artUri` 字符串作为封面来源符合类型定义；解析失败时仍有内嵌封面和默认图降级。
  - 可接受边界：`loopMode/isFavorite` 暂不发布、不注册系统回调，避免系统露出不可回写 App 的按钮。未来如果产品要求系统播控里可点，需要新增公共 Dart 控制接口后另开跨 lane 任务。
  - 最新 P1：产品截图确认中间 pause 图标可见但点击无法暂停。ohos lane 必须让系统 pause/play 与 `AVPlaybackState`、`AVPlayer` 和 `isPlaying/state` 真正一致，不能只提前发布展示态。
  - 最新 P2：产品截图确认左侧播放模式按钮和右侧点赞按钮仍灰色露出且不可点击。验收口径是“可见即可用”：如果保留显示，就必须与应用播放模式/收藏状态闭环；如果暂不能闭环，就必须隐藏或通过 AVSession 能力配置让系统面板不露出，不允许灰色坏入口。
  - 已闭合：`b106d33` 中系统 pause 回调先发布 `AVPlaybackState.PAUSE`，再 await `AVPlayer.pause()` 并同步 `isPlaying/state`，能覆盖中间 pause 点击不生效的问题。
  - 已闭合：`loopMode/isFavorite` 重新发布后同时注册 `setLoopMode/setTargetLoopMode/toggleFavorite`，并通过 HarmonyOS-only 私有 MethodChannel 回到 Dart `MusicController.setPlaybackMode()` / `toggleFavorite()`，不再是原生临时状态。
  - 已闭合：应用内切换播放模式、收藏、切歌和封面 metadata 更新后会把当前控制状态同步回 AVSession，满足系统播控与 App 状态同源。
  - 最新 P1：产品复测 `b66594f` 仍失败。系统 pause 点击后音频实际暂停，但 AVSession/系统播控仍显示 playing，导致无法再从系统播控恢复播放。下一版必须证明 pause 前后 `AVPlayer.state/isPlaying/state` 与 `AVPlaybackState.state` 都稳定变为 PAUSE，且没有后续 timeUpdate/stateChange/Dart bridge 把状态覆盖回 PLAY。
  - 最新 P2：左侧播放模式按钮点击没有生效。下一版必须证明 `setLoopMode` 或 `setTargetLoopMode` 回调真实触发、枚举映射正确、Dart `MusicController.setPlaybackMode()` 成功执行，并且回写后的 AVSession `loopMode` 与 App 内模式一致。
  - 已闭合：`52bee7d` 把系统 play/pause 通过 HarmonyOS-only 私有通道回到 Dart `MusicAudioHandler.play()/pause()`，避免只操作底层 AVPlayer 后被业务状态刷新回 playing。
  - 已闭合：`52bee7d` 暂停态继续发布 `speed: 1.0`，规避当前设备上 `speed=0` 导致 AVSession 拒绝 paused 状态的问题；ohos 自验证 `show_controller_info` 已显示 pause 后 `state: paused speed: 1.000000`，play 后回到 `state: playing`。
  - 已闭合：`52bee7d` 系统播放模式点击按 AI Music 应用内按钮语义推进 `sequence -> list -> single -> shuffle -> sequence`，并移除当前 SDK 报无效事件的 `setTargetLoopMode` 注册；ohos 自验证 loop 点击后 `loopmode: list`。
  - 已闭合：`52bee7d` favorite 点击后 `show_controller_info` 显示 `is favorite: true`，仍通过 Dart `MusicController.toggleFavorite()` 回写真实收藏状态。
- Architect Findings:
  - 下一版 review 不再只看代码方向。ohos lane 必须提供点击系统 pause/play/loop 前后的 `hidumper -s AVSessionService -a '-show_session_info'` 与 `hidumper -s AVSessionService -a '-show_controller_info'` 关键字段变化，并附对应播放器日志。
  - 必须对照付华丽/符华利参考实现列出差异：`AvSessionController.ets` 的 `setAVPlayBackState()` 是由业务播放状态持续驱动，AI Music 需要确认真实播放器状态变化后是否重新发布 AVSession 状态，而不是仅在系统命令回调里预设状态。
- Notes: 本次主体是 HarmonyOS/ArkTS/AVSession，包含最小公共 Dart bridge，但所有入口均由 `isOpenHarmonyPlatform` / 私有 channel 限定到 HarmonyOS。不分发 iOS；不需要 android 回改。

## 产品验收反馈
- Result: changes_requested
- 反馈时间：2026-06-21
- 暂停恢复：暂停后系统播控中心图标状态没有跟着变，且无法从系统播控恢复播放。优先级最高。
- 点赞/收藏：之前还能点赞，当前系统播控里点不了了；如果不能和应用收藏闭环，不能保留一个看起来可用但实际不可用的入口。
- 播放模式：左侧切换播放模式当前点不了；如果未实现双向同步，必须隐藏/禁用到不误导用户，或补齐闭环实现。
- 封面：产品确认当前封面仍未替换为当前音乐封面；需要用真实歌曲封面验证，不能只验证默认图或应用 icon。
- 验收口径：本任务不能再标记为产品可验收。下一版必须先由 ohos lane 真机验证，再由架构师 review，最后发 `demo_ready` 给 product。

## 最新产品截图反馈
- Result: changes_requested
- 反馈时间：2026-06-21
- 截图结论：当前音乐封面已经可以显示，封面问题有进展，后续不要回退。
- 中间按钮：系统播控中心中间显示暂停图标，但点击后无法暂停；需要确认 `pause` command 是否注册、是否收到回调、是否调用 `AVPlayer.pause()`，以及是否立刻发布 `AVPlaybackState` 为 paused。
- 左侧按钮：左侧播放模式按钮灰色不亮且不可点击；如果产品要求播控中心支持切换播放模式，就必须实现闭环；如果暂不支持，不能露出灰色坏入口。
- 右侧按钮：右侧点赞按钮灰色不亮且不可点击；如果产品要求播控中心支持点赞/收藏，就必须实现闭环；如果暂不支持，不能露出灰色坏入口。
- 验收口径：底部三个产品关注按钮必须满足“可见即可用”。不可点击的灰色按钮不能作为 accepted 版本交付。

## 产品体验状态
- Status: accepted_pushed
- Owner Lane: ohos
- Thread: `019ee7db-7cfc-7c41-9827-6b851ce89548`
- Notes: 产品已确认鸿蒙播控中心功能体验 OK；`52bee7d8a8700b28310dfc856fc0cbf1e01a3716` 已推送到远端 `origin/main`，并确认远端 main 指向同一 SHA。AM-003 归档为 pushed/accepted；若后续出现新体验反馈，另开后续任务处理。
