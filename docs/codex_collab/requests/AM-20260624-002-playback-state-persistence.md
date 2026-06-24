# AM-20260624-002 播放状态持久化

Status: assigned
Owner Lane: android
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.1
Priority: P1 first implementation
Base Branch: main
Work Branch: lane/android
Worktree Path: /Users/huangqi/AIHome/projects/ai_music_android
Merge Branch: main
Created: 2026-06-24
Updated: 2026-06-24

## 目标

杀进程或重进 App 后，恢复用户的播放体验上下文：

- 上次播放模式持久化，例如列表循环、单曲循环、随机播放。
- 上次播放队列来源持久化，例如收藏列表、自建歌单、本地缓存或搜索缓存队列。
- 上次队列顺序和当前歌曲持久化。
- 重启后可恢复当前歌曲和队列，但播放进度从 0 开始；默认不自动播放。

## 责任边界

- Android lane 是公共 Dart 实现 owner。
- Architect lane 只做方案 review、边界把关、合并发布和冲突裁决，不直接实现本任务业务代码。
- ohos/iOS lane 只在平台验证发现问题时参与；本任务不要求它们先改宿主代码。

## 范围

包含：

- 公共 Dart 播放状态持久化模型。
- `MusicController` 或相邻应用层恢复编排。
- 播放模式、队列来源、队列 track ids、当前 track id 的保存和恢复。
- 删除歌曲、缓存缺失或队列来源不存在时的安全降级。
- 单元测试和必要 widget/controller 测试。

不包含：

- FLAC/Auto 双源搜索。
- 歌词/封面 metadata pipeline。
- Android 系统播控槽位、随机短听策略。
- HarmonyOS vendored plugin 或 AVSession 修复。
- 1.0.0 release 代码变更。

## 验收标准

- 用户在收藏列表播放一首歌，杀进程重进后恢复收藏队列和当前歌曲，进度从 0 开始且不自动播放。
- 用户在自建歌单播放一首歌，杀进程重进后恢复该歌单队列、顺序和当前歌曲。
- 用户在搜索缓存队列播放一首歌，杀进程重进后恢复可用缓存队列；不可用曲目安全跳过。
- 播放模式恢复：顺序、列表循环、单曲循环、随机播放均能持久化。
- 如果某首歌已被删除，恢复时跳到队列中下一个可用歌曲；没有可用歌曲时降级为空队列，不崩溃。
- 恢复过程不触发自动播放，不重新下载音频，不强行触发 metadata 网络补全。

## 测试要求

- `flutter test` 全量通过。
- `flutter analyze` 通过。
- 单测覆盖收藏队列恢复、自建歌单队列恢复、搜索缓存队列恢复。
- 单测覆盖播放模式恢复。
- 单测覆盖删除歌曲后的降级。
- Android lane 在小米 10 Pro 上做杀进程/重进手动自测，并记录步骤和结果。

## 消息记录

- 2026-06-23 type=task lane=product summary=产品提出播放状态记录需求，建议进入 1.0.1，不混入 AM-20260622-003。
- 2026-06-24 type=correction lane=product summary=产品要求 1.0.1 公共 Dart 业务切回 Android lane 主责，架构师不要长期直接写业务代码。
- 2026-06-24 type=task lane=architect summary=架构师将播放状态持久化拆为 Android lane 独立 1.0.1 任务。

## Review 结果

- Reviewer Lane: architect
- Result: assigned
- Android Findings: Android lane 按本任务单实现，不混入 1.0.0 release 收口。
- iOS Findings: 暂不涉及。
- HarmonyOS Findings: 暂不涉及。
- Architect Findings: 架构师只做 review/合并/发布，不直接写本任务公共 Dart 业务。
