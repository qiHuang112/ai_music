# 2026-06-21 鸿蒙 AVSession 播控中心最小实验策略

Lane: architect
Request: AM-20260621-002
Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Related Commit: 769dee8, 97bf894

## 背景

鸿蒙 lane 曾一次性重构 `MediaAvPlayer.ets` 的 AVSession metadata、queue、playbackState、launch ability、extras 和命令回调链路。用户真机验证发现不但没有接上播控中心，还破坏了播放能力，随后用 `97bf894` 回退。

## Review 判断

- `MediaAvPlayer` 同时承载 just_audio 播放状态机、fd 生命周期、下一首预加载、metadata 读取和 AVSession 发布，属于高风险核心链路。
- 播控中心接入不能用大范围重构证明正确，应先保护“能播放”这个基线。
- AVSession 的 `activate()` 顺序要严格围绕命令、metadata 和 playbackState 初始化，但任何异步回调都可能绕过表面顺序。

## 后续拆分原则

- 第一步只做可观测性：保留当前播放链路，只增加 `hidumper AVSessionService` 能验证到的最小 session 信息。
- 第二步只补一个能力点：例如只调整 metadata 或只调整 launch ability，不要同时碰 queue、loopMode、预加载和播放器状态机。
- 每一步都必须真机手动播放验证，不能只靠 HDC 自动点击。
- 只有单步验证通过后，才能进入下一步。

## Review 检查清单

- 是否改动了 `loadAssent()`、`stateCall`、`playingState()`、预加载或 fd ownership；如果改了，默认高风险。
- 是否在初始化完成前暴露半成品 `this.session`；如果暴露，要检查所有状态回调是否可能提前 activate。
- 是否新增全量 queue 发布；大歌单可能带来性能和时序风险，应单独实验。
- 是否把“前台播控中心可见”和“后台持续播放”混在一个提交里；这两个需求必须分开。

## 分发规则

这类问题只涉及鸿蒙宿主和 vendored 鸿蒙音频插件，默认只回 `ohos` lane。只有改到 Dart 播放 API、队列语义或跨端用户行为时，才通知 `android` lane。
