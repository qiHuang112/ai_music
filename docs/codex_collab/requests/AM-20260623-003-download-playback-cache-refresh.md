# AM-20260623-003 下载后播放、缓存状态与 HarmonyOS 串歌修复

Status: assigned
Owner Lane: android
Assist Lane: ohos, architect
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.1.0 verification
Base Branch: release/1.1.0
Work Branch: feature/1.1.0/AM-20260623-003-cache-first-full-audio-playback
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260623-003_android_cache_first
Merge Branch: release/1.1.0
Created: 2026-06-23
Updated: 2026-07-11

## 目标

- 修复产品在集成体验中发现的下载后播放与缓存状态刷新问题，保证 Android 与 HarmonyOS 的下载、播放、metadata 体验一致且可解释。
- 本轮已闭合 HarmonyOS P1：多首下载后逐个点击播放时，实际播放源与点击行不一致或无声。
- 2026-07-11 新增 release/1.1.0 P1：HarmonyOS 证明已缓存 `source_gequhai` full-audio candidate 再次点击仍走 transient proxy，导致 `playback_load_failed`；首因指向公共 Dart `playCandidate` 缓存优先级。
- 公共 Dart 其它 P2 仍保留后续处理：下载完成播放按钮延迟、搜索结果当前播放态误导、已有封面重复拉取。

## 范围

- 包含：
  - HarmonyOS 下载完成后立即播放、连续切换搜索结果和旧队列预加载场景。
  - HarmonyOS vendored plugin 旧 `MediaSource` 队列复用、预加载播放器跨队列升格和 load failure 上抛。
  - 下载完成后搜索结果或列表播放按钮应立即切换为可播放状态，不应延迟 2 到 3 秒。
  - 已有封面 metadata 的缓存歌曲播放时不应重复走网络封面下载；只有缓存缺封面时才允许后台补全。
  - 必要的日志、测试和知识沉淀。
- 不包含：
  - 新增音乐源、歌词/封面 provider 或搜索 UI 大改。
  - Android 系统播控槽位、随机播放策略或 HarmonyOS AVSession 按钮能力。
  - 未经架构师 review accepted 的其它 lane 改动。

## 问题拆分

### P1 HarmonyOS：旧队列复用导致串歌或无声

- 现象：HarmonyOS 搜索结果下载多首后逐个点击播放，Flutter UI 和 AVSession metadata 已切到点击歌曲，但 AVPlayer 未加载目标 source，用户感知为串歌或无声。
- 产品澄清：该 P1 发生在 HarmonyOS，Android 没有复现。此前把串歌 P1 派给 android 主责属于定责错误，已改为 ohos 主责。
- 复现路径：先播放自建歌单 `qi` 中 3 首歌，建立旧 3 首 native 队列和 next preload；再搜索 `yellow`，下载并逐个播放多条搜索结果。
- 根因：`AudioPlayer.getAudioSource()` 会按 just_audio 传来的 `audioSource.id` 缓存 `MediaSource`，full `load` 前没有清空/刷新 `mediaSources`，导致 native `songList` 沿用旧队列；`MediaAvPlayer.loadAssent()` 在 index 越界或 uri 缺失时只同步错误后 return，没有可靠把 load failure 回传 Dart。
- 修复提交：`5916b4c6ff782f3513db69d961841225dd6b0dc2`（`修复鸿蒙播放器旧队列复用`）。
- 修复内容：
  - `AudioPlayer.ets` full `load` 使用 `getFreshAudioSource()` 重建 native source tree，避免复用旧 `mediaSources`。
  - `MediaAvPlayer.ets` full load 释放旧 `avPlayerNext` / `pendingAvPlayerNext`，避免旧队列预加载播放器跨队列升格。
  - `loadAssent()` 对 index 越界、空 uri 可靠上抛 error。
  - 增加 `loadAssent source` 与 file dataSrc path/size 日志。
  - 新增 `docs/codex_collab/knowledge/ohos/media-source-cache-and-preload.md`。

### P2 公共 Dart：下载后播放按钮延迟出现

- 现象：Android 与 HarmonyOS 下载完成后，搜索结果或列表里的播放按钮没有立即出现，要等约 2 到 3 秒。
- 初步归属：android lane 负责公共 Dart 状态刷新。
- 排查重点：
  - 下载完成后是否立即更新 candidate/cache 映射，而不是等待异步索引轮询或 metadata 后台任务。
  - `isCandidateCached` / cache index / candidate list 状态是否在下载成功回调里同步刷新。
  - UI 是否被 metadata 补全、封面下载或歌词解析阻塞。
  - 下载完成后不应因为后台补封面/歌词导致播放按钮延迟。

### P1 公共 Dart：已缓存歌曲海完整音频必须优先走正式缓存播放

- 现象：OHOS 在 `release/1.1.0@45b302d` signed HAP 上复现，`外婆 / 周杰伦` 下载完成并 promote 正式 mp3 后，再次点击已完成候选仍进入 `source_gequhai` transient proxy，随后旧 session canceled、新 session `bytes=0`、`promote-failed Bad state: No element`、AVPlayer `NET_ERR-server-IO error`、UI `playback_load_failed`。
- 证据摘要：HAP sha256 `d2c0123307035a74e12eda375bc8fd610b5b17852d0f55ee0a9d94545c3849ed`；设备 `192.168.31.53:6666`；MUSIC=3、mute=0；搜索 `外婆` 得到 `歌海/外婆/周杰伦/可下载`；首次播放 `first_byte_ms=2244`、`download_complete_ms=7617`、正式缓存 mp3 已生成；再次点已完成结果仍走 `http://127.0.0.1:<port>/audio/...` transient proxy。
- 架构判断：这是公共 Dart 路由优先级问题，不是 OHOS 原生 AVPlayer 首因。`lib/src/application/music_controller.dart` 的 `playCandidate` 对 `source_gequhai` 先进入 `_playFullAudioStreamingCandidate` 并 return，导致 `_cachedRecordForCandidate` 本地文件路径分支不可达。
- 修复要求：已缓存 full-audio candidate 必须优先走正式缓存播放路径；只有未缓存且通过 `direct_audio/canCacheAudio/clientReady` gate 的 full-audio candidate 才进入 transient streaming；失败或取消不得写正式缓存。
- Owner 裁决：由 `android` lane 修公共 Dart，独立工程 `/Users/huangqi/AIHome/projects/ai_music_AM-20260623-003_android_cache_first`，分支 `feature/1.1.0/AM-20260623-003-cache-first-full-audio-playback`，基线 `origin/release/1.1.0=45b302d48649330446d381b8593c50e22b9099f5`。
- 回传证据：新 commit、targeted test 覆盖 `playCandidate` 对已缓存 `source_gequhai` full-audio 优先走 cache 而不打开 transient、`flutter analyze --no-pub`、scope diff、防回退说明、可验证 APK/HAP 构建点。OHOS 收到后复测 `外婆`、`一丝不挂`、`稻香`、`哎呀`，带 HAP sha、截图/录屏、hilog、AVSession 和 cache index 证据。

### P2 公共 Dart：搜索结果当前播放态误导

- 现象：搜索结果行只根据 `isCached` 固定显示 play 图标，不订阅当前 `mediaItem` / `playbackState`；播放成功时搜索列表行仍可能显示三角形，而底部 mini player / 系统状态已是播放中。
- 初步归属：android lane 负责公共 Dart/UI。
- 验收方向：搜索结果中当前正在播放的缓存歌曲不能继续表现成“未播放”的普通三角形，至少需要 active/equalizer/pause 态或其它明确反馈。

### P2 公共 Dart：已有封面播放时重复下载封面

- 现象：点击播放后封面似乎又重新下载了一次；如果歌曲已经有封面，不应该播放时重复下载。
- 初步归属：android lane 负责公共 Dart metadata/cache 策略；ohos 只在确认 HarmonyOS 平台重复触发时参与。
- 排查重点：
  - 播放已有 `coverUrl`、本地 artwork 或 metadata 的缓存歌曲时，metadata pipeline 应优先复用缓存。
  - 已有封面时不得调用网络封面 provider；只有缓存缺封面、或用户手动“重新获取歌词/封面”时才允许绕过。
  - 后台歌词恢复不能顺手重复拉封面。
  - 需要日志或单测证明已有封面播放不会触发网络 provider。

## 验收标准

- HarmonyOS：连续点击至少 3 首不同歌曲，点击行、Dart `mediaItem`、AVSession metadata、ArkTS 当前 source/path/fd、AVPlayer 实际播放源必须完全一致。
- HarmonyOS：复测路径必须覆盖旧队列和 next preload，即先播放自建歌单 `qi` 的多首歌，再搜索/下载/逐个播放多首 `yellow`。
- HarmonyOS：不得再出现 `loadIndexOutOfRange`、`loadSourceUriMissing`、`load file data src failed` 或 UI/AVSession 已切歌但 AVPlayer 未进入 `prepared/playing/play succeeded`。
- HarmonyOS：验收前必须确认 `AudioPolicyService -a '-v'` 中 MUSIC 音量非 0 且未 mute，避免设备静音误判。
- Android 与 HarmonyOS：下载完成后，搜索结果或列表中的播放按钮立即切换为可播放状态，不能出现 2 到 3 秒空窗。
- Android 与 HarmonyOS：metadata/歌词/封面后台补全可以继续执行，但不能阻塞播放按钮状态。
- 已有封面的缓存歌曲点击播放时复用已有 metadata，不再调用网络封面 provider。
- 缓存缺封面时允许后台补全封面；手动重新获取可以绕过 miss TTL，但不得重新下载音频。

## 分工

- ohos lane：
  - 已完成 HarmonyOS P1 旧队列复用修复并自测通过。
  - 负责 `third_party/just_audio_harmonyos/**`、`ohos/**`、`docs/codex_collab/knowledge/ohos/**`。
  - 如后续需要改公共 Dart，必须先回报架构师确认边界。
- android lane：
  - 立即负责 P1 已缓存歌曲海完整音频 cache-first 播放路由修复。
  - 继续负责 P2 下载后播放按钮状态延迟、搜索结果当前播放态误导、封面重复下载的公共 Dart 排查。
  - Android 公共 Dart 队列/index 防串歌修复可作为后续安全加固；除非 HarmonyOS 修复后仍复现，否则不作为本轮 P1 主线。
  - 自测使用小米 10 Pro或其它开发测试设备，不使用小米 17 Pro。
- architect lane：
  - 负责定责、review、合入主线、推送和安装通知。
  - 只有证据显示问题跨平台或归属变化时，才调整 owner。
  - 2026-07-05 起作为唯一 owner 负责把旧多 owner 综合任务拆成 Android/OHOS 可执行子任务，避免继续违反唯一 owner 规则。

## HarmonyOS 自测证据

- `FLUTTER_ROOT=/Users/huangqi/AIHome/tools/flutter /Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub`：107 tests passed。
- `flutter analyze --no-pub`：通过。
- `OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh`：通过，产物 `build/ohos/hap/entry-default-signed.hap`，约 23.7MB。
- 已安装到无线 HDC 设备 `192.168.31.53:10178`，`hdc install` 返回 `install bundle successfully`，应用可启动。
- 产品路径复测：
  - 先进入 `qi` 歌单，逐个播放 `十年 / 陈奕迅`、`浮夸 / 陈奕迅`、`Midnight City / M83`，建立旧 3 首队列和 next preload。
  - 搜索 `yellow`，连续点击前四条。
  - `yellow1` metadata 为 `Yellow / 蔡健雅`，原生日志 source 为 `蔡健雅-Yellow-473fb4e2b0.mp3`，size `11343630`，`AVPlayer play succeeded`。
  - `yellow2` metadata 为 `Yellow / Coldplay`，原生日志 source 为 `Coldplay-Yellow-7fc14e3e93.mp3`，size `10673856`，`AVPlayer play succeeded`。
  - `yellow3` metadata 为 `Yellow / 酷玩乐队`，原生日志 source 为 `酷玩乐队-Yellow-5334759b21.mp3`，size `10673848`，`AVPlayer play succeeded`。
  - `yellow4` metadata 为 `Yellow Submarine / The Beatles`，原生日志 source 为 `The Beatles-Yellow Submarine-6b3f7b953e.mp3`，size `6391826`，`AVPlayer play succeeded`。
  - 四次点击均未出现 `loadIndexOutOfRange`、`loadSourceUriMissing` 或 `load file data src failed`，AudioPolicyService 有 active renderer。
- 自测截图和日志：`/tmp/ai_music_ohos_am003_fix/`，包括 `yellow{1,2,3,4}_metadata.txt`、`yellow{1,2,3,4}_hilog.txt`、`yellow{1,2,3,4}_audio.txt`。

## 消息记录

- 2026-06-23 type=bug_report lane=product summary=产品反馈 HarmonyOS 下载完立即播放无声，杀进程重进可播；Android 未复现。
- 2026-06-23 type=bug_report lane=product summary=产品反馈 Android 与 HarmonyOS 下载完成后播放按钮延迟 2 到 3 秒出现，疑似公共 Dart cache/candidate 状态刷新问题。
- 2026-06-23 type=bug_report lane=product summary=产品反馈播放已有封面歌曲时疑似重复下载封面，要求已有封面时复用缓存 metadata。
- 2026-06-23 type=status lane=ohos summary=ohos lane 音量恢复后用全新未缓存 `yellow` 严格复现下载后立即播放，未复现原生播放失败；发现搜索结果行不跟随当前播放态。
- 2026-06-24 type=correction lane=product status=blocker summary=产品澄清串歌发生在 HarmonyOS，Android 没有问题；串歌 P1 主 owner 改为 ohos lane，android 只保留协助角色。
- 2026-06-24 type=blocker lane=ohos status=blocked summary=ohos lane 在 `192.168.31.53:10178` 复现核心链路：下载 `yellow` 搜索结果第 2/3/4 条后，点击第 3 条 `Yellow / 酷玩乐队`，Flutter UI 和 AVSession metadata 都显示酷玩乐队，但原生没有进入 `prepared/playing/play succeeded`，`AudioPolicyService` 显示 AudioRenderer `rendererState=5`，日志出现 `MediaAvPlayer current musicIndex 2`，对应 `loadAssent()` index 越界分支。
- 2026-06-24 type=status lane=ohos status=in_progress summary=进一步定位为 HarmonyOS vendored plugin 缓存旧 `MediaSource` 队列：先播放 3 首自建歌单 `qi`，再搜索下载/播放多首 `yellow` 后，native duration 对上旧队列里的 `浮夸`/`Midnight City`；第 3/4 条进入 `loadAssent()` index 越界。
- 2026-06-24 type=review_request lane=ohos status=ready_for_review summary=ohos lane 提交 `5916b4c` 修复旧队列复用，并提供 `qi` 歌单后连续播放 `yellow1` 到 `yellow4` 的 HDC 自测证据。
- 2026-07-11 type=blocker lane=ohos status=blocked summary=OHOS 在 release/1.1.0 HAP 上复现下载后立即播放失败：正式缓存已存在但已缓存歌曲海 full-audio candidate 仍走 transient proxy，日志出现 `bytes=0`、`promote-failed Bad state: No element`、AVPlayer `NET_ERR-server-IO error`、UI `playback_load_failed`；判断为公共 Dart `playCandidate` cache-first 路由缺失。
- 2026-07-11 type=task lane=architect status=assigned summary=Architect 裁决由 Android owner 修公共 Dart。专项工程 `/Users/huangqi/AIHome/projects/ai_music_AM-20260623-003_android_cache_first` 已基于 `origin/release/1.1.0=45b302d48649330446d381b8593c50e22b9099f5` 创建，分支 `feature/1.1.0/AM-20260623-003-cache-first-full-audio-playback`；若 Android 10 到 15 分钟仍无 review_request 或 blocker，architect 将接管或重分配专项 owner。
- 2026-07-11 type=review_result lane=architect status=accepted summary=Architect 窄复核 Android 回改 accepted：`playCandidate` 先查 `_cachedRecordForCandidate`，命中后走 `_refreshCachedCandidateMetadata` 与正式缓存 file 播放；只有未缓存 full-audio source 才进入 `_playFullAudioStreamingCandidate`。复核路径为 `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`，diff 仅认可 `lib/src/application/music_controller.dart` 与 `test/music_controller_test.dart` 的 AM-20260623-003 部分；同目录 `swipe_to_skip.dart` 与 `widget_test.dart` 属 AM-20260625/AM-003 WIP，合入前必须拆分，不得混入本任务提交。

## 相关提交

- `5916b4c6ff782f3513db69d961841225dd6b0dc2`：修复鸿蒙播放器旧队列复用。

## 版本与发布

- Target Version: 1.0.1
- Release Tag: pending
- Android APK: pending
- HarmonyOS HAP: `build/ohos/hap/entry-default-signed.hap`
- Push Status: pending_main_push

## Review 结果

- Reviewer Lane: architect
- Result: HarmonyOS P1 accepted; Android/common Dart P2 pending
- Android Findings: P2 下载按钮即时刷新、搜索结果当前播放态、已有封面不重复拉取仍需后续处理。
- iOS Findings: 不涉及。
- HarmonyOS Findings: `5916b4c` 修复方向和证据充分。full load 强制重建 native source tree，清理 next preload，并在 `loadAssent()` 越界/空 uri 时可靠上抛，直接覆盖本次 P1 根因；HDC 复测四首 `yellow` 的 metadata、source path、file size 与播放状态一致，未再出现越界或无声。
- Architect Findings: HarmonyOS P1 可合入 main 并推送；推送后需从 main 构建 signed HAP，安装到 HarmonyOS 测试机并通知 product。小米 17 Pro 是 Android 设备，本轮 HarmonyOS HAP 不适用；如后续要给小米 17 Pro 装包，必须基于 Android/common Dart accepted 代码另行构建 APK。
- Architect Findings 2026-07-11 cache-first review: accepted for code boundary. `lib/src/application/music_controller.dart` now checks cache before full-audio streaming, so cached `source_gequhai` candidates use the local file path instead of transient proxy. Regression test `playCandidate plays cached Gequhai full audio before opening transient stream` covers `loadedIds=cacheId`, `uri.scheme=file`, and `playingCachedFile`; `_FailingStreamingPlayback` would fail if transient opened. Verification run by architect: `/Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/music_controller_test.dart test/music_cache_test.dart test/progressive_audio_cache_test.dart --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true` = 63 passed; `/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze --no-pub lib/src/application/music_controller.dart test/music_controller_test.dart` = no issues. Scope caveat: Android implemented inside `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`, where unrelated WIP files `lib/src/presentation/swipe_to_skip.dart` and `test/widget_test.dart` are also dirty; release merge requires cherry-picking or committing only the two accepted AM-20260623-003 files into the designated clean Project Path/branch.

## 2026-07-11 Active Request Convergence

- Result: still_active_as_verification
- Covered By:
  - AM-20260711-004 已恢复 Android 公共 Dart 歌曲海完整搜索、边下边播、正式缓存转正、歌词/封面 metadata。
  - AM-20260711-003 已补当前队列入口、mini player 点击层级和 Library First UI。
- Remaining Scope:
  - HarmonyOS 下载完成后立即播放是否有声、是否无需杀进程重进。
  - HarmonyOS 下载完成后缓存状态、播放态和歌词/封面 metadata 是否与 Android 1.1.0 主链路一致。
  - Android 公共 Dart 已有封面不重复拉取的历史疑点仅在新证据复现时再开 bugfix；本轮不作为 release/1.1.0 blocker。
- Owner:
  - `android` 负责公共 Dart cache-first 播放路由修复。
  - `ohos` 负责修复后真机验证与 HAP 证据。
- Project Path / Device:
  - Android Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260623-003_android_cache_first`
  - OHOS Project Path: `/Users/huangqi/AIHome/projects/ai_music_ohos`
  - Device: `ALN-AL00` / HDC target `192.168.31.53:6666`（或 OHOS lane 回传的新 target）。
  - Android release baseline for comparison: `release/1.1.0@45b302d48649330446d381b8593c50e22b9099f5`。
- Acceptance Samples:
  - 正向样例优先：`外婆 / 周杰伦`、`一丝不挂 / 陈奕迅`、`稻香 / 周杰伦`、`哎呀 / 王蓉`。
  - 每首必须覆盖：搜索歌曲海完整音频、点击下载/播放、下载完成后立即播放有声、media session/AVSession playing、正式缓存 mp3 与 `.lrc`、缓存 index、歌词/封面 metadata。
  - 设备前置：验证前记录 MUSIC 音量非 0 且未 mute。
  - 证据：HAP path/sha、source commit、是否清数据、`hdc hilog`、截图/录屏、缓存文件列表和播放状态。
