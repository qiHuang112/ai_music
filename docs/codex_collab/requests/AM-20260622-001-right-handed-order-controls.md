# AM-20260622-001 调整顺序操作右手化

Status: pushed
Owner Lane: android
Source Thread: product lane `019eea5b-9b46-7f92-a35c-7d080ea1e986`
Created: 2026-06-22
Updated: 2026-06-22

## 背景
- AM-20260621-005 已把自建歌单排序入口简化为“调整顺序”，并已安装到小米 17 Pro Max/小米 17 系列设备。
- 产品体验后提出新的手感要求：调整顺序相关操作不要放左边，左侧不是惯用手区域，应把排序操作集中到右侧，方便右手拇指操作。

## 目标
- 把所有“调整顺序/排序编辑”相关的主要操作放到右侧或右手易触达区域。
- 保留 AM-004/AM-005 已修好的排序编辑态能力，不回退保存、取消、返回确认、搜索过滤禁入、编辑态隐藏 mini player 等行为。

## 范围
- 包含：公共 Flutter/Dart UI 和相关 widget 测试。
- 不包含：Android 原生宿主、iOS、HarmonyOS 播控中心。
- 默认只影响自建歌单/自定义列表的排序交互；如果发现收藏列表自定义排序同样有左侧拖拽把手，也要评估是否一并右移，并在 review_request 里说明影响范围。

## 交互要求
- 普通态的“调整顺序”入口靠右展示，不能作为左侧主要按钮。
- 排序编辑态里每一行的拖拽把手放到歌曲行右侧，作为 trailing 操作，不要放在左侧。
- 排序编辑态的主完成/保存操作放在右侧；取消、返回可以按平台常规保留左侧或系统返回位置。
- 多选、播放、添加到歌单、更多菜单等非排序操作不要因为本任务被大幅重排。
- 不要引入覆盖列表的大块 UI；列表仍是主体。

## 验收标准
- 自建歌单普通态里，“调整顺序”入口出现在右侧操作区。
- 进入排序编辑态后，拖拽把手在每首歌右侧，右手可以直接拖拽排序。
- 完成/保存排序的主操作在右侧。
- AM-004/AM-005 已有能力不回退：拖拽不闪屏、完成才保存、取消/返回有未保存确认、搜索过滤时不能进入排序、编辑态隐藏 mini player。
- `../tools/flutter/bin/flutter test` 和 `../tools/flutter/bin/flutter analyze` 通过。

## Test Plan
- Widget 测试：自建歌单普通态“调整顺序”入口位于工具区右侧。
- Widget 测试：进入排序编辑态后拖拽把手的 x 坐标位于歌曲标题右侧。
- Widget 测试：完成/保存按钮位于右侧操作区。
- 回归测试：AM-004/AM-005 现有排序编辑态测试继续通过。

## 消息记录
- 2026-06-22 type=task lane=product summary=产品要求把所有调整顺序相关操作放到右边，原因是左边不是惯用手区域。
- 2026-06-22 type=review_request lane=android status=ready_for_review summary=android lane 已实现右手化排序操作：普通态“调整顺序”入口在 AppBar 右侧并加稳定 key；排序编辑态拖拽把手移到每行右侧 trailing；完成/保存主操作仍在右侧；保留 AM-004/AM-005 的草稿拖拽、完成保存、搜索过滤禁入、返回确认、隐藏 mini player 和 onReorder 兼容逻辑。
- 2026-06-22 type=review_result lane=android status=accepted summary=架构师 review 通过：排序相关主要操作已集中到右侧，非排序播放/收藏/加歌单/更多/多选操作未被重排；测试覆盖右侧入口、右侧拖拽把手、右侧完成按钮，并保留既有排序编辑态回归。
- 2026-06-22 type=status lane=product status=pushed summary=右手化排序操作已提交为 `8f04d15` 并推送到远端 `origin/main`；提交范围只包含 `lib/src/presentation/music_home_page.dart` 和 `test/widget_test.dart`。

## 相关提交
- `8f04d15` 调整排序操作到右侧：pushed/accepted。

## Review 结果
- Reviewer Lane: architect
- Result: pushed/accepted
- Android Findings: 未发现阻塞问题。提交时应只 stage 本任务相关的 `lib/src/presentation/music_home_page.dart`、`test/widget_test.dart`，不要混入既有 AM-003 归档账本脏改或其它未跟踪协同文件；如需提交任务单/reviews 记录，请在提交范围里明确标注为协同账本更新。
- iOS Findings: 不涉及
- HarmonyOS Findings: 不涉及
