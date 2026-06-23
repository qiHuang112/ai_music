# AM-20260623-001 首页默认展示与播放状态恢复

- Request: AM-20260623-001
- Owner lane: ohos
- Architect lane: architect
- Product lane: product
- Status: review
- Target Version: 1.0.1
- Base Branch: release/1.0.1
- Work Branch: feature/1.0.1/AM-20260623-001-home-default-ohos
- Worktree Path: /Users/huangqi/AIHome/worktrees/ai_music/ohos-AM-20260623-001
- Merge Branch: release/1.0.1
- Created: 2026-06-23
- Updated: 2026-06-23

## 背景

产品提出两个 1.0.1 播放体验需求：第一，首页未搜索时默认展示收藏列表和自定义歌单；第二，杀进程/重进后恢复播放模式、队列来源、队列顺序和当前歌曲。

产品已决定暂不新增第二 Android lane。不冲突的公共 Dart 业务可以由 iOS 或鸿蒙 lane 承接。当前先把“首页默认展示收藏列表和自定义歌单”拆给 ohos lane；“播放状态记录”涉及 `MusicController`、`PlaybackUseCase`、设置持久化和队列恢复，可能与 AM-20260622-003 正在修改的 `MusicController`/播放/搜索/metadata 链路冲突，暂缓实现，待架构师确认边界后再拆。

本任务虽然由 ohos lane 承接，但代码范围是公共 Flutter/Dart UI，不是 HarmonyOS 宿主或 ArkTS 任务。ohos lane 必须严格避开 AM-20260622-003 feature 分支正在修改的文件；如确需触碰冲突文件，先发 `blocker` 向架构师申请边界确认。

## 本轮实现范围

只实现首页默认展示：

- 首页在未搜索、没有在线搜索态、没有用户输入关键词时，默认展示用户的收藏列表和自建歌单入口/摘要。
- 收藏区域应有可识别入口或摘要，例如收藏数量、前几首收藏歌曲；具体 UI 形式由 ohos lane 结合现有页面实现。
- 自建歌单区域应展示已有歌单入口或摘要；无自建歌单时有稳定空态。
- 点击收藏区域可以直接播放收藏列表，点击自建歌单可以进入或直接播放对应歌单；入口必须可发现，不要只藏在更多菜单。
- 用户开始搜索后，搜索结果态覆盖默认首页内容；清空搜索后回到默认首页展示。

## 暂缓范围

以下内容本轮不做，避免和 AM-20260622-003 冲突：

- 播放模式持久化。
- 播放列表来源、队列顺序、当前歌曲持久化。
- 杀进程/重进后的播放上下文恢复。
- 搜索源、FLAC、歌词、封面、Auto 双源搜索和搜索结果信息密度。
- Android 系统播控、HarmonyOS 播控或平台宿主代码。

如果 ohos lane 认为首页默认展示必须改动上述暂缓范围，先停止实现并通知架构师。

## 可写范围

优先可写：

- `lib/src/presentation/`
- 与首页展示直接相关的 widget 测试文件
- 必要的任务单和 ohos/architect 知识沉淀

谨慎可写，改动前需要在 review_request 里重点说明：

- `lib/src/application/` 中只读数据聚合、列表选择、播放入口相关的极小范围
- `test/` 中 controller/widget 测试辅助类

禁止本轮触碰：

- `lib/src/data/music_resolver*`
- FLAC/BuguYY/Auto 搜索源解析逻辑
- `lib/src/playback/music_audio_handler.dart`
- Android 原生工程、HarmonyOS 宿主工程、iOS 宿主工程
- AM-20260622-003 worktree 或分支

## 验收口径

- 未搜索首页展示收藏和自建歌单入口/摘要。
- 有收藏、有自建歌单时，页面能让用户直接进入或播放对应列表。
- 无收藏或无自建歌单时，空态稳定，不挤压搜索入口和现有下载/本地列表入口。
- 搜索态、下载管理、本地列表、播放页、歌单详情页不回退。
- 不改 AM-20260622-003 的搜索结果 UI、FLAC/歌词/封面逻辑。
- 不使用小米 17 Pro；如需真机验证，使用鸿蒙 lane 自己的 HarmonyOS 测试机，或先仅做 Flutter widget/controller 测试。

## 测试要求

- 至少补 widget 测试覆盖：未搜索默认首页、搜索后隐藏默认首页、清空搜索后恢复默认首页。
- 如实现了直接播放收藏/歌单，补 controller 或 widget 测试覆盖点击入口调用正确播放队列。
- 运行 `/Users/huangqi/AIHome/tools/flutter/bin/flutter test` 和 `/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze`；如 Flutter/OHOS SDK 环境冲突，说明使用的 Flutter SDK 路径和失败原因。

## 分发记录

2026-06-23 架构师根据产品决策，把 AM-20260623-001 中不冲突的“首页默认展示收藏列表和自定义歌单”分配给 ohos lane，并创建独立 worktree `/Users/huangqi/AIHome/worktrees/ai_music/ohos-AM-20260623-001`。播放状态记录暂缓，待 AM-20260622-003 收口后再评估是否由 android、ohos 或其它 lane 承接。

## 实现记录

2026-06-23 ohos lane 在独立 worktree 完成首页默认展示部分：

- 首页无关键词、无在线搜索结果时展示“我的音乐”，包含收藏入口/摘要、自建歌单入口/摘要和无自建歌单空态。
- 收藏和自建歌单入口复用现有歌单详情页，点击后进入对应列表；本轮没有新增直接播放队列逻辑，避免触碰 `MusicController`/播放链路。
- 用户输入并执行在线搜索后隐藏默认首页内容；清空搜索后恢复默认展示。
- 已补 widget 测试覆盖默认首页、搜索覆盖和清空恢复，并保留原有歌单详情回归测试。

## Review 结果

2026-06-23 架构师 review accepted。提交 `9d38b5a9836b7d55b7f9bc4f5342272393a3e737` 范围符合分配边界，只改 `lib/src/presentation/app_localizations.dart`、`lib/src/presentation/music_home_page.dart`、`test/widget_test.dart` 和协同账本；未触碰 `MusicController`、`PlaybackUseCase`、`music_audio_handler`、FLAC/搜索解析、metadata 或平台宿主代码。首页默认展示收藏和自建歌单入口/摘要、搜索态隐藏默认首页、清空搜索恢复默认首页均有 widget 测试覆盖。架构师复跑 `/Users/huangqi/AIHome/tools/flutter/bin/flutter test test/widget_test.dart --no-pub` 和 `/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze --no-pub` 通过。

本轮接受“点击首页卡片进入现有详情页”的保守实现，不要求直接播放整列表，因为直接播放会触碰播放队列链路，可能与 AM-20260622-003 的公共播放修正冲突。若产品后续坚持首页卡片一键播放，应单独拆小任务，在 AM-20260622-003 收口后由架构师评估冲突。

2026-06-23 产品补充小回改后，状态从 accepted 改回 changes_requested。默认首页已有“我的音乐”、收藏和自建歌单入口后，搜索框下方原来的旧空态提示块需要移除，包括图标、“搜索音乐”和“输入歌手或歌曲名，下载后会保存在本机缓存里。”默认态只保留收藏/歌单相关内容。修复时仍只改展示层和 widget 测试，不触碰播放、搜索、metadata、FLAC 或平台宿主；搜索输入态和搜索结果态不能回退。

2026-06-23 ohos lane 已完成该小回改：未搜索默认首页不再渲染 `_SearchEmptyPrompt`，只保留“我的音乐”、收藏和自建歌单入口/摘要；`_SearchEmptyPrompt` 仍保留给非默认的输入未搜索状态，避免扩大搜索交互变更。widget 测试已补充默认首页、清空搜索恢复首页时不再出现“搜索音乐”和旧说明文案。
