# AM-20260624-ANDROID-RELEASE-MEDIA-CONTROL Android release 播控中心消失

Status: urgent_p1
Owner Lane: android
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.0
Base Branch: main
Work Branch: lane/android
Worktree Path: /Users/huangqi/AIHome/projects/ai_music_android
Merge Branch: main
Created: 2026-06-24
Updated: 2026-06-24

## 目标

修复产品在小米 17 Pro 安装最新 Android release 包后发现的 P1：播放歌曲后系统播控中心没有出现。

本任务目标是恢复 AI Music 之前已经支持过的 Android 系统播控中心能力，不是新增“通知权限功能”。`POST_NOTIFICATIONS` 只能作为 Android 13+ / MIUI release 包兼容和排查点，不能作为需求本身，也不能在缺少播放后 active MediaSession、notification controls 和四槽位证据时 declared fixed。

这是 1.0.0 release blocker。修复闭环前，不推进新的 1.0.1 公共 Dart 功能，不把当前 `v1.0.0` release 包继续作为正式可发布包交付。

## 背景

- 最新 Android release 包路径：`/Users/huangqi/AIHome/projects/ai_music_integration/build/release/ai-music-v1.0.0-android-arm64.apk`。
- APK SHA256：`54230c472cda52da0dd56d498edb98b8335ba5da50dead02d3bcce73c7a2d4e3`。
- 已安装到产品授权的小米 17 Pro `192.168.31.190:45075`。
- 设备包信息：`com.qi.ai.music` / `versionCode=2001` / `versionName=1.0.0` / `arm64-v8a` / `lastUpdateTime=2026-06-24 22:02:10`。
- 产品反馈：release 包播放后系统播控中心没有了。

## 初始怀疑点

Android lane 需要基于 release 包定位，不允许只用 debug 包证明：

- release 和 debug 的差异导致 `audio_service`、`MediaSession`、notification 或 foreground service 没启动。
- release shrink/混淆/资源裁剪影响 notification icon、custom action、service 或 receiver。
- Android 13+ / MIUI 通知权限、前台服务权限或 media notification slot 策略在 release 包下表现不同。
- `POST_NOTIFICATIONS` 缺失可以解释普通通知不可见，但不能单独作为最终根因；Android 官方文档说明 media session 相关通知属于通知运行时权限豁免项。因此如果播放后 `dumpsys media_session` 没有 active session，优先继续查 audio_service 初始化、播放状态发布、service/foreground notification 启动链路。
- 必须对比旧可用包或旧可用提交与当前 release 的差异，覆盖 `audio_service` active session、`PlaybackState` / `MediaItem` 发布、notification controls、foreground service、manifest service/receiver 和 release 打包差异。
- 如果当前 release 播放后已经存在 `media-session com.qi.ai.music/media-session`、metadata 和 queue，但 `active=false`、`PlaybackState state=0`，则优先按播放状态链路排查：点击播放是否真正调用 `AudioHandler.play/loadQueue`，`just_audio` 是否报错，`playbackState` 是否发布 `playing`，foreground service 是否因状态未 playing 而未升起。
- 当前最强根因假设：release logcat 出现 `IllegalArgumentException: You must specify an icon resource id to build a CustomAction`；源码里有 `ic_notification_favorite*.xml`，但 8.86MB release APK 的 `aapt dump resources` 未看到这两个资源。自定义收藏 action 的 `androidIcon` 在 release APK 中不可用，会导致 `audio_service` 构建 `CustomAction` 失败，进而阻断 `playbackState`/notification 发布。
- `MediaItem`、`PlaybackState`、`controls`、`androidCompactActionIndices` 在 release 包播放链路中没有正确发布。
- release 构建脚本、manifest、R8/proguard、签名或安装覆盖导致系统媒体会话未被系统识别。

## 范围

包含：

- Android release 包播放后的系统媒体控件、通知、前台服务、MediaSession 和 audio_service 链路。
- `android/`、`lib/src/playback/`、`lib/src/application/` 中与系统播控发布相关的最小修复。
- Android release 构建脚本、manifest、proguard/R8 规则、notification resource 或权限声明。
- Android 小米 10 Pro 开发机自测；如 product 已授权，可在小米 17 Pro 复核安装。
- 后续开发验证默认使用小米 10 Pro。小米 17 Pro 只作为 product 最终验收设备；需要用户点“允许通知”时，由 architect/product 协调，不由开发 lane 当作日常自测设备反复操作。

不包含：

- 1.0.1 播放状态持久化。
- 1.0.1 歌词/封面 metadata pipeline。
- HarmonyOS HAP 或 iOS 宿主修复。
- FLAC/Auto 搜索体验的新功能扩展。

## 验收标准

- Android release 包安装后，播放一首歌曲，系统播控中心必须重新出现。
- `aapt dump resources` 必须能证明自定义收藏 action 使用的图标资源已经进入 release APK，或代码改为使用 release APK 中确定存在的内置/应用资源。
- 四槽位顺序保持既定口径：收藏/取消收藏、上一首、播放/暂停、下一首。
- 收藏、上一首、播放/暂停、下一首均可用。
- 不能把“通知权限已声明/已授权”当作 accepted 条件；accepted 条件必须是播放后播控中心出现且四槽位可见可点。
- `dumpsys media_session` 能看到 AI Music active session、metadata、playback state 和 controls/custom actions。
- 通知或系统媒体控件可见；如受 MIUI/Android 版本策略限制，需提供具体系统证据说明不是 App 未发布。
- release 包验证必须覆盖小米 10 Pro 开发机；如安装到小米 17 Pro，需要明确 product 授权来源和端口。
- 下一轮 review 优先接受小米 10 Pro 的 release 播放证据；小米 17 Pro 只用于最终验收，并需要产品手动允许通知权限后复测。
- 修复后重新构建 Android arm64 release 包，记录路径、大小、sha256、安装设备和 `dumpsys package` 信息。

## Android lane 必须提供的定位证据

- debug 包是否正常出现系统播控中心。
- release 包是否复现系统播控中心消失。
- 当前 release 播放后如果 session 存在但 inactive，必须提供 `AudioHandler`/`just_audio`/`playbackState` 的调用和错误日志，不能继续停留在通知权限。
- 播放后 `dumpsys media_session` 关键字段：session 是否存在、active 状态、metadata、state、actions、custom actions。
- 播放后 `dumpsys notification` 或等价命令中是否有 AI Music media notification。
- `logcat` 中 audio_service、MediaSession、foreground service、notification 相关错误。
- 如果曾出现 `You must specify an icon resource id to build a CustomAction`，修复后必须提供小米 10 release 播放 logcat 证明该异常消失。
- `aapt dump resources` 对比：当前 8.86MB arm64 release 是否缺少 `ic_notification_favorite` / `ic_notification_favorite_border`，修复后这两个资源是否进入 APK；或者说明已改用其它有效资源。
- release 构建是否启用了 shrink/minify/resource shrink；如启用，需要验证 proguard keep 和资源是否被裁。
- 旧可用包或旧可用提交与当前 release 的关键差异：manifest、service/receiver、foreground service、notification controls、`audio_service` 初始化和 playback state 发布。

## 消息记录

- 2026-06-24 type=bug_report lane=product status=urgent_p1 summary=产品反馈最新 Android release 包安装到小米 17 Pro 后系统播控中心没了，要求作为 1.0.0 release blocker，暂停正式 release，先让 Android 定位。
- 2026-06-24 type=task lane=architect status=assigned summary=架构师将该问题切给 Android lane 主责定位，1.0.1 新功能不得覆盖该 P1。
- 2026-06-24 type=status lane=android status=in_progress summary=Android lane 静态确认 release manifest 中 `AudioService`、`MediaButtonReceiver`、`AudioServiceActivity` 均存在，release 未启用 minify/R8；小米 17 Pro `appops` 显示 `POST_NOTIFICATION: ignore`，且当前 `dumpsys media_session` 只看到 Last MediaButtonReceiver/Audio playback uid，未见 active AI Music session，notification 列表未见 AI Music media notification。
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=允许补 `POST_NOTIFICATIONS` 声明和 Android 13+ 运行时请求作为兼容修复，但该点不能作为唯一根因；accepted 前必须证明 release 播放后 active media session、media notification 和四槽位均恢复。
- 2026-06-24 type=review_request lane=android status=review summary=Android lane 已完成最小补丁并构建安装 release 包：Manifest 声明 `POST_NOTIFICATIONS`，`MainActivity` 在 Android 13+ 请求通知权限，回归测试覆盖声明和请求逻辑；小米 17 Pro 已出现系统权限弹窗但设备屏幕黑/弹窗不可操作，`pm grant` 不被 user build 允许，当前仍等待用户允许通知权限后复验。
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=代码方向无明显架构风险，但 P1 未达 accepted：缺少用户允许权限后 release 播放的 active media session、media notification 和四槽位可用证据；测试和知识库措辞需避免把 `POST_NOTIFICATIONS` 写成官方通用唯一根因。
- 2026-06-24 type=follow_up lane=product status=action_required summary=产品强调设备规则：Android lane 开发验证使用小米 10 Pro，小米 17 Pro 只做最终验收。架构师需盯住本 P1，不让 1.0.1 新功能覆盖；等 Android 回小米 10 验证结果后快速给 accepted/changes_requested/blocker 结论，并主动回 Android 和 product。
- 2026-06-24 type=coordination lane=architect status=blocker summary=Android 构建环境卡住后，架构师选择 B 路径接手构建环境协助：停止卡住的 integration debug build / Gradle daemon，并用 integration 当前修复现场成功构建 arm64 release 包 `build/release/ai-music-v1.0.0-android-arm64.apk`，大小约 8.86 MB，sha256 `0b896cb87a42e21d9962e0707fc24a4c32dd81c45170df71368afa60451a88e3`。安装到小米 10 Pro `192.168.31.76:41325` 时失败，原因为设备已有 `com.qi.ai.music` 的签名不同：`INSTALL_FAILED_UPDATE_INCOMPATIBLE`。小米 10 Pro 当前包 `versionCode=1`、`versionName=1.0.0`、`lastUpdateTime=2026-06-24 07:31:56`。下一步需要 Android/产品确认是否允许卸载小米 10 Pro 现有包后安装 release，或改用一致签名体系重打包；业务修复仍归 Android。
- 2026-06-24 type=status lane=architect status=blocker summary=按 product 要求复查第二条 debug build，pid `96369`/`96453` 超过 2 分半仍停在 `assembleDebug`，未产出新的 debug 包。架构师已停止该 debug build 和 Gradle daemon，不再无声重试 debug 路径。当前可用验证包为已成功构建的 release APK：`build/release/ai-music-v1.0.0-android-arm64.apk`，sha256 `0b896cb87a42e21d9962e0707fc24a4c32dd81c45170df71368afa60451a88e3`。下一步仍是解决小米 10 Pro 签名冲突后安装 release 包验证，或 Android 提供同签名 release/debug 构建。
- 2026-06-24 type=product_decision lane=product status=approved_dev_device_uninstall summary=产品确认小米 10 Pro 是开发验证机，允许卸载当前旧包后安装本次 release 包验证；该授权只适用于小米 10 Pro，不适用于小米 17 Pro。
- 2026-06-24 type=status lane=architect status=ready_for_android_validation summary=架构师已在小米 10 Pro `192.168.31.76:41325` 卸载旧包并安装 release 包成功，包 `versionCode=2001`、`versionName=1.0.0`、`lastUpdateTime=2026-06-24 22:32:22`。通知权限已通过 ADB 授权，`POST_NOTIFICATION: allow`，runtime `android.permission.POST_NOTIFICATIONS: granted=true`。下一步由 Android lane 在小米 10 Pro 播放歌曲并回传 active media session、notification/logcat 和四槽位证据。
- 2026-06-24 type=product_correction lane=product status=scope_correction summary=产品明确纠偏：Android P1 不是让团队实现通知权限，而是找回之前已经支持过、现在 release 包回归丢失的系统播控中心能力。通知权限只是可能的兼容/排查点，不能作为需求本身，也不能在没有播放后 active session/四槽位证据时 declared fixed。
- 2026-06-24 type=blocker lane=android status=playback_session_not_active summary=Android lane 在小米 10 Pro release 包中搜索 `Taylor`，下载并点击播放 `last christmas / taylor`。`dumpsys media_session` 显示 `media-session com.qi.ai.music/media-session` 存在，metadata 为 `last christmas, taylor`，queue size=1，但 `active=false`，`PlaybackState state=0 position=0 actions=3669711`；notification 中未抓到 AI Music 媒体通知。结论：安装和通知权限 blocker 已解除，当前核心是 release 下点击播放后 audio_service/just_audio 状态没有进入 active/playing。
- 2026-06-24 type=evidence_update lane=product status=playback_state_root_cause_direction summary=产品确认当前根因方向应从“通知权限”切到“release 下播放状态没有进入 active/playing 或 playbackState 没发布”。后续 review 优先卡点击播放后音频是否实际开始、`AudioHandler.play` / `playbackState.add` 是否执行、`processingState` / `playing` 是否更新、release 与 debug 在该链路是否不同、8MB arm64 包是否缺 `audio_service` 类、manifest service/receiver 或 notification controls。
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=Android 的新定位方向正确：继续查播放按钮触发、`AudioHandler.play/loadQueue`、`just_audio` 错误、foreground service 和 playbackState 发布。架构师本地未找到可直接交付的旧可用 APK 路径；Android 需要从 git 历史、早期 release 或已知旧提交中找旧可用包/commit 做对照。
- 2026-06-24 type=review_evidence lane=product status=root_cause_likely_confirmed summary=新证据显示 logcat 有 `IllegalArgumentException: You must specify an icon resource id to build a CustomAction`；源码有 `ic_notification_favorite*.xml`，但当前 8.86MB release APK 的 `aapt dump resources` 没有这两个资源。音频实际在播，metadata/queue 有，但 playbackState 卡 `state=0`、notification 不出。根因高度指向自定义收藏 action 的 `androidIcon` 资源在 release APK 中不可用，导致 `audio_service` 构建 `CustomAction` 失败。
- 2026-06-24 type=status lane=architect status=owner_followup_required summary=架构师核对 integration 工程，当前未提交代码仍只有通知权限相关 diff：`AndroidManifest.xml`、`MainActivity.kt`、`test/release_config_test.dart`；源码中存在 `res/drawable/ic_notification_favorite*.xml`，但还没有新增资源 keep 规则、没有测试覆盖 release APK 资源表，也没有证明 `aapt dump resources` 能看到收藏图标资源。Android owner 需要立即把 CustomAction icon 资源修复落成代码或回 blocker。

## Review 结果

- Reviewer Lane: architect
- Result: changes_requested
- Android Findings: `POST_NOTIFICATIONS` 声明和 Android 13+ 运行时请求方向可以保留为兼容修复，但不是根因闭环。小米 10 Pro release 证据显示 session、metadata、queue 已出现但 `active=false`、`PlaybackState state=0`；新增 logcat 和 APK 资源证据进一步指向自定义收藏 action 的 `androidIcon` 资源在 release APK 中不可用，导致 `CustomAction` 构建异常。accepted 前必须看到 `aapt dump resources` 证明图标资源进入 APK或已改用有效资源、小米 10 release 播放 logcat 无该异常、active MediaSession、media notification 和四槽位可用。
- iOS Findings: 不涉及。
- HarmonyOS Findings: 不涉及。
- Architect Findings: `v1.0.0` tag 已存在，但发布状态已降为 blocked。修复闭环前不继续把当前 release APK 当作正式交付包。当前小米 10 Pro 已可用于 release 验证：release 包安装成功且通知权限已授权。Android lane 必须按“恢复既有系统播控能力”验收，优先修复 CustomAction icon 资源进入 release APK 或改用有效资源；拿到 `aapt dump resources`、无异常 logcat、active MediaSession、notification controls 和四槽位可用证据后，再回 architect lane 发 `review_request`。
