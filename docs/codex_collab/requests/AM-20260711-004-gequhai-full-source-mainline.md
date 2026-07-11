# AM-20260711-004 歌曲海完整搜索下载边播主链路

Status: assigned
Owner Lane: android-source
Assist Lane: source-researcher, android-streaming, android, architect, ui, qa-researcher
Source Thread: 019f4ed4-106e-7860-875d-a32f81629e4e
Target Version: 1.1.0
Priority: P0
Base Branch: release/1.0.2
Work Branch: feature/1.1.0/AM-20260711-004-gequhai-full-source-mainline
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-004
Merge Branch: release/1.1.0
Created: 2026-07-11
Updated: 2026-07-11
Workflow: superpowers-v1
Work Type: bugfix
Risk Level: P0
User Visible: yes
Design Doc: docs/superpowers/specs/2026-07-11-am004-gequhai-full-source-mainline-design.md
Implementation Plan: docs/superpowers/plans/2026-07-11-am004-gequhai-full-source-mainline.md
Required Skills: systematic-debugging, test-driven-development, verification-before-completion, chrome:control-chrome, ai-music-team-ops
TDD Mode: required
TDD Exception: none
TDD Exception Review: not_applicable
Baseline Commit: b306932d03e1eedbe96fd50dafe0f95805b0eab4
Head Commit: pending
Root Cause Evidence: AM-20260711-003 WIP 包仍沿用混合歌源和不可下载候选，Product 真机反馈搜索、下载、边下边播主链路不可用；Chrome 复核证明歌曲海页面播放器可脚本化获得完整 mp3。
Research Evidence: docs/codex_collab/knowledge/source-researcher/2026-07-11-am004-gequhai-full-source-protocol.md
Red Evidence: pending
Green Evidence: pending
Targeted Tests: pending
Self Test Evidence: pending
Product Main Path Evidence: pending
Baseline Freshness Evidence: Project Path 已基于 origin/release/1.0.2@b306932d03e1eedbe96fd50dafe0f95805b0eab4 创建独立工程。
Scope Diff Evidence: pending
Spec Review Result: pending
Code Quality Review Result: pending
Full Verification Evidence: pending
Blocking Findings: none
Merge Evidence: pending
Push Evidence: pending
Product Notification Evidence: pending
Knowledge Evidence: pending

## 背景

Product 明确指出：布谷和 FLAC 两个旧源当前返回网盘或防护路径，不能再作为下载完成路径。客户端此前把试听、不可下载、普通候选和完整可下载候选混在一起，导致用户看到结果但无法完整播放、下载或边下边播。

Product 指定新主链路只展示歌曲海资源，并要求按真实浏览器流程落地：

1. 搜索页 `https://www.gequhai.com/s/外婆` 搜索歌曲。
2. 点击搜索结果进入 `https://www.gequhai.com/play/6330`。
3. 详情页播放器进度条使用页面实际边播音频。
4. 歌词来自详情页歌词区或歌词下载链路。
5. 封面来自详情页内联数据或播放器封面。
6. 下载歌曲弹层中“试听品质（不推荐）”对应页面播放器实际完整 mp3；夸克网盘不算完成路径。

## 根因

- 当前客户端仍允许不可下载来源参与搜索结果和源选择，导致主路径出现“搜到但不能播/不能下”。
- AM-003 UI WIP 包在核心歌源能力未恢复前被安装体验，暴露出 UI 进展不能替代主链路可用性。
- 旧 provider 没有把“Chrome 可播”“网盘下载”“试听 30 秒”“页面播放器完整 mp3”做成严格分类。

## 目标

- 只把歌曲海可脚本化、可验证的完整音频展示为搜索结果。
- 搜索结果中每一条可见歌曲都必须能完整播放、完整下载或边下边播。
- 不再展示试听、PREVIEW、30s、网盘、HTML、防护页、不可下载普通候选作为完成路径。
- 落地歌曲海搜索、详情、歌词、封面、`/api/music`、HEAD/Range 校验、边下边播、完成后缓存转正。
- 保留失败分类和低频访问原则，不高并发压测第三方站点。

## 验收标准

- `外婆 / 周杰伦` 搜索必须返回歌曲海完整音频候选，点击可边下边播，最终完整缓存转正；不得命中非歌曲或错误艺人。
- 样例覆盖 `外婆`、`一丝不挂`、`稻香`、`哎呀`，以及一个失败样例；每个样例必须有搜索、详情、音频校验、歌词、封面、缓存行为证据。
- 歌曲海音频必须通过 HEAD `200 audio/*`、正数 Content-Length 或 Range total、Range `206` 后才能 `direct_audio/canCacheAudio=true`。
- 首声时间必须早于完整下载完成时间，part 文件有增长序列，完成后写正式 mp3 和 `_cache_index.json`。
- 歌词和封面必须写入 metadata；播放页能看到歌词或有 metadata/cache 证据。
- 失败样例必须 fail closed，不显示可播放行，不写正式缓存。
- 小米 10 Pro 主路径自测必须从 App 搜索入口跑到播放和下载完成，不允许只用脚本或 XML 代替。

## 分工

- `source-researcher`：低频复核歌曲海多样例，输出 Chrome 证据、脚本、字段表和失败分类。
- `android-source`：在公共 Dart 落地 provider、resolver、cache、controller 和 UI 过滤，owner 本任务闭环。
- `android-streaming`：复核边下边播首声、Range、part 增长、完成转正、失败不写缓存和 LRU 隔离。
- `android`：复核公共 Dart/Android 边界、主路径自测和防回退。
- `ui`：仅复核搜索结果只出现可完整播放资源后的 UI 表达，不阻塞 P0 主链路。
- `architect`：review、合入、推送和体验包判断。

## 当前决策

- AM-20260711-003 UI WIP 包不能作为验收包继续推进，直到 AM-004 恢复核心搜索、下载、边下边播主链路。
- 搜索结果宁可少，也不能展示不可完整播放的歌曲。
- 歌曲海以页面播放器实际完整音频为准；夸克网盘、iTunes preview、布谷/FLAC 网盘、防护页都不算完成。

## 消息记录

- 2026-07-11 `product`：AM-004 作为当前 P0 调度入口；AM-003 UI WIP 包不能继续作为验收包，直到歌曲海完整搜索、完整下载、完整播放和边下边播主链路恢复。
- 2026-07-11 `android-streaming`：已接收 streaming 复核任务，`validate-request` 与 `validate-workflow --gate start` 均 OK；后续按 `Spec Review Result` 和 `Code Quality Review Result` 双结论复核首声、Range/206、part 增长、缓存转正、失败隔离、LRU、metadata、targeted tests、analyze、diff-check 和缓存语义。
- 2026-07-11 `architect`：已将 AM-004 request、design、plan、歌曲海协议知识页和 `team_ops` gate 工具同步到 Project Path `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004`；当前等待 `android-source` 回传 HEAD、targeted tests、analyze、APK sha 和小米 10 Pro 主路径证据。
