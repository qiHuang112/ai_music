# AM-20260711-005 歌曲海搜索与边下边播主链路回归

Status: in_progress
Owner Lane: android
Assist Lane: source-researcher, android-streaming, qa-researcher, architect review
Source Thread: 019f4ed4-106e-7860-875d-a32f81629e4e
Target Version: 1.1.0
Base Branch: release/1.1.0
Work Branch: feature/1.1.0/AM-20260711-005-gequhai-search-streaming-regression
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-005_gequhai_search_streaming
Merge Branch: release/1.1.0
Created: 2026-07-11
Updated: 2026-07-11
Workflow: superpowers-v1
Work Type: bugfix
Risk Level: P0
User Visible: yes
Design Doc: docs/superpowers/plans/2026-07-11-am005-gequhai-search-streaming-regression.md
Implementation Plan: docs/superpowers/plans/2026-07-11-am005-gequhai-search-streaming-regression.md
Required Skills: systematic-debugging, test-driven-development, ai-music-team-ops, verification-before-completion
TDD Mode: required
Baseline Commit: 2f309fbd0619c34da6f1bf99d4d451b8953a7b7d

## 背景

Product 在小米 10 Pro 最新体验包上反馈四个主链路问题：

1. 在线边播模式下拖动进度条后无法继续播放。
2. 部分歌曲点击边下边播时报 HTTP 错误失败，但同一歌曲可以下载。
3. 搜索《剩下的果实》没有搜到资源。
4. 只搜演唱者时召回失败或不稳定：
   - 搜 `周杰伦` 一个都没搜到，但搜 `周杰伦的外婆` 可以搜到。
   - 搜 `黄蓉的哎呀` 可以搜到。

这些问题不能降级为试听、网盘、HTML、防护页、Chrome-only 链接或“可下载但不可边播”。1.1.0 主链路要求是：搜索结果只展示完整可播资源；可见完整结果必须支持完整播放、下载和边下边播；失败必须有结构化原因和不写缓存证据。

## 目标

- 修复歌曲海完整音频在线边播 seek 后无法继续播放。
- 修复“边下边播 HTTP 失败但下载可用”的路径差异，统一边播与下载的 media validation/header/range 策略。
- 补齐歌曲名搜索《剩下的果实》的歌曲海召回或结构化 miss chain。
- 补齐歌手/组合查询能力：`周杰伦` 应能召回周杰伦歌曲列表；`周杰伦的外婆`、`黄蓉的哎呀` 这类自然语言查询要保留可用。

## 范围

- 包含：歌曲海 search/detail/api/media validation/provider chain、MusicController 在线边播 seek、ProgressiveAudioCache/Range 代理、候选过滤和 UI 状态提示。
- 包含：source-researcher 用 Chrome 用户态和脚本低频串行复核上述查询与 detail/play/download/lyrics/cover 关系。
- 包含：android-streaming 复核 seek 后续播、HTTP 失败和缓存/下载一致性。
- 包含：QA 按真实设备矩阵复核结果只展示完整可播资源，无 PREVIEW/网盘/HTML 完成路径。
- 不包含：恢复 BuguYY/FLAC 作为主完成路径；不包含批量压测歌曲海。

## 验收标准

- 小米 10 Pro 上在线边播 `外婆`、`一丝不挂`、`稻香`、`哎呀` 中至少两首，拖动进度条到中段后能继续有声播放；media_session 仍 `state=3`，日志显示有效 Range/seek 或 player position 继续推进。
- 对 Product 指出的“边播 HTTP 错误但可下载”样例，必须抓到具体歌曲名、detail URL、边播请求、下载请求、headers、status、failureCode；修复后边播和下载都成功，或两者都结构化 fail closed 且不写正式缓存。
- 搜索 `剩下的果实` 必须给出歌曲海候选或完整 miss chain；若有候选，必须通过 detail/api/media validation 后才显示完整可播行。
- 搜索 `周杰伦` 必须召回周杰伦歌曲列表，至少包含 `外婆` 或其它高置信周杰伦完整音频候选；搜索 `周杰伦的外婆` 继续可用。
- 搜索 `黄蓉的哎呀` 继续可用；如果真实歌手为 `王蓉`，系统应通过歌曲名/别名/低置信规则解释匹配，不得误写错误 artist metadata。
- 搜索结果中可见的可操作行必须是 `source_gequhai/direct_audio/canCacheAudio/clientReady`；PREVIEW/网盘/HTML/防护页/低置信候选不得显示为可播放/可下载完成路径。
- 交付必须包含：HEAD、APK sha、targeted RED/GREEN tests、analyze、真机截图/录屏、logcat/media_session、cache index/mp3/lrc/artwork 证据和 pass/fail/blocker 矩阵。

## 消息记录

- 2026-07-11 type=task lane=product status=in_progress summary=Product 反馈歌曲海完整源主链路四个问题：在线边播 seek 后不能继续播放；部分歌曲边播 HTTP 失败但可下载；搜索《剩下的果实》无资源；歌手搜索 `周杰伦` 无召回但自然语言 `周杰伦的外婆` 可用。
