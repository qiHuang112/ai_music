# Android Native Compose 增量差异 R1

Status: implementable
Revision: NCUX-20260726-R1
Requirement: sha256:b8414836fa8ced7574f0463d497d2c22029828cc0e60c4c99771d93e734131ee
Native baseline: codex/native-unified-milestone@d948a893f5d14d53942fbbaedf333a974e2ae015
Compose review source: `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_compose_ui`

## 用户批准证据

三张图是唯一视觉方向，Flutter final3 与旧 style explorer 均只作历史输入。

| 页面 | 冻结图 | sha256 |
| --- | --- | --- |
| 首页 / 库与发现 | `user-approved-home-library-discovery.png` | `790007848a9521b7e96ea90b4e08360ee60987f594316b868e79c15dfd6a3d27` |
| 搜索结果 / 键盘 | `user-approved-search-results-keyboard.png` | `0013211aaf8110b6a90d4acdd1dd6d8e85e1c98bde543905f8167e88f486bbbb` |
| 全屏播放 / 队列 | `user-approved-player-queue.png` | `268ef7db1cece8b41f605b2acb7105a83047c33a5ef3dc5ed745f70b5818691b` |

视觉基调固定为黑色偏青背景、薄边界深色表面、薄荷青主操作、真实封面优先、系统 Material 图标。不得恢复来源文字方块、播放中/可下载/已缓存胶囊标签或模拟键盘。

## 三图到当前 Compose 的最小可见差异

### 首页 / 库与发现

- 已实现：深色主题、顶部下载/队列入口、整行搜索入口、收藏与自建歌单、热榜、发现卡、真实封面、底部迷你播放器、三项底部导航及加载/空态/失败态。
- S5 最小差异：维持三图的信息顺序；搜索框为最高层级控制；收藏与歌单并排；热榜和发现使用大卡但不嵌套卡；迷你播放器固定在底部导航上方，显示封面、标题、歌手、上一首/播放暂停/下一首。
- 能力依赖：收藏数、歌单数、热榜摘要和发现歌曲来自产品数据仓库；下载、队列、设置入口只有存在路由时才可点击。无路由时隐藏，不展示假控件。

### 搜索结果 / 键盘

- 已实现：真实输入框、系统 IME Search、清空、结果数、封面/占位封面、标题/歌手/格式/大小、播放、下载可用/下载中/已下载/不可下载/失败、加载/空态/失败保留、刷新和加载更多。
- S5 最小差异：首条结果保持视觉重点；每行只保留一个主播放按钮和一个下载状态动作；下载中使用环形进度；严格校验失败用琥珀色说明，不把失败项伪装成成功；键盘使用 Android 系统键盘，允许遮挡底部内容，不制作模拟键盘。
- 能力依赖：综合/单曲/歌手/专辑/歌单/歌词分类及“可下载优先”需要真实分类和排序能力。本轮未具备时不显示这些控件，不扩业务规则。

### 全屏播放 / 队列

- 已实现：返回、队列数量、方形真实封面、标题/歌手、同步歌词高亮、进度拖动与时长、上一首/播放暂停/下一首、队列开合、队列封面、当前行标识、点选跳转、无播放空态。
- S5 最小差异：播放页按“封面 > 曲名歌手 > 歌词 > 进度 > 控制”单轴排布；主播放按钮使用薄荷青实心圆；队列作为同页底部面板，当前行用弱抬升表面和薄荷青均衡器标识，其他行保持低对比。
- 能力依赖：收藏、加歌单、播放模式、停止、清空、移除、重排和行菜单只有对应 repository/controller API 存在时才能接入。当前没有能力时不得显示或作为验收阻断；队列点选、上一首、下一首、播放暂停和 seek 可直接使用现有事件。

## S5 可直接实现清单

1. 复用 `MusicPresentationColors`，保持 `#06100E` 背景、`#111A18` 表面、`#77DED3` 强调色；卡片圆角不超过 8dp，触控目标至少 48dp。
2. `LibraryFirstScreen` 保持三图顺序，并把 `MusicMiniPlayer` 固定在底部导航上方；封面无 URL 时使用 Material Album 图标，不使用文字来源占位。
3. `SearchResultsScreen` 保持系统键盘与当前状态模型；统一结果行高度、封面尺寸、操作列宽，避免下载状态变化引起布局跳动。
4. `PlayerQueueScreen` 保持方形封面和同步歌词；队列当前行使用现有 `isCurrent/isPlaying`，补充视觉强调但不新增队列业务动作。
5. 复用现有 loading、empty、failure、refreshing、loading-more、download-state、playing 状态；失败保留已有结果，不切换为全页错误。
6. 所有图标使用 Material Icons；所有可交互图标提供中文 contentDescription；系统状态栏、导航栏及 IME 使用安全区。

## 影响面

- UI：`ui/LibraryFirstScreen.kt`、`ui/SearchResultsScreen.kt`、`ui/PlayerQueueScreen.kt`、`ui/MusicPresentationComponents.kt`。
- Presentation：只消费现有 `LibraryUiState`、`SearchScreenUiState`、`PlayerUiState`，不要求改变 domain 规则。
- Data/playback：仅提供真实计数、封面、歌词、下载和队列状态；缺失能力不由 S5 伪造。

## Design QA

1. 首页、搜索、播放三页均与对应冻结图同状态截图并排复核，检查层级、间距、封面裁切、字体、边界与 8dp 圆角。
2. 360x800、393x873 与小米 10 Pro 真机无横向溢出，长标题两行或省略，操作列不被挤压。
3. 首页验证 loading、empty、failure、real-data、playing；迷你播放器不与底部导航重叠。
4. 搜索验证输入、系统键盘、首批 loading、结果、全空、失败保留、加载更多、下载五态。
5. 播放验证无歌曲、封面加载失败、无歌词、同步歌词、seek、暂停/播放、上一首/下一首和队列开合。
6. 队列验证 0/1/多首、当前行、播放中、长标题、真实封面缺失；未支持的清空/移除/重排/菜单不得出现。
7. TalkBack 可读顺序符合视觉顺序，图标有中文语义，文字和主要控件达到可读对比。
8. 设计稿验收与真实落地 UI 验收分开；本 revision 只授权粗实现和增量修正，不代签真机最终 UI。

## Proposal（不进入本轮 P1）

- 搜索分类、可下载优先、收藏、加歌单、播放模式、队列清空/移除/重排。
- 这些能力可保留在后续设计，不得在没有真实 API 时先展示可点击假控件。
