# AM-20260711-003 Library First 移动端 UI 实现设计

Created: 2026-07-11
Owner Lane: android
Source Lane: product
Status: approved_for_planning

## 目标

基于 Product 选定的 `Library First / 我的音乐与继续播放优先` 方向，落地 AI Music 1.1.0 移动端主界面。实现必须优先服务真实主路径：搜索完整音频、播放、下载缓存、歌词封面、当前队列、收藏和歌单管理。

## 非目标

- 不恢复 `试听/PREVIEW/30s` 作为搜索结果或验收完成路径。
- 不把 2t58、22a5、gequhai、gequbao 等当前不可自动完整下载源伪装成可下载。
- 不改变 AM-014/015/016/017 已验收的 direct_audio、canCacheAudio、Range/长度、缓存转正和 fail-closed 闸口。
- 不在本 request 中实现第二套或第三套视觉方向。
- 不做营销首页、装饰 hero 或不含真实播放/搜索/下载路径的概念页。

## 输入

- Selected Direction: `Library First / 我的音乐与继续播放优先`
- Selected Image: `/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`
- Product Design Audit: `docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md`
- Android Screenshot Baseline: `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`
- Android Screenshot APK SHA256: `ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3`
- OHOS Screenshot Baseline: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/screenshots`
- OHOS Constraints: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/ohos-platform-constraints.md`
- OHOS Library First Implementation Notes: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/library-first-ohos-implementation-notes.md`
- QA Matrix: `docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`
- Implementation Project: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003`
- Baseline: `origin/release/1.0.2=b306932d03e1eedbe96fd50dafe0f95805b0eab4`
- Work Branch: `feature/1.1.0/AM-20260711-003-library-first-ui`

## 产品结构

Library First 不是单页皮肤，而是信息架构约束：

1. 首页优先展示搜索、本地资产和继续播放。
2. 发现能力保留为次级入口，热榜必须表达“发现/搜索匹配”，不能暗示第三方直接播放。
3. mini player 是全局持续播放控制，不应在下载管理、设置、排序编辑等页面消失。
4. 播放详情必须明确区分当前队列入口、收藏/喜欢、加入歌单。
5. 搜索结果必须把完整音频和已缓存项置顶，不可下载候选可见但不可误操作，preview 不出现。

## 页面范围

### 首页

- 顶部保留标题、搜索入口、下载、歌单、设置。
- `我的音乐` 区域包含收藏、自建歌单、已保存热榜歌单和本地缓存摘要。
- `继续播放` 或 mini player 必须有明确视觉焦点。
- `热榜发现` 与 `热榜歌单` 必须视觉区分：前者是发现入口，后者是本地资产。

### 搜索与下载

- 搜索提交后键盘、焦点和结果滚动必须明确。
- 完整音频或已缓存项显示播放/下载主操作。
- 不可下载候选显示短原因，例如 `未通过完整音频校验，不能下载`。
- 禁止出现 `试听/PREVIEW/30s` 作为完成路径。

### 播放详情与当前队列

- 播放详情首屏同时展示封面/歌词/进度/主播放控制。
- 当前队列入口必须可见，且与加入歌单入口视觉区分。
- 当前队列 sheet/list 必须展示当前歌曲、队列来源和下一首。
- 完整音频边下边播状态不能隐藏收藏和加入歌单入口。

### 歌单、收藏、热榜、下载管理和设置

- 歌单/收藏列表行统一展示标题、歌手、缓存/不可下载状态和更多操作。
- 热榜详情必须消除 `overflowed by 4.0 pixels` debug 条。
- 下载管理保留高密度，但使用状态 chip、进度条和错误摘要提高扫读性。
- 设置页音乐源改为分组状态列表，四个 Product 指定源可见但 disabled，不可误选。

## 跨端约束

- Android 和 OHOS 均需要 SafeArea/insets 适配，不写死状态栏、导航栏或手势区像素。
- 所有关键触控目标不小于 48px。
- 横滑切歌、返回和面板拖拽避开系统边缘返回区。
- 搜索键盘常驻时至少保留 4 条结果可扫读，主操作不被键盘遮挡。
- 大字号和较长歌名/歌手名下不得依赖固定卡高承载关键语义。
- 歌单选择 sheet、当前队列 sheet、下载管理长列表和设置音乐源列表必须可滚动。
- OHOS 按 foreground-only 设计；启动窗白色与暗色首帧不一致列为平台风险，不在设计图或实现中假设已解决。
- UI 页面级规范必须显式标注 safe area、键盘态、mini player 固定规则、当前队列入口、48px 触控目标、大字号/长文本策略和长列表/sheet 滚动策略。
- Android 实现不得写死 Android 状态栏、键盘或导航栏高度；必须通过 Flutter/平台 insets 适配 Android 和 OHOS。

## Owner 与 Handoff

- UI lane 必须先输出页面级实现规范，包含 tokens、组件层级、页面状态和截图标注。
- Android owner 在 UI 规范后实现公共 Flutter UI、测试和小米 10 Pro 自测。
- OHOS owner 按 `library-first-ohos-implementation-notes.md` 复核安全区、系统手势、大字号、搜索键盘、队列入口、mini player、foreground-only 和启动首帧风险。
- QA researcher 按矩阵验收截图、录屏、包 SHA、设备和失败升级规则。
- Architect 负责 review gate、scope diff、防回退、合入和 Product 通知。

## 验收门禁

- Start gate：request、design、plan、Project Path、baseline、owner 全部有效。
- Review gate：必须有 HEAD、RED/GREEN 或 TDD 证据、targeted tests、scope diff、self-test 和 Android/OHOS/QA 主路径证据。
- Merge gate：Android owner、UI/spec、OHOS constraints、QA matrix 或明确 blocker 均已回传；无 P0/P1/P2 阻塞。

## 风险

- 选定图是方向基准，不是像素级最终稿；实现必须以真实产品路径和审计约束为准。
- 如果 UI 规范缺失页面状态，Android 不应直接做大改。
- 如果当前队列入口、热榜 overflow、mini player 跨页或完整音频收藏/加歌单缺证据，不允许 accepted。
- 如果视觉大改造成 AM-014/016/017 完整音频路径回退，按 P0 打回。
