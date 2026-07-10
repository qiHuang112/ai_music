# UI Product Design 回归验收矩阵

Request: AM-20260711-002
Workflow: superpowers-v1
Lane: qa-researcher
Thread: 019f2fdd-e1e5-79c2-8a19-dd385fd20398
Created: 2026-07-11
Work Type: research/process
TDD Mode: not_applicable
Status: active

## 目标

为 AI Music 全量 UI Product Design 建立可重复执行的截图巡检和视觉验收矩阵。该矩阵服务 UI lane、QA lane、architect review 和 product 最终验收，覆盖：

- 首页、搜索、下载、mini player、播放详情、歌词、队列、收藏、自建歌单、热榜、下载管理、设置。
- Android 与 HarmonyOS。
- 空态、加载、失败、长文本、小屏、深色主题和可访问性风险。
- 1.1.0 设计硬约束：队列入口、跨页 mini player、完整音频边播收藏/加歌单入口、系统手势区、48px 触控目标、键盘处理、大字号、滚动 sheet/长列表、SafeArea 和 OHOS foreground-only/启动首帧风险。

本资产不等待其它 lane 出包才开始整理；真实验收时必须把本矩阵实例化为带包 SHA、设备、操作步骤、预期、实际、截图/录屏/日志路径的证据包。

## 证据目录规范

推荐目录：

```text
artifacts/AM-20260711-002/
  <platform>/
    <device>/
      manifest.txt
      screenshots/
        00_baseline/
        01_home/
        02_search/
        03_download/
        04_mini_player/
        05_player/
        06_lyrics/
        07_queue/
        08_favorites/
        09_custom_playlist/
        10_hotlist/
        11_download_manager/
        12_settings/
        13_system_controls/
        14_accessibility/
      recordings/
      logs/
      diagnostics/
```

截图命名：

```text
<request>_<platform>_<device>_<page>_<state>_<step>.png
```

录屏命名：

```text
<request>_<platform>_<device>_<scenario>_<result>.mp4
```

`manifest.txt` 必填：

```text
request:
package:
sha256:
versionName:
versionCode:
commit:
platform:
device:
deviceId:
osVersion:
screenSize:
fontScale:
theme:
network:
musicSource:
tester:
testTime:
```

## 状态覆盖表

| 页面/模块 | 必测状态 | 长文本/小屏 | 失败/降级 | Android 差异 | HarmonyOS 差异 |
| --- | --- | --- | --- | --- | --- |
| 首页 | 冷启动、有库、空库、mini player、热榜区块 | 长歌单名、4 个以上入口、小屏首屏是否挤压 | 热榜失败不影响本地音乐 | 返回键收起搜索/二次退出 | 返回行为、窗口安全区 |
| 搜索 | 输入、搜索中、未缓存、已缓存、当前播放、空结果 | 长歌名、多歌手、来源标签换行 | 网络失败、provider 失败、重试 | 输入法遮挡、系统返回 | 输入法/返回栈 |
| 下载 | 未下载、下载中、取消、完成、重复点击 | 下载按钮不挤压标题 | 下载失败、非音频、无 URL | 通知/后台切换后状态 | 后台恢复、沙箱路径 |
| mini player | 未播放、播放中、暂停、长标题、封面缺失 | 小屏底部无遮挡 | 当前 track 删除后降级 | 后台/通知同步 | AVSession 同步 |
| 播放详情 | 有封面歌词、无封面、有歌词无封面、播放模式、seek | 长标题、长歌手、控制区不换乱 | 音频加载失败、metadata miss | media session 状态 | AVPlayer/AVSession 状态 |
| 歌词 | 预览、详情、自动跟随、手动滚动、点击 seek | 长句、多语言、时间轴密集 | 无 timed LRC、重新获取失败 | 滚动性能 | 滚动/seek 同步 |
| 队列 | 入口、bottom sheet、当前曲高亮、长列表、跳播 | 50 首长列表、小屏 sheet 高度 | 空队列、单曲队列 | 手势冲突 | sheet 安全区 |
| 收藏 | 空收藏、有收藏、当前播放、高亮、取消收藏 | 长歌名、排序菜单 | 本地文件已删 | 系统收藏控件同步 | 播控点赞同步 |
| 自建歌单 | 空态、新建、详情、多选、排序、未保存确认 | 长歌单名、长列表、多操作按钮 | 删除/移除失败 | 返回确认 | 返回确认 |
| 热榜 | 首页入口、卡片成功、加载、stale、详情、点击搜索 | 长榜单名、长歌曲名、坏封面 | 全部失败、无网、缓存过期 | 点击条目进入搜索 | 入口/详情渲染 |
| 下载管理 | 活跃任务、最近任务、已缓存、排序、删除 | section 标题和按钮不拥挤 | 失败任务、空缓存、搜索无匹配 | 后台任务状态 | 后台任务状态 |
| 设置 | 语言、主题、音乐源、日志导出入口 | 长说明文案、小屏列表 | 日志导出失败 | Android 日志导出 | HarmonyOS 日志/权限 |
| 系统播控 | 锁屏/通知/播控中心、封面、标题、play/pause、next/prev、模式、收藏 | 长标题歌手截断合理 | 封面缺失降级、状态不同步 | notification/media_session | AVSession/hidumper |
| 可访问性 | 语义标签、触控目标、字号、对比度、焦点顺序 | fontScale 1.3/1.5、小屏 | 图标无语义、文字截断 | TalkBack 基线 | 屏幕朗读/焦点 |

## 必须截图的操作步骤

## 1.1.0 设计硬门禁

以下项目是 AM-20260711-002 的设计、截图和后续实现 QA 必验项；Product 选择视觉方向前只作为设计约束，不触发代码实现。

| Gate | Owner | Required Evidence | Fail Level |
| --- | --- | --- | --- |
| 当前播放队列有可见入口 | public Dart / UI implementation | 播放详情或 mini player 到当前队列的截图/录屏 | P1 |
| mini player 跨下载管理、设置、排序编辑持续可见 | public Dart / UI implementation | 三个页面截图，播放中状态不丢失 | P1 |
| 完整音频边下边播时有收藏和加入歌单入口 | public Dart / UI implementation | streaming 状态播放详情截图或录屏 | P1 |
| 横滑切歌避开系统边缘返回区 | public Dart + OHOS owner | Android/HarmonyOS 手势区验证截图或录屏 | P1 |
| 所有关键操作满足 48px 最小触控目标 | public Dart / UI implementation | 标注截图或 QA 测量记录 | P1 |
| 搜索提交后键盘收起/焦点/滚动行为正确 | public Dart / UI implementation | 搜索提交录屏，结果和主操作不被键盘遮挡 | P1 |
| 大字号下不依赖固定卡高 | public Dart + QA | fontScale 1.3/1.5 首页、搜索、播放、歌单截图 | P1 |
| 歌单选择 sheet 和下载长列表可滚动 | public Dart / UI implementation | 长列表滚动录屏，底部操作可达 | P1 |
| SafeArea/系统手势区不写死 | public Dart + OHOS owner | 刘海/状态栏/导航栏/手势区截图，内容不被遮挡 | P1 |
| OHOS foreground-only 与启动首帧风险被标注 | OHOS owner | HAP 启动、前后台或不可验证 blocker、白色启动窗到暗色首帧证据 | P2 |

### 00 Baseline

1. 安装指定包，打开 App。
2. 进入设置确认语言、主题、音乐源。
3. 截 `00_baseline/settings_source_theme`。
4. 预期：包版本和测试前置可复核；实际写入 manifest。

### 01 首页

1. 清空或准备空库，冷启动进入首页。
2. 截空库首页：`01_home/empty_library_light`。
3. 准备至少 3 首缓存、1 个收藏、2 个自建歌单，重启。
4. 截有库首页：`01_home/populated_library_light`。
5. 播放一首歌返回首页，截 mini player：首页底部不遮挡内容。
6. 切深色主题，截 `01_home/populated_library_dark`。

Pass 标准：本地音乐入口优先；热榜不挤掉收藏/自建歌单；长标题不溢出；mini player 不遮挡主操作。

### 02 搜索

1. 输入普通关键词，截搜索中：`02_search/loading`。
2. 截未缓存结果：`02_search/results_uncached`。
3. 点击下载按钮，截下载中：`02_search/downloading`。
4. 下载完成后截已缓存可播放：`02_search/cached_playable`。
5. 播放该结果，截当前播放态：`02_search/current_playing`。
6. 输入长关键词或无结果关键词，截空态/失败态。

Pass 标准：当前播放态必须可见；下载完成状态不被 metadata/歌词后台任务阻塞；失败态有重试，不误导为本地库故障。

### 03 下载 / 11 下载管理

1. 从搜索发起下载，进入下载管理。
2. 截活跃任务：`11_download_manager/active_downloading`。
3. 取消一次任务，截 canceled。
4. 触发失败或断网，截 failed 和错误摘要。
5. 下载成功后，截最近任务和已缓存列表。
6. 在已缓存列表搜索、排序、播放、删除，分别截图。

Pass 标准：活跃任务、最近任务、缓存列表层级清晰；失败有可解释状态；删除确认不误删；当前播放态在缓存列表可见。

### 04 mini player

1. 播放短标题歌曲，截默认 mini player。
2. 播放长标题/长歌手歌曲，截小屏。
3. 暂停，截暂停态。
4. 删除当前缓存或切歌后返回首页，截状态是否合理降级。
5. 分别进入下载管理、设置、排序编辑，截图确认 mini player 是否持续存在。

Pass 标准：标题/歌手可读，控制按钮可点，底部安全区正常，不遮挡页面主要入口。

### 05 播放详情

1. 播放有封面有歌词歌曲，截 `05_player/art_lyrics_playing`。
2. 暂停，截 pause。
3. 切换播放模式 sequence/list/single/shuffle，截至少一个模式菜单或状态。
4. seek 到中段，截进度和歌词同步。
5. 播放无封面歌曲，截降级封面。
6. 播放长标题歌曲，小屏截图。

Pass 标准：封面比例稳定；主控制区不拥挤；播放模式状态可理解；长文本不盖住歌词/按钮。

### 06 歌词

1. 从播放页进入歌词详情。
2. 截自动跟随态。
3. 手动滚动，截暂停跟随或用户滚动态。
4. 点击某句歌词 seek，录屏。
5. 无歌词歌曲，截无歌词和重新获取入口。
6. 重新获取失败，截失败反馈。

Pass 标准：当前歌词高亮明确；点击 seek 有可见反馈；无歌词不表现成加载卡死。

### 07 队列

1. 从播放详情打开当前队列 bottom sheet。
2. 截短队列、长队列、当前曲高亮。
3. 点击队列第 3 首跳播，录屏。
4. 单曲队列截空/不可切降级。
5. 截当前队列入口所在页面；如果没有入口，标记为 P1 设计断点。

Pass 标准：当前曲可定位；点击跳播后播放页、mini player 和系统播控一致；sheet 小屏不挡核心操作。

### 08 收藏

1. 在播放页收藏当前歌曲，返回收藏列表。
2. 截收藏列表普通态和当前播放态。
3. 取消收藏，截列表更新。
4. 使用排序菜单，截菜单。
5. 系统播控收藏/点赞可用的平台，录屏双向同步。
6. 完整音频边下边播状态下截图确认收藏入口仍可用。

Pass 标准：收藏状态 App 内和系统播控一致；列表空态和有数据态都可解释。

### 09 自建歌单

1. 新建歌单，截命名 dialog。
2. 从播放页或列表添加歌曲到歌单，截添加 sheet。
3. 打开歌单详情，截普通态。
4. 长按进入多选，截多选操作栏。
5. 进入排序编辑，截拖拽把手、完成按钮。
6. 未保存返回，截确认 dialog。
7. 删除歌单，截确认。
8. 完整音频边下边播状态下截图确认加入歌单入口仍可用。

Pass 标准：长歌单名不挤压操作；多选和排序是明确模式；危险操作有确认。

### 10 热榜

1. 首页截热榜入口成功态，至少一个 QQ 热歌榜卡片。
2. 截热榜加载中。
3. 模拟无网或 provider 失败，截全部失败/不可用，本地音乐仍可见。
4. 打开榜单详情，截顶部信息：封面、来源、更新时间、说明。
5. 截榜单列表：排名、封面、歌名、歌手。
6. 截坏封面/无封面占位。
7. 点击条目，录屏进入搜索，搜索词必须为 `title + artist`。
8. 截搜索命中、下载/播放或无结果。

Pass 标准：热榜只做发现元数据，不出现播放全部/下载全部暗示；失败不影响首页本地主路径；点击条目进入现有搜索链路，不直接播放第三方音频。

### 12 设置

1. 截设置首页。
2. 截语言页，切换中英文后返回关键页面各一张。
3. 截主题页，浅色/深色关键页面各一张。
4. 截音乐源页，Auto/BuguYY/FLAC 或当前可用源状态。
5. 如有诊断日志入口，执行导出并记录路径。

Pass 标准：设置项当前值明确；长说明不溢出；切换主题/语言后主要页面无布局破坏。

### 13 系统播控

Android：

1. 播放歌曲后下拉通知或锁屏。
2. 截标题、歌手、封面、play/pause、prev/next。
3. 点击 pause/play/next，录屏并保存 `dumpsys media_session`。

HarmonyOS：

1. 播放歌曲后打开播控中心。
2. 截标题、歌手、封面、play/pause、播放模式、收藏。
3. 点击 pause/play/loop/favorite，录屏并保存 `hidumper -s AVSessionService` 关键字段。

Pass 标准：可见即可用；系统状态和 App 状态双向同步；无封面时使用明确降级图，不串其它歌曲封面。

### 14 可访问性 / 小屏

1. 小屏设备或最小宽度模式截首页、搜索、播放页、歌单多选、热榜详情。
2. 设置系统字号到较大，截同一组页面。
3. 检查主要 icon 是否有语义说明，触控目标是否足够。
4. 深色主题检查文字/图标/分割线对比度。

Pass 标准：核心按钮可点；文字不互相遮挡；状态色不只依赖颜色表达；当前播放、失败、危险操作有文字或语义辅助。

## 视觉验收证据模板

```text
Design QA Evidence
request: AM-20260711-002
related_request:
platform: Android|HarmonyOS
package:
sha256:
versionName:
versionCode:
commit:
device:
deviceId:
osVersion:
screenSize:
fontScale:
theme:
tester:
testTime:

page:
state:
scenario:
steps:
  1. action:
     expected_visual:
     actual_visual:
     evidence:
result: pass|fail|blocker
visual_risk: none|layout|state_feedback|accessibility|platform_difference|copy|motion
severity: P0|P1|P2|P3|none
screenshots:
recordings:
app_logs:
platform_logs:
diagnostics_path:
owner_suggestion: ui|android|ohos|architect|product|qa
next_action:
```

## pass / fail 标准

`pass` 必须同时满足：

- 指定状态截图齐全，文件名能定位平台、页面、状态和步骤。
- 关键操作有录屏，动态结果和静态截图一致。
- 预期/实际逐步填写，不用“正常”“OK”代替。
- 主要页面在浅色/深色、小屏、长文本下无阻断级布局问题。
- Android/HarmonyOS 差异已记录，不把平台能力差异误判为通用失败。

`fail` 任一成立：

- 主入口缺失或被新模块挤掉。
- 当前播放、下载中、失败、空态等状态不可辨认。
- 长文本/小屏遮挡主操作或危险操作。
- 热榜暗示直接播放/批量下载第三方音频，超出产品范围。
- 系统播控可见按钮不可用或与 App 状态不同步。
- 截图显示问题但无明确 owner 或无复现步骤。

`blocker` 任一成立：

- 包无法安装、启动崩溃、核心页面打不开。
- 设备锁定、网络/音源前置不可恢复，且 10 到 15 分钟内无替代设备/包。
- 无法取得任何截图/录屏/日志，导致 UI 验收不可复核。

## 后续 design-qa 对比要求

UI lane 或 product 后续提供设计稿、截图标注或 Figma 时，QA 必须做逐项对比：

| 对比项 | 要求 |
| --- | --- |
| 信息架构 | 首页主路径、热榜位置、下载管理和设置入口与设计一致 |
| 状态覆盖 | 设计稿有的 normal/loading/empty/error/active/disabled 都有真机截图 |
| 文案 | 标题、按钮、失败说明、危险确认与产品口径一致 |
| 视觉层级 | 主操作、次操作、危险操作层级一致 |
| 平台差异 | Android/HarmonyOS 差异标注为平台差异或 bug |
| 响应式 | 小屏、长文本、大字号不破坏主流程 |
| 动效 | 滑动切歌、队列 sheet、下载状态、歌词跟随有录屏对比 |
| 可访问性 | 触控目标、语义、对比度、焦点顺序可接受 |

设计对比输出格式：

```text
Design QA Compare
design_source:
build_source:
matched:
deviations:
  - page:
    state:
    expected:
    actual:
    severity:
    owner:
    evidence:
accepted_differences:
blockers:
next_action:
```

## 回传要求

完成截图巡检后，回 UI、architect、product：

- 知识库路径：本文件路径。
- 证据目录：`artifacts/AM-20260711-002/...` 或实际路径。
- 包 SHA、设备、commit。
- 必须截图清单完成率：例如 `42/48`。
- 失败清单：按 P0/P1/P2/P3 分组。
- design-qa 对比结论：是否可进入产品验收、是否需要 UI/Android/OHOS 回改。

没有真实包时，只能交付 `Research Evidence`，不得声明 UI 验收通过。
