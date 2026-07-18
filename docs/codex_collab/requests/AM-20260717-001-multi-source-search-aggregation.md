# AM-20260717-001 多源完整音频搜索动态聚合

Status: accepted
Owner Lane: mobile-ai-music-developer
Assist Lane: mobile-ai-music-product, mobile-ai-music-ux
Source Thread: 019f6b0e-972c-7eb1-91cd-a43cdbfa7d1e
Product Return Thread: 019f6b0e-a150-7892-aec8-d8aa8314d802
Target Version: 1.2.0
Base Branch: release/1.1.0
Work Branch: feature/1.2.0/AM-20260717-001-multi-source-search-aggregation
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260717-001_multi_source_search_aggregation
Merge Branch: release/1.2.0
Created: 2026-07-17
Updated: 2026-07-18
Workflow: superpowers-v1
Work Type: feature
Risk Level: P1
User Visible: yes
Design Doc: docs/superpowers/specs/2026-07-17-multi-source-search-aggregation-design.md
Implementation Plan: docs/superpowers/plans/2026-07-17-multi-source-search-aggregation.md
Required Skills: executing-plans, test-driven-development, ai-music-team-ops, verification-before-completion
TDD Mode: required
TDD Exception: none
TDD Exception Review: not_applicable
Baseline Commit: 3e5a95f4213aa957f084d1e27e629da2c2ba0edf
Head Commit: 47f714e32bd08c45ae97a5489623e75889979d56
Requirement Revision: sha256:5861c7a4f58e7d401e7a494ba51bc41af47d8ddbd96aea5484b659cecd569f65 user_approved
UX Revision: sha256:e159044beea3520bf21750ff900fd6252a13c04d5d853f9696b16d19f2e0e759 accepted authorization=true
Discovery Evidence: DISC-0005 through DISC-0009 resolved by product/UX. Bound behavior: local complete cache publishes immediately; online results grow in batches of at least two; first screen may serially prefetch up to three pages or eight songs; existing results keep only tail loading; single-source failure is localized; BuguYY/FLAC/22a5 remain excluded from Auto.
Root Cause Evidence: Xiaomi direct DNS for `www.gequhai.com` resolves to `154.201.73.66` but TCP connect times out; the Mac HTTP 200 result traverses a proxy/TUN address and cannot prove device reachability. The former one-row behavior then came from the only Kuwo candidate passing complete-audio validation. See `evidence/qa-am001-multi-source-20260717/device-network-and-source-admission.md`.
Research Evidence: One serial Xiaomi probe per candidate source found BuguYY search rows but only failed direct resolution/Quark pan completion, FLAC anti-CC HTML, and 22a5 security-verification HTML. All remain fail closed; no challenge, certificate, or access control was bypassed.
Red Evidence: cache-first search initially retained blocking loading after local hits; artist-title cache matching returned no candidates; coordinator logger coverage did not compile before logger injection; a timeout source was called again on the second search before timeout was included in the circuit policy; two local complete-cache rows for the same normalized title+artist but different source/id both appeared. Round 3 RED: three initial pages each returned `count=0 hasNextPage=true` but UI fell back to the initial search panel; SocketException and all-candidate HEAD/Range 403/429/defender failures were swallowed as ordinary empty candidates and did not open source circuit.
Green Evidence: local complete-cache artist and artist-title matching passes; local rows win over remote identity duplicates; two local cross-source duplicate cached rows collapse to one stable row; online-source diagnostic rows remain distinct; timeout opens the per-source two-minute circuit. Round 3 GREEN: bounded three-page empty search now emits `noOnlineMatchesFound`; SocketException and all-candidate source-level validation failures propagate to coordinator, open a two-minute circuit, skip the failed source on the next same-process search, and keep Kuwo/cache results; ordinary bad candidates remain fail-closed without poisoning the source.
Targeted Tests: 2026-07-18 fresh `music_controller_test.dart` + `multi_source_search_coordinator_test.dart` + `music_resolver_test.dart` + `widget_test.dart`: 178/178 passed. Focused source-failure rerun `r3-source-failure-circuit-targeted-32040770.log` covers SocketException, provider_http_403, circuit-open, circuit-skip, and result retention.
Self Test Evidence: `flutter test` 299/299 passed; 2026-07-18 fresh `flutter analyze` no issues; fresh `git diff --check` clean; debug APK build and preserve-data install succeeded; built/installed SHA-256 match.
Product Main Path Evidence: `evidence/qa-am001-multi-source-20260717/search-coldplay-initial-f0a2.*` proves one result set containing `完整` Kuwo rows and `歌海` Gequhai rows; `kuwo-coldplay-playing-*` and `gequhai-coldplay-playing-*` prove both sources play on the same final package; `ux-append-progress-angel-page3-100ms-f0a2.png` proves tail loading with clickable existing rows; `search-only-radiohead-*` proves search-only candidates do not create part/formal cache files. Round 3 final package evidence: `r3-final-empty-32040770.*` shows the exact three-page all-empty `hasNextPage=true` log and final `没有找到在线结果` UI; `r3-failure-retention-coldplay-clean-32040770.*` shows ordinary `audio_too_short` candidates filtered while complete/cache and `歌海` results remain visible.
Baseline Freshness Evidence: Independent clone created from `origin/release/1.1.0@3e5a95f4213aa957f084d1e27e629da2c2ba0edf`; feature branch HEAD and merge-base both match this accepted AM-005 release baseline. Fresh baseline verification: Flutter full suite 274 passed, analyze no issues, diff-check clean; collaboration tool suite 17 passed.
Scope Diff Evidence: implementation commit `47f714e32bd08c45ae97a5489623e75889979d56` is scoped to multi-source resolver/coordinator, search controller/UI loading behavior, resolver trust gates, matching tests, frozen requirement/UX docs, and collaboration-lane validation. Local device evidence and APK exports remain excluded from Git.
Spec Review Result: accepted
Spec Review Evidence: R2 requirement `5861c7...` and UX revision `e15904...` are satisfied, including bounded three-page final no-match, local-cache aggregation, batch growth, localized source failure, dynamic queue, and strict full-audio admission.
Code Quality Review Result: accepted
Code Quality Review Evidence: SocketException and all-candidate source-level validation failures now propagate to the coordinator circuit while ordinary bad candidates remain candidate-local fail-closed; fresh 178 targeted, 299 full, analyze, diff-check, and collaboration tests pass.
Full Verification Evidence: full suite 299/299, targeted suite 178/178, analyze 0, diff-check 0. Final APK `build/app/outputs/flutter-apk/app-debug.apk` SHA-256 `3204077023db2ef5cdccbcf4730a0d70a412d07dd2d79c6a3902446ac19ca98f`; Xiaomi 10 Pro pulled `base.apk` SHA-256 matches; `lastUpdateTime=2026-07-18 09:09:16`; evidence files `apk-final-32040770.sha256`, `device-apk-final-32040770.sha256`, `package-final-32040770.txt`.
Blocking Findings: none
Residual Risk: Exact real-device Gequhai SocketException/403 induction was intentionally not forced; deterministic resolver/coordinator tests cover circuit-open/circuit-skip and result retention, while the Xiaomi package covers ordinary bad-candidate fail-closed. BuguYY, FLAC, and 22a5 remain intentionally excluded under the no-bypass policy.
Merge Evidence: pending
Push Evidence: pending
Product Notification Evidence: pending
Knowledge Evidence: `docs/superpowers/specs/2026-07-17-multi-source-search-aggregation-design.md`; `docs/superpowers/specs/2026-07-18-am001-multi-source-search-requirement-r2.md`; `docs/codex_collab/knowledge/mobile-ai-music-ux/2026-07-18-am001-search-aggregation-ux-reconciliation.md`; `docs/superpowers/plans/2026-07-17-multi-source-search-aggregation.md`.

## 目标

- `Auto` 搜索并行聚合歌曲海与酷我完整音频，任一来源先完成严格校验即可先显示，后续来源只在列表尾部动态追加。
- 新增结果同步进入当前搜索歌曲库与 media session 队列，不改变当前播放歌曲、位置和播放模式，也不预下载未播放歌曲。

## 范围

- 包含：多源分页协调器、歌曲海与酷我独立分页/熔断/错误、严格完整音频准入、跨来源及跨页去重、动态队列增长、初始与追加 loading 状态。
- 包含：公共 Dart/Flutter 定向与全量测试、Android debug APK、小米 10 Pro 两来源真实搜索/播放/seek/缓存证据。
- 不包含：BuguYY、FLAC、22a5、PREVIEW、网盘、HTML、防护页或绕过验证码；不新增页面、筛选器或来源设置。
- 不包含：回滚或重开 AM-20260711-005；AM-005 只作为已验收基线和历史证据。

## 验收标准

1. `Auto` 同一查询动态展示歌曲海和酷我两个来源的严格可播结果，先出现的已有行不重排、不跳动。
2. 所有可见结果均满足 `directAudio/canCacheAudio/clientReady`、音频 HEAD 和总长一致的 Range 206；PREVIEW、HTML、网盘、防护页及低置信候选不可见。
3. 单来源失败、空结果或两分钟熔断时，另一来源仍可搜索、分页和播放；只有两个来源都失败或都无有效候选时才显示聚合错误或空态。
4. 动态追加结果进入搜索歌曲库和 media session 队列，当前歌曲、位置和播放模式不变，未播放候选不创建 progressive session、part 文件或正式缓存。
5. 定向测试、全量测试、analyze、diff-check、默认音频 APK/设备包 SHA 与小米 10 Pro 两来源搜索、播放、seek、缓存转正和失败不污染缓存证据全部通过。

## 工作流边界

- 用户已批准规格与实施计划，开发可立即按 RED-GREEN 开始真实 P1 路径和 80% 可体验包。
- 产品与 UX 必须在最终 requirement/UX freeze、负责人 review approval 和提交前吸收或明确处置 DISC-0005 至 DISC-0007。
- 开发不得 stage、commit、merge 或 push；负责人是唯一 Git owner。
- P2 视觉细化、长尾文案和跨端补齐不阻塞 Android P1 可体验包。

## 消息记录

- 2026-07-17 08:20 type=status lane=mobile-ai-music-developer status=accepted summary=AM-005 已关闭；用户新增并批准“歌曲海与酷我严格校验后多源动态聚合”，DISC-0005 至 DISC-0007、规格和计划已准备。
- 2026-07-17 08:25 type=task lane=mobile-ai-music-developer status=assigned summary=负责人建立新 request 与独立 Project Path；开发按已批准计划 RED-GREEN 实施，不得回滚或重开 AM-005。
- 2026-07-18 07:48 type=review_request lane=mobile-ai-music-developer status=review_requested summary=完成真机反馈回改：本地完整缓存即时聚合、首屏最多三页/八首批量增长、来源超时熔断与诊断；周杰伦和王蓉真机搜索闭环，61/61 critical、293/293 full、analyze/diff 通过，APK 与小米设备包 SHA 一致。额外来源经单次低频准入探测均因网盘/挑战页/安全验证 fail closed，未绕过、未接入。
- 2026-07-18 09:00 type=review_request lane=mobile-ai-music-developer status=review_requested summary=按 R2 复审修复本地跨源同曲缓存重复显示；同一最终包补齐酷我与歌曲海各一首播放、seek state=3、transient-to-formal、未播放零缓存、尾部 loading、最终空态和默认 IME 恢复证据；62/62 targeted、294/294 full、analyze/diff 通过，APK/设备 SHA 为 f0a2d5661cd74daa7cfa0b56d14b20225f30540ce3ba0b7bd8b16ddb261e3b9b。
- 2026-07-18 09:18 type=review_request lane=mobile-ai-music-developer status=review_requested summary=按 R3 复审仅补两项 P1：三页全空但 `hasNextPage=true` 后显示最终空态；SocketException/全候选源级校验失败传播到 coordinator 并熔断，普通坏候选仍只过滤本候选。178/178 targeted、299/299 full、analyze/diff 通过；新 APK/小米包 SHA 为 3204077023db2ef5cdccbcf4730a0d70a412d07dd2d79c6a3902446ac19ca98f。
- 2026-07-18 09:25 type=review_result lane=mobile-ai-music-lead status=accepted summary=Spec Review 与 Code Quality Review accepted；UX accepted，fresh 178/299、analyze、diff-check、实时设备 APK SHA 通过，实现提交为 47f714e32bd08c45ae97a5489623e75889979d56。

## 版本与发布

- Target Version: 1.2.0
- Release Tag: pending
- Android APK: `build/app/outputs/flutter-apk/app-debug.apk` SHA-256 `3204077023db2ef5cdccbcf4730a0d70a412d07dd2d79c6a3902446ac19ca98f`; installed on Xiaomi 10 Pro with matching device package SHA.
- Push Status: not_ready

## Review 结果

- Reviewer Lane: mobile-ai-music-lead
- Result: accepted
- Spec Findings: none. R3 最终空态、两分钟单源熔断、另一来源保留均满足冻结 R2。
- Code Quality Findings: none. 失败传播只在全部候选均为 source-circuit 错误时升级，普通坏候选继续本地淘汰。
- Notes: P1 基于 R2 requirement 与 UX revision 完成验收；负责人进入 release/1.2.0 合入与推送。
