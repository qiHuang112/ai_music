# HarmonyOS AVSession 元数据与控制能力

## 背景

AI Music 的 HarmonyOS 播控中心接入后，系统面板能出现但仍可能缺少歌曲信息、封面、循环模式、点赞状态，或者暂停后从系统播控中心恢复失败。这类问题优先在 vendored `just_audio_harmonyos` 的 `MediaAvPlayer.ets` 层处理，避免触碰公共 Dart 播放业务。

## 处理策略

- 系统 `play` 回调不能只依赖 Dart 再发一次播放命令；原生层需要先把 `isPlaying/state` 更新为播放目标态并同步 `AVPlaybackState`，再调用 `AVPlayer.play()`，否则系统播控图标可能停在暂停态。
- 系统 `pause` 回调也要先同步目标暂停态；如果当前 AVPlayer 已经不是 `playing`，仍要向 AVSession 发布暂停态并返回成功，避免系统播控按钮卡住。
- `just_audio_platform_interface` 的 MethodChannel 消息不会把 Dart 的 `MediaItem` tag 序列化给 HarmonyOS 原生插件。AI Music 用 `com.qi.ai_music.ohos_media_controls` 私有通道只在 OpenHarmony 平台补传当前 `MediaItem.id/title/artist/artUri/duration`，避免改动 Android/iOS 播放路径。
- `AVPlaybackState` 的 `loopMode` 和 `isFavorite` 必须和应用内状态同源。AI Music 通过 `com.qi.ai_music.ohos_media_controls` 让系统 `setLoopMode/setTargetLoopMode/toggleFavorite` 回调进入 Dart，再由 `MusicController.setPlaybackMode()` / `toggleFavorite()` 写入真实应用状态，最后同步回 AVSession。
- HarmonyOS 的 `LoopMode` 需要映射到 AI Music 四种模式：`LOOP_MODE_SEQUENCE -> sequential`、`LOOP_MODE_LIST -> loopAll`、`LOOP_MODE_SINGLE -> repeatOne`、`LOOP_MODE_SHUFFLE -> shuffle`。不能只用 `AudioServiceRepeatMode`，因为它无法表达随机播放。
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
