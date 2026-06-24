# Android release 系统播控通知排查

## 背景

AI Music 1.0.0 arm64 release 包安装到小米 17 Pro 后，产品反馈 Android 系统播控中心消失。旧 debug 包曾能显示播控，release 包的 `AudioService` 和 `MediaButtonReceiver` 也都还在 Manifest 中。

## 现象

- `dumpsys package com.qi.ai.music` 能看到 `com.ryanheise.audioservice.AudioService` 和 `MediaButtonReceiver`。
- `dumpsys media_session` 能看到 `Last MediaButtonReceiver` 指向 AI Music。
- `appops get com.qi.ai.music` 显示 `POST_NOTIFICATION` 为 ignored。
- 允许通知权限后，release 播放仍可能没有播控中心；这时不能继续停在权限问题。
- 本轮关键证据是 logcat 出现 `IllegalArgumentException: You must specify an icon resource id to build a CustomAction`，同时 release APK 资源表中缺少 `ic_notification_favorite*`。这说明自定义收藏 action 的 icon 资源在 release APK 中不可用，`audio_service` 构建 CustomAction 失败，进而影响 playbackState / notification 发布。

## 排查命令

```bash
adb -s <device> shell dumpsys package com.qi.ai.music
adb -s <device> shell appops get com.qi.ai.music POST_NOTIFICATION
adb -s <device> shell dumpsys media_session
adb -s <device> shell dumpsys notification --noredact
aapt dump resources build/release/ai-music-v1.0.0-android-arm64.apk | grep ic_notification_favorite
```

重点看：

- `requested permissions` 是否包含 `android.permission.POST_NOTIFICATIONS`。
- `runtime permissions` 中 `POST_NOTIFICATIONS` 是否 granted。
- `dumpsys media_session` 中 `com.qi.ai.music/media-session` 是否 active、是否有 metadata。
- notification 列表里是否存在 AI Music 的 media notification。
- release APK 资源表里是否包含 `ic_notification_favorite` 和 `ic_notification_favorite_border`。
- logcat 是否还出现 `You must specify an icon resource id to build a CustomAction`。

## 解决方案

- Manifest 增加 `android.permission.POST_NOTIFICATIONS`。
- Android 13+ 启动时请求运行时通知权限。
- 增加 `res/raw/keep.xml`，用 `tools:keep` 保留 `@drawable/ic_notification_favorite` 和 `@drawable/ic_notification_favorite_border`，避免 release 资源裁剪后 CustomAction icon resource id 无效。
- 回归测试覆盖 Manifest 声明、MainActivity 请求逻辑和 keep 规则。

## 注意事项

- 高版本 MIUI user build 可能不允许 `adb shell pm grant` 直接授予通知权限，需要用户在弹窗或系统设置中点允许。
- 通知权限只是兼容项，不是本 P1 的 accepted 条件。accepted 必须看到播放后 active MediaSession、metadata、foreground media notification 和四槽位可见可点。
- 如果权限已允许但仍无播控，优先查 `audio_service` CustomAction icon、playbackState 和 foreground notification 发布链路。
- 小米 17 Pro 是产品验收机，默认只在产品授权时安装或验证；开发自测优先用小米 10 Pro。
