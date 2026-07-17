# AM-20260711-005 歌曲海搜索与边下边播主链路回归

Status: pushed
Owner Lane: android
Assist Lane: source-researcher, android-streaming, qa-researcher, architect review
Source Thread: 019f4ed4-106e-7860-875d-a32f81629e4e
Target Version: 1.1.0
Base Branch: release/1.1.0
Work Branch: feature/1.1.0/AM-20260711-005-gequhai-search-streaming-regression
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-005_gequhai_search_streaming
Merge Branch: release/1.1.0
Created: 2026-07-11
Updated: 2026-07-17
Workflow: superpowers-v1
Work Type: bugfix
Risk Level: P0
User Visible: yes
Design Doc: docs/superpowers/plans/2026-07-11-am005-gequhai-search-streaming-regression.md
Implementation Plan: docs/superpowers/plans/2026-07-11-am005-gequhai-search-streaming-regression.md
Required Skills: systematic-debugging, test-driven-development, ai-music-team-ops, verification-before-completion
TDD Mode: required
Baseline Commit: c754ac7443020303dafae490890cce3efc540066
Head Commit: b21578c77ee5ea5e1df7dd5f8b483a1980135657
Business Implementation Commit: d9525aee5154e1d69fb8d0e31d61a4a94a0b88b2
Root Cause Evidence: `周杰伦` artist-only query was filtered because 歌曲海 candidate matching required title containment unless the query carried explicit title/artist separators; progressive playback also assumed the initial upstream `Range: bytes=0-` request would succeed, so upstreams that reject Range could fail streaming while full GET/download remained viable.
Red Evidence: RED reproduced with `flutter test --no-pub test/music_resolver_test.dart --plain-name 'auto keeps gequhai artist-only search results visible' --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true` failing before the resolver matching change, and `flutter test --no-pub test/progressive_audio_cache_test.dart --plain-name 'upstream range failure falls back to full GET for seekable proxy playback' --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true` failing before the progressive fallback change.
Green Evidence: The same two RED tests now pass; `auto tries later gequhai candidates when the top match fails validation` also passes, preserving fail-closed fallback to later validated 歌曲海 candidates.
Targeted Tests: R3 eight-file suite = 189 passed; after integrating the latest `release/1.1.0`, exact promoted-Kuwo, neutral-no-lyrics, artist-correction tests = 3 passed, progressive suite = 20 passed, full `/Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true` = 274 passed.
Self Test Evidence: `/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze --no-pub` no issues; `git diff --check` clean; final default-audio debug APK at `build/app/outputs/flutter-apk/app-debug.apk` and Xiaomi 10 Pro installed `base.apk` sha256 both `bb6287c45a86e1794d23567a08aac786bc4ec8ee58bbe8bdc3194f6b06cda2da`; device `lastUpdateTime=2026-07-17 08:08:56`, app launch confirmed.
Baseline Freshness Evidence: `origin/release/1.1.0@c754ac7443020303dafae490890cce3efc540066` is an ancestor of final candidate `b22bcbf3190196dac1af5574d30d1028e63dab83`; integration retained the target branch's natural-language artist correction, concurrent-seek and truncated-stream hardening.
Scope Diff Evidence: Final candidate contains 29 request-owned code, test and collaboration files relative to `origin/release/1.1.0`; raw QA, Chrome and script evidence directories remain untracked and excluded from Git.
Product Main Path Evidence: `evidence/qa-am005-r3-20260717/SUMMARY.md` records initial capped 206 fail-closed with `incomplete_audio_response`, strict same-song validated Kuwo evidence reuse, neutral no-lyrics state and Xiaomi 10 Pro playback continuation. Final installed candidate additionally preserves dynamic pagination, artist correction, source timeout fallback, HTTP fail-closed/cache integrity and real drag seek behavior.
Spec Review Result: accepted
Code Quality Review Result: accepted
Full Verification Evidence: R3 eight-file suite 189 passed; post-integration exact P1/UI tests 3 passed, progressive suite 20 passed, release merge full Flutter suite 274 passed; analyze no issues, diff-check clean and merge gate OK. Final default-audio debug APK and Xiaomi 10 Pro installed base.apk SHA-256 both `bb6287c45a86e1794d23567a08aac786bc4ec8ee58bbe8bdc3194f6b06cda2da`, device `lastUpdateTime=2026-07-17 08:08:56`; R3 device evidence records dynamic pagination, strict source failover/cache integrity, neutral no-lyrics playback and real seek continuation with `state=3`.
Blocking Findings: none
Merge Evidence: `release/1.1.0` merge commit `b21578c77ee5ea5e1df7dd5f8b483a1980135657` merged the accepted AM-005 feature over target baseline `c754ac7443020303dafae490890cce3efc540066` without conflicts.
Push Evidence: `git push origin release/1.1.0` succeeded; `git ls-remote origin refs/heads/release/1.1.0` confirmed remote release at `b21578c77ee5ea5e1df7dd5f8b483a1980135657` before this final push-evidence ledger update.
Push Status: pushed
Product Notification Evidence: lead final response and Android review result include release commit, remote release HEAD, APK/device SHA, installation time, verification results, residual P2 risks and experience readiness.
Knowledge Evidence: `reports/am005-gequhai-query-normalization-status.md`; `docs/superpowers/plans/2026-07-16-am005-search-library-lyrics.md`; `docs/superpowers/plans/2026-07-16-am005-streaming-search-pagination.md`; `docs/superpowers/specs/2026-07-16-am005-search-library-lyrics-design.md`; `docs/superpowers/specs/2026-07-16-am005-streaming-search-pagination-design.md`.

## 2026-07-17 R3 集中复核结论

- Spec Review Result / 规格符合性：accepted。R3 两项 P1 修复满足修订后的主链路验收：不完整初始 206 不转正缓存；同歌曲严格验证证据可跨刷新 CDN URL 复用，未降低普通匹配门槛；无歌词保持中性可播放状态。
- Code Quality Review Result / 代码质量：accepted。关键状态转换、缓存写入边界和 same-song 约束均有 RED-GREEN 回归测试；合入最新目标基线后定向 23 项和全量 274 项测试通过，analyze 与 diff-check 通过，无阻塞 finding。
- 真机结论：final default-audio APK 与 Xiaomi 10 Pro `base.apk` SHA-256 一致，应用已安装并启动；R3 设备证据显示同曲流媒体升格后继续播放，forced metadata recovery 未出现 `low_match_confidence`，seek 后 `state=3`。
- 非阻塞后续：设备日志中的转义 artist 文本和 Android NDK 未来版本告警归入 P2，不阻塞本次体验包和 1.1.0 合入。

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

## QA Gate

- Matrix: `docs/codex_collab/knowledge/qa-researcher/2026-07-11-am20260711-005-gequhai-p1-regression-matrix.md`
- Android 若 10 到 15 分钟内未给 APK/sha/设备/证据目录，architect 追 Android owner 补齐可复核证据。
- QA 收到 Android APK 后，按矩阵复核完整搜索、下载按钮、边下边播、seek、HTTP fail-closed、cache 转正和 pass/fail/blocker。

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
- 2026-07-11 type=status lane=architect status=in_progress summary=Product/architect 巡检当前 Project Path 发现仅 `test/music_resolver_test.dart` 与 `test/progressive_audio_cache_test.dart` 有 RED 测试改动，尚无生产实现、提交或 APK；review gate 缺 HEAD、Root Cause、RED/GREEN、Targeted Tests、Self Test、Scope Diff 和 Product Main Path Evidence。有效 RED 当前聚焦 `周杰伦` 歌手搜索失败与 Range 失败回退失败；`剩下的果实` 兜底测试已通过，需要 Android 补真实 miss 复现或调整证据口径。
- 2026-07-11 type=status lane=architect status=self_tested summary=Architect 兜底收口 AM-005 P1 最小 GREEN：提交 `586fa96874dc3a92bc12366e39643750e31ac29e`，修复 歌曲海 artist-only 查询召回与 progressive Range 失败 full GET fallback；targeted suite 157 passed，analyze no issues，debug APK sha256 `47bf23e46cc3f1d6123feb1027a3ebb3fd5887cc2456bba32adb8ba7d6a7f4b4` 已安装小米 10 Pro。下一步需 android-streaming/QA 用已安装包补真实 seek 后续播设备证据。
