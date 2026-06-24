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
| 2026-06-22 | AM-20260622-002 | architect | android | changes_requested | 撤回此前 accepted 口径：产品小米 17 Pro 真机验收确认安卓播控收藏和随机短听跳过均未达到验收。后续 review 必须要求 Android 系统媒体控件 compact slot、custom action 回调、收藏状态同步、手动 next 与自动下一首区分、播放器原生 shuffle 覆盖风险的真机证据。 |
| 2026-06-22 | AM-20260622-003 | architect | android | blocked | 因 AM-20260622-002 真机验收失败，恢复 FLAC 资源源任务暂停推进；android lane 先修复 AM-20260622-002 并复盘单测/review 与真机结果不一致的问题。 |
| 2026-06-22 | AM-20260622-002 | architect | android | changes_requested | 第二轮复审仍需回改：`MediaAction.rewind` 承载收藏槽位方向可继续验证，但关闭 `just_audio` 内建 shuffle 后，当前代码只让手动 `skipToNext()` 走 Dart planner；自然播放到下一首仍可能按原队列顺序前进，导致随机播放语义退化。 |
| 2026-06-22 | AM-20260622-002 | architect | android | changes_requested | 第三轮复审仍需回改：自动播完走 `nextAfterCompleted()` 的方向正确，但 `_manualTargetIndex` 在手动 seek/恢复到当前同一 index 时可能因 `currentIndexStream` 不发新 index 而残留，下一次自然播放会被误判成手动跳转并绕过自动随机重定向。 |
| 2026-06-22 | AM-20260622-002 | architect | android | changes_requested | 第四轮复审代码方向通过但验收证据不足：`PlaybackIndexTracker` 已覆盖手动目标残留边界，收藏槽位 workaround 可继续；accepted 前仍需补多曲开发测试设备证据，证明 shuffle 自然播下一首不顺序化、10 秒内手动 next 短听排除生效、10 秒后手动 next 不排除、自动下一首不触发短听排除。 |
| 2026-06-22 | AM-20260622-002 | architect | android | changes_requested | 第五轮复审仍需补证据：产品最新槽位口径已满足，系统播控只发布收藏 custom action、播放/暂停、下一首三项，不再发布 Stop；小米 10 Pro 多曲自然播完已证明随机不顺序化。剩余缺口是 10 秒内手动 next 触发短听排除缺少开发设备实测证据。 |
| 2026-06-22 | AM-20260622-002 | product | android | changes_requested | 产品截图补充后推翻第五轮槽位判断：安卓系统播控中心 P0 必须是 4 个槽位，顺序为收藏/取消收藏、上一首、播放/暂停、下一首；3 controls 或挤掉上一首不符合预期。下一轮必须真机证明 4 槽位可见可点。 |
| 2026-06-22 | AM-20260622-002 | architect | android | changes_requested | 第六轮复审确认 4 槽位代码和小米 10 Pro 证据通过：完整 controls 为收藏/取消收藏、上一首、播放/暂停、下一首，Stop 不进入系统播控，compact indices 为 `[0,2,3]`。任务未 accepted 的唯一剩余缺口是 10 秒内手动 next 触发短听排除仍缺开发设备实测证据。 |
| 2026-06-22 | AM-20260622-002 | architect | android | accepted | 第七轮复审通过：小米 10 Pro 已验证系统播控四槽位为收藏/取消收藏、上一首、播放/暂停、下一首，收藏同步生效；多曲自然播完随机不顺序化；App 内下一首按钮 10 秒内连续手动 next 后未立即回到短听跳过歌曲，满足当前随机短听排除验收。 |
| 2026-06-22 | AM-20260622-002 | product | android | clarification_needed | 产品继续调整安卓播控中心逻辑：点赞/收藏从左侧改到右侧，右侧原点赞位置改成切换播放模式。该口径和当前 accepted 的 4 槽“收藏、上一首、播放/暂停、下一首”冲突；如果同时要求播放模式、上一首、播放/暂停、下一首、收藏，则是 5 个动作，需要先确认 Android/MIUI 系统槽位能力并由 product 决定取舍。 |
| 2026-06-22 | AM-20260622-002 | android | architect | blocked | android lane 暂停 AM-002/AM-003，回报小米 10 Pro/MIUI 稳定主槽位为 4 个，若同时放播放模式、上一首、播放/暂停、下一首、收藏则需要 5 个动作，必须 product 决定取舍。android 建议保留上一首/播放暂停/下一首/收藏四槽，播放模式放 App 内或扩展入口。另有未提交的收藏导致进度条回跳修复，需随最终槽位方案一起 review。 |
| 2026-06-22 | AM-20260622-002 | product | android | review | 产品确认播放模式重排暂缓/撤回：Android 系统播控继续使用已验证 4 槽“收藏/取消收藏、上一首、播放/暂停、下一首”。后续 review 不再要求槽位重排，只聚焦收藏点击导致播控进度条跳变修复，以及既有 4 槽位/随机短听逻辑不回退。 |
| 2026-06-22 | AM-20260622-002 | architect | android | accepted | 第八轮复审通过：`syncControlState()` 同步收藏控件时补齐当前 position、buffer、speed 和 queueIndex，避免只刷新 controls 导致 Android 系统播控进度条按旧 position/新 timestamp 跳变；测试覆盖不触发 loadQueue、restore 或 seek，小米 10 Pro 证据显示收藏/取消收藏后进度自然前进且队列不变。提交范围限 AM-002 三个业务/测试文件。 |
| 2026-06-23 | AM-20260623-001 | architect | ohos | accepted | `0ef5e58` 小回改复审通过：默认首页不再渲染旧搜索提示块，不显示 icon、“搜索音乐”和“输入歌手或歌曲名，下载后会保存在本机缓存里。”；收藏/自建歌单入口仍保留，`_SearchEmptyPrompt` 只保留给非默认的输入未搜索状态；提交范围未触碰 `MusicController`、播放链路、搜索/FLAC/metadata 或平台宿主。提交前需 amend trailer 为 `Reviewed-by-lane: architect`。 |
| 2026-06-23 | AM-20260623-003 | architect | android/ohos | assigned | 产品集成体验发现 3 个问题，已拆分定责：P1 鸿蒙下载完成立即播放无声、杀进程重进可播，先由 ohos lane 只复现定位；P2 Android 与 HarmonyOS 下载完成后播放按钮延迟 2 到 3 秒出现，先由 android lane 查公共 Dart cache/candidate 状态刷新；P2 已有封面的缓存歌曲播放时疑似重复下载封面，先由 android lane 查 metadata/cache 策略，ohos 只在证据显示 HarmonyOS 平台重复触发时参与。 |
| 2026-06-23 | AM-20260623-003 | architect | android | changes_requested | Android 公共 Dart 修复方向基本正确：下载完成后先 upsert 内存 `LibrarySnapshot`、metadata/loadCache 后台执行、已有 artUri 不重复 `updateCurrentMediaItem`、metadata provider 增加封面/歌词能力标记都符合验收方向。但仍有 1 个 P2：已有缓存封面但缺歌词时，`_refreshCachedCandidateMetadata()` 会走 `resolve()` 补歌词，而 `_mergeResolvedMetadata()` 仍会用 resolved `coverUrl` 覆盖已有 `current.coverUrl`，可能导致播放时换封面/重新拉图。要求已有 cover 时只补歌词，不允许 resolved cover 覆盖；只有 `missingCover == true` 时才允许补封面，并补“已有 cover + resolver 返回不同 cover + 缺歌词”的测试。 |
| 2026-06-23 | AM-20260623-003 | architect | ohos/android | changes_requested | ohos 严格复现补充后，P1 暂不按 HarmonyOS 原生播放失败处理：MUSIC 音量从 0/mute 调到 5 后，全新未缓存 `Yellow / 蔡健雅` 下载完成立即播放成功，`AVPlayer initialized/prepared/playing`、position 递增、AudioRenderer 和 AVSession metadata 均正常。保留验收前检查 MUSIC 音量的流程要求。新增公共 Dart/UI finding：搜索结果行只按 `isCached` 固定显示 play 图标，不跟随当前 `mediaItem`/`playbackState`，播放成功时仍可能显示三角形，容易让产品误判没播；该问题归 android lane，需在搜索结果当前播放歌曲上显示 active/equalizer/pause 态或等价反馈。 |
| 2026-06-23 | AM-20260623-001 | architect | ohos | accepted | 首页默认展示收藏和自建歌单实现通过：提交 `9d38b5a` 只改公共展示层和 widget 测试，未触碰 `MusicController`、播放链路、搜索/FLAC/metadata 或平台宿主；未搜索首页展示收藏/自建歌单入口，搜索态隐藏默认首页，清空搜索恢复默认首页。接受点击进入现有详情页的保守实现，直接播放整列表后续另拆。 |
| 2026-06-23 | AM-20260623-001 | product | ohos | changes_requested | 产品补充小回改：默认首页已经展示“我的音乐”、收藏和自建歌单入口后，搜索框下方旧空态提示块应移除，包括 icon、“搜索音乐”和“输入歌手或歌曲名，下载后会保存在本机缓存里。”修复后仍需保留收藏/歌单入口，搜索输入和搜索结果状态不能回退。 |
| 2026-06-24 | AM-20260623-003 | product | ohos | blocker | 产品澄清新 P1 串歌发生在 HarmonyOS，Android 没有问题。ohos lane 为主 owner，需复现并排查 `just_audio_harmonyos` 本地 fd/data source、AVPlayer source、预加载播放器升格、AVSession metadata 与 Dart mediaItem 是否错位；accepted 前必须提供鸿蒙测试机 3 首不同歌曲逐个点击播放不串歌证据。 |
| 2026-06-24 | AM-20260623-003 | architect | ohos | blocked | 进一步定位为 HarmonyOS vendored plugin 缓存旧 `MediaSource` 队列：full `load` 前没有清空/刷新 `mediaSources`，native `songList` 沿用旧 3 首队列。请在 `lane/ohos` 修 `AudioPlayer.ets` mediaSources 刷新和 `MediaAvPlayer.loadAssent()` 越界/load failure 可靠回传；Android 公共 Dart 队列修复降为后续安全加固/必要时协助。 |
| 2026-06-24 | AM-20260623-003 | architect | ohos | in_progress_fix | 已分派 ohos 直接进入修复阶段，不再等待新 worktree：在 `/Users/huangqi/AIHome/projects/ai_music_ohos` 的 `lane/ohos` 修改 `AudioPlayer.ets` full load 清空/刷新 `mediaSources`，并修改 `MediaAvPlayer.loadAssent()` 越界/load failure 可靠回传 Dart。修复后构建 signed HAP，安装到 `192.168.31.53:10178`，复测 `qi` 歌单后搜索/下载/播放多首 `yellow` 的串歌路径。 |
| 2026-06-24 | AM-20260623-003 | architect | ohos | accepted | `5916b4c` 鸿蒙播放器旧队列复用修复通过：full load 重建 native source tree，清理旧 next preload，`loadAssent()` 越界/空 uri 可靠上抛；ohos 已在 `qi` 旧队列后连续播放 `yellow1` 到 `yellow4`，metadata、source path、file size 和 `AVPlayer play succeeded` 一致，未再出现串歌/无声。Android/公共 Dart 的下载按钮延迟、搜索结果当前播放态和封面重复拉取 P2 仍后续处理。 |
| 2026-06-24 | AM-20260622-003 | architect | android | accepted | 产品已在小米 17 Pro 验收 integration 包 OK，架构师复审并合入 `71a51bd`：Auto 双源渐进搜索、来源标记和副标题收敛、FLAC 歌词/封面字段解析、历史缓存 metadata 恢复、播放页重试入口、下载后缓存状态即时刷新、已有封面不重复拉取和暂停切歌自动播放均纳入 1.0.0。验证通过 `flutter analyze --no-pub`、`flutter test --no-pub` 121 项，release APK 约 9MB。 |
| 2026-06-24 | AM-20260624-001 | architect | ios | accepted | iOS provider 风险调研通过并同步知识库：第一版 metadata pipeline 推荐已有源字段、本地内嵌封面、iTunes 封面、LRCLIB 歌词；LrcAPI/MusicBrainz-CAA 低优先级或实验开关；网易/QQ/酷我非官方直连不进入第一版默认链路。Android 实现完成后需 handoff iOS 做 ATS、本地 file URI、锁屏封面和后台音频更新验证。 |
| 2026-06-24 | AM-20260624-003 | architect | android | assigned | 滑动切歌任务边界通过并创建专属 worktree `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260624-003`，分支 `feature/1.0.1/AM-20260624-003-swipe-to-skip`。Android 当前继续优先 AM-001，后续有容量时在该 worktree 开工，不混入 AM-001/AM-002 或 release hotfix。 |
| 2026-06-24 | AM-20260624-001 | architect | android | changes_requested | 第一轮 metadata pipeline review 要求回修：miss TTL 需持久化；iTunes/LRCLIB 匹配需加入 `country=CN` 和专辑评分；手动重试 API 需从 lyrics-only 语义改为 metadata miss 语义。 |
| 2026-06-24 | AM-20260624-001 | architect | android | accepted | 第二轮 metadata pipeline review 通过并合入 `c23ae84`：字段级歌词/封面 miss TTL 已持久化，iTunes/LRCLIB 匹配已收紧，`loadBypassingMetadataMiss` 语义清楚；架构师复跑 metadata 单测、analyze 和全量测试通过。 |
| 2026-06-24 | AM-20260624-003 | architect | android | accepted | 滑动切歌 review 通过并合入 `5ec19b6`：mini player 和播放详情页主体左右滑动复用现有上一首/下一首逻辑，按钮点击未回退；测试覆盖 mini player、播放详情页和 Slider 拖动不误触切歌，小米 10 Pro 同签 release 单曲边界验证通过。 |

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
