# AM-20260624-002 播放状态持久化

Status: device_verified
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
Updated: 2026-06-25
Merged Commits: 98d64a1, 473ac61, 9cbde92

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
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=首版方向正确但需修复收藏/歌单恢复语义：收藏和自建歌单恢复不能从本地缓存补回已移除成员；收藏/歌单成员变化后必须刷新或清理持久化快照；清理快照时必须同步清掉内存 active queue/source/current；同时要求基于最新 `origin/main` 重测，避免覆盖 AM-001 metadata 和 AM-003 手势。
- 2026-06-24 type=status lane=ohos summary=ohos 已将 `lane/ohos` rebase 到 `origin/main` `a05fff9`，并修复二轮 review findings：收藏/歌单来源只按当前成员恢复，成员删除或取消收藏后刷新快照，清快照时同步清内存队列和来源。
- 2026-06-24 type=review_result lane=architect status=changes_requested summary=二轮业务逻辑 review 通过；唯一阻塞是分支基线落后，缺少已推主线的 AM-003 滑动切歌 `5ec19b6` 和账本 `3322552`，要求以 `origin/main=3322552e4a7fe8a5ff46559712e61c016b40acde` 为基线重放并重测。
- 2026-06-24 type=status lane=ohos summary=ohos 已将 AM-002 两个提交 rebase 到 `origin/main` `3322552`；自动合并无冲突，确认 `music_home_page.dart` 同时保留 AM-003 迷你播放器滑动切歌和 AM-002 播放状态来源传递；同时补齐 `player_page_test` 新滑动用例的 fake playback store 隔离，避免测试 runner 因真实持久化 store 收尾卡住。
- 2026-06-25 type=review_result lane=architect status=accepted summary=架构师二轮 review 通过：AM-002 已基于 `origin/main=3322552`，保留 AM-003 滑动切歌；恢复时不自动播放，收藏/自建歌单恢复不复活已移除歌曲，成员变化会刷新或清理持久化快照。架构师复跑 analyze、关键测试和 diff check 通过。
- 2026-06-25 type=status lane=architect status=merged summary=架构师已将 AM-002 三个提交 cherry-pick 合入 integration main，合入后提交为 `98d64a1`、`473ac61`、`9cbde92`；HDC 仍是设备安装 blocker，后续由 ohos lane 恢复后补真机杀进程重进验证。
- 2026-06-25 type=validation_result lane=ohos status=device_verified summary=ohos lane 已使用 `hdc tconn 192.168.31.53:6666` 连接鸿蒙测试机，`hdc list targets -v` 显示 `192.168.31.53:6666 TCP Connected localhost`；HAP 安装、启动、杀进程重进验证通过。重启后恢复当前歌曲 `十年 / 陈奕迅`，播放页显示 `00:00 / 03:25` 且中央为播放按钮；点击下一首切到 `浮夸 / 陈奕迅`，证明恢复队列可用。

## 验证记录

- 2026-06-24 `flutter analyze --no-pub`：通过，No issues found。
- 2026-06-24 `flutter test --no-pub test/music_controller_test.dart`：通过，28 tests passed。
- 2026-06-24 `flutter test --no-pub test/widget_test.dart`：通过，34 tests passed。
- 2026-06-24 `flutter test --no-pub test/player_page_test.dart`：通过，3 tests passed；同时修复该测试拖动歌词后遗留 2 秒 timer 的测试收尾问题。
- 2026-06-24 `flutter test --no-pub`：通过，127 tests passed。
- 2026-06-24 `OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh`：通过，生成 `build/ohos/hap/entry-default-signed.hap`，23.8MB。
- 2026-06-24 无线 HDC 安装阻塞：`hdc tconn 192.168.31.53:10178` 和 `hdc list targets` 均返回 `Connect server failed`；HAP 已生成，但本轮无法完成设备安装/杀进程重进手测。
- 2026-06-24 二轮修复后 `flutter analyze --no-pub`：通过，No issues found。
- 2026-06-24 二轮修复后 `flutter test --no-pub test/music_controller_test.dart`：通过，32 tests passed；覆盖已移除收藏不从缓存恢复、歌单不存在清快照、取消收藏/移除歌单成员后不复活旧队列。
- 2026-06-24 二轮修复后 `flutter test --no-pub test/widget_test.dart`：通过，34 tests passed。
- 2026-06-24 二轮修复后 `flutter test --no-pub test/player_page_test.dart`：通过，3 tests passed。
- 2026-06-24 二轮修复后 `flutter test --no-pub`：通过，137 tests passed。
- 2026-06-24 二轮修复后 `OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh`：通过，生成 `build/ohos/hap/entry-default-signed.hap`，23.8MB；构建副作用 `pubspec.lock` 和 `third_party/just_audio_harmonyos/ohos/BuildProfile.ets` 已恢复。
- 2026-06-24 二轮修复后无线 HDC 仍阻塞：`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -v` 返回 `Ver: 3.2.0c`；`hdc start -r` 无输出，`hdc list targets` 与 `hdc tconn 192.168.31.53:10178` 均返回 `Connect server failed`，因此本轮无法完成设备安装和杀进程重进手测。
- 2026-06-24 基于 `origin/main` `3322552` 重放后 `flutter analyze --no-pub`：通过，No issues found。
- 2026-06-24 基于 `origin/main` `3322552` 重放后 `flutter test --no-pub test/music_controller_test.dart`：通过，32 tests passed。
- 2026-06-24 基于 `origin/main` `3322552` 重放后 `flutter test --no-pub test/widget_test.dart`：通过，36 tests passed，包含 AM-003 迷你播放器滑动切歌测试。
- 2026-06-24 基于 `origin/main` `3322552` 重放后 `flutter test --no-pub test/player_page_test.dart`：通过，5 tests passed，包含 AM-003 播放页滑动切歌和 slider 不误触切歌测试。
- 2026-06-24 基于 `origin/main` `3322552` 重放后 `flutter test --no-pub`：通过，141 tests passed。
- 2026-06-24 基于 `origin/main` `3322552` 重放后 `OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh`：通过，生成 `build/ohos/hap/entry-default-signed.hap`，23.8MB；构建副作用 `pubspec.lock` 和 `third_party/just_audio_harmonyos/ohos/BuildProfile.ets` 已恢复。
- 2026-06-24 基于 `origin/main` `3322552` 重放后无线 HDC 仍阻塞：`hdc list targets` 返回 `Connect server failed`，仍属本机 HDC 服务层问题。
- 2026-06-25 鸿蒙真机补验：先执行 `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc tconn 192.168.31.53:6666`，`hdc list targets -v` 显示 `192.168.31.53:6666 TCP Connected localhost`。安装命令 `hdc -t 192.168.31.53:6666 install -r build/ohos/hap/entry-default-signed.hap` 返回 `install bundle successfully`；启动命令 `hdc -t 192.168.31.53:6666 shell aa start -a EntryAbility -b com.qi.ai.music` 返回 `start ability successfully`。
- 2026-06-25 鸿蒙杀进程重进验证：执行 `aa force-stop com.qi.ai.music` 后重新启动，首页 mini player 恢复当前歌曲 `十年 / 陈奕迅`，收藏入口显示 `2 首 · 浮夸 / 十年`，自建歌单 `qi` 显示 `3 首 · 十年 / 浮夸 / Midnight City`。进入播放页显示当前歌曲 `十年 / 陈奕迅`，进度 `00:00 / 03:25`，中央为播放按钮，确认默认不自动播放且进度从 0 开始；点击下一首后页面切到 `浮夸 / 陈奕迅`。证据截图：`/Users/huangqi/AIHome/worktrees/ai_music/ai_music_screen_am002.png`、`/Users/huangqi/AIHome/worktrees/ai_music/ai_music_player_screen_am002.png`、`/Users/huangqi/AIHome/worktrees/ai_music/ai_music_after_next_screen_am002.png`。

## Review 结果

- Reviewer Lane: architect
- Result: accepted/merged
- Android Findings: Android lane 暂不实现本任务，改为协助复核公共 Dart/Android 行为；收到 ohos review_request 后，请检查播放队列恢复、测试覆盖和 Android 行为风险。
- iOS Findings: 暂不涉及。
- HarmonyOS Findings: AM-002 已通过代码 review、合入 main，并在鸿蒙测试机完成安装和杀进程重进补验。恢复播放模式/队列/current track 的核心路径可用；默认不自动播放，进度从 0 开始。
- Architect Findings: 架构师已复跑 analyze、关键 widget/controller/player 测试和 diff check，并将提交合入 integration main；ohos lane 已补齐 HDC 真机验证，AM-002 可按 device_verified 归档。
