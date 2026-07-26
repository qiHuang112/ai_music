# Android Native 统一全速交付需求 R2

Request: AM-20260726-001
Status: user_feedback_integrated
Approved Evidence: 2026-07-26 Native 首轮功能验收反馈 / DISC-0012
Primary Repository: /Users/huangqi/AIHome/ai_music_android_native
Delivery Branch: codex/native-unified-milestone
Supersedes: semantic R1 sha256:b8414836fa8ced7574f0463d497d2c22029828cc0e60c4c99771d93e734131ee

## 用户目标

在同一 Android Native Epic 内修复首轮真机验收暴露的应用壳层、中文搜索、歌源耐久、分页和歌词详情问题，同时保留已经成立的真实完整音频、Media3 播放、边播 seek、下载/缓存转正、歌词封面、队列和失败隔离能力。用户只体验最终修复候选，无需参与中间审批。

## 范围

- Android Native Compose 应用内导航与 edge-to-edge 系统栏。
- 现有批准数据源范围内的中文 IME 搜索、重复搜索保护、来源失败恢复和批量分页。
- 播放页进入使用真实歌词数据与播放进度的同步歌词详情。
- 既有真实仓库、完整音频准入、Media3 播放及正式/瞬时缓存合同的防回退。
- 修复完成后的单设备、单 owner、单候选串行真机回归。

## P1 验收

1. **应用壳层：**在任一首页子页或详情页触发系统 Back，先返回上一应用页面，只有位于应用根层级时才允许退到系统；所有目标页面采用 edge-to-edge，状态栏区域与页面背景连续，浅色/深色场景下系统图标均清晰可读。
2. **搜索可靠性：**搜狗等标准中文 IME 的 composing/commit 能提交并搜索完整中文词句（含“周杰伦的外婆”）；同一会话连续执行重复同词、切换关键词和加载更多后，单个来源失败不得导致崩溃、永久退化或污染已有结果，后续重试可恢复。一次加载更多最多串行推进 3 个 provider cursor，总候选验证预算固定为 `3+3+2=8`；按稳定歌曲身份去重后达到至少 2 首即一次发布，三页或八个候选仍不足时允许一次发布已有增量，并保留正确的后续 cursor 或在确无更多合格结果时终止。
3. **歌词详情：**播放页提供可到达的歌词详情入口；详情页展示当前真实歌曲的完整同步歌词列表，列表可滚动，当前行随 Media3 播放进度高亮并跟随，系统 Back 返回播放器。真实歌词缺失或加载失败时显示明确状态，不使用 demo 歌词，也不阻断返回和继续播放；不要求未批准的收藏或歌单控件。
4. **真实音乐主路径不回退：**产品页面继续由真实仓库驱动；现有批准来源只发布严格校验的完整音频，失败来源 fail closed；搜索到 Media3 播放、边播 backward seek、下载/缓存转正、正式缓存复用、封面、歌词、动态队列和失败隔离保持可用，失败不污染正式缓存或中断已在播歌曲。
5. **最终串行真机回归：**开发完成上述修复、fresh tests/lint/build、双 review 和证据清单后，只对最终修复候选执行一次 preserve-data 替换安装；小米 10 Pro 设备窗口仅由一个明确 owner 操作，依次验证 Back、edge-to-edge、“周杰伦的外婆”搜索、连续搜索与批量分页、真实歌词详情、播放和 backward seek，并绑定新 HEAD、APK/设备 SHA、截图、UI XML 与 logcat 后给出 pass/fail。

## 六个 Finding 映射

| 用户 finding | P1 |
| --- | --- |
| 子页系统 Back 直接退桌面 | P1-1 |
| 状态栏未沉浸通顶 | P1-1 |
| 中文 IME composing/commit 不可靠 | P1-2 |
| 短时连续搜索后歌源退化 | P1-2 |
| 结果过少且加载更多逐条增长 | P1-2 |
| 缺少完整歌词详情页 | P1-3 |

P1-4 保留 R1 已通过的真实音乐逻辑证据并防止修复回退；P1-5 是六项 finding 与既有主路径的最终设备门禁。

## 非目标

- 不新增或扩大音乐数据源，不放宽完整音频严格准入，不改变已批准的来源优先级、频率或熔断合同。
- 不新增播放模式或重写 Media3、队列、下载、正式缓存及边播 seek 合同。
- 不要求逐字复刻 Flutter UI；Flutter、旧歌源窄任务和小爱专项继续仅作历史、回退或替代输入。
- HarmonyOS 与 iOS 继续仅研究，不进入本 Epic 的 Android Native P1。
- 不安装或验收中间 APK；UX 设计稿验收不能替代最终真实代码 UI 与功能验收。

## 谱系

R2 继承 semantic R1 的用户目标、Android Native 单一 Epic、历史替代边界和真实音乐主路径。R1 的已验证正向证据继续有效；R2 仅吸收首轮真机验收六个 finding，并将其收敛为恰好五条 P1。旧的整文件快照 `sha256:005b75f7adf7814268a3df760bc1c3ffca4317cd32407a5f63cd1214169bdcc8` 与 semantic R1 `sha256:b8414836fa8ced7574f0463d497d2c22029828cc0e60c4c99771d93e734131ee` 均保留为历史，不回滚、不重开 request。
