# HarmonyOS AVSession 元数据与控制能力

## 背景

AI Music 的 HarmonyOS 播控中心接入后，系统面板能出现但仍可能缺少歌曲信息、封面、循环模式、点赞状态，或者暂停后从系统播控中心恢复失败。这类问题优先在 vendored `just_audio_harmonyos` 的 `MediaAvPlayer.ets` 层处理，避免触碰公共 Dart 播放业务。

## 处理策略

- 系统 `play` 回调不能只依赖 Dart 再发一次播放命令；原生层需要把 `isPlaying` 置回 true，并在当前 `AVPlayer` 为 `paused/prepared` 时直接走 `playingState()`。
- `just_audio_platform_interface` 不保证把 Dart 的 `MediaItem` tag 序列化给 HarmonyOS 原生插件。缓存文件名通常包含 `artist-title-id.ext`，原生层可作为歌名/歌手兜底。
- `AVPlaybackState` 可以展示 `loopMode`，但系统 `setLoopMode` 回调如果只改原生 `playMode`，Flutter UI 和公共播放状态不会更新。当前只做 App -> AVSession 展示同步，未接公共 Dart 回写前不注册 `setLoopMode`。
- 收藏/点赞是 AI Music 公共 Dart 业务状态，当前 `just_audio_harmonyos` 播放源只解码 `id/uri/type/header`，没有 `favorite` 或持久化回调。未接公共收藏业务前不能注册 `toggleFavorite`，否则系统按钮会制造一个重启即丢、App 不知道的临时状态。
- 播控中心封面优先用临时 `AVMetadataExtractor.fetchAlbumCover()` 从当前音频文件抽取内嵌封面，临时 extractor 使用独立 fd，读完立即 release/close，避免和播放 fd、预加载 next player 或共享 metadata extractor 互相污染；没有内嵌封面或解析失败时才降级为默认图。AI Music 的网络 `artUri` 当前在 Dart `AudioSource.tag` 中，鸿蒙插件还没有解码 `tag`，因此网络封面要完整进入系统播控，需要后续公共层/插件协议补传。
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
