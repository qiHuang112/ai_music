# AM-20260726-001 Android Native 统一全速交付 Epic

Status: in_progress
Owner: mobile-ai-music-负责人
Integrator: mobile-ai-music-开发
Management Root: /Users/huangqi/AIHome/ai_music
Primary Repository: /Users/huangqi/AIHome/ai_music_android_native
Baseline Branch: codex/native-unified-milestone
Baseline Commit: d948a893f5d14d53942fbbaedf333a974e2ae015
Integration Project Path: /Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_unified_epic
Integration Branch: codex/native-unified-epic-20260726
Created: 2026-07-26
Workflow: superpowers-v1 continuous-agile

## 用户目标

从现有 Android Native 里程碑继续，移除 demo 数据并接入真实产品仓库，使真实搜索、完整音频播放、边播 seek、下载缓存转正、歌词封面、队列和失败隔离在 Compose UI 中闭环。Flutter 只保留历史和回退。

## P1 验收

1. `LibraryRepository`、`DownloadRepository`、`HotlistRepository`、`SourceSettingsRepository` 均使用真实持久化或真实来源，不再由 demo 数据驱动产品页面。
2. 歌曲海搜索只发布严格校验的完整音频；PREVIEW、HTML、防护页、低置信匹配和失败来源 fail closed，且不会拖垮已有结果。
3. Media3 完成搜索到播放、边播 seek、下载转正、正式缓存复用、歌词、封面和动态队列主路径，失败不污染正式缓存。
4. Native Compose 首页、搜索、播放详情和队列按已批准三张 Product Design 图增量落地，并覆盖真实数据、加载、空态、失败保留和播放中状态。
5. 逻辑验收候选具备 fresh tests/lint/build、完整主路径和 evidence manifest；只在该逻辑候选安装一次小米 10 Pro，最终真实 UI 全接线后再安装一次。

## 非目标与替代

- Flutter UI 与 Flutter 业务实现：`historical_fallback_only`，由本 Epic 替代为 Android Native 交付。
- 旧歌源窄 request：`historical_input`，其严格校验、fail-closed 和缓存证据吸收到本 Epic，不继续形成独立等待链。
- 小爱事项：`historical_or_replaced`，不阻塞当前 Native P1；未来如重启必须作为原生能力增量进入同一产品基线。
- HarmonyOS/iOS：`research_only`，可并行沉淀协议和风险，不进入本 Epic 关键路径。

## 六个互斥切片

| Slice | Owner | Independent Clone | Writable Scope | Integrator-Owned Exclusions | Status |
| --- | --- | --- | --- | --- | --- |
| S1 歌曲海搜索 | native-gequhai-search / Galileo | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_gequhai` | `domain/model/MusicSearchModels.kt`, `domain/repository/MusicSearchRepository.kt`, `domain/usecase/SearchMusicUseCase.kt`, `domain/usecase/MusicSearch.kt`, `data/source/**`, `data/repository/GequhaiMusicSearchRepository.kt` 及同路径 unit tests | app wiring、Gradle、Manifest、UI、缓存与播放器 | integrated_targeted_50_of_50 |
| S2 Media3 播放 | native-media3-playback / Poincare | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_media3` | `playback/PlaybackService.kt`, `Media3PlaybackController.kt`, `PlaybackController.kt`, `PlaybackControllerCloseGate.kt`, `Media3ReconnectStateMachine.kt` 及对应 tests | progressive cache、UI、app wiring、Gradle、Manifest | slice_complete_integrated |
| S3 缓存下载 | native-cache-download / Anscombe | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_cache_download` | `cache/**`, `playback/ProgressiveCache*`, `HttpRangeSource.kt`, `RangePlaybackContract.kt`, `CacheWriterLeaseRegistry.kt` 及对应 tests | Media3 controller/service、UI、app wiring、Gradle、Manifest | slice_complete_integrated_shared_cache_green |
| S4 产品数据层 | native-product-data / Bernoulli | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_product_data` | 新建 `domain/repository/{Library,Download,Hotlist,SourceSettings}Repository.kt`, `data/{library,download,hotlist,settings}/**` 及同路径 tests | 搜索、播放器、缓存、UI、app wiring、Gradle、Manifest | integrated_slice_195_of_195_composition_green |
| S5 Compose UI | native-compose-ui / Harvey | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_compose_ui` | `ui/**`, `ui/presentation/**` 及 `src/test/**/ui/**` | data/domain/playback/cache、MainActivity、Gradle、Manifest、androidTest | slice_complete_integrated |
| S6 QA 证据 | native-qa-evidence / Lagrange | `/Users/huangqi/AIHome/projects/ai_music_android_native_AM-20260726-001_qa_evidence` | `docs/qa/**`, `src/androidTest/**`, `src/test/resources/contracts/**`, evidence manifest schema/scripts | production Kotlin、Gradle、Manifest、app wiring | slice_complete_integrated |

统一开发集成者独占：`MainActivity.kt`、`ui/AiMusicApp.kt` 的跨层装配、`composition/**`、`AndroidManifest.xml`、Gradle/settings、依赖版本和最终冲突解决。子 Agent 不得修改这些共享文件。

## 事件驱动集成

- 任一切片完成或距上次集成四小时，以先到者触发 integration。
- 任一切片 15 分钟无新增事实，开发立即收窄、替换 Agent 或切换替代路径；不得等待。
- 每次集成先验证互斥写集与基线新鲜度，再运行匹配测试；全量 tests/lint/build 只在稳定候选与验收点执行。
- 中间 APK 不安装。第一次设备安装只发生在逻辑验收候选；第二次只发生在最终真实 UI 验收候选。

## 下一集成点

六切片已全部进入统一工程。当前 UI 装配编译通过即连续运行 fresh targeted/full tests、lint、assemble、diff-check 与集中 Spec/Code Quality review；finding 自动回改直至 accepted，随后由负责人完成首个 Native 集成提交/推送，不等待 UX 文档。

## 启动基线证据

- Integration clone：`codex/native-unified-epic-20260726@d948a893f5d14d53942fbbaedf333a974e2ae015`，启动时工作区干净。
- Fresh `testDebugUnitTest + lintDebug + assembleDebug`：`BUILD SUCCESSFUL`，JVM tests `176/176`，未安装 APK。
- Baseline APK SHA-256：`2e979cde5b51927a9a991651d1a0f2de95b2a4d77201b7f9ff251d0a341a284c`。
- Demo 数据缺口已定位：`SearchPresenter.kt` 的 `SampleSearchPresenter/sampleResult`，`AiMusicApp.kt` 的 `demoQueueTracks/InMemoryPlaybackController` 及热榜 demo 列表。
- 开发集成线程已进入 active；六个完整 clone、六条独立 `codex/` 分支和六个继承用户全局默认的 Agent 均已启动，起点均为 `d948a893f5d14d53942fbbaedf333a974e2ae015`。
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
