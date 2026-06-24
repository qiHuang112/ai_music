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
- `MediaItem`、`PlaybackState`、`controls`、`androidCompactActionIndices` 在 release 包播放链路中没有正确发布。
- release 构建脚本、manifest、R8/proguard、签名或安装覆盖导致系统媒体会话未被系统识别。

## 范围

包含：

- Android release 包播放后的系统媒体控件、通知、前台服务、MediaSession 和 audio_service 链路。
- `android/`、`lib/src/playback/`、`lib/src/application/` 中与系统播控发布相关的最小修复。
- Android release 构建脚本、manifest、proguard/R8 规则、notification resource 或权限声明。
- Android 小米 10 Pro 开发机自测；如 product 已授权，可在小米 17 Pro 复核安装。

不包含：

- 1.0.1 播放状态持久化。
- 1.0.1 歌词/封面 metadata pipeline。
- HarmonyOS HAP 或 iOS 宿主修复。
- FLAC/Auto 搜索体验的新功能扩展。

## 验收标准

- Android release 包安装后，播放一首歌曲，系统播控中心必须重新出现。
- 四槽位顺序保持既定口径：收藏/取消收藏、上一首、播放/暂停、下一首。
- 收藏、上一首、播放/暂停、下一首均可用。
- `dumpsys media_session` 能看到 AI Music active session、metadata、playback state 和 controls/custom actions。
- 通知或系统媒体控件可见；如受 MIUI/Android 版本策略限制，需提供具体系统证据说明不是 App 未发布。
- release 包验证必须覆盖小米 10 Pro 开发机；如安装到小米 17 Pro，需要明确 product 授权来源和端口。
- 修复后重新构建 Android arm64 release 包，记录路径、大小、sha256、安装设备和 `dumpsys package` 信息。

## Android lane 必须提供的定位证据

- debug 包是否正常出现系统播控中心。
- release 包是否复现系统播控中心消失。
- 播放后 `dumpsys media_session` 关键字段：session 是否存在、active 状态、metadata、state、actions、custom actions。
- 播放后 `dumpsys notification` 或等价命令中是否有 AI Music media notification。
- `logcat` 中 audio_service、MediaSession、foreground service、notification 相关错误。
- release 构建是否启用了 shrink/minify/resource shrink；如启用，需要验证 proguard keep 和资源是否被裁。

## 消息记录

- 2026-06-24 type=bug_report lane=product status=urgent_p1 summary=产品反馈最新 Android release 包安装到小米 17 Pro 后系统播控中心没了，要求作为 1.0.0 release blocker，暂停正式 release，先让 Android 定位。
- 2026-06-24 type=task lane=architect status=assigned summary=架构师将该问题切给 Android lane 主责定位，1.0.1 新功能不得覆盖该 P1。
- 2026-06-24 type=status lane=android status=in_progress summary=Android lane 静态确认 release manifest 中 `AudioService`、`MediaButtonReceiver`、`AudioServiceActivity` 均存在，release 未启用 minify/R8；小米 17 Pro `appops` 显示 `POST_NOTIFICATION: ignore`，且当前 `dumpsys media_session` 只看到 Last MediaButtonReceiver/Audio playback uid，未见 active AI Music session，notification 列表未见 AI Music media notification。
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=允许补 `POST_NOTIFICATIONS` 声明和 Android 13+ 运行时请求作为兼容修复，但该点不能作为唯一根因；accepted 前必须证明 release 播放后 active media session、media notification 和四槽位均恢复。
- 2026-06-24 type=review_request lane=android status=review summary=Android lane 已完成最小补丁并构建安装 release 包：Manifest 声明 `POST_NOTIFICATIONS`，`MainActivity` 在 Android 13+ 请求通知权限，回归测试覆盖声明和请求逻辑；小米 17 Pro 已出现系统权限弹窗但设备屏幕黑/弹窗不可操作，`pm grant` 不被 user build 允许，当前仍等待用户允许通知权限后复验。
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=代码方向无明显架构风险，但 P1 未达 accepted：缺少用户允许权限后 release 播放的 active media session、media notification 和四槽位可用证据；测试和知识库措辞需避免把 `POST_NOTIFICATIONS` 写成官方通用唯一根因。

## Review 结果

- Reviewer Lane: architect
- Result: changes_requested
- Android Findings: `POST_NOTIFICATIONS` 声明和 Android 13+ 运行时请求方向可以继续，`MainActivity` 仍继承 `AudioServiceActivity`，未发现破坏 audio_service 初始化的明显问题。但当前只证明了权限请求弹窗出现，还没有证明产品允许权限后 release 播放能恢复 active MediaSession、media notification 和四槽位。`test/release_config_test.dart` 的 reason 文案和知识库现象说明需收敛为“小米/Android 13+ release 兼容条件”，不要表述成 Android 官方一定隐藏 media notification。
- iOS Findings: 不涉及。
- HarmonyOS Findings: 不涉及。
- Architect Findings: `v1.0.0` tag 已存在，但发布状态已降为 blocked。修复闭环前不继续把当前 release APK 当作正式交付包。Android lane 完成 wording 回改并拿到用户允许通知后的 release 播放证据后，再回 architect lane 发 `review_request`。
