# AM-20260711-002 AI Music 移动端 Product Design 重做设计

Created: 2026-07-11
Owner Lane: architect
Source Lane: product
Status: approved_for_planning

## 目标

基于 AI Music 当前真实移动端 App 页面，先完成 Product Design 审计，再生成恰好 3 套独立视觉方向供 Product 选择。选定视觉方向前，Android、OHOS、iOS 或其它开发 lane 不允许直接重写 UI。

本轮目标是规划 1.1.0 的移动端体验升级，不阻塞 1.0.2 的完整音频、下载、缓存和歌源收口。设计对象是完整 App，而不是单个页面皮肤：必须覆盖首页发现与我的音乐、搜索下载、播放详情与当前队列、歌单管理。

## 非目标

- 不在 AM-20260711-002 中直接修改 Flutter UI 代码。
- 不在视觉方向选定前创建实现任务或让开发 lane 抢跑。
- 不改变 1.0.2 已验收的搜索、完整音频播放、下载缓存、歌词封面、热榜和歌单业务逻辑。
- 不把营销落地页、装饰性首页或单屏概念图当作完整 App 设计方案。

## 审计基线

- Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-002`
- Audit Base Branch: `origin/release/1.0.2`
- Audit Baseline Commit: `b306932d03e1eedbe96fd50dafe0f95805b0eab4`
- Architect-confirmed AM-017 APK: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017_android_source/build/app/outputs/flutter-apk/app-debug.apk`
- Architect-confirmed AM-017 APK SHA256: `4eebeed8803576266d0e2456e47a0fb11a083eaff58284d3ec4d85a7852b068a`
- Android screenshot APK: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-016/build/app/outputs/flutter-apk/app-debug.apk`
- Android screenshot APK SHA256: `ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3`
- Device baseline: 小米 10 Pro 真实 App 截图；如 Product 要验收视觉细节，再补小米 17 Pro 截图。
- Current date anchor: 2026-07-11，用于截图清单、设计 mock 中的日期和报告命名。

Android 侧曾创建 `AM-20260711-002-android-current-product-screenshots.md`、`2026-07-11-am002-android-current-product-screenshots-design.md` 和 `2026-07-11-am002-android-current-product-screenshots.md`。这些文件的内容并入本设计规格和计划作为截图采集子证据清单，不再作为独立 request 或第二套 AM-20260711-002 口径。

当前截图采集 blocker：

- Android：小米 10 Pro 无线调试不可达，`adb devices -l` 和 `adb mdns services` 无可用 target；Android 已停止旧 32d183c/AM-016 包，改用 b306932 debug APK。
- OHOS：Mac 到 `192.168.31.53:6666` 端口可达，`hdc tconn` 返回 `Connect OK`，client/server 版本均为 `3.2.0c`，server log 显示 RSA 授权成功；但设备握手返回空 `connectKey`、`devname=localhost` 后 `CMD_KERNEL_CHANNEL_CLOSE`，`hdc list targets -v` 仍为空，暂不能安装 HAP、shell、uitest 或截图。设备侧需重新关闭再开启无线调试和调试授权，必要时重新配对或重启手机端调试服务。

## 必审路径

1. 首页发现与我的音乐：
   - 热榜发现入口、热榜歌单入口、我的音乐区域、收藏和自建歌单入口。
   - 空态、已缓存歌曲态、热榜加入歌单后的回显态。
2. 搜索下载：
   - 搜索输入、结果列表、完整音频候选、不可下载候选原因、下载/重新下载、缓存状态。
   - 禁止把 `试听/PREVIEW/30s` 当成完成路径。
3. 播放详情与当前队列：
   - 播放详情、封面、歌词、进度、播放控制、当前队列、缓存/下载状态。
   - 系统播放态或 media session 证据由 Android 提供，UI 只审 App 内可见体验。
   - 必须审计当前播放队列是否有可见入口；若没有入口，列为 1.1.0 P1 设计约束。
   - 必须审计 mini player 在下载管理、设置、排序编辑等页面是否持续存在；若跨页中断，列为 1.1.0 P1 设计约束。
   - 必须审计完整音频边下边播状态是否保留收藏和加入歌单入口；若缺失，列为 1.1.0 P1 设计约束。
4. 歌单管理：
   - 自建歌单、热榜歌单、加入歌单反馈、歌单详情、歌曲条目状态和不可下载原因。

## Product Design 流程

### Audit

UI lane 必须使用真实当前页面截图作为 Product Design audit 输入。审计输出必须包含：

- 每个必审路径的截图路径，截图来自本轮采集。
- 每个步骤的健康度、UX 问题、视觉层级问题、可访问性风险和截图证据限制。
- 不可审计项必须写成 blocker，例如设备锁屏、页面无法进入、截图为空或包版本不一致。

### Ideate

UI lane 在 audit 后生成恰好 3 套独立视觉方向。每套方向必须：

- 使用移动端 `390 x 844` 作为主屏尺寸，必要时补长屏滚动片段。
- 覆盖完整 App 信息架构，不只画首页。
- 保留音乐产品核心路径：发现、搜索、完整音频播放、下载缓存、歌词封面、队列和歌单。
- 明确不把 preview 作为完成路径，不把第三方不可下载源伪装成可下载。
- 三套方向在信息层级、导航结构、播放体验或视觉系统上明显不同。

Product 选择前，UI lane 只交付 audit 和三套方向，不交付可合入代码。

## 视觉约束

- AI Music 是工作型音乐工具，不做营销 hero，不做单纯装饰页。
- 设计应利于反复搜索、下载、播放、管理队列和维护歌单。
- 触控目标、文字层级、列表密度、缓存/失败状态要清楚，不能靠小字或低对比提示承担关键语义。
- 页面中允许使用封面、歌词和播放状态作为真实视觉资产；不要用无意义渐变、装饰球或纯气氛背景替代内容。
- UI 需要考虑 Android 和 HarmonyOS 双端实现约束，优先使用 Flutter 可共享组件和状态。
- 横滑切歌、返回和面板拖拽必须避开系统边缘返回区，不能把核心操作放在 OS 手势热区。
- 关键按钮、列表行操作、mini player 控件、播放控件和 sheet 操作必须满足 48px 最小触控目标。
- 搜索提交后必须定义键盘收起、焦点和结果区域滚动行为。
- 大字号、系统字体缩放和较长歌名/歌手名下，不得依赖固定卡片高度承载关键状态。
- 歌单选择 sheet、下载管理、搜索结果和缓存长列表必须可滚动，不能被固定高度或键盘遮挡。
- SafeArea、状态栏、导航栏和系统手势区必须使用平台能力适配，不得在 UI 设计或实现 handoff 中写死像素。
- OHOS 现阶段按 foreground-only 约束设计；启动窗白色与暗色首帧不一致列为平台风险，不能在 1.1.0 设计图里假设已解决。

## Lane 分工

- architect：维护 request、设计文档、实施计划和 gate；协调 owner 回传；选定后拆实现 request。
- android：提供最新 1.0.2 Android 真机截图、包 SHA、主路径动作和必要 media session 日志。
- ui：执行 Product Design audit 和 ideate；输出审计报告、截图、3 套视觉方向和选择说明。
- ohos：补 HarmonyOS 安全区、系统手势区、导航、播放控件、字体、大字号、HAP 适配、foreground-only 限制、启动首帧风险和跨端限制。
- qa-researcher：建立截图验收矩阵，定义后续 Beta/RC 视觉验收清单和失败升级规则；矩阵路径 `docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`。

## 1.1.0 设计约束与实现 handoff

这些约束来自 Product 静态审计和跨端静态勘察。它们必须进入视觉方向、设计评审和后续实现 request，但在 Product 选择视觉方向前不派 UI 代码。

| Constraint | Owner After Selection | Gate |
| --- | --- | --- |
| 当前播放队列需要可见入口 | public Dart / UI implementation | 播放详情、mini player 或全局导航中必须能进入当前队列 |
| mini player 需跨下载管理、设置、排序编辑等页面持续存在 | public Dart / UI implementation | 页面跳转不应中断播放可见性和基础控制 |
| 完整音频边下边播状态需保留收藏与加歌单入口 | public Dart / UI implementation | 播放详情和关键行操作不因 streaming 状态降级 |
| 横滑切歌需避开系统边缘返回区 | public Dart + OHOS owner | Android/HarmonyOS 手势区内不放核心横滑触发 |
| 48px 最小触控目标 | public Dart / UI implementation | 图标按钮、列表操作、sheet 操作和播放控件均达标 |
| 搜索提交后键盘、焦点和滚动行为明确 | public Dart / UI implementation | 提交后结果可见，键盘不遮挡主操作 |
| 大字号下不得依赖固定卡高 | public Dart + QA | 字体缩放后歌名、状态和按钮不重叠、不截断关键语义 |
| 歌单选择 sheet 和下载长列表必须可滚动 | public Dart / UI implementation | 长内容可达，底部操作不被系统栏或键盘遮挡 |
| SafeArea/系统手势区不能写死 | public Dart + OHOS owner | 使用平台 safe area/insets，禁止硬编码状态栏/导航栏高度 |
| OHOS foreground-only、启动窗白色与暗色首帧不一致 | OHOS owner | 作为平台风险进入设计说明和 QA，不在设计图中假设后台能力或首帧一致 |

## 风险

- 真实页面截图如果来自旧包，会导致设计方向误判；截图包 SHA 与 release/1.0.2 基线必须一致或写清偏差。
- 当前功能仍在 1.0.2 收口，UI 大改不得覆盖或回退已验收业务路径。
- 三套方向如果只变颜色不变结构，不满足 Product Design ideate 目标。
- 如果设计方向包含当前产品没有的业务能力，必须标为未来能力，不进入 1.1.0 默认实现。
- 如果视觉方向忽略队列入口、mini player 持续性、完整音频收藏/加歌单、系统手势区、48px 触控、大字号、滚动 sheet 或 OHOS foreground-only 约束，必须打回 UI ideation。

## 验收标准

- AM-20260711-002 request、设计文档和实施计划通过 `validate-request`、`validate-workflow --gate design` 和 `validate-workflow --gate start`。
- Android 回传四条核心路径的真实截图和包/设备证据；截图必须来自 b306932 或更新的 release/1.0.2 包，不能使用 32d183c 旧包。
- UI 基于本轮截图输出 audit，且 findings 均能指向截图步骤。
- UI 生成恰好 3 套独立视觉方向，并停止等待 Product 选择。
- OHOS 回传跨端限制，QA researcher 回传截图验收矩阵。
- Product 选择前没有 UI 实现代码进入开发或合入。
