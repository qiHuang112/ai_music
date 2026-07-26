# Android Native 统一全速交付需求 R1

Request: AM-20260726-001
Status: user_approved
Approved: 2026-07-26
Primary Repository: /Users/huangqi/AIHome/ai_music_android_native
Baseline: codex/native-unified-milestone@d948a893f5d14d53942fbbaedf333a974e2ae015

## 用户目标

从现有 Android Native 里程碑继续，移除 demo 数据并接入真实产品仓库，使真实搜索、完整音频播放、边播 seek、下载缓存转正、歌词封面、队列和失败隔离在 Compose UI 中闭环。Flutter 只保留历史和紧急回退。

## P1 验收

1. `LibraryRepository`、`DownloadRepository`、`HotlistRepository`、`SourceSettingsRepository` 均使用真实持久化或真实来源，不再由 demo 数据驱动产品页面。
2. 歌曲海搜索只发布严格校验的完整音频；PREVIEW、HTML、防护页、低置信匹配和失败来源 fail closed，且不会拖垮已有结果。
3. Media3 完成搜索到播放、边播 seek、下载转正、正式缓存复用、歌词、封面和动态队列主路径，失败不污染正式缓存。
4. Native Compose 首页、搜索、播放详情和队列按已批准三张 Product Design 图增量落地，并覆盖真实数据、加载、空态、失败保留和播放中状态。
5. 逻辑验收候选具备 fresh tests/lint/build、完整主路径和 evidence manifest；只在该逻辑候选安装一次小米 10 Pro，最终真实 UI 全接线后再安装一次。

## 非目标

- Flutter、旧歌源窄任务和小爱专项不再形成独立交付或等待链，只作为历史、回退或本 Epic 输入。
- HarmonyOS 与 iOS 暂只研究，不进入 Android Native P1 关键路径。
- 中间 APK 不安装；测试、构建、review、commit、push 和独立切片完成都不是停点。
- 六个子 Agent 不修改 integration clone 的共享装配、Gradle、Manifest 或最终冲突。
