# AM-20260621-005 自定义列表排序交互简化

Status: pushed
Owner Lane: android
Source Thread: product lane `019eea5b-9b46-7f92-a35c-7d080ea1e986`
Created: 2026-06-21
Updated: 2026-06-22

## 背景
- AM-20260621-004 已修复排序编辑模式里的滑动闪烁、无法保存、未保存草稿绕过确认等问题，并已安装到小米 17 Pro。
- 产品体验后确认前两个问题已修复，但仍觉得当前“切换到自定义排序”后的界面会把自定义列表区域盖住，观感奇怪，交互仍偏重。

## 目标
- 简化自建歌单/自定义列表的排序交互。
- 自定义列表里默认只围绕“自定义排序”工作，不再让用户在多个排序模式和覆盖式编辑区之间来回理解。
- 保留 AM-004 已修好的稳定拖拽、保存、取消、返回确认能力。

## 产品方案
- 自建歌单/自定义列表只支持自定义排序。
- 列表有一个默认顺序：
  - 新歌单或未手动排序过的歌单，默认按加入顺序展示。
  - 用户手动排过后，默认展示用户保存的自定义顺序。
- 页面里提供一个明确入口，例如“自定义排序”或“调整顺序”。
- 点击入口后进入排序编辑态，直接拖拽排序，点完成保存。
- 不要在用户切到“自定义排序”时用大块编辑 UI 把原列表区域盖住。
- 不要再让自建歌单里出现让用户困惑的“加入时间/标题/自定义顺序”多模式切换；如果其它列表仍需要多排序模式，保持原逻辑，不扩大范围。

## 交互要求
- 自建歌单打开时直接显示当前默认顺序。
- 顶部或列表工具区只保留一个轻量入口：“自定义排序/调整顺序”。
- 点击后进入 AM-004 的排序编辑态：
  - 只显示必要的取消/完成和拖拽把手。
  - 不遮住整块列表内容。
  - 不重新引入拖拽闪烁。
  - 不丢失未保存确认。
- 排序保存后，回到普通列表态，列表按最新自定义顺序展示。
- 如果用户没有改动就退出，不写入。
- 如果搜索过滤中，不允许进入排序编辑态，提示清除搜索后再调整。

## 范围
- 包含：自建歌单/自定义列表的排序入口、展示顺序、编辑态 UI、相关 widget/unit 测试。
- 不包含：本地音乐列表、平台宿主、鸿蒙播控中心、iOS。
- 收藏列表是否跟随此简化方案，由 android lane 先按当前代码结构判断；如果会影响收藏既有排序能力，先不要顺手改，向 architect/product 汇报。

## 验收标准
- 自建歌单页面不再出现会让用户困惑的多排序模式切换。
- 自建歌单默认展示加入顺序或用户保存过的自定义顺序。
- 点击“自定义排序/调整顺序”后才进入排序编辑态。
- 进入排序编辑态时不遮住整块列表区域，列表仍是主体。
- AM-004 已修复的问题不回退：拖拽不闪屏，完成才保存，取消/返回有未保存确认。
- 搜索过滤时不能进入排序编辑态。
- `flutter test` 和 `flutter analyze` 通过。

## Test Plan
- Widget 测试：自建歌单普通态不显示多排序模式菜单，只显示轻量排序入口。
- Widget 测试：未手动排序过的自建歌单按加入顺序展示。
- Widget 测试：保存自定义排序后，重新进入仍按保存顺序展示。
- Widget 测试：点击排序入口进入编辑态，列表内容仍可见，不出现覆盖整块列表的 UI。
- Widget 测试：AM-004 保存/取消/返回确认行为保持不变。
- Widget 测试：搜索过滤时不能进入排序编辑态。

## 消息记录
- 2026-06-21 type=task lane=product summary=产品体验 AM-004 后确认滑动闪烁和无法保存已修复，但不希望切换到自定义排序时把自定义列表区域盖住；希望自定义列表只支持自定义排序，有默认顺序，点自定义排序后直接排序即可。
- 2026-06-21 type=task lane=android summary=创建 AM-005，分派给 android lane 做公共 Dart 自建歌单排序交互简化。
- 2026-06-21 type=task lane=architect summary=请求架构师 review AM-005 交互口径和后续 android 实现；本任务不涉及 iOS/鸿蒙。
- 2026-06-21 type=review_request lane=android status=review summary=android lane 已完成自建歌单排序简化：自建歌单详情页不再显示“排序”菜单，普通态直接展示加入顺序/保存顺序，只保留“调整顺序”入口；点击后进入 AM-004 编辑态。收藏列表保留原排序能力，不扩大范围。`flutter test` 和 `flutter analyze` 均通过。
- 2026-06-21 type=review_result lane=android status=assigned summary=架构师 review 交互口径通过，但收紧范围：本次只改自建歌单/自定义列表，不改本地列表、不改收藏列表、不改平台宿主；保留 AM-004 的拖拽草稿、完成保存、取消/返回确认、搜索过滤禁入能力。
- 2026-06-21 type=review_request lane=android status=review summary=android lane 已实现自建歌单排序交互简化：自建歌单详情强制自定义顺序，隐藏排序菜单，只保留轻量“调整顺序”入口；收藏列表保留原多排序能力；AM-004 编辑态能力继续复用。验证通过 `flutter test` 和 `flutter analyze`。
- 2026-06-21 type=review_result lane=android status=accepted summary=架构师复审通过：实现范围只限自建歌单公共 Dart/test；未误伤本地列表、收藏列表和平台宿主；自建歌单默认按 entries 顺序展示，保存后按持久化顺序展示；AM-004 保存/取消/返回/搜索过滤/mini player 隐藏能力未回退。
- 2026-06-22 type=demo_ready lane=product status=accepted summary=Android lane 已构建并安装 AM-005 debug 包到小米 17 Pro Max/小米 17 系列设备；无线 ADB 为 `192.168.31.190:41641`，安装命令 `adb -s 192.168.31.190:41641 install -r -d build/app/outputs/flutter-apk/app-debug.apk` 返回 Success，`dumpsys package com.qi.ai.music` 确认 `versionName=1.0.0` 和 `primaryCpuAbi=arm64-v8a`，并已用 monkey 启动一次。原 Android lane 本地提交对象为 `9db526c`，因父提交仍指向旧的 `cdb68d7`，已在当前 `52bee7d` 主线上以同内容提交重挂为 `cefd82c`。
- 2026-06-22 type=status lane=architect status=pushed summary=按“功能闭环后自动推送”规则，AM-005 最终主线提交 `cefd82c135bca3280f6ff705cf1eadcfd1e97bda` 已推送到远端 `origin/main`，远端 main 已确认指向同一 SHA；提交范围只包含 `lib/src/presentation/music_home_page.dart` 和 `test/widget_test.dart`。

## 相关提交
- `cefd82c` 简化自建歌单排序入口：pushed/accepted，已安装到小米 17 Pro Max/小米 17 系列设备，并已推送到远端 `origin/main`。

## 产品体验状态
- Status: accepted_pushed
- Owner Lane: android
- Thread: `019ee41d-647e-7250-bb01-f1ae81098696`
- Device: 小米 17 Pro Max/小米 17 系列设备，ADB `192.168.31.190:41641`
- Notes: 当前设备已安装 `build/app/outputs/flutter-apk/app-debug.apk`。可体验内容：自建歌单不再显示多排序模式菜单，普通态直接展示加入顺序或保存顺序，只保留“调整顺序”入口；点击后进入排序编辑态，保留 AM-004 的拖拽草稿、完成保存、取消/返回未保存确认、搜索过滤禁入和编辑态隐藏 mini player。收藏列表排序能力未改。最终提交 `cefd82c135bca3280f6ff705cf1eadcfd1e97bda` 已推送到远端 `origin/main`，AM-005 归档为 pushed/accepted；当前工作区 `music_home_page.dart` / `widget_test.dart` 后续未提交改动归属 AM-20260622-001。

## Review 结果
- Reviewer Lane: architect
- Result: accepted
- Android Findings:
  - 设计方向通过：自建歌单不再暴露“加入时间/标题/自定义顺序”多排序模式，能减少 AM-004 之后仍存在的理解成本。
  - 范围收紧：本次只改自建歌单/自定义列表。不要改本地音乐列表；不要改 iOS/HarmonyOS/Android 原生宿主；收藏列表暂不跟随，除非 product 另行明确。
  - 默认顺序口径：未手动排序过的自建歌单按加入顺序展示；保存过自定义排序后按持久化顺序展示。实现不能因为移除排序菜单而丢掉已有 playlist entry 顺序。
  - 入口口径：自建歌单普通态只保留轻量“调整顺序/自定义排序”入口；点击后进入 AM-004 的排序编辑态，不能引入覆盖整块列表区域的新 UI。
  - 回归要求：AM-004 已修好的行为不能回退，包括拖拽只改草稿、完成才写入、取消/系统返回未保存确认、搜索过滤禁入、编辑态隐藏 mini player 和行内操作。
  - 测试要求：至少覆盖自建歌单无排序菜单、默认加入顺序、保存后持久化顺序、搜索过滤禁入、未保存返回确认，以及收藏列表仍保留原有排序能力。
  - 已闭合：自建歌单通过 `effectiveSortMode = custom` 强制按 playlist entries 顺序展示，不再显示排序菜单；普通态只保留“调整顺序”入口。
  - 已闭合：收藏列表仍显示排序菜单，并保留加入时间/首字母/自定义顺序能力；本地列表和平台宿主未改。
  - 已闭合：AM-004 的编辑态草稿、完成保存、搜索过滤禁入、未保存返回确认、编辑态隐藏 mini player 和 `onReorder` 兼容逻辑未回退。
- iOS Findings: 不涉及
- HarmonyOS Findings: 不涉及
- Architect Findings: 不涉及
