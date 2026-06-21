# HarmonyOS AVSession 播放中心排查

## 背景

AI Music 的 HarmonyOS 播放中心由 `third_party/just_audio_harmonyos` 内的 ArkTS 插件直接接入 `AVSessionKit`。播放中心和后台长时任务是两件事：前台播放中心可见、可控依赖 `AVSession`；后台持续播放才需要连续任务能力。本项目当前不为播放中心新增 `BackgroundTasksKit`、`KEEP_BACKGROUND_RUNNING` 或 `backgroundModes: audioPlayback`。

## 关键实现

- 用真实 `UIAbilityContext` 调用 `avSession.createAVSession(context, 'AI Music', 'audio')`。
- 创建会话后先注册 `play/pause/stop/playNext/playPrevious/seek/setLoopMode`，再发布 `AVMetadata`、`AVQueueItem` 和 launch ability，最后 `activate()`。
- 华为文档要求元数据和控制命令注册完成后再激活；因此 `setAVMetadata()` 需要 `await`，不能 fire-and-forget。
- 没有真实封面时不要随手写不确定的 `mediaImage` URI，避免参数校验失败导致会话无法激活。
- 播放状态要同步 `state/position/duration/bufferedTime/speed/activeItemId/loopMode`；状态切换、seek、buffering 起止强制刷新，普通进度更新可以节流。

## 常用验证命令

无线 HDC 目标：

```bash
hdc -t 192.168.31.53:10178 shell aa start -d 0 -a EntryAbility -b com.qi.ai.music
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_session_info'
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_metadata'
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_controller_info'
hdc -t 192.168.31.53:10178 shell hidumper -s BackgroundTaskManager
```

预期：

- `AVSessionService` 能看到 `AI Music` 会话，且播放时为 active。
- metadata 里有当前曲目的 `assetId/title/artist/duration`。
- controller 能看到播放状态、进度和有效控制命令。
- `BackgroundTaskManager` 不应出现 AI Music 新增连续后台任务。

## 常见坑

- `just_audio_platform_interface` 不会把 Dart `AudioSource.tag` 自动序列化给原生 MethodChannel；原生侧不能假设能拿到 Dart 的 `MediaItem`。
- 如果只能从 `hidumper -show_metadata` 看到旧数据，但 `-show_session_info` 的 Count 为 0，说明当前没有活跃 session，通常是播放链路未触发或 session 已释放。
- HDC 自动点击 Flutter 圆形按钮可能不稳定；最终播放中心验收仍以手动真机播放和 hidumper 为准。
