# AM-20260621-004 排序编辑模式交互优化

Status: accepted
Owner Lane: android
Source Thread: product lane `019eea5b-9b46-7f92-a35c-7d080ea1e986`
Created: 2026-06-21
Updated: 2026-06-21

## 背景
- AM-20260621-002 已完成列表与歌单交互优化并安装到小米 17 Pro。
- 产品体验后反馈：收藏/自建歌单拖拽排序体验仍不顺。拖拽结束后列表会闪一下，像是每次拖完都触发了保存、刷新或重建；排序模式也没有清晰的退出、取消和保存入口，用户不知道怎么返回，也不知道调整是否已保存。

## 目标
- 把“自定义顺序”从隐式拖拽改成明确的排序编辑模式。
- 拖拽过程中列表稳定，不因每次 drop 触发全量刷新、闪屏或滚动位置跳动。
- 用户有明确的进入、取消、保存和返回路径。

## 范围
- 包含：收藏列表、自建歌单列表的自定义排序交互、公共 Flutter/Dart UI 状态、controller/use case 保存时机、widget/unit 测试。
- 不包含：iOS 宿主、HarmonyOS 宿主、Android 原生宿主、非收藏/自建歌单列表排序。

## 交互设计

### 入口
- 收藏和自建歌单的排序菜单保留“自定义顺序”。
- 选择“自定义顺序”只切换展示顺序，不自动进入拖拽编辑。
- 当当前列表为“自定义顺序”且没有搜索过滤时，工具栏显示“调整顺序”入口。
- 如果存在搜索过滤，隐藏或禁用“调整顺序”，提示“清除搜索后可调整顺序”。

### 编辑模式
- 点击“调整顺序”进入排序编辑模式。
- 顶部栏切换为编辑态：
  - 左侧：取消/关闭入口。
  - 中间：标题“调整顺序”。
  - 右侧：保存/完成入口。
- 列表行进入编辑态：
  - 显示拖拽把手。
  - 隐藏收藏、添加到歌单、更多等行内操作。
  - 点击歌曲不触发播放，避免误触。
  - 多选模式和排序编辑模式互斥。

### 拖拽行为
- 进入编辑模式时，对当前列表 trackId 顺序做一份本地草稿。
- 每次拖拽只更新本地草稿和当前屏幕列表，不立即写入 `playlists.json`，不触发 controller 全量刷新。
- 这里“暂停”的含义是暂停列表刷新、排序重算和异步 reload，不是暂停音乐播放；音乐播放可以继续。
- 拖拽结束后不弹 toast、不显示 loading、不闪屏、不跳滚动位置。
- 只有被拖动项和相邻项产生正常重排动画，整页不能重新闪一下。

### 保存与退出
- 点“保存/完成”时，才一次性调用 `reorderFavoriteTracks` 或 `reorderPlaylistTracks` 持久化草稿顺序。
- 保存成功后退出编辑模式，列表保持在自定义顺序，滚动位置尽量保持。
- 点“取消/关闭”：
  - 如果没有改动，直接退出编辑模式。
  - 如果有未保存改动，弹确认：“放弃本次排序调整？”
  - 操作项：继续编辑、放弃、保存并退出。
- 系统返回键和页面返回都走同一套退出逻辑：
  - 无改动直接退出编辑模式。
  - 有改动先确认，不能直接丢改动，也不能让用户卡住。

### 状态边界
- 排序编辑模式下，如果外部歌单数据刷新、歌曲被删除或收藏状态变化，先不打断用户拖拽；退出或保存时再做最小 reconcile。
- 如果保存时发现草稿里某些歌曲已经不存在，跳过不存在歌曲，并保留其它歌曲相对顺序。
- 切换 tab、打开搜索、切换排序方式、进入其它页面前，如果有未保存改动，必须先走保存/放弃确认。

## 验收标准
- 自定义顺序列表不会默认进入拖拽模式，必须点“调整顺序”才进入。
- 排序编辑模式有清晰的取消/关闭和保存/完成入口。
- 拖拽结束后列表不闪屏、不全量 reload、不跳滚动位置。
- 拖拽期间只更新本地草稿，点击保存后才持久化。
- 系统返回键可以退出排序编辑模式；有未保存改动时会提示保存或放弃。
- 取消后恢复进入编辑模式前的顺序；保存后返回页面再进入仍保持新顺序。
- 搜索过滤时不能进入排序编辑模式，并给出明确提示或禁用状态。
- `flutter test` 和 `flutter analyze` 通过。

## Test Plan
- Widget 测试：自定义顺序下显示“调整顺序”，默认不显示拖拽把手。
- Widget 测试：进入排序编辑模式后行内操作隐藏，拖拽把手显示，点歌曲不播放。
- Widget 测试：拖拽后未点保存，退出并选择放弃，顺序恢复。
- Widget 测试：拖拽后点保存，重新进入页面顺序保持。
- Widget 测试：系统返回键在无改动时退出编辑模式，有改动时弹确认。
- Widget 测试：搜索过滤时不能进入排序编辑模式。
- Unit 测试：草稿排序保存时只调用一次 reorder，并保留 `PlaylistTrackEntry.addedAt`。

## 消息记录
- 2026-06-21 type=task lane=product summary=产品体验 AM-20260621-002 后反馈：拖拽排序每次拖完列表会闪一下，排序模式没有退出按钮，也没有明确保存入口，无法确认如何返回或保存。
- 2026-06-21 type=task lane=android summary=本任务已完成交互设计，分派给 android lane 实现公共 Dart 排序编辑模式。
- 2026-06-21 type=task lane=architect summary=请求架构师 review 交互设计和后续 android 实现；本任务只涉及公共 Flutter/Dart，不分发给 iOS 或鸿蒙。
- 2026-06-21 type=review_result lane=android status=assigned summary=架构师 review 交互设计通过。实现时必须保证拖拽只改本地草稿，保存才持久化；取消/返回统一走未保存确认；搜索过滤、多选和排序编辑互斥；测试覆盖保存/放弃/返回/过滤边界。
- 2026-06-21 type=review_result lane=android status=changes_requested summary=实现版复审发现 1 个 P2：排序编辑态底部 mini player 仍可直接进入播放页，绕过未保存确认；另提醒本次提交只 stage AM-004 三个文件，不要混入 AM-003 鸿蒙元数据通道脏改。
- 2026-06-21 type=handoff lane=android status=assigned summary=AM-003 鸿蒙构建验证发现当前 main 的 `ReorderableListView.builder(onReorderItem:)` 不被 `flutter_ohos` 支持，导致 HAP 未打临时补丁时构建失败。AM-004 改排序编辑态时需使用标准 Flutter 与 flutter_ohos 都兼容的 reorder API，并保持当前 post-removal index 测试语义。
- 2026-06-21 type=task lane=android status=changes_requested summary=产品询问安卓排序编辑业务逻辑是否已有新包；如已修复 P2 并通过验证，请构建 Android debug 包并安装到小米 17 Pro；如尚未通过架构师 review，需先补 review_request/复审状态，安装时明确是否为待 review 体验包。
- 2026-06-21 type=review_request lane=android status=review summary=android lane 已修复两个 P2：排序编辑态隐藏 mini player，避免绕过未保存确认；排序列表改用标准 `onReorder` 并把 raw `newIndex` 转换为 post-removal 草稿索引，移除 `onReorderItem` 跨端兼容问题。隔离 AM-003 脏改后 `flutter test` 和 `flutter analyze` 均通过。
- 2026-06-21 type=review_result lane=android status=accepted summary=架构师复审通过：排序编辑态已隐藏 mini player，未保存草稿不能再绕过确认进入播放页；排序列表已改用标准 `onReorder`，用 `reorderTargetIndexFromRawReorder()` 兼容 flutter_ohos 并保持 post-removal 草稿 helper 语义；提交范围仅限 AM-004 三个公共 Dart/test 文件。
- 2026-06-21 type=status lane=product status=accepted_pending_install summary=AM-004 代码 review accepted。android lane 可提交并构建/安装 Android debug 包到小米 17 Pro；安装完成后再发正式 `demo_ready` 给 product。
- 2026-06-21 type=demo_ready lane=android status=accepted summary=AM-004 已提交、复审通过并安装到小米 17 Pro。提交 `984f9f6`（优化排序编辑模式交互）只包含 `lib/src/presentation/app_localizations.dart`、`lib/src/presentation/music_home_page.dart`、`test/widget_test.dart`；已修复排序编辑态 mini player 绕过未保存确认和 `onReorderItem` 跨端兼容两个 P2；`flutter test` 与 `flutter analyze` 均通过；debug 包 `build/app/outputs/flutter-apk/app-debug.apk` 已安装到 `2509FPN0BC` / `192.168.31.190:40145` 并通过 `monkey` 启动一次。
- 2026-06-21 type=task lane=product status=accepted summary=产品体验后确认 AM-004 的滑动闪烁和无法保存问题已修复；但自定义列表切到自定义排序后的覆盖感仍奇怪，已拆到后续任务 `AM-20260621-005` 简化自建歌单排序交互。

## 相关提交
- `984f9f6`：优化排序编辑模式交互，负责人 `android` lane，已通过架构师 review，并已安装到小米 17 Pro。

## Review 结果
- Reviewer Lane: architect
- Result: accepted
- Android Findings:
  - 设计通过：明确区分“自定义顺序展示”和“排序编辑模式”，能解决 AM-002 里每次 drop 立即持久化导致的闪屏/刷新感。
  - 实现硬性要求：进入编辑模式时创建本地草稿列表；`onReorder` 只更新草稿和当前 UI，不调用 `reorderFavoriteTracks`/`reorderPlaylistTracks`，不触发 controller 全量刷新。
  - 实现硬性要求：保存时只调用一次持久化接口；取消、页面返回、系统返回、切换搜索/排序/页面时共用同一套未保存确认逻辑。
  - 实现硬性要求：排序编辑模式与多选互斥；搜索过滤时禁用或隐藏“调整顺序”，并给明确提示。
  - 实现硬性要求：保存前 reconcile 已删除歌曲，跳过不存在项并保留其它歌曲相对顺序。
  - 测试要求：至少覆盖草稿拖拽不持久化、保存后持久化一次、取消恢复、系统返回确认、搜索过滤禁入、多选互斥、行内操作隐藏且点击歌曲不播放。
  - P2：当前实现里 `_PlaylistDetailPageState.build()` 在排序编辑态仍保留 `_MiniPlayer`，而 `_MiniPlayer` 的 `onTap` 会直接 `Navigator.push` 到播放页。用户拖拽产生未保存草稿后点底部播放器，会绕过“保存/放弃/继续编辑”确认，违反“进入其它页面前必须先走确认”的验收标准。修复方向：排序编辑态隐藏/禁用 mini player，或让 mini player 点击先复用 `_requestExitReorderEditing()`，只有用户选择保存或放弃后再进入播放页；补 widget 测试覆盖脏草稿时点击 mini player 不会直接进入播放页。
  - P2：当前公共 UI 使用 `ReorderableListView.builder(onReorderItem:)`，`flutter_ohos` 不支持，导致 AM-003 signed HAP 未打临时补丁时在 FlutterTask 阶段失败。修复 AM-004 时需要改为标准 Flutter 与 flutter_ohos 都支持的 reorder 写法，并保留当前拖拽 helper 对 post-removal index 的测试覆盖。
  - 已闭合：排序编辑态现在隐藏 `_MiniPlayer`，并新增 widget 测试覆盖有 mini player 时进入排序编辑态后入口消失，未保存草稿不会绕过确认进入播放页。
  - 已闭合：排序列表改用标准 `onReorder`，通过 `reorderTargetIndexFromRawReorder(oldIndex, newIndex)` 把 raw index 转成 post-removal target index，保留 flutter_ohos 兼容性和当前草稿 helper 语义。
  - 提交范围提醒：当前工作区还有 `lib/src/playback/music_audio_handler.dart` 和 `third_party/just_audio_harmonyos/.../MediaAvPlayer.ets` 脏改，属于 AM-003/鸿蒙链路，不要混入 AM-004 android 提交。
- iOS Findings: 不涉及
- HarmonyOS Findings: 不涉及
- Architect Findings: 不涉及

## 产品体验状态
- Status: accepted
- Owner Lane: android
- Thread: `019ee41d-647e-7250-bb01-f1ae81098696`
- Notes: 当前版本已通过架构师复审并提交，提交为 `984f9f6`。android lane 已将 debug 包安装到小米 17 Pro。体验入口：收藏/自建歌单选择“自定义顺序”后只展示顺序；点击“调整顺序”进入编辑态；拖拽只改本地草稿，不闪屏保存；点“完成”才持久化；关闭或系统返回有未保存改动时提示继续编辑、放弃、保存并退出；搜索过滤时提示清除搜索后再调整。安装包路径：`build/app/outputs/flutter-apk/app-debug.apk`。设备：`2509FPN0BC` / `192.168.31.190:40145`。已知限制：这是 debug 包；当前工作区仍有 AM-003/鸿蒙相关未提交脏改，但未进入 AM-004 提交范围和本次 Android 包体验逻辑。
