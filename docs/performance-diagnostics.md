# 页面跳转卡顿：记录与定位

2026-11-10 建立。目标：用户说“某处跳转卡”，不靠现场复现，先从他上传的日志里找到是哪次跳转、卡在哪一类原因，再按需深挖。

## 三层

| 层 | 在哪 | 什么时候用 | 能回答 |
|---|---|---|---|
| ① 应用内跳转体检 | `lib/src/application/transition_profiler.dart`，release 常开 | 一直在记；用户在“设置→上传日志”后可读 | 哪次跳转卡、掉几帧、UI 还是光栅、是否本进程首次、过场中谁通知了全应用 |
| ② 报告汇总 | `python3 tool/perf_transitions.py [报告ID或文件]` | 拿到上传报告或 `operations.jsonl` 后 | 按页面汇总次数／卡顿／最差帧，列出最卡的几次及线索 |
| ③ 时间线深挖 | `dart run tool/frame_probe.dart`，需 profile 包 | ② 指出页面和线索类别后 | 每一帧 UI／光栅、着色器编译数、按控件汇总的自身耗时 |

### ① 记什么

`TransitionProfiler` 是一个 `NavigatorObserver`，在每次 push／pop／返回手势／弹出菜单与对话框、底部 Tab 切换（`MusicHomePage._selectTab`）、页内分区切换（如下载页三个分区，调用 `TransitionProfiler.noteSwitch`）时开一个观测窗：动画时长＋200 ms。窗内每帧记下引擎帧号（`PlatformDispatcher.frameData.frameNumber`）；release 的帧耗时（`FrameTiming`）会晚到 1 s 内批量回调，按帧号对回这次跳转后再判定。平时只有每帧一次空判断。

全应用级的 `ChangeNotifier`（`MusicController`、`OnlinePlaylistTasks`）在 `notifyListeners` 里调用 `TransitionProfiler.noteNotify(this)`；只有观测窗开着时才取调用栈，记下第一个非通知框架的调用者（release 栈里保留类名与方法名）。新增全应用级通知源时照此接入。

判定为卡顿（写 `perf.transition`）：过场帧掉帧 ≥2、UI＋光栅超预算帧 ≥3、首帧 UI >4 个预算、任一帧光栅 >3 个预算，或滑入刚结束那几帧 UI >3 个预算。过场之后页面安静下来的稀疏帧（如背景 15 fps）不算掉帧。每 40 次跳转、进入后台、上传日志前各写一条按页面的汇总 `perf.transitions`。

`perf.transition` 字段：`kind`（push/pop/swipe_back/popup/popup_close/tab/section）、`from`、`to`（路由名；未命名的 `AppPageRoute` 用页面控件类型名，根路由为 `home`）、`firstOpen`（本进程首次）、`frames`、`dropped`、`overBudgetUi`／`overBudgetRaster`（首帧以外）、`firstUiMs`／`firstRasterMs`、`worstUiMs`／`worstRasterMs`、`afterSlideWorstUiMs`、`budgetMs`、`hints`、`notifies`（`source`、相对首帧的帧序、`caller`），以及皮肤、是否在播放。

### 线索 → 已知原因 → 修法

| hint | 含义 | 本项目遇到过的原因与修法 |
|---|---|---|
| `first_frame_build` | 新页面第一帧（Hero 离屏布局帧）UI 很重 | 列表首屏行多且每行重。安卓上 `AppPageRoute` 已把慢首帧从滑动计时里扣掉（`SlowFirstFrameVsync`），不会再“跳一下”，但仍是点击到开始滑动的延迟；减行成本或推迟非首屏内容 |
| `notify_mid_slide` | 过场中有全应用通知且 UI 超预算 | 看 `caller`。2026-11-10：`recordPlaylistUsage`／`loadMetadataForCurrentTrack` 本该在 `afterRouteEntrance` 后执行，但离屏首帧让它误判“已滑入”。全应用通知一律放到 `afterRouteEntrance` 之后 |
| `notify_after_slide` | 滑入刚结束时一次通知让整应用重建一大帧 | 同上的 `recordPlaylistUsage`（41 ms）。不在过场内，但用户立刻滑动会顿；缩小通知范围（只通知用到的监听者） |
| `ui_mid_slide` | 过场中 UI 超预算但无全应用通知 | 页面自己重复重建：如 `StreamBuilder` 每次 build 新建流＋subject 重放（已用 `DistinctStreamBuilder`）；Tab 切换时正文尺寸变化导致 `IndexedStack` 全部重排、根 `setState` 重建全部 Tab（已修）；图片解码 |
| `raster_first_open` | 本进程首次打开且光栅很重 | Skia 现场编译着色器（77 因 Adreno 驱动关闭了 Impeller）。常用页面可在启动空闲时预画（`PlayerWarmUp`）；注意过场本身的效果（滑入边缘阴影、半透明图层）静态预画覆盖不到 |
| `raster_heavy` | 非首次，光栅持续超预算 | ① 整页半透明（`FadeTransition` 触发 saveLayer）叠在复杂背景/模糊上：自带不透明背景的页面（播放页、歌词）已不淡入、下层不淡出（`AppPageRoute.coversBackdrop`）。② 超时帧每隔约 66 ms 出现一次＝撞上背景 15 fps 刷新（极光一步要重画整片天空并让玻璃栏重新模糊，约 14 ms）：背景类 `AmbientClock(backdrop: true)` 在页面过场和 Tab 切换期间暂停（`AmbientClock.quietBackdrops`），2026-11-10 返回首页因此每次掉 3–6 帧。新增背景动画用 `backdrop: true` |

## 操作

1. 让用户在“设置→上传日志”上传（局域网服务 `192.168.31.167:8788`，报告落在 `/Users/huangqi/ClaudeProject/releases/ai_music/diagnostics/`）。
2. `python3 tool/perf_transitions.py` 看最新报告（或带报告 ID）。先看汇总表里卡顿多的页面，再看“最卡的几次”的线索和 `caller`。
3. 需要看到具体控件或着色器时，在开发手机上装 profile 包（开发证书、保留数据：`flutter build apk --profile --target-platform android-arm64 --build-number <大于已装>`，`adb install -r` 前核对序列号），冷启动后：

   ```sh
   dart run tool/frame_probe.dart --device 192.168.31.78:38015 --tap 586,1180 --widgets
   ```

   `--tap` 用 adb 点击触发跳转，`--back` 按返回键（都不带则录 `--seconds` 秒手动操作）；注入前会确认前台是“来听”，否则不按任何键直接退出（别人正在用手机时不会误点到其他应用）；`--widgets` 打开控件级构建与布局计时（有额外开销，只看相对比例）。输出触摸后 450 ms（`--window`）内逐帧 UI／光栅（`*` 为超预算）、掉帧、着色器编译数，以及 UI 线程按名称汇总的自身耗时；完整时间线存 `build/frame_probe/`，可拖进 ui.perfetto.dev。冷启动后首次与再次各测一次，区分着色器编译与稳定开销。
4. 修复后用同一方法对比数字，并看 ① 的日志是否不再出现该页面。

## 约定

- 新的页面跳转都用 `AppPageRoute`；需要稳定名字时给 `RouteSettings(name:)`。
- 会让全应用重建的工作（通知、加载）放到 `afterRouteEntrance` 之后；新增全应用级 `ChangeNotifier` 时在 `notifyListeners` 里接 `TransitionProfiler.noteNotify`。
- 页内带动画的切换（分区、分页）调用 `TransitionProfiler.noteSwitch`。
- 卡顿排查结论写进当天工作日志，并补到上表“已知原因”。
