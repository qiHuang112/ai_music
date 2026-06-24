# AM-20260624-003 状态栏和播放页滑动切歌

Status: assigned
Owner Lane: android
Source Thread: 019eea5b-9b46-7f92-a35c-7d080ea1e986
Target Version: 1.0.1
Priority: P2 after AM-20260624-001 worktree starts or when Android has capacity
Base Branch: release/1.0.1
Work Branch: feature/1.0.1/AM-20260624-003-swipe-to-skip
Worktree Path: /Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260624-003
Merge Branch: release/1.0.1
Created: 2026-06-24
Updated: 2026-06-24

## 目标

- 底部播放状态栏支持左右滑动切歌。
- 单曲播放详情页支持左右滑动切歌。
- 保留现有点击上一首/下一首按钮能力，滑动只是更顺手的补充交互。

## 责任边界

- Android lane 是公共 Flutter/Dart UI 和播放队列交互 owner。
- Architect lane 负责 review、冲突裁决和合入。
- ohos/iOS lane 只在平台手势或构建验证发现平台差异时参与。

## 范围

包含：

- 底部 mini player / 播放状态栏横向滑动手势。
- 播放详情页横向滑动手势。
- 手势触发上一首/下一首时复用现有播放队列切歌逻辑。
- 无上一首/下一首、单曲队列、加载中、错误态的安全处理。
- Widget/controller 测试覆盖滑动方向和边界。

不包含：

- Android 系统播控中心四槽位。
- 随机播放短听排除策略。
- 播放状态持久化。
- 歌词/封面 metadata pipeline。
- 平台宿主手势能力或原生播放器改动。

## 交互口径

- 在底部状态栏整体区域左滑：切到下一首。
- 在底部状态栏整体区域右滑：切到上一首。
- 在播放详情页主体区域左滑：切到下一首。
- 在播放详情页主体区域右滑：切到上一首。
- 滑动阈值要避免和轻微误触冲突；不应影响点击播放/暂停、收藏、上一首/下一首按钮。
- 如果当前队列不能切歌，应保持当前歌曲并给出不打扰的状态处理，不能崩溃。

## 验收标准

- 底部状态栏左滑能切下一首，右滑能切上一首。
- 播放详情页左滑能切下一首，右滑能切上一首。
- 现有点击上一首/下一首按钮不回退。
- 单曲队列或没有可切歌曲时，滑动不会崩溃，不会误改播放状态。
- 随机/循环/单曲循环等模式下，滑动复用现有手动切歌语义。
- Android 小米 10 Pro 自测通过；小米 17 Pro 只在 product 授权时安装验收。

## 测试要求

- `flutter test` 全量通过。
- `flutter analyze` 通过。
- Widget 测试覆盖 mini player 左滑/右滑。
- Widget 测试覆盖播放详情页左滑/右滑。
- 单测或 controller 测试覆盖单曲队列、空队列和当前播放项缺失边界。
- Android lane 在小米 10 Pro 做手势真机自测，并记录步骤和结果。

## 消息记录

- 2026-06-24 type=task lane=product summary=产品新增需求：底部播放状态栏整体左右滑动时能切歌；单曲播放详情页也支持左右滑动切歌。

## 相关提交

- pending

## 版本与发布

- Target Version: 1.0.1
- Release Tag: pending
- Android APK: pending
- Push Status: not_ready

## Review 结果

- Reviewer Lane: architect
- Result: pending
- Android Findings: pending
- iOS Findings: 暂不涉及。
- HarmonyOS Findings: 暂不涉及。
- Architect Findings: pending
