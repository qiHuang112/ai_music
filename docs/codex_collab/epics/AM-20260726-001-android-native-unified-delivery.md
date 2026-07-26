# AM-20260726-001 Android Native 统一全速交付 Epic

Status: integrating
Owner: mobile-ai-music-负责人
Integrator: mobile-ai-music-开发
Management Root: /Users/huangqi/AIHome/ai_music
Primary Repository: /Users/huangqi/AIHome/ai_music_android_native
Baseline Branch: codex/native-unified-epic-20260726
Baseline Commit: 96093aa771e3a89ff11d523ed99fcacfeaa9b8ee
Integration Project Path: /Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_unified_epic
Integration Branch: codex/native-unified-epic-20260726
Created: 2026-07-26
Workflow: ai-music-rapid-delivery-v2

## 用户目标

从冻结 Native `96093aa` 继续，建立至少两个公开 Provider 的严格多源聚合，
完成真实搜索、完整播放、边播 seek、下载缓存转正、歌词封面、队列和失败隔离。
Flutter 不修改，但其已验收播放器、歌词、进度和加载状态是 Compose 强制等价合同。

## P1 验收

当前唯一产品语义基线为
`docs/codex_collab/epics/AM-20260726-001-rapid-delivery-v2-semantic-requirement.md`，
SHA-256 `798e260ea5695d64ff38597e05af01a70b6b76947302bcbf486315b0d2bdd59b`。
Bootstrap `bfd213c5` 只保留为用户批准证据；旧 semantic R2/R1、旧候选与
NCUX-R1/R2 只作防回退 lineage，不再约束为单歌曲海或 `3+3+2` 分页。

1. 歌曲海及至少一个第二公开 Provider 通过普通用户路径和完整音频门禁；低压
   限流，不绕验证码、登录、防护、付费或 DRM，不接试听、网盘、HTML 或错歌。
2. 歌名、歌手、自然语言完成多源聚合、同歌去重和备用源保留；首屏最多 12 条，
   加载更多按 6-12 条原子批次发布，单源故障不影响其他来源。
3. 完整音频首声、边播前后 seek、正式缓存原子转正/复用、换源续播，以及歌词、
   封面、队列和 MediaSession metadata 形成真实闭环且失败不污染。
4. Compose 播放/歌词/进度/轻量加载与 Flutter 已验收状态同屏对照通过；自定义
   进度控件满足 4dp/14dp/40dp/24dp 尺寸和播放/缓冲/未加载三态。
5. 至少两个 Provider 及完整主路径、fresh tests/lint/build、集中 review、
   Flutter/Compose 对照和 evidence manifest 全通过后，只安装一次小米 10 Pro
   功能候选；完整真实 UI 接线后再安装一次最终 UI 候选。

## 非目标与替代

- Flutter UI 与业务不修改；状态、行为和视觉作为 Native 强制合同及紧急回退。
- 旧歌源窄 request：`historical_input`，其严格校验、fail-closed 和缓存证据吸收到本 Epic，不继续形成独立等待链。
- 小爱事项：`historical_or_replaced`，不阻塞当前 Native P1；未来如重启必须作为原生能力增量进入同一产品基线。
- HarmonyOS/iOS：`research_only`，可并行沉淀协议和风险，不进入本 Epic 关键路径。

## 四条互斥执行线

| Line | Owner | Independent Clone | Writable Scope | Integrator-Owned Exclusions | Status |
| --- | --- | --- | --- | --- | --- |
| R1 公开歌源低压研究及接入 | Nietzsche `019f9db3-15af-7142-a16e-20e263b9dcb8` | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_provider_research` | `data/source/providers/**`、provider-specific tests、低压研究脚本与来源状态表 | 聚合仓库、UI、播放/cache、Gradle、Manifest、app wiring | Kuwo accepted_overlaid；BuguYY research_pass_candidate、RED/GREEN 接入 active；GD 双域低压准入 active |
| R2 多 Provider 聚合与分页 | Bernoulli `019f9db3-5046-7f62-ba44-a2cd5579f6f2` | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_provider_aggregation` | `domain/source/**`、聚合 repository/use case、查询结构化、去重/备用源/健康度/批量分页及 tests | provider-specific adapters、UI、Media3/cache、Gradle、Manifest | accepted_overlaid_atomic_loader_29 |
| R3 Flutter UX 等价迁移 | Kepler `019f9db3-6d06-7c60-bdee-9968ae2b8c72` | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_flutter_ux_parity` | `ui/**`、Compose screenshot/layout tests、Flutter 只读对照证据 | data/domain/provider、playback/cache、Gradle、Manifest、Flutter 文件 | ncux_r3_accepted_direct_delta_and_runtime_wiring_active |
| R4 自动化与证据 | Raman `019f9db3-8cb4-70c1-bc08-e89e20baba82` | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_rapid_qa` | `docs/qa/**`、`src/androidTest/**`、evidence contracts/scripts、test resources | production provider、UI、playback/cache、Gradle、Manifest | accepted_overlaid_validator_31_production_8_red |

统一开发集成者独占：`MainActivity.kt`、`ui/AiMusicApp.kt`、`composition/**`、
`AndroidManifest.xml`、Gradle/settings、共享模型装配和最终冲突解决。四条执行线
必须从 `96093aa` 建立独立完整 clone，禁止 worktree。

## 事件驱动集成

- 任一切片完成立即触发 integration，不等待其他执行线。
- 任一切片 15 分钟无新增事实，开发立即收窄、替换 Agent 或切换替代路径；不得等待。
- R1 对 `buguyy.top`、`music.gdstudio.xyz`、`music.gdstudio.org` 按同一低压
  研究线并行核验；任一站先通过完整音频准入即接入既有 Provider 模型，不等待
  其余站。GD 双域只有在故障域和生产契约确实独立时才可分别计数，否则只作为
  同一 Provider 的域名冗余。
- 每次集成先验证互斥写集与基线新鲜度，再运行匹配测试；全量 tests/lint/build 只在稳定候选与验收点执行。
- 单个 Provider 外部故障只冻结该 Provider，其他 Provider、聚合、播放、UX 和 QA
  继续。中间 APK 不安装；第一次设备安装只发生在功能候选，第二次只发生在最终
  真实 UI 候选。

## 下一集成点

R1、R2、R3、R4 与共享 Gequhai safety/transport 已精确叠加统一工程。负责人
fresh 证据为 R1 targeted `44/44`、独立 full JVM `334/334`，R2 aggregator +
atomic multi-round loader `29/29`，Gequhai repository/safety/transport `59/59`，
R4 validator/legacy evidence `31/31` 且 production contract 诚实保持 `1 pass /
8 RED`。Production composition 已接入真实 Gequhai + `source_kuwo_full_audio`
aggregator、multi-provider loader 和一次性 v1→v2 source-settings 迁移，focused
`11/11`，当前统一叠加态 intermediate fresh full JVM `388/388`。

NCUX-20260726-R3 `6f3b60bb...` 已 accepted 为可实施合同。下一事件是完成两项
联合 P1：第一，validated alternate 必须只替换传输资源与 resource-specific cache
identity，保持 logical track、title/artwork/lyrics、queue selection 和 MediaSession，
同次自动失败不回环但用户显式新播放可开始新 attempt；第二，把真实 lyrics
metadata phase 与 seek pending/success/failure lifecycle 接入 40dp 稳定进度槽。
两项 accepted 后立即跑联合 targeted、AndroidTest compile、fresh full、lint、
assemble、diff-check 与双 review；四线不互等，不安装中间 APK。

## Rapid v2 启动事实

- 四个完整 clone 和独立 `codex/` 分支均从干净 `96093aa` 启动，统一绑定
  semantic V2 R1 `798e260ea5695d64ff38597e05af01a70b6b76947302bcbf486315b0d2bdd59b`。
- R1 已新增 Kuwo 迁移合同 RED，明确 HTTPS、无固定 `musicRid` seed、不预设
  browser/script 可播和使用 8 KiB Range；低压普通路径实测继续。
- R2 已新增多 Provider 聚合 RED，并证实现有 `ProviderSearchCursorV1` 只有
  `page + candidateOffset`，不能表达各 Provider 独立 cursor；共享模型扩展只由
  integrator 串行接入。现有 loader 仍为首屏 8、append threshold 2。
- R3 已新增三段进度所需 `bufferedPositionMs` 和 4dp/14dp/40dp/24dp 稳定尺寸
  RED，不修改 Flutter。
- R4 production contract 9 项中 6 项按预期失败，覆盖第二 Provider、独立
  cursor、6-12 原子批次、备用源、单源隔离、完整播放旅程和 Flutter/Compose
  对照；8 KiB admission、首屏不超过 12 和 blocked manifest 拒绝已通过。
  生成的 `__pycache__` 必须在切片 handoff 前排除。
- 当前没有 ADB、安装、stage、commit 或 push。首个集成事件优先接收 R2
  cursor/12 首屏/6-12 批次可运行切片，随后接 R1 Kuwo 低压普通路径事实。
- R2 首轮 review 发现 success page 返回未前进 cursor 会永久卡住加载更多并阻止
  合法尾批。三项 RED/GREEN 已覆盖空页、重复/无效候选和释放 1-5 尾批；停滞
  Provider 现在按协议错误局部隔离。负责人复审 accepted，生产/测试文件 SHA-256
  分别为 `a2d296125243100eba89d3d156996f7e5eb819a1224024d0afdb9675ebb544c9`
  和 `ddf6d6ec505ee8efb83d933bca047b58aba23669a7d90ec6970f1ae9531cf393`。
- R1 早期 review 已锁定单 token 歌名/歌手查询不可达，以及每源单并发、1.5 秒
  间隔、三次传输失败冷却和 403 立即暂停缺口；对应 RED/GREEN 不阻塞其他线。
- R3 的三段进度尚缺 `PlaybackState.bufferedPositionMs` 到
  `PlaybackPresentationSnapshot` 的生产装配；该 shared wiring 仅由集成者处理。
- R4 需把 Provider 低压约束、首声早于下载、未下载区双向 seek、备用源续播、
  离线复用、缓存零污染及 MediaSession 一致性纳入真实 artifact-bound 门禁，
  不允许自报布尔值替代证据。
- NCUX-R3 自启动 15 分钟仍无 revision/hash，已在同一 UX 任务和线程内替换执行，
  仅交 Flutter/Compose 等价 revision/hash、最小差异、能力依赖和 QA 清单；不建
  新 request，也不阻塞四线。
- R2 已叠加统一工作区，并在集成态发现停滞末源只返回已加载歌曲的合法 alternate
  时被 failure publication 丢弃。该场景 RED/GREEN 后，alternateSources 非空会
  作为局部成功返回；R2 targeted `17/17`。
- Integrator 新增的 shared loader 以不透明页 token 持有各 Provider 独立 cursor，
  targeted `4/4`；生产 `SearchComposition`、`MainActivity`、SourceSettings 和
  playback fallback 尚未完成，因此 compatibility cursor 与 alternate sidecar
  均不得被记为最终生产闭环。
- R3 已叠加统一工作区，`PlaybackState.bufferedPositionMs` 进入 presentation
  snapshot，自定义进度控件保留 4dp track、14dp thumb、40dp touch target 与
  24dp parent margin。R2/R3 focused `28/28`、AndroidTest compile 通过；仍需
  集中集成 review 与同状态真机证据。
- R1 Kuwo fresh targeted `24/24` 后 review 为 changes_requested：候选级
  403/429/defender 或 transport failure 不得被同次后续成功掩盖；空格查询必须
  支持多种歌手/歌名解释；完整音频不得用 `90..600` 秒硬阈值。回改同时验证实际
  Range body 为 8192 bytes，未 accepted 前禁止叠加。
- 共享 Gequhai 仍在第一次 timeout/connection/5xx 后开启两分钟 circuit，且缺少
  每源单并发与 1.5 秒间隔。Integrator-owned RED/GREEN 必须改为第三次传输失败后
  15 分钟冷却、成功重置、403/429/defender 立即暂停、取消不记失败。
- R4 fresh validator tests `23/23`；production contract 仍有 8/9 预期 RED。
  Review 另证明全 Provider `pauseReason=none` 可错误通过，且把未来 cooldown end
  当作 artifact not-before 会强制空等。门禁必须要求真实三失败冷却和即时防护
  场景，并把证据绑定到实际事件而不是未来时间。
- 首次 UX 替换仍超过 15 分钟无 revision/hash，已在同一 NCUX-R3 任务/线程内再次
  替换执行者，只交 revision/hash、最小可见差异、能力依赖、direct implementation
  与 screenshot/XML QA；未新建团队、线程或 request。
- R2 的一次加载更多现在会在 loader 内跨 Provider round 累积，只有得到 6-12 条
  或所有 cursor 耗尽后的唯一 1-5 尾批才向 UI 回调；fresh aggregator + loader
  `29/29`，不再暴露中间空 success page。
- R1 Kuwo 正式复审 accepted：歌名、歌手、组合与自然语言语义、财经非音乐
  fail-closed、真实 8192-byte Range、每源单并发/1.5 秒、三失败 15 分钟冷却和
  保护即时暂停均成立；targeted `44/44`、full JVM `334/334`，公开请求总数仍为
  `5`、review-cycle 为 `0`。切片已精确叠加。
- R4 正式复审 accepted：全部 QA tests 中 validator/legacy evidence `31/31`
  通过，production contract 九项中八项继续按预期 RED；即时暂停必须绑定同源
  真实 request timestamp，重复 Provider、失败时间和 artifact 内容绕过均被拒绝。
  两个生成 `__pycache__` 未叠加。
- Gequhai shared safety 与 bounded transport 正式复审 accepted：fresh `59/59`，
  只读取最多 8192 原始 Range bytes 并以实际 byte count 准入，忽略 Range 的
  `200`、空/截断 `206` 均 fail closed；redirect/retry 关闭，等待共享 gate 的旧
  请求在取消 generation 变化后不能发出。
- Integrator 已新增 production RED：真实 factory 必须返回
  `MultiProviderSearchPageLoader`，两源使用独立 enable gate；旧设备仅有歌曲海
  的 settings 首次升级时加入 `source_kuwo_full_audio`，用户随后主动关闭后不得
  在重启时再次启用。播放 alternate failover 仍是下一项独占 wiring。
- Production 双源装配已转绿：MainActivity 不再使用旧单源 loader，Gequhai 与
  Kuwo 使用 canonical source id 和独立 enable gate；v1 settings 只迁移一次并
  保留用户后续关闭。Focused `11/11`，统一叠加态 intermediate fresh JVM
  `388/388`，该中间结果不替代最终门禁。
- NCUX-20260726-R3 已冻结并经 feasibility review accepted，文件 SHA-256
  `6f3b60bb41f96ed7bcb9eb846d62565b1aa0b535ad93485041f95c6154be2ec9`。已实现
  三行/完整歌词、跟随、2 秒恢复和行 seek 保持；直接增量只含真实歌词四态、真实
  seek lifecycle 与 4dp/14dp/40dp/24dp 三态进度。
- Alternate playback 首轮 review 拒绝把 alternate 的逻辑 metadata 和 id 覆盖
  primary；回改必须分离 logical track 与 resource/cache identity、验证时长兼容、
  安全夹取 position，并把防循环限制在单次 playback attempt，而非整个 App 生命周期。
- 用户新增并亲测 `https://buguyy.top/`、`https://music.gdstudio.xyz/` 与
  `https://music.gdstudio.org/`。R1 必须按普通 Chrome 用户路径、每源并发 1、
  间隔至少 1.5 秒、整轮少于 20 请求执行低压准入，逐站记录搜索、详情/解析、
  `HEAD 200 audio/*` 正长度、`Range 206` 正 total 与实际至少 8 KiB、歌词、
  封面、URL 有效期和故障分类。验证码、登录、403、429、防护、付费或 DRM
  立即停止；试听、网盘、HTML 和防护页不得计为完整音频。
- BuguYY 首轮低压研究以 15 个请求完成：自然搜索“外婆”命中周杰伦并动态
  解析 HTTPS MP3，`HEAD 200 audio/mpeg`、长度 `9783513`，`Range 206
  bytes 0-8191/9783513` 且实际 `8192` 字节，歌词、封面和正时长齐全，
  未观察到 403/429/防护。该事实触发立即 RED/GREEN 接入；由于媒体上游疑似
  Kuwo，BuguYY 可作为独立 Provider 身份，但在候选证据中不得虚报为与 Kuwo
  独立的 origin failure domain。GD 双域研究继续，不等待 BuguYY 实现。

## 历史 Native R1/R2 证据

以下记录只证明 `96093aa` 冻结起点的既有能力和来路，不是 v2 当前执行线状态。

- Integration clone：`codex/native-unified-epic-20260726@d948a893f5d14d53942fbbaedf333a974e2ae015`，当时工作区干净。
- Fresh `testDebugUnitTest + lintDebug + assembleDebug`：`BUILD SUCCESSFUL`，JVM tests `176/176`，未安装 APK。
- Baseline APK SHA-256：`2e979cde5b51927a9a991651d1a0f2de95b2a4d77201b7f9ff251d0a341a284c`。
- Demo 数据缺口已定位：`SearchPresenter.kt` 的 `SampleSearchPresenter/sampleResult`，`AiMusicApp.kt` 的 `demoQueueTracks/InMemoryPlaybackController` 及热榜 demo 列表。
- 旧 R1 开发集成曾启动六个完整 clone、六条独立 `codex/` 分支和六个继承用户全局默认的 Agent，起点均为 `d948a893f5d14d53942fbbaedf333a974e2ae015`；这些执行线已被 v2 四线替代。
- 启动后写集证据：S1 已修改 Gequhai 生产/测试；S2 已写 PlaybackController RED test；S3 已新增 CacheInventory 生产/测试；S4 已新增 Library repository RED test；S6 已新增 evidence manifest 压力契约与 QA tests。S5 已启动分析且尚未产生工作区 diff。
- S1 已完成并在统一仓通过搜索定向 `50/50`；S4 的四个真实仓库与受控热榜源已完成，切片测试 `195/195`，并在统一仓完成 `ProductDataComposition` 首个 RED/GREEN。
- S2、S6 已完成并叠加到统一工作区，统一验证仍在继续；S3、S5 保持并行。统一仓当前只有未提交集成 diff，未进行 ADB 或中间包安装。
- 协同校验器已用 RED/GREEN 增加 `Work Type: epic`；18 项 `team_ops` 测试及本任务 `validate-workflow --gate start` 均通过。
- 2026-07-26 模型策略校正不改变当前六线状态：运行中 Agent 不重启；后续派工、续接、恢复、替换和账本均继承用户全局默认，不写死模型或思考强度。
- S3 已完成并叠加：可恢复下载器、缓存库存、事务替换与清理策略进入统一工程；播放与显式下载共享 writer lease 和正式缓存实例，`PlaybackCacheComposition` 测试已 RED/GREEN。
- UX 超过 15 分钟无 revision 新事实后已按规则收窄当前执行，只要求 revision/hash、三图最小差异、能力依赖与 S5 可直接实现清单；未重启、未重复派工。
- S2+S3+S4 联合验证和集中 review 已触发；S5/S6 不是前置依赖，中间 APK 继续禁止安装。
- S5 已完成并叠加，六切片全部进入统一工程；新增 `ProductDataPresenter`、真实下载/热榜/歌源页面，`MainActivity`/`AiMusicApp` 已接真实仓库，约 800 行不可达 demo 正在物理删除。
- 联合 Spec review 的 storefront 冒充与非法 Range evidence 两项 P1 已完成 RED/GREEN 回改。
- UI 装配编译通过后的统一 fresh tests/lint/assemble/diff-check 和集中双 review 已设置为立即触发事件；中间 APK 继续禁止安装。
- 工作流/Epic 管理白名单已独立提交并推送 `main@4b484d3392cd5204056bf657d400756da24e5a71`，未带入 Native 业务代码。
- 集中 Code Quality review 当前 5 个 P1 正在自动回改；已出现 `HttpRangeSource`、损坏正式缓存自愈和 fixture 修复的新 diff，开发未停工。
- UX 在 action_required 后再次超过 15 分钟仍无 revision/hash；原执行已 superseded，并在同一 UX 任务/线程内以新 task_assignment 替换执行，继续复用三图范围，不重建团队、不建新 request。
- 五项 Code Quality P1 的三个高风险项已完成回改：播放 URL 请求前及重定向后均执行 HTTPS 门禁，损坏/缺失正式缓存会在 writer lease 内隔离并回源重建，产品数据运行时使用单写与 generation 防迟到覆盖；fresh JVM `244/244`、AndroidTest compile 通过。当前仅补回新 Compose 页面设备自动化语义标签，随后继续 lint、assemble、diff-check 和双 review。
- Compose 设备自动化语义标签与真实验证 fixture 已补齐；第二轮定向、fresh full、AndroidTest compile、lint、assemble 通过，未安装 APK。
- 性能接缝已回改：最坏 8 秒的热榜只读请求从显式下载单线程拆到独立长期 executor，并补 `ProductDataPresenter` 测试；随后发现持久化歌源启用/停用尚未约束搜索入口，开发正按同一业务契约补跨层门禁与测试。
- 第二轮 Spec review 确认上一轮四项 finding 均关闭，并新增两项有效 finding：显式下载在已持有同键 writer lease 时再次获取非可重入租约会自锁；证据校验仍允许过短 Range。开发正改为租约内直接读取进度，并将证据固定为批准的 `bytes=0-8191`，两项均以失败测试起步。
- 上述窄改完成后必须重新运行 fresh full、AndroidTest compile、lint、assemble、diff-check 和 Spec/Code Quality 双 review；任一 finding 自动回改，全部 accepted 才允许负责人提交/推送。
- 中间 APK 继续禁止安装；Native accepted 前只运行代码验证、review 与回改。
- 最终 Spec/Code Quality 双 review 均 accepted；fresh JVM `253/253`、QA validator `6/6`、AndroidTest compile、lint、assemble、diff-check 全通过。
- 负责人精确 stage 83 个 Native app source/test 与 QA contract 文件，排除 pycache、APK/build 产物和管理主仓历史；提交并推送 `codex/native-unified-epic-20260726@e371b7be97e24c5d3369e6cf15f3278401fa9693`，工作区与远端一致。
- 新 HEAD 产物 SHA-256 为 `fef9c3651e56be0850c05590ad5470809c8dbf7b21384aad5696667e2be2c2f6`；唯一一次逻辑候选 `install -r` 在 `Mi 10 Pro` 成功，设备 `base.apk` SHA 一致，`lastUpdateTime=2026-07-26 13:09:31`，搜狗输入法保持默认。
- Product 已收到 `demo_ready` 并进入功能验收；开发/S6只在当前已安装包采搜索完整音频、Media3 边播 seek、下载/缓存转正、歌词封面队列、失败隔离与不污染的完整 manifest，不得重装。
- UX 替换执行再次超过 15 分钟无 revision/hash 后，已在同一任务/线程内再次 superseded 并替换；只交四项最小差异包，不阻塞本次逻辑候选。
- UX 已回传 `NCUX-20260726-R1`，文件 SHA-256 `653e125079ff79e687c48adeea73366a5a615f3907ac56b950f50c2946e1872f`，正确绑定 requirement `b8414836` 与三张批准图。负责人 feasibility review accepted：S5 只实现三页信息层级、稳定尺寸、mini player 安全停靠、播放/队列当前态、Material 中文语义和安全区；未具备 repository/controller API 的未来能力必须隐藏。
- Product Gate 2 `changes_requested`：证据 `search-waipo-final-candidate.png` 与 `search-waipo-candidate-retry.png` 显示搜狗候选 `外婆` 可见，但搜索框仍为 `周杰伦的waipo`/`周杰伦的wip`。源码审计定位到搜索输入仅提升纯 `String`，IME composing range 未贯穿状态链；开发必须先用真实 composing/commit RED 测试确认根因再做最小修复。
- 同包正向证据继续有效：Media3 state=3、真实封面歌词、单曲队列、3,576,668-byte 正式缓存、transient 增长且 formal 不污染、provider connection 失败时既有播放继续。
- 设备互斥规则立即生效：S6 停止所有点按，只整理现有证据；修复包进入复验时只允许一个 owner 操作小米 10 Pro，先完成 `周杰伦的外婆` 搜索、播放和 backward seek，再向 Product 交回设备。
- 用户新增五项同 Epic finding：系统返回键在子页直接退桌面；状态栏黑底白字且未沉浸通顶；搜索短时使用后歌源被打崩；结果过少且加载更多常只增一条；缺少 Flutter 已有歌词详情页。它们与中文 IME P1 合并为一次修复批次，不建新 request。
- 并行写集由开发统一管理：IME 输入状态、Back/edge-to-edge shell、歌源耐久、批量分页、歌词详情、QA 证据分别 RED-GREEN；共享 `AiMusicApp`/`MainActivity` 装配由 integrator 最后串行接线。中间 APK 禁止安装。
- 用户五项反馈已捕获为 `DISC-0012`，等待 Product R2 与 UX 增量 revision 分别 integrated；该门禁不暂停开发。统一工程的 IME composition policy 与导航 controller 定向测试通过，AndroidTest 编译通过。
- S1 根因审计确认单个候选 timeout/connection 曾被过早升级为整源熔断；候选批次现在只在全部 transport failure 时开启两分钟 circuit，403/429/defender/provider 5xx 仍立即熔断，普通坏候选继续 fail closed。S1 fresh targeted `53/53`，负责人已批准只叠加相对 `e371b7b` 的真实增量。
- 本轮 UX 增量执行超过 15 分钟仍无 revision/hash，已在同一 UX 任务内按 stale 规则替换执行者；继续复用 `NCUX-20260726-R1`、三张批准图与 `DISC-0012`，不重建团队、不建新 request，也不阻塞 S5。
- Product 已将 `DISC-0012` integrated 并冻结 semantic R2 `sha256:4ac5d1f892808c4fb3550bfbbdda66328407c64a8770942b2ada2d7601aa0628`。R2 把六项现场 finding 收敛为上述五条 P1，继承 semantic R1 与旧 whole-Epic snapshot 的历史边界，不扩大数据源、搜索、缓存或播放合同。
- UX 已回传并由负责人 feasibility accepted `NCUX-20260726-R2`，文档 `docs/codex_collab/knowledge/mobile-ai-music-ux/2026-07-26-native-compose-incremental-diff-r2.md`，SHA-256 `62c08ae173a620fece21873e50f22c1b9422d5d63be0a15dfcac3d7ef3830957`。直接实现范围为统一 Back/edge-to-edge、稳定三行歌词入口、保留真实 timestamp 的完整列表、手动滚动后两秒恢复跟随和复用现有 seek；无 API 控件继续隐藏。Product/UX 均已 acknowledge `DISC-0012`，严格 discovery check 为 `unresolved_count=0`。
- 团队 canonical work item 已通过正式状态机 `revise_requirement -> approve_requirement -> start_parallel` 重绑 semantic R2；最终仍为 `parallel_in_progress`，submission authorization 保持失效，未把设计规范通过误写成真实 UI 或提交授权。
- R2 最终统一 diff 经 fresh JVM `290/290`、AndroidTest compile、lint、assemble、QA validator `6/6`、diff-check 与 Spec/Code Quality 双 review accepted；负责人提交并推送 `codex/native-unified-epic-20260726@f4afca41e047229a7ea57cb2e576b713ee8b093a`，工作区与远端一致。
- 最终候选 APK 与小米 10 Pro `base.apk` SHA-256 均为 `c3117e44efc44d9c2cc509bb1f3369ffbe062570caae0ffe4f25b9e4cb8c2975`；唯一 preserve-data 安装成功，`lastUpdateTime=2026-07-26 15:06:28`，最终默认输入法为搜狗。
- 设备 QA 结论为 `external_blocked`：当前包导航、edge-to-edge、搜狗“周杰伦的外婆”完整 commit、产品状态、重复失败熔断和 formal cache 不污染通过；歌曲海可见 App 请求超时且单次主机探测 TLS 失败，无法合法进入新搜索结果后的分页、Media3/backward seek、歌词/队列闭环。证据根目录为 `/Users/huangqi/AIHome/evidence/AM-20260726-001-f4afca41-20260726T070544Z`。
- 正式 evidence validator 对阻断态返回 exit `1`：schema 只接受完整 `pass`，且当前阻断态 manifest 未满足正式完整字段。输出已原样保留，禁止伪造 pass；设备已恢复搜狗、退出 App，并记录 `device_window_released=true`。
- Product 已按 semantic R2 完成一次性只读 Gate 2 review，结论为 `blocked / external_blocked`，未代签用户体验。Artifact index `73/73` 通过；P1-1 与 P1-2 的中文输入/失败隔离局部证据有效，P1-2 在线结果/分页恢复、P1-3 歌词详情、P1-4 当前候选播放/seek/缓存转正/队列、P1-5 正式 manifest 均未通过。
- 另确认 QA schema 的 `requirementSha256` 仍写死 superseded R1 `b8414836`。同一 Epic 已派离线 RED-GREEN 将 schema/test/fixture/runbook 绑定升级到 R2 `4ac5d1f8`，但不放宽 `verdict: pass` 或任何完整主路径门禁；该修正不触碰设备、不重装，也不改变歌曲海 TLS 外部阻断。
- 上述 R2 evidence-contract 修正经负责人 review accepted：QA tests `7/7`、diff-check 通过，五文件精确提交并推送 `codex/native-unified-epic-20260726@96093aa771e3a89ff11d523ed99fcacfeaa9b8ee`，本地与远端一致、工作区干净。当前 blocked manifest 已不再出现 `E_REQUIREMENT_HASH`，仍保留 `E_VERDICT`、完整音频 admission、Media3/seek 与缓存转正失败码；已安装 APK 仍绑定应用候选 `f4afca41` / `c3117e44`。
