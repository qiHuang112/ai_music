# HarmonyOS just_audio 队列刷新与预加载 ownership

## 背景

AM-20260623-003 复现到：先播放 3 首自建歌单 `qi`，再搜索/下载多首 `yellow` 并逐个点击播放时，HarmonyOS 侧会出现 UI/AVSession 已显示目标歌曲，但原生 AVPlayer 播放旧歌、停在 stopped 或无声。Android 同场景未复现，因此优先排查 vendored `just_audio_harmonyos`。

## 现象

- 第 1/2 条搜索结果有时能更新歌名，但 duration 或实际音源仍像上一队列里的歌曲。
- 第 3/4 条搜索结果更容易无声，`AudioPolicyService` 里没有活跃 renderer，日志进入 `loadAssent()` index 越界分支。
- `hidumper -s AVSessionService -a '-show_metadata'` 只证明系统 metadata 已更新，不能证明 AVPlayer 实际 data source 已切到同一首歌。

## 根因

`AudioPlayer.getAudioSource()` 会按 just_audio 传来的 `audioSource.id` 缓存 `MediaSource`。full `load` 时如果不清空这张 `mediaSources` map，而 just_audio 在新队列里复用了 root/children id，HarmonyOS 原生层会复用上一轮 root/children，导致 `MediaAvPlayer.songList` 仍是旧队列。

另外，原生预加载的 `avPlayerNext` 可能已经持有上一队列的 next source。full `load` 只递增 generation 不能释放已经就绪的旧 next player；如果新队列点击 index 恰好等于旧 `preMusicIndex`，旧 next player 可能被升格成当前播放器。

## 修复原则

- full `load` 必须重建原生 source tree，不能复用旧 `mediaSources`。
- full `load` 必须释放/清空旧 `avPlayerNext` 和 pending next player，避免旧队列预加载播放器跨队列升格。
- `loadAssent()` 遇到 index 越界、source 不存在、uri 缺失或 `loadUri()` 失败时，必须通过错误通道回传 Dart，不能只同步 AVSession error 后静默 return。
- 本地文件加载日志至少记录 index、队列长度、uri/path 和 file size，便于 HDC 自验证“点击行、AVSession metadata、ArkTS source/path/fd、AVPlayer 实际播放源”是否一致。

## 验证命令

```bash
hdc -t 192.168.31.53:10178 shell hilog -r
hdc -t 192.168.31.53:10178 shell aa start -d 0 -a EntryAbility -b com.qi.ai.music
hdc -t 192.168.31.53:10178 shell "hidumper -s AVSessionService -a '-show_metadata'"
hdc -t 192.168.31.53:10178 shell "hidumper -s AudioPolicyService -a '-s'"
hdc -t 192.168.31.53:10178 shell "hilog -z 4000 -P $(hdc -t 192.168.31.53:10178 shell pidof com.qi.ai.music | tr -d '\r')"
```

复测路径：

1. 先进入自建歌单 `qi`，播放至少 3 首不同歌曲，让旧队列和 next preload 都跑起来。
2. 搜索 `yellow`，下载/确认已有至少 3 首不同结果。
3. 逐个点击第 1/2/3/4 条播放。
4. 每次点击后对照 UI 标题、`show_metadata` 标题/歌手、`loadAssent source` 日志里的 index/length/uri，以及 `load file data src current` 的 path/size。

## 后续复用

以后只要出现“系统播控 metadata 正确但实际播放旧歌/无声”，不要只查 AVSession。先确认 native `songList` 长度和当前 `loadAssent source` 是否来自本次 full load，再确认是否有旧 `avPlayerNext` 被升格。
