# AM-20260621-002 列表与歌单交互优化

Status: accepted
Owner Lane: android
Source Thread: 当前 Codex 对话初稿；已移交 `android` lane `019ee41d-647e-7250-bb01-f1ae81098696`
Created: 2026-06-21
Updated: 2026-06-21

## 目标
- 优化 AI Music 本地列表、收藏和自建歌单的常用管理路径，减少“添加到歌单”和“删除本地音乐”的操作成本。

## 范围
- 包含：公共 Flutter/Dart 应用层、歌库 UI、歌单弹层、本地化文案、controller/widget 测试。
- 不包含：iOS、HarmonyOS、Android 原生宿主工程、真正的歌手分组页。

## 验收标准
- 下载管理页不再显示“修复老资源”按钮，自动修复逻辑保留。
- 单曲行直接显示“添加到歌单”按钮，本地列表可从更多菜单删除本地音乐。
- 长按歌曲进入多选模式，可批量加歌单、批量删除本地缓存或从收藏/歌单移除。
- 收藏和自建歌单可切换到“自定义顺序”并拖拽排序，默认仍按加入时间显示。
- `flutter test` 和 `flutter analyze` 通过。

## 消息记录
- 2026-06-21 type=task lane=android summary=用户确认交互方案，要求实现列表与歌单管理优化。
- 2026-06-21 type=status lane=android summary=已完成公共 Dart 实现和测试，等待架构师 review。
- 2026-06-21 type=review_request lane=android summary=请求架构师 review 本地列表删除、多选批量、直接加歌单和拖拽排序改动。
- 2026-06-21 type=handoff lane=android summary=用户指出公共 Dart 业务必须由安卓 lane 负责；当前未提交实现改动移交安卓 lane 复核、修复架构师 P2，并由安卓 lane 后续请求 review/提交。
- 2026-06-21 type=review_request lane=android summary=android lane 已修复上轮 2 个 P2 并通过 `flutter analyze`/`flutter test`，请求架构师复审。
- 2026-06-21 type=review_result lane=android status=changes_requested summary=复审发现 1 个 P2：当前使用 `onReorderItem` 已经收到调整后的 `newIndex`，helper 又额外 `newIndex - 1`，向下拖拽仍会落错位置；删除队列中非当前缓存歌曲的问题已闭合。
- 2026-06-21 type=demo_ready lane=android status=ready_to_try summary=android lane 反馈本地可体验版本已完成但尚未提交，等待 architect review；内容包括隐藏“修复老资源”、直接添加到歌单、本地删除、长按多选批量处理、收藏/歌单自定义排序、修复拖拽 newIndex 语义、删除队列中非当前缓存歌曲时重建过滤队列；已通过 `flutter analyze` 和 `flutter test`。
- 2026-06-21 type=review_result lane=android status=changes_requested summary=product 侧收到 demo_ready 后架构师复审当前工作区，确认上一轮拖拽 P2 仍未修复：`onReorderItem` 已提供调整后的 `newIndex`，helper 仍重复 `newIndex - 1`；暂不向 product 确认 accepted。
- 2026-06-21 type=task lane=android status=blocked_by_review summary=产品要求给小米 17 Pro 安装体验包；由于当前仍有拖拽排序 P2，要求 android lane 优先修复并重新请求 review，再基于当前工作区构建安装；如果先装临时包，必须向 product 明确这是带已知问题的未通过 review 版本。
- 2026-06-21 type=review_request lane=android summary=android lane 已按 `onReorderItem` 当前语义修复拖拽 helper，并把测试改为 post-removal target index 语义：`oldIndex=0,newIndex=1` 得到 `[B,A,C]`，`oldIndex=0,newIndex=2` 得到 `[B,C,A]`。
- 2026-06-21 type=review_result lane=android status=accepted summary=架构师复审 `stash@{0}` 中 AM-20260621-002 公共 Dart/test 改动通过；删除队列和拖拽排序两个历史 P2 均已闭合。提交/安装前需要 android lane 先恢复 stash 中的 AM-002 改动。
- 2026-06-21 type=demo_ready lane=product status=ready_to_try summary=AM-20260621-002 已通过架构师 review，可让产品体验 Android/公共 Flutter 版本：本地列表删除、直接加歌单、长按多选批量操作、收藏/自建歌单自定义顺序拖拽。已知限制：当前 review 对象位于 `stash@{0}`，需 android lane 恢复后构建安装 debug 包。
- 2026-06-21 type=demo_ready lane=android status=ready_to_try summary=android lane 已按产品要求把 debug 体验包安装到小米 17 Pro；设备为 `2509FPN0BC` / Android 16 / API 36，ADB 目标 `192.168.31.190:40145`，包路径 `build/app/outputs/flutter-apk/app-debug.apk`，安装命令 `adb -s 192.168.31.190:40145 install -r -d build/app/outputs/flutter-apk/app-debug.apk`，`dumpsys` 确认包名 `com.qi.ai.music`、`versionName 1.0.0`、`primaryCpuAbi arm64-v8a`，并已通过 `monkey` 启动一次；`flutter analyze` 和 `flutter test` 均通过。
- 2026-06-21 type=status lane=android status=accepted summary=android lane 已完成提交：业务提交 `bbc90cf`（完善列表与歌单交互）只包含 8 个公共 Dart/test 文件，提交 trailer 已包含 `Request: AM-20260621-002`、`Lane: android`、`Thread: 019ee41d-647e-7250-bb01-f1ae81098696`、`Reviewed-by-lane: architect`；归属记录提交 `ceb51ca` 新增 `docs/codex_collab/changes.md` 并记录 `bbc90cf`。小米 17 Pro 上已安装的是该 accepted 版本的 debug 体验包。
- 2026-06-21 type=task lane=product status=accepted summary=产品体验 accepted 版本后反馈拖拽排序编辑体验仍需优化：拖完会闪一下，缺少清晰退出、取消和保存入口；已拆分为后续任务 `AM-20260621-004` 处理。

## 相关提交
- `bbc90cf`：完善列表与歌单交互，负责人 `android` lane，已通过架构师 review。
- `ceb51ca`：记录列表与歌单交互提交归属，新增 `docs/codex_collab/changes.md` 并记录 `bbc90cf`。

## Review 结果
- Reviewer Lane: architect
- Result: accepted
- Android Findings:
  - 已闭合：删除本地缓存现在会检查整个当前播放队列；删除非当前队列歌曲时会过滤队列、保留当前歌曲、当前进度和播放模式。
  - 已闭合：`reorderTracksForReorderableListView()` 现在直接使用 `onReorderItem` 传入的 post-removal `newIndex` 插入，不再二次 `newIndex - 1`；测试覆盖 `oldIndex=0,newIndex=1` 得到 `[B,A,C]` 和 `oldIndex=0,newIndex=2` 得到 `[B,C,A]`。
- iOS Findings: 不涉及
- HarmonyOS Findings: 不涉及
- Architect Findings: 无
- Notes: 本次只触碰公共 Flutter/Dart 层和测试；按协同规则不分发给 iOS 或鸿蒙 lane。架构师本轮没有重新跑命令测试，采用 android lane 已通过 `../tools/flutter/bin/flutter test` 和 `../tools/flutter/bin/flutter analyze` 的验证声明。当前 review 对象位于 `stash@{0}`。

## 产品体验状态
- Status: accepted
- Owner Lane: android
- Thread: `019ee41d-647e-7250-bb01-f1ae81098696`
- Notes: 当前版本已通过架构师复审并提交，业务提交为 `bbc90cf`，归属记录提交为 `ceb51ca`。android lane 已将 accepted 版本 debug 包安装到小米 17 Pro。体验入口：下载管理页确认“修复老资源”入口隐藏；本地列表歌曲行直接加歌单/更多菜单删除；长按进入多选后批量加歌单、批量删除、从收藏/歌单移除；收藏和自建歌单切到“自定义顺序”后拖拽排序。安装包路径：`build/app/outputs/flutter-apk/app-debug.apk`。设备：`2509FPN0BC` / Android 16 / API 36 / `192.168.31.190:40145`。
