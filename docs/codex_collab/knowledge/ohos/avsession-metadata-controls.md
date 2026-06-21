# HarmonyOS AVSession 元数据与控制能力

## 背景

AI Music 的 HarmonyOS 播控中心接入后，系统面板能出现但仍可能缺少歌曲信息、封面、循环模式、点赞状态，或者暂停后从系统播控中心恢复失败。这类问题优先在 vendored `just_audio_harmonyos` 的 `MediaAvPlayer.ets` 层处理，避免触碰公共 Dart 播放业务。

## 处理策略

- 系统 `play` 回调不能只依赖 Dart 再发一次播放命令；原生层需要把 `isPlaying` 置回 true，并在当前 `AVPlayer` 为 `paused/prepared` 时直接走 `playingState()`。
- `just_audio_platform_interface` 不保证把 Dart 的 `MediaItem` tag 序列化给 HarmonyOS 原生插件。缓存文件名通常包含 `artist-title-id.ext`，原生层可作为歌名/歌手兜底。
- `AVPlaybackState` 可以同步 `loopMode` 和 `isFavorite`。当前未接公共收藏业务时，点赞先在 AVSession 层做本地临时状态，避免系统按钮无响应。
- 播控中心封面可用应用图标转 `PixelMap` 后写入 `AVMetadata.mediaImage`。不要使用未验证的本地字符串 URI。

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
