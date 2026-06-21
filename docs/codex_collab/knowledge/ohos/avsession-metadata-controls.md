# HarmonyOS AVSession 元数据与控制能力

## 背景

AI Music 的 HarmonyOS 播控中心接入后，系统面板能出现但仍可能缺少歌曲信息、封面、循环模式、点赞状态，或者暂停后从系统播控中心恢复失败。这类问题优先在 vendored `just_audio_harmonyos` 的 `MediaAvPlayer.ets` 层处理，避免触碰公共 Dart 播放业务。

## 处理策略

- 系统 `play` 回调不能只依赖 Dart 再发一次播放命令；原生层需要先把 `isPlaying/state` 更新为播放目标态并同步 `AVPlaybackState`，再调用 `AVPlayer.play()`，否则系统播控图标可能停在暂停态。
- 系统 `pause` 回调也要先同步目标暂停态；如果当前 AVPlayer 已经不是 `playing`，仍要向 AVSession 发布暂停态并返回成功，避免系统播控按钮卡住。
- 对照东财 `AvSessionController` / `AudioPlayManager` 后确认：系统 `play/pause` 回调应反向驱动业务播放器入口，而不是只直接操作底层 `AVPlayer`。否则歌曲可能暂停了，但 Dart/just_audio/audio_service 仍认为正在播放，后续 timeUpdate、buffering 或控制状态同步可能把 AVSession 刷回 playing。
- AI Music 当前做法是：AVSession 收到 `play/pause` 后，先发布目标 `AVPlaybackState`，再通过 `com.qi.ai_music.ohos_media_controls` 回到 Dart `MusicAudioHandler.play()/pause()`，让 Dart 播放状态、原生 AVPlayer 和系统播控同源；原生直接 `play()/pause()` 只保留为 Dart handler 缺失时的兜底。
- `AVPlaybackState.PLAYBACK_STATE_PAUSE` 不能把 `speed` 写成 `0`。在 `LNG0223804000125` 上复现到：系统 `pause` 命令到达、音频也暂停，但 `setAVPlaybackState({ state: PAUSE, speed: 0 })` 会被 AVSession 拒绝并打印 `SetAVPlaybackState: state not valid`，`show_controller_info` 仍停在 `playing`。参考东财实现后改为暂停态也发布当前倍率，例如 `speed: 1.0`，系统播控中心才能稳定切成 paused/play 图标。
- `just_audio_platform_interface` 的 MethodChannel 消息不会把 Dart 的 `MediaItem` tag 序列化给 HarmonyOS 原生插件。AI Music 用 `com.qi.ai_music.ohos_media_controls` 私有通道只在 OpenHarmony 平台补传当前 `MediaItem.id/title/artist/artUri/duration`，避免改动 Android/iOS 播放路径。
- `AVPlaybackState` 的 `loopMode` 和 `isFavorite` 必须和应用内状态同源。AI Music 通过 `com.qi.ai_music.ohos_media_controls` 让系统 `setLoopMode/toggleFavorite` 回调进入 Dart，再由 `MusicController.setPlaybackMode()` / `toggleFavorite()` 写入真实应用状态，最后同步回 AVSession。
- HarmonyOS 的 `LoopMode` 需要映射到 AI Music 四种模式：`LOOP_MODE_SEQUENCE -> sequential`、`LOOP_MODE_LIST -> loopAll`、`LOOP_MODE_SINGLE -> repeatOne`、`LOOP_MODE_SHUFFLE -> shuffle`。不能只用 `AudioServiceRepeatMode`，因为它无法表达随机播放。
- 当前系统面板点击左侧播放模式按钮时，实际发的是 `cmd=setLoopMode`，参数可能仍是当前模式或系统内部值；如果原样应用参数，会出现点击后 `sequence -> sequence`，产品看到“没生效”。AI Music 需要把这个回调按应用内按钮语义处理为“切到下一个模式”：`sequence -> list -> single -> shuffle -> sequence`。当前 SDK 对 `setTargetLoopMode` 注册会报 `eventName is invalid`，不要注册这个无效事件。
- 系统面板可能保留 loop/favorite 固定位置；如果发布了 `loopMode/isFavorite` 但没有注册对应回调，产品会看到灰色不可点击入口。当前验收口径是“可见即可用”，因此必须同时发布状态和注册回写回调。
- 播控中心封面优先使用 Dart 当前 `MediaItem.artUri`。没有 `artUri` 时，再用临时 `AVMetadataExtractor.fetchAlbumCover()` 从当前音频文件抽取内嵌封面；临时 extractor 使用独立 fd，读完立即 release/close，避免和播放 fd、预加载 next player 或共享 metadata extractor 互相污染；两者都失败时才降级为默认图。
- `setAVMetadata()` 内部有异步封面读取，必须在 `await` 前快照 `musicIndex/songItem/avMetadata/lifecycleGeneration`，返回后确认仍是同一曲目再调用 `setAVMetadata()`，防止快速切歌时 assetId、title、artist、mediaImage 错配。

## 构建注意

如果工作区有公共 Dart/UI 改动，`OHOS_CODESIGN=true tool/build_ohos_hap.sh` 可能先被 Flutter 编译挡住，导致无法验证 ArkTS。例如 `flutter_ohos` 不支持某些 Flutter 新参数时会在 `FlutterTask` 阶段失败。验证鸿蒙插件时可以临时 stash 这些公共 Dart 改动，构建完成后必须立即 `git stash pop` 恢复，且不能把它们纳入 ohos 提交。

## 验证命令

```bash
OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh
hdc -t 192.168.31.53:10178 install -r build/ohos/hap/entry-default-signed.hap
hdc -t 192.168.31.53:10178 shell aa start -d 0 -a EntryAbility -b com.qi.ai.music
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_metadata'
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_session_info'
```

播放后再执行 `hidumper` 才能看到活跃 session；仅启动 App 但未播放时，`Session Information: Count : 0` 是正常现象。

系统播控状态复测时需要同时抓点击前后：

```bash
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_session_info'
hdc -t 192.168.31.53:10178 shell hidumper -s AVSessionService -a '-show_controller_info'
perl -e 'alarm 60; exec @ARGV' hdc -t 192.168.31.53:10178 shell hilog \
  | grep -E 'MediaAvPlayer|AudioPlayer|AVSession play|AVSession pause|AVSession loop|SetAVPlaybackState|on pause|on play|setLoopMode'
```

如果日志中能看到 `on pause` 和 `SetAVPlaybackState request state=PAUSE`，但 `show_controller_info` 仍显示 playing，优先检查是否有后续 `timeUpdate/buffering/updateControlState` 又调用 `syncCurrentAVSessionPlaybackState()` 并覆盖状态。若日志没有 `on pause`，先查命令注册和 session active/topsession。

AM-20260621-003 在 `LNG0223804000125` 上的最终自验关键结果：

- `pause`：点击系统大面板中间按钮后，`show_controller_info` 当前 session 从 `state: playing` 变为 `state: paused`，`speed: 1.000000`，session id 不变。
- `play`：再次点击中间按钮后，当前 session 回到 `state: playing`。
- `loop`：点击左侧播放模式后，当前 session `loopmode` 从 `sequence` 变为 `list`；连续点击可继续到 `single`、`shuffle`。
- `favorite`：点击右侧心形后，当前 session `is favorite` 从 `false` 变为 `true`。
