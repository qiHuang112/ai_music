# AM-20260624-002 播放状态持久化

Status: review
Owner Lane: ohos
Assist Lane: android review, architect review
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.1
Priority: P1 first implementation
Base Branch: main
Work Branch: lane/ohos
Worktree Path: /Users/huangqi/AIHome/projects/ai_music_ohos
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

- ohos lane 是本任务实现 owner，负责在 `/Users/huangqi/AIHome/projects/ai_music_ohos` / `lane/ohos` 做公共 Dart 实现和 HarmonyOS 基础验证。该安排是为了和 Android lane 的 1.0.1 metadata pipeline 并行，避免 Android lane 空转或被单点占满。
- Android lane 是公共 Dart owner 方向的协助方：不直接抢写本任务，但在架构师 review 后负责检查公共 Dart 播放队列、测试和 Android 行为风险。
- Architect lane 只做方案 review、边界把关、合并发布和冲突裁决，不直接实现本任务业务代码。
- iOS lane 暂不参与，除非恢复状态在 iOS 真机上出现平台差异。
- ohos lane 开工前必须读取 `harmonyos-development` skill；如果只改公共 Dart，也要额外确认不会触碰鸿蒙串歌修复或 Android release 播控热修文件。

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
- Android release 播控热修文件：`android/app/src/main/AndroidManifest.xml`、`android/app/src/main/kotlin/com/qi/ai/music/MainActivity.kt`、`android/app/src/main/res/raw/keep.xml`、`test/release_config_test.dart`。
- 整个 `android/` 目录；如 ohos lane 发现必须改 Android 宿主或 Android 打包，先发 blocker 给 architect，不得直接修改。
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
- ohos lane 在 HarmonyOS 测试机上做杀进程/重进手动自测，并记录步骤和结果。
- Android lane 在收到 architect review_result 后，基于同一提交做公共 Dart/Android 风险复核；如需要真机验证，再使用小米 10 Pro，不使用小米 17 Pro。

## 消息记录

- 2026-06-23 type=task lane=product summary=产品提出播放状态记录需求，建议进入 1.0.1，不混入 AM-20260622-003。
- 2026-06-24 type=correction lane=product summary=产品要求 1.0.1 公共 Dart 业务切回 Android lane 主责，架构师不要长期直接写业务代码。
- 2026-06-24 type=task lane=architect summary=架构师将播放状态持久化拆为 Android lane 独立 1.0.1 任务。
- 2026-06-24 type=coordination_request lane=product summary=P1 release 播控由架构师备援推进时，其它 lane 不能空转；播放状态持久化改由 ohos lane 在独立工程并行实现，前提是不碰 Android release 播控文件、不碰 `android/`。
- 2026-06-24 type=unblock_start lane=product summary=产品确认当前 Android release 播控 P1 不需要 ohos 参与，允许 ohos 在 `/Users/huangqi/AIHome/projects/ai_music_ohos`、`lane/ohos` 并行承接 AM-002 公共 Dart 首版。
- 2026-06-24 type=status lane=ohos summary=ohos 完成首版实现：新增播放状态持久化模型，恢复播放模式、队列来源、队列顺序和当前歌曲；恢复时进度从 0 开始且不自动播放；删除缺失曲目时安全降级。

## 验证记录

- 2026-06-24 `flutter analyze --no-pub`：通过，No issues found。
- 2026-06-24 `flutter test --no-pub test/music_controller_test.dart`：通过，28 tests passed。
- 2026-06-24 `flutter test --no-pub test/widget_test.dart`：通过，34 tests passed。
- 2026-06-24 `flutter test --no-pub test/player_page_test.dart`：通过，3 tests passed；同时修复该测试拖动歌词后遗留 2 秒 timer 的测试收尾问题。
- 2026-06-24 `flutter test --no-pub`：通过，127 tests passed。
- 2026-06-24 `OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh`：通过，生成 `build/ohos/hap/entry-default-signed.hap`，23.8MB。
- 2026-06-24 无线 HDC 安装阻塞：`hdc tconn 192.168.31.53:10178` 和 `hdc list targets` 均返回 `Connect server failed`；HAP 已生成，但本轮无法完成设备安装/杀进程重进手测。

## Review 结果

- Reviewer Lane: architect
- Result: assigned
- Android Findings: Android lane 暂不实现本任务，改为协助复核公共 Dart/Android 行为；收到 ohos review_request 后，请检查播放队列恢复、测试覆盖和 Android 行为风险。
- iOS Findings: 暂不涉及。
- HarmonyOS Findings: ohos lane 接手实现。完成后回 architect lane，带 commit、`flutter test --no-pub`、`flutter analyze --no-pub`、HarmonyOS 杀进程/重进验证摘要；如触碰公共 Dart 高冲突文件，必须在 review_request 中列出文件和冲突风险。
- Architect Findings: 架构师只做 review/合并/发布，不直接写本任务公共 Dart 业务。
