# AM-20260623-003 下载后立即播放与缓存状态刷新

Status: assigned
Owner Lane: android, ohos
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.1
Base Branch: integration/1.0.1/preview-am003-home
Work Branch: pending split
Worktree Path: pending split
Merge Branch: release/1.0.1
Created: 2026-06-23
Updated: 2026-06-23

## 目标

- 修复产品在集成体验中发现的下载后播放与缓存状态刷新问题，保证 Android 与 HarmonyOS 的下载、播放、metadata 体验一致且可解释。

## 范围

- 包含：
  - HarmonyOS 下载完成后立即播放无声、杀进程重进后可播放的独有问题复现和修复。
  - 下载完成后搜索结果或列表播放按钮应立即切换为可播放状态，不应延迟 2 到 3 秒。
  - 已有封面 metadata 的缓存歌曲播放时不应重复走网络封面下载；只有缓存缺封面时才允许后台补全。
  - 必要的日志、测试和知识沉淀。
- 不包含：
  - 新增音乐源、歌词/封面 provider 或搜索 UI 大改。
  - Android 系统播控槽位、随机播放策略或 HarmonyOS AVSession 按钮能力。
  - 未经确认直接合入 main、release 或推送远端。

## 问题拆分

### P1 HarmonyOS 独有：下载完成立即播放无声

- 现象：鸿蒙测试机下载完歌曲后立即播放没有声音；杀进程重进后同一缓存歌曲可以恢复播放。
- Android 未复现，先由 ohos lane 只复现定位。
- 2026-06-23 阶段性结论：在 MUSIC 音量从 0/mute 恢复到 5 后，ohos lane 用全新未缓存关键词 `yellow` 复现链路，下载 `Yellow / 蔡健雅` 后立即播放未复现原生播放失败。`hilog` 显示 `AVPlayer state initialized/prepared/playing`、`AVPlayer play succeeded`，position 从 0 递增到 6.9s；`AudioPolicyService` 显示 AudioRenderer 存在、`rendererState=2`、`appVolume=25`；AVSession metadata 正确。当前证据不支持文件未落盘、路径权限或 `AVPlayer` 立即 load/play 失败。
- 新发现：搜索结果行只根据 `isCached` 固定显示 play 图标，不订阅当前 `mediaItem` / `playbackState`；播放成功时搜索列表行仍可能显示三角形，而底部 mini player / 系统状态已是播放中。这是公共 Dart/UI 误导风险，归 android lane 评估。
- 排查重点：
  - 下载文件 close/flush 与 `AVPlayer` / `just_audio_harmonyos` 立即 `loadUri` 的时序。
  - HAP 沙箱路径、`file://` 路径、fd/openSync/read 权限和文件大小是否稳定。
  - cache index 刷新和播放队列 source path 是否拿到完整本地文件。
  - `MediaAvPlayer.ets` / `AudioPlayer.ets` 的 load、prepare、play、error 回调。
  - 杀进程前后同一文件路径、文件大小、metadata 和播放器状态差异。

### P2 公共 Dart：下载后播放按钮延迟出现

- 现象：Android 与 HarmonyOS 下载完成后，搜索结果或列表里的播放按钮没有立即出现，要等约 2 到 3 秒。
- 初步归属：android lane 负责公共 Dart 状态刷新。
- 排查重点：
  - 下载完成后是否立即更新 candidate/cache 映射，而不是等待异步索引轮询或 metadata 后台任务。
  - `isCandidateCached` / cache index / candidate list 状态是否在下载成功回调里同步刷新。
  - UI 是否被 metadata 补全、封面下载或歌词解析阻塞。
  - 下载完成后不应因为后台补封面/歌词导致播放按钮延迟。

### P2 公共 Dart：已有封面播放时重复下载封面

- 现象：点击播放后封面似乎又重新下载了一次；如果歌曲已经有封面，不应该播放时重复下载。
- 初步归属：android lane 负责公共 Dart metadata/cache 策略；ohos 只在确认 HarmonyOS 平台重复触发时参与。
- 排查重点：
  - 播放已有 `coverUrl`、本地 artwork 或 metadata 的缓存歌曲时，metadata pipeline 应优先复用缓存。
  - 已有封面时不得调用网络封面 provider；只有缓存缺封面、或用户手动“重新获取歌词/封面”时才允许绕过。
  - 后台歌词恢复不能顺手重复拉封面。
  - 需要日志或单测证明已有封面播放不会触发网络 provider。

## 验收标准

- HarmonyOS：同一首歌下载完成后立即点击播放有声音；不需要杀进程重进才能播放。
- HarmonyOS：提供下载完成立即播放失败/成功前后的 `hdc hilog` 或关键播放器状态日志，能说明根因。
- HarmonyOS：验收前必须确认 `AudioPolicyService -a '-v'` 中 MUSIC 音量非 0 且未 mute，避免设备静音误判为播放失败。
- 公共 UI：搜索结果中当前正在播放的缓存歌曲不能继续表现成“未播放”的普通三角形，至少需要有 active/equalizer/pause 态或其它明确反馈，避免产品误判“没播”。
- Android 与 HarmonyOS：下载完成后，搜索结果或列表中的播放按钮立即切换为可播放状态，不能出现 2 到 3 秒空窗。
- Android 与 HarmonyOS：metadata/歌词/封面后台补全可以继续执行，但不能阻塞播放按钮状态。
- 已有封面的缓存歌曲点击播放时复用已有 metadata，不再调用网络封面 provider。
- 缓存缺封面时允许后台补全封面；手动重新获取可以绕过 miss TTL，但不得重新下载音频。
- 补充公共 Dart 单测或 widget 测试覆盖下载完成状态即时刷新和已有封面不重复拉取。
- 如涉及 HarmonyOS 插件修复，补充 ArkTS/HarmonyOS 侧最小验证日志，并沉淀到 `docs/codex_collab/knowledge/ohos/`。

## 分工

- ohos lane：
  - P1 当前未复现原生播放失败，继续保留为验证前置条件和日志归档；不改公共 Dart。
  - 使用 HarmonyOS 测试机 `192.168.31.53:10178`，优先抓 `hdc hilog`、播放器状态、文件路径/大小和 load/play/error 日志。
  - 如果确认为 ArkTS/插件问题，再申请专用 hotfix worktree 后修改。
- android lane：
  - 负责 P2 下载后播放按钮状态延迟、搜索结果当前播放态误导、封面重复下载的公共 Dart 排查。
  - 优先在当前 AM-20260622-003 feature worktree 或架构师分配的新 bugfix worktree 中定位，不能混入未登记需求。
  - 自测使用小米 10 Pro 或其它开发测试设备，不使用小米 17 Pro。
- architect lane：
  - 负责定责、review 和跨分支合入顺序。
  - 只有证据显示问题跨平台或归属变化时，才调整 owner。

## 消息记录

- 2026-06-23 type=bug_report lane=product summary=产品反馈 HarmonyOS 下载完立即播放无声，杀进程重进可播；Android 未复现。
- 2026-06-23 type=bug_report lane=product summary=产品反馈 Android 与 HarmonyOS 下载完成后播放按钮延迟 2 到 3 秒出现，疑似公共 Dart cache/candidate 状态刷新问题。
- 2026-06-23 type=bug_report lane=product summary=产品反馈播放已有封面歌曲时疑似重复下载封面，要求已有封面时复用缓存 metadata。
- 2026-06-23 type=status lane=ohos summary=ohos lane 已开始只复现定位，不改代码；如需修改会先发 blocker 等待 worktree 和边界确认。
- 2026-06-23 type=status lane=ohos summary=音量恢复后用全新未缓存 `yellow` 严格复现下载后立即播放，未复现原生播放失败；播放器、AudioRenderer、AVSession metadata 均正常。发现搜索结果行不跟随当前播放态，可能造成“播放了但列表仍显示三角形”的误判，该 UI 问题转公共 Dart/Android lane。

## 相关提交

- pending

## 版本与发布

- Target Version: 1.0.1
- Release Tag: pending
- Android APK: pending
- HarmonyOS HAP: pending
- Push Status: not_ready

## Review 结果

- Reviewer Lane: architect
- Result: pending
- Android Findings: pending
- iOS Findings: 不涉及
- HarmonyOS Findings: 音量恢复后严格复现未发现原生播放失败；当前更像设备静音前置条件与公共 UI 播放态反馈不足叠加。
- Architect Findings: P1 暂不要求 ohos 改代码；验收前必须检查 MUSIC 音量。新增公共 UI finding：搜索结果当前播放歌曲需要 active/pause 态反馈，归 android lane。P2 下载按钮即时刷新与封面重复下载仍归 android lane。
- Notes: 当前阻断重点转向公共 Dart/UI 与 metadata/cache 策略；ohos 只继续保留验证日志和平台侧复现兜底。
