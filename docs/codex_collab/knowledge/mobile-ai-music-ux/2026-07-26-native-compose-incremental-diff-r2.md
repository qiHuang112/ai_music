# Android Native Compose 增量差异 R2

Status: implementable
Revision: NCUX-20260726-R2
Request: AM-20260726-001
Requirement: sha256:4ac5d1f892808c4fb3550bfbbdda66328407c64a8770942b2ada2d7601aa0628
Requirement file: `docs/superpowers/specs/2026-07-26-android-native-unified-epic-requirement-r2.md`
Supersedes in scope: NCUX-20260726-R1 的 Back、system bars 与歌词呈现说明
Native delivery: Android Native Compose，同一 Epic，不新增 request

## 结论与边界

R2 是首轮 Native 真机反馈的最小 UX 增量，只新增或收紧以下可见行为：

1. 子页、播放器、歌词详情和队列使用同一套应用内 Back 层级。
2. 所有目标页使用 edge-to-edge，系统栏背景与页面连续，图标始终可读。
3. 播放页保留三行歌词摘要入口，并新增完整可滚动歌词详情。
4. 歌词详情支持播放进度跟随、手动滚动后恢复、点行 seek、空态以及与队列互斥。

搜索耐久、批量分页、中文 IME、歌源熔断、完整音频准入、Media3、缓存和下载仍由 requirement R2 与开发切片约束，本 UX revision 不改业务规则。

## 谱系与冻结依据

### Requirement

- 唯一绑定：`sha256:4ac5d1f892808c4fb3550bfbbdda66328407c64a8770942b2ada2d7601aa0628`。
- semantic R1 `sha256:b8414836fa8ced7574f0463d497d2c22029828cc0e60c4c99771d93e734131ee` 只保留历史谱系，不再作为 NCUX-R2 的实施门禁。
- DISC-0012 的六个 finding 已由 requirement R2 收敛为五条 P1；本文件只负责其中应用壳层和歌词详情的 UX 增量。

### NCUX-R1

- 基线文档：`docs/codex_collab/knowledge/mobile-ai-music-ux/2026-07-26-native-compose-incremental-diff-r1.md`。
- 基线 revision：`NCUX-20260726-R1`。
- 基线 sha256：`653e125079ff79e687c48adeea73366a5a615f3907ac56b950f50c2946e1872f`。
- R1 中的黑青视觉 tokens、三页信息顺序、真实封面优先、系统 Material 图标、稳定结果行、mini player 安全停靠、播放页单轴层级和队列当前行强调继续有效。
- R2 只在 Back、edge-to-edge/system bars、歌词摘要与歌词详情上取代 R1；其它 R1 规则不重写。

### 三张用户批准图

| 页面 | 冻结图 | sha256 | R2 关系 |
| --- | --- | --- | --- |
| 首页 / 库与发现 | `user-approved-home-library-discovery.png` | `790007848a9521b7e96ea90b4e08360ee60987f594316b868e79c15dfd6a3d27` | 保持首页层级、黑青背景与底部安全区 |
| 搜索结果 / 键盘 | `user-approved-search-results-keyboard.png` | `0013211aaf8110b6a90d4acdd1dd6d8e85e1c98bde543905f8167e88f486bbbb` | 保持系统 IME、紧凑结果行与深色系统栏 |
| 全屏播放 / 队列 | `user-approved-player-queue.png` | `268ef7db1cece8b41f605b2acb7105a83047c33a5ef3dc5ed745f70b5818691b` | 保持播放器单轴层级；歌词详情是该页的下一层，不替换队列设计 |

Flutter final3、旧 style explorer、模拟键盘、来源文字方块和未批准控件继续只作历史输入。

## 最小可见差异

| 区域 | 当前问题 | R2 最小结果 | 不做 |
| --- | --- | --- | --- |
| Back | 子页系统 Back 可直接退桌面 | 先消费应用内层级，只有 Library 根页才交回系统 | 不引入第二套返回逻辑 |
| System bars | 状态栏为独立黑条，页面未通顶 | 页面背景绘制到系统栏下方，内容按安全区避让，图标按背景明暗切换 | 不用固定黑色状态栏遮住页面 |
| 歌词摘要 | 播放页缺少明确的完整歌词入口 | 当前行前后共三行摘要，整块可进入详情 | 不新增收藏、歌单或来源标签 |
| 歌词详情 | 只能看到局部歌词 | 完整列表、当前行跟随、手动浏览恢复、点行 seek、明确空态 | 不伪造歌词、时间戳或加载结果 |

## Back 层级

系统 Back、顶部返回图标和手势返回必须进入同一个导航处理器，结果一致。可见层级按以下顺序消费：

1. 系统 IME、对话框或底部浮层可见时，先关闭当前系统/临时层，不离开页面。
2. 歌词详情可见时，返回播放器主视图；播放、进度和当前歌曲保持不变。
3. 播放器队列可见时，只关闭队列，仍留在播放器。
4. 播放器主视图返回打开播放器前的来源页，例如 Search 或 Library。
5. Search、Downloads、Hotlist、Settings、Favorites、Playlists 等普通子页返回 Library 或其真实来源页。
6. 只有 Library 根页且没有任何临时层时，才把 Back 交给系统退出。

### Back 与队列

- 歌词详情与队列互斥，不能同时显示。
- 从播放器打开歌词详情时先确保队列关闭；歌词详情不展示队列入口或隐藏的队列面板。
- 队列打开时，系统 Back 和顶部返回第一次都只关闭队列。
- 歌词详情 Back 返回播放器时队列保持关闭，不能重新弹出此前队列状态。
- 顶部返回与系统 Back 复用同一事件，不允许一个回播放器、另一个退桌面。

## Edge-to-edge 与 system bars

### 背景

- Window 采用 edge-to-edge；状态栏背景透明，由当前页面最外层 surface 延伸填充。
- Library、Search、Player、Lyrics Detail 与 Queue 的默认顶层背景均延续 R1 的 `#06100E`，不得再出现独立纯黑状态栏带。
- 滚动页顶部发生折叠或内容经过状态栏时，顶部 surface 仍延伸到状态栏区域，避免背景闪变或图标落在复杂封面上。
- 底部导航栏区域透明或使用与当前底部 surface 一致的深色，不出现与页面割裂的亮条或黑条。

### 图标

- `#06100E`、`#111A18` 等深色背景使用浅色状态栏和导航栏图标。
- 如果未来页面实际顶层 surface 为浅色，图标模式必须随该 surface 切为深色；不能把图标模式写死为白色。
- 系统栏图标可读性由最终截图判断；UI XML 只用于证明应用控件未侵入状态栏触控区域。

### Insets

- 背景可以通顶，顶部返回、标题、搜索框等可交互内容必须位于 `statusBars`/`displayCutout` 安全区之后。
- mini player、底部导航、队列末行和歌词末行必须包含 `navigationBars` 底部安全区。
- Search 在 IME 打开时由系统键盘占用底部；结果列表使用 IME inset，不把最后一行主操作压在键盘后方。
- 同一 inset 只消费一次，禁止 `SafeArea` 与手工 padding 叠加造成双倍空白。

## 歌词摘要入口

- 位置保持在播放器的“曲名歌手”之后、“进度条”之前，不改变 R1 的单轴层级。
- 有同步歌词时显示当前行及相邻行，最多三行；当前行使用 `#77DED3`、较高字重，其他行使用次级文字色。
- 整个摘要区域是一个触控目标，最小高度 96dp、触控高度不小于 48dp；点击进入歌词详情。
- 摘要区提供中文语义“查看完整歌词”，不能只依赖颜色或手势猜测。
- 当前行变化不得让摘要区域高度跳动；长歌词单行省略，不挤压进度条与播放控制。
- 只有普通无时间戳歌词时可显示前三行真实文本，但不显示伪高亮。
- 无歌词时显示中性文案“暂无歌词”；仍允许进入详情查看同一明确空态。
- 若 presentation 能明确区分加载与失败，则分别显示“正在加载歌词”和“歌词加载失败，可继续播放”；不能根据 `lyrics == null` 猜测失败。

## 完整歌词详情

### 页面结构

1. 顶部栏：返回图标与标题“歌词”，位于状态栏安全区下方。
2. 歌曲信息：当前真实歌曲名与歌手，各自限制行数并省略超长文本。
3. 歌词区：占用剩余空间的完整可滚动列表。
4. 页面不重复放置封面、播放控制、收藏、歌单、来源标签或队列按钮，保持歌词阅读单一任务。

### 同步与跟随

- 同步歌词保留每行真实 timestamp；播放进度变化时更新当前行。
- 未发生手动滚动时，当前行保持在视口约 45% 至 50% 的稳定阅读位置。
- 只有当前行索引发生变化时才做 200ms 至 300ms 的轻量滚动，不跟随每个 position tick 抖动。
- 当前行使用 `#77DED3`、较高字重和更高字号；非当前行使用次级文字色。颜色之外还必须有字重或语义状态差异。
- 切歌或歌词内容变化时，重置旧滚动状态，并跟随新歌曲当前行。
- 暂停时保持当前行，不自动跳回列表顶部；继续播放后从当前进度恢复跟随。

### 手动滚动与恢复

- 用户开始拖动歌词列表时立即暂停自动跟随，避免列表与手势争抢。
- 手动浏览期间可显示中线引导和该行真实时间；不得伪造没有 timestamp 的时间。
- 每次新的滚动都重置恢复计时；最后一次滚动结束并空闲 2 秒后，自动回到当前播放行并恢复跟随。
- 恢复使用一次短动画；不新增长期悬浮的“回到当前”假状态按钮。

### 点行 seek

- 只有带有效 timestamp 的歌词行可点击。
- 点击后调用现有 seek 能力跳到该行时间，立即结束手动浏览并恢复当前行跟随。
- 点行 seek 不改变播放/暂停状态，不重建队列，不切歌，也不触发下载或缓存业务。
- 无时间戳普通歌词只可阅读，不响应 seek，不显示可点击反馈。

### 空态与失败态

- 当前歌曲没有可用歌词：显示“暂无歌词”，保留顶部返回和歌曲信息。
- 歌词加载中且状态真实可用：显示小型进度指示与“正在加载歌词”。
- 歌词加载失败且错误状态真实可用：显示“歌词加载失败，可继续播放”；不把播放器切成全页错误。
- 普通无时间戳歌词：完整显示真实文本，但不伪造当前行、自动跟随、时间或点行 seek。
- 切歌后旧歌词必须立即退出，不能短暂显示到新歌名下。

## 能力依赖

### 当前能力可直接复用

- `PlayerUiState.currentTrack` 提供真实歌曲名、歌手、封面和歌词 metadata。
- `PlayerUiState.positionMs`、`durationMs` 与现有 Media3 状态提供当前播放进度。
- 现有 `SeekRequested(positionMs)` 可承担点行 seek，不需要新增播放业务动作。
- 现有队列显隐、歌词显隐和播放器来源页状态可承载 Back 层级。
- R1 的 `MusicPresentationColors`、Material 图标、中文语义和安全区规则继续复用。

### S5 / integrator 需要补齐的 presentation 能力

- 同步歌词 presentation 行必须保留真实 `timestampMs`；如果中间 UI model 丢弃 timestamp，点行 seek 不得用列表索引或估算时间代替。
- 自动跟随、手动浏览、2 秒恢复和中心引导全部是页面本地 UI 状态，不要求修改 Media3 或 domain 合同。
- edge-to-edge、system bar 图标模式和全局 Back 由共享 shell 接线；S5 只负责页面 surface、insets 和可见状态。
- 若需要区分“加载中 / 无歌词 / 加载失败”，上游必须提供真实 availability/error 状态。未提供前只能展示中性“暂无歌词”，不能伪造网络失败。

### 必须隐藏的无能力控件

- 收藏、收藏计数、加歌单、自建歌单编辑。
- 播放模式、停止、队列清空、移除、重排、行菜单。
- 搜索分类、可下载优先等尚无真实分类/排序 API 的控件。
- 任何来源标签、模拟键盘、假进度、假重试或不能执行的按钮。

## S5 可直接实现清单

1. 复用 R1 tokens 和三页层级，只增量修改 shell、播放器歌词区与歌词详情，不重排首页或搜索页业务内容。
2. 让系统 Back、顶部返回和手势返回走同一导航处理器；按“临时层 / 歌词 / 队列 / 播放器 / 普通子页 / Library 根页”消费。
3. 在共享 shell 开启 edge-to-edge；页面背景绘制到系统栏，顶部与底部交互内容分别消费正确 insets，深色场景使用浅色系统图标。
4. 播放页歌词区域固定为最多三行摘要，保持稳定高度、当前行强调、整区点击和中文“查看完整歌词”语义。
5. 歌词详情复用真实歌曲、歌词和 position；完整列表保留 timestamp，当前行稳定跟随，普通歌词不伪造同步状态。
6. 用页面本地滚动状态实现“手动滚动暂停跟随，空闲 2 秒恢复”；切歌和歌词变化时重置状态。
7. 带 timestamp 的行点击发送现有 `SeekRequested`；保持播放/暂停、歌曲和队列不变。
8. 实现无歌词、真实加载中、真实失败和普通歌词状态；上游未提供的状态不猜测。
9. 歌词详情和队列保持互斥；详情页不显示无 API 控件，队列 Back 只关闭队列。
10. 保留或新增稳定 test tag 与中文 semantics：`player-lyrics-content`、`player-lyrics-empty`、`lyrics-detail`、`lyrics-detail-list`、`lyrics-detail-active-line`、`lyrics-detail-empty`、`返回播放器`。

## 最终 Screenshot / XML Design QA

最终验收使用同一 HEAD、同一 APK、同一设备、同一播放会话采证；截图证明视觉，UI XML 证明层级、语义和控件边界，二者不能互相代替。

1. **Back 根层级：**从 Library 进入 Search，系统 Back 先关闭 IME，再返回 Library；Library 根页才允许退出。截图/XML 记录每一层，不能只给最终首页。
2. **播放器来源页：**从 Search 打开 Player，再按 Back 返回 Search；播放状态与当前曲目不丢失。
3. **队列与歌词：**Player 打开 Queue，Back 只关闭 Queue；进入 Lyrics Detail 时 Queue 已关闭；Lyrics Detail Back 返回 Player 且 Queue 不复现。
4. **Edge-to-edge：**Library、Search+IME、Player、Lyrics Detail、Queue 各一组截图。状态栏背景与页面连续、无独立黑条，系统图标清晰；XML 中顶部可交互控件 bounds 不侵入状态栏。
5. **歌词摘要：**同一真实歌曲截图/XML 显示最多三行、当前行强调、稳定区域与“查看完整歌词”语义；无歌词样例显示中性空态。
6. **同步跟随：**同一播放会话采两帧不同 position，当前行随 Media3 进度变化且位于稳定阅读区；绑定 media position/logcat，不能只用两张静态 fixture。
7. **手动滚动与恢复：**先采手动浏览状态，再在最后一次滚动结束 2 秒后采自动跟随恢复；XML/test 证明滚动期间不被 position tick 拉回。
8. **点行 seek：**记录点击行 timestamp、seek 前后 position、当前行和播放/暂停状态；期望位置跳转、播放状态不变、队列不变。
9. **歌词状态：**覆盖同步歌词、普通歌词、无歌词，以及状态真实可用时的加载/失败；不得在 XML 中出现 demo 歌词、假时间或不可执行按钮。
10. **安全区与无假控件：**小米 10 Pro 及 360x800、393x873 至少完成布局检查；歌词末行、队列末行、mini player 不被导航栏/IME 遮挡，收藏/歌单/清空/移除/重排/菜单等无 API 控件不出现在截图或 XML。

## 风险与验收边界

- 系统栏图标颜色无法由 UI XML 独立证明，必须使用真实截图复核。
- 当前 Native presentation 若只暴露 `lyrics: String?`，无法可靠区分加载失败与无歌词；该差异必须由真实状态输入解决，UX 不允许猜测。
- 普通歌词没有 timestamp 时只能阅读；不应为满足动效而制造伪同步。
- 本 revision 是可实施 UX 增量，不代签最终真机 UI。最终通过仍以 requirement R2 的单候选、串行小米 10 Pro screenshot/XML/logcat 与用户体验结论为准。
