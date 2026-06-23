# Review 索引

这里记录 review 结果索引。和具体任务强相关的详细 findings，放到对应任务单里。

| 日期 | Request | Reviewer Lane | Target Lane | Result | 摘要 |
| --- | --- | --- | --- | --- | --- |
| 2026-06-21 | AM-20260621-001 | architect | architect | accepted | 协同账本属于文档和流程维护改动。 |
| 2026-06-21 | ad-hoc | architect | ohos | accepted | `eb4f8d6` 鸿蒙播控中心、品牌资源和沙箱目录修复通过；无阻塞问题，记录 1 个 P3 后续优化：系统播控标题最好优先使用 Dart `MediaItem` 或可读文件名，避免无内嵌 metadata 时显示 just_audio 内部 id。 |
| 2026-06-21 | ad-hoc | architect | ohos | accepted | 鸿蒙 prepared diff 通过：为 AVSession metadata 增加 DLNA/Cast+ filter，创建 session 后设置 `requireAbilityList=['url-cast']`，并补齐 WantAgent `actionType`；只涉及鸿蒙，不分发 Android/iOS。 |
| 2026-06-21 | AM-20260621-002 | architect | ohos | changes_requested | `769dee8` 鸿蒙 AVSession 接入仍有初始化顺序风险：`createSession()` 初始化中途暴露 `this.session`，播放状态回调可能在 metadata/queue/launch/extras 完成前提前 activate；另需在重提时把 commit trailer 改为 `Reviewed-by-lane: architect`。 |
| 2026-06-21 | AM-20260621-002 | architect | ohos | accepted | `97bf894` 回退 `769dee8` 通过；相对 `769dee8^` 无代码 diff，已恢复到可播放基线。后续播控中心必须基于可播放版本做最小 AVSession 实验，不再一次性大范围改 `MediaAvPlayer` 播放链路。 |
| 2026-06-21 | AM-20260621-002 | architect | android | changes_requested | 公共 Dart 列表与歌单交互 review 发现 2 个 P2：自定义顺序拖拽向下移动未按 `ReorderableListView` 语义修正 `newIndex`；删除本地缓存只检查当前播放歌曲，没有处理当前播放队列中其它被删除歌曲。 |
| 2026-06-21 | AM-20260621-002 | architect | android | changes_requested | android lane 修复后复审仍有 1 个 P2：当前代码使用新版 `ReorderableListView.builder(onReorderItem:)`，该回调已经传入调整后的 `newIndex`，但 helper 仍按旧 `onReorder` 语义再次 `newIndex - 1`，向下拖拽会落错位置；删除播放队列中非当前缓存歌曲的问题已闭合。 |
| 2026-06-21 | AM-20260621-002 | architect | android | changes_requested | product 收到 demo_ready 后复审当前工作区，确认上一条 P2 仍存在：`music_home_page.dart` 继续使用 `onReorderItem` + helper 重复调整 `newIndex`；暂不向 product 确认 accepted。 |
| 2026-06-21 | AM-20260621-002 | architect | android | accepted | 复审 `stash@{0}` 中公共 Dart/test 改动通过：拖拽排序 helper 已按 `onReorderItem` post-removal `newIndex` 语义修正并补测试；删除队列中非当前缓存歌曲会重建队列并保留当前进度。可让 product 体验 Android debug 包。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | changes_requested | `4664d87` 鸿蒙播控中心元数据和控制状态修复方向正确，但仍有 4 个 P2：`setAVMetadata()` 异步取封面后用旧 `assetId` 搭配当前曲目信息，快速切歌可能写入错配 metadata；`setLoopModeCall` 只改原生播放模式不回写应用状态；`toggleFavorite` 只维护原生临时集合，不回写公共收藏业务；封面固定应用 icon，不满足当前歌曲真实封面动态更新要求。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | accepted | `8f0e779` 鸿蒙播控中心状态边界收紧通过：移除后台长时任务残留；metadata 更新增加曲目快照校验；封面优先抽取当前音频内嵌图并失败才降级默认图；未接公共 Dart 回写前不注册系统 `setLoopMode`/`toggleFavorite`，避免系统按钮产生 App 不知道的临时状态。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | changes_requested | 产品验收推翻 `8f0e779` 可体验结论：暂停后系统播控图标状态未变且无法恢复播放；点赞和播放模式按钮仍存在但不可点击；封面仍未显示当前音乐真实封面。下一版优先修 AVPlaybackState 与暂停恢复，系统按钮必须真实闭环或隐藏到不误导用户。 |
| 2026-06-21 | AM-20260621-004 | architect | android | design_accepted | 排序编辑模式交互设计通过：自定义顺序展示与编辑模式分离，拖拽只改本地草稿，保存才持久化；后续实现必须覆盖取消/保存/系统返回、搜索过滤和多选互斥，以及避免每次 drop 全量刷新。 |
| 2026-06-21 | AM-20260621-004 | architect | android | changes_requested | 实现版复审发现 1 个 P2：排序编辑态仍保留底部 mini player，点击会直接进入播放页，绕过未保存排序草稿的保存/放弃确认；提交时还需确保只包含 AM-004 三个公共 Dart/test 文件，不混入 AM-003 鸿蒙元数据通道改动。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | accepted | 鸿蒙播控中心后续修复通过：HarmonyOS-only 私有 Dart bridge 用平台保护同步真实 `MediaItem`；AVSession play/pause 先发布目标态再驱动 AVPlayer；`mediaImage` 使用 `artUri` 字符串符合当前 SDK 类型；loop/favorite 不发布不注册，避免不可回写按钮。另发现当前 main 的 `onReorderItem` 阻塞 flutter_ohos 构建，需 handoff android。 |
| 2026-06-21 | AM-20260621-003 | architect | android | changes_requested | 公共 Dart 跨端兼容 handoff：当前 main 使用 `ReorderableListView.builder(onReorderItem:)`，`flutter_ohos` 不支持，ohos lane 只能临时补丁后构建 HAP；android lane 需在公共 UI 修复中改为 flutter_ohos 兼容写法并保持排序测试语义。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | changes_requested | 产品截图验收推翻上一版 accepted：封面、歌名、歌手已有进展，但中间 pause 图标点击无法暂停；左侧播放模式和右侧点赞仍灰色露出且不可点击。验收口径为“可见即可用”，灰色坏入口不能交付。 |
| 2026-06-21 | AM-20260621-004 | architect | android | accepted | AM-004 实现复审通过：排序编辑态隐藏 mini player，避免未保存草稿绕过确认；排序列表改用标准 `onReorder` 并用 raw index 转换函数保持 post-removal 草稿语义，移除 flutter_ohos 不支持的 `onReorderItem`。提交范围限 AM-004 三个公共 Dart/test 文件。 |
| 2026-06-21 | AM-20260621-005 | architect | android | design_accepted | 自建歌单排序简化设计通过，但范围收紧为只改自建歌单/自定义列表：移除多排序模式，只保留轻量排序入口并复用 AM-004 编辑态；本地列表、收藏列表、平台宿主不在本次范围。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | accepted | `b106d33` 鸿蒙播控中心按钮闭环通过：系统 pause/play、loopMode、favorite 都接回真实 AVPlayer/`MusicController` 状态；HarmonyOS-only 私有通道有平台保护，不影响 Android/iOS。流程提醒：推送前把 `Reviewed-by-lane: none` 修正为 `architect`。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | accepted | `b106d33` 已 amend 为 `b66594f`，代码 diff 不变，commit trailer 已修正为 `Reviewed-by-lane: architect`。 |
| 2026-06-21 | AM-20260621-005 | architect | android | accepted | 自建歌单排序简化实现通过：自建歌单强制按自定义 entries 顺序展示并隐藏排序菜单，只保留轻量调整入口；收藏列表保留原排序能力；AM-004 编辑态能力未回退。 |
| 2026-06-21 | AM-20260621-003 | architect | ohos | changes_requested | 产品复测 `b66594f` 未通过：系统 pause 后音频实际暂停，但 AVSession/系统播控仍显示 playing，无法再从系统播控恢复；左侧播放模式点击未生效。下一版必须对照付华丽参考实现，并提供 pause/play/loop 前后 `hidumper` 证据。 |
| 2026-06-22 | AM-20260621-003 | architect | ohos | accepted | `52bee7d` 鸿蒙播控中心状态闭环复审通过：系统 play/pause 回到 HarmonyOS-only Dart 业务入口，暂停态 `AVPlaybackState.speed` 保持 1.0 避免系统拒绝 paused，播放模式按 AI Music 顺序推进，移除无效 `setTargetLoopMode` 注册；ohos 已提供 pause/play/loop/favorite 后 `show_controller_info` 关键字段，commit trailer 已修正为 `Reviewed-by-lane: architect`。 |
| 2026-06-22 | AM-20260621-003 | product | ohos | accepted | 产品确认 `52bee7d` 鸿蒙播控中心功能体验 OK；最终提交已推送到远端 `origin/main`，远端 main 已确认指向 `52bee7d8a8700b28310dfc856fc0cbf1e01a3716`。 |
| 2026-06-22 | AM-20260622-001 | architect | android | accepted | 右手化排序操作实现通过：普通态“调整顺序”入口位于右侧操作区，编辑态拖拽把手位于歌曲行右侧，完成/保存主操作位于右侧；AM-004/AM-005 的草稿拖拽、完成保存、搜索过滤禁入、返回确认、编辑态隐藏 mini player 和 onReorder 兼容逻辑未回退。 |
| 2026-06-22 | AM-20260621-005 | architect | android | pushed/accepted | `cefd82c` 自建歌单排序简化已按自动推送规则推送远端；`origin/main` 已确认指向 `cefd82c135bca3280f6ff705cf1eadcfd1e97bda`，提交范围只包含 `music_home_page.dart` 和 `widget_test.dart`。 |
| 2026-06-22 | AM-20260622-001 | architect | android | pushed/accepted | `8f04d15` 右手化排序操作已按自动推送规则推送远端；提交范围只包含 `music_home_page.dart` 和 `widget_test.dart`。 |
| 2026-06-23 | AM-20260622-003 | architect | android | accepted | FLAC 源恢复首轮实现通过：设置页恢复 Auto/BuguYY/FLAC，设置存储真实保存读取 source，Auto 按 BuguYY 空或失败后 fallback FLAC；搜索结果展示真实来源，resolve/download 按候选具体 source 分派；HTTP client 增加瞬时网络重试并补测试。小米 10 Pro 证据显示搜索 `黑夜传说` 时 BuguYY count=0、FLAC count=40，下载和播放链路成功。 |
| 2026-06-23 | AM-20260622-003 | product | android | changes_requested | 产品新增两个 1.0.0 阶段版必修验收点，撤回首轮 accepted：Auto 模式必须同时搜索 BuguYY 和 FLAC，不再只在 BuguYY 无结果时 fallback；FLAC 源歌曲必须解决封面和歌词缺失问题。修复后需重新提供 `黑夜传说` 真机证据和日志摘要，再由 architect 复审。 |
| 2026-06-23 | AM-20260622-003 | architect | android | changes_requested | Auto 双源并搜和 FLAC 字段扩展方向通过，但旧缓存 metadata 刷新条件过窄：只在旧缓存无封面且搜索候选自带封面时 resolve，漏掉搜索候选无封面但 getUrl 有封面、以及旧缓存已有封面但缺歌词的场景。需扩大轻量 resolve 条件并补测试，仍不得重新下载音频。 |
| 2026-06-23 | AM-20260622-003 | product | android | changes_requested | 产品补充最终 review gate：Auto 文案必须是双源并搜；搜索结果左侧来源标记 BuguYY 显示“布谷”、FLAC 显示 `FLAC`；副标题不能显示搜索源名称；FLAC 下载、resolve、历史缓存刷新必须能补歌词；播放页“暂无歌词”要自动尝试恢复并提供“重新获取歌词”，手动重试绕过 miss TTL 且不重新下载音频。 |
| 2026-06-23 | AM-20260622-003 | architect | android | changes_requested | 复审仍需回改：UI 文案/来源标记/副标题、Auto 双源并搜、播放页手动歌词恢复和 miss TTL 绕过方向已覆盖；但旧缓存缺封面刷新仍要求搜索候选自带封面，漏掉候选无封面但 resolve/getUrl 返回封面的历史缓存场景。需去掉候选封面前置条件并补不重新下载音频的测试。 |

## 结果值

- `accepted`：已通过，不需要继续处理。
- `changes_requested`：有可执行问题，需要发回 owner lane 修复。
- `blocked`：缺少上下文或外部条件，暂时无法完成 review。
- `not_reviewed`：明确跳过 review，必须说明原因。

## 分发规则

- 任何 lane 提交或准备提交后，先发给 `architect` lane review。
- 架构师 review 后，必须按实际影响范围分类。
- 分类后的问题只发给相关 lane 处理，用户不负责手动搬运 review 结果。
- 如果不涉及某个 lane，不要通知它；不要为了“同步”而广播无关 review。
- 如果某个分类无问题，review 摘要里明确写“无问题”。
- 鸿蒙代码的默认闭环是 `ohos -> architect review -> ohos`；只有确实涉及公共 Dart、Android 或 iOS 时，才额外通知其它 lane。
