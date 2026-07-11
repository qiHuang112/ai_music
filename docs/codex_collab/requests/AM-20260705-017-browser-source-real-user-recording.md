# AM-20260705-017 真实浏览器操作下歌源播放/下载分类修正

Status: verified
Owner Lane: android-source
Assist Lane: source-researcher, android-streaming, android, architect
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Target Version: 1.0.2
Priority: P0
Base Branch: release/1.0.2
Work Branch: feature/1.0.2/AM-20260705-017-gequhai-player-audio-poc
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260705-017_android_source
Merge Branch: release/1.0.2
Created: 2026-07-05
Updated: 2026-07-11
Workflow: superpowers-v1
Work Type: bugfix
Risk Level: P2
User Visible: no
Design Doc: docs/superpowers/specs/2026-07-11-am017-gequhai-cookie-jar-design.md
Implementation Plan: docs/superpowers/plans/2026-07-11-am017-gequhai-cookie-jar.md
Required Skills: systematic-debugging, test-driven-development
TDD Mode: required
TDD Exception: none
TDD Exception Review: not_applicable
Baseline Commit: 32d183c8c2038000f4f6e42c60b72125021a5cae
Head Commit: b306932d03e1eedbe96fd50dafe0f95805b0eab4
Root Cause Evidence: `_fetchPage` at d84080f dropped first 403 response cookies before `/api/music`; RED showed API cookie was only `session=b`, missing `guard=a`.
Research Evidence: source-researcher evidence `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/script/gequhai-38173-probe-result.json`; re-review accepted HEAD b306932.
Red Evidence: `/tmp/am017-redcheck` on d84080f with new test `gequhai retry carries merged page cookies to api but not CDN media` failed: expected API cookie contains `guard=a`, actual `session=b`.
Green Evidence: HEAD b306932 same test passed: `flutter test --no-pub test/music_resolver_test.dart --plain-name 'gequhai retry carries merged page cookies to api but not CDN media'` = 1 passed.
Targeted Tests: `flutter test --no-pub test/music_resolver_test.dart test/music_cache_test.dart test/progressive_audio_cache_test.dart test/music_controller_test.dart test/widget_test.dart` = 138 passed; `flutter analyze --no-pub` = no issues.
Self Test Evidence: android-source verified cookie jar test, full targeted suite, analyze, diff-check, and debug APK build sha256 `4eebeed8803576266d0e2456e47a0fb11a083eaff58284d3ec4d85a7852b068a`.
Product Main Path Evidence: not_applicable
Baseline Freshness Evidence: HEAD b306932 is based on `origin/release/1.0.2=32d183c8c2038000f4f6e42c60b72125021a5cae`; `git diff --check origin/release/1.0.2..HEAD` clean.
Scope Diff Evidence: P2 diff from d84080f to b306932 only `lib/src/data/gequhai_player_audio_resolver.dart` and `test/music_resolver_test.dart`.
Spec Review Result: accepted
Code Quality Review Result: accepted
Full Verification Evidence: android-streaming accepted HEAD b306932；targeted suite 138 passed，flutter analyze no issues，diff-check/conflict marker clean；上一轮小米 10 Pro `/tmp/am017-device-evidence/gequhai-player-audio/` 边下边播证据仍适用。
Blocking Findings: none
Merge Evidence: superseded_by_AM-20260711-004: AM-004 将歌曲海从单样例 PoC 扩展为完整搜索/下载/边下边播主链路，并已合入 release/1.1.0。
Push Evidence: release/1.1.0 已推送；AM-004 release HEAD `aef2bf3c79623581b897d815315248fb15724d10`，后续 AM-003 release HEAD `45b302d48649330446d381b8593c50e22b9099f5` 保留该歌曲海主链路。
Product Notification Evidence: AM-004 已回 product，歌曲海四首正向和东方财富 fail closed 作为正式验收口径；本次 AM-TEAM-AUDIT 将 AM-017 标记为被 AM-004 覆盖关闭。
Knowledge Evidence: docs/codex_collab/knowledge/source-researcher/2026-07-11-am004-gequhai-full-source-protocol.md; docs/codex_collab/requests/AM-20260711-004-gequhai-full-source-mainline.md

## 背景

Product 通过 Record & Replay 亲自演示歌源真实浏览器使用路径，指出当前客户端把一些歌曲标为“完整”但实际并不是可完整下载/完整缓存的歌曲。

录制证据：

- Session: `/var/folders/4w/6v4q2nr96q71wbh3lv42_ghh0000gn/T/sky/event_stream/1394AED0-456E-459F-9AD3-4614F5D24143/session.json`
- Events: `/var/folders/4w/6v4q2nr96q71wbh3lv42_ghh0000gn/T/sky/event_stream/1394AED0-456E-459F-9AD3-4614F5D24143/events.jsonl`

关键观察：

- `22a5.com/mp3/gslelxsl.html`：黑夜传说页面在 Chrome 中有播放器、歌词和进度，能浏览器播放；下载区同时出现夸克网盘、本站下载和 LRC 下载，不能直接等同于客户端可完整缓存。
- `22a5.com/mp3/admgx.html`：周杰伦《外婆》页面显示“该歌曲无权播放！歌曲相关资源已被删除”，不能标为完整可播或可下载。
- `gequhai.com/play/6330`：周杰伦《外婆》页面在 Chrome 中能播放，标题显示正在播放音频；音质弹层包含“下载到电脑”和“试听品质（不推荐）”，其中“下载到电脑”跳到夸克网盘。
- `gequhai.com/play/38173`：王蓉《哎呀》页面在 Chrome 中能播放，页面显示播放进度；下载歌曲链接为夸克网盘。

## 目标

- 重新定义歌源分类，不能再把浏览器可播、试听品质、网盘下载、站内完整直链、口令下载混成同一个“完整”。
- 找到可客户端脚本化、可完整下载、可完整播放、可边下边播的真实路径。
- 对只能浏览器播放但无法脚本化直链的来源，标为 `browser_playable_only` 或等价失败/限制状态，不能显示为完整可下载。
- 对网盘下载、口令下载、安全验证、防护页、无权播放，保持 fail closed，不写正式缓存。

## Product 决策

- 优先使用歌曲海页面播放器实际边下边播的音频源，不使用夸克网盘资源。
- 以 `https://www.gequhai.com/play/38173` 为第一条样例链路：页面里《哎呀 / 王蓉》能在线播放，歌词和封面也可在页面链路中获取。
- 目标不是点击“下载到电脑”进入网盘，而是抓取页面播放器实际使用的完整音频流，验证它能边下边播、完整播放，并在完成后作为正式缓存。
- 歌词和封面也应从歌曲海页面或页面关联接口中提取并落地到客户端 metadata。
- 研究必须低频模拟真实用户浏览器操作，先用 Chrome 观察真实请求，再转成脚本，再沉淀 skill，最后交客户端实现。

## 分类要求

- `direct_full_audio`: 客户端可拿到完整音频直链，HEAD/Range 校验通过，可边下边播，可完成后转正式缓存。
- `browser_playable_only`: Chrome 用户态能播放，但客户端脚本暂未拿到稳定完整直链；不能当作完整下载完成。
- `audition_quality_only`: 页面明确是试听品质或低质量试听；不能当作完整下载完成。
- `external_pan_link`: 夸克等网盘；不能写正式缓存。
- `site_download_with_password`: 站内下载但需要口令或额外用户动作；未脚本化前不能写正式缓存。
- `unavailable_removed`: 页面显示无权播放、资源删除或同类不可用状态。
- `security_or_defender`: 安全验证、防护页或需要真实交互绕过；不能高频探测。

## 验收标准

- source-researcher 用 Chrome 真实用户态和低频脚本复核 22a5、gequhai，至少覆盖：
  - 哎呀 / 王蓉 / `https://www.gequhai.com/play/38173`
  - 黑夜传说 / 麻园诗人
  - 外婆 / 周杰伦
  - 哎呀 / 王蓉
  - 一丝不挂 / 陈奕迅
  - 稻香 / 周杰伦
- 每首歌输出分类表：页面 URL、是否浏览器可播、是否有站内播放进度、下载按钮去向、是否网盘、是否试听品质、是否可脚本化 direct_full_audio、失败原因。
- android-source 只能把 `direct_full_audio` 展示为完整可播放/可下载；其它分类必须显示原因或隐藏操作按钮。
- 如果发现 gequhai 或 22a5 的真实音频 URL，必须证明 HEAD 200 audio、Range 206、Content-Length/Range total 正数、完整播放、边下边播、完成后缓存转正。
- 不允许因为 Chrome 能播放就直接标为客户端完整可下载。
- 歌曲海 `play/38173` 必须输出：
  - 播放器实际请求的音频 URL 或可脚本化换取该 URL 的接口。
  - 歌词来源和解析结果。
  - 封面来源和解析结果。
  - 不依赖夸克网盘的完整音频边下边播证据。
  - 客户端可复现的最小协议。

## 回传要求

source-researcher 回 product/architect/android-source：

- 录制事件复盘摘要。
- 五首歌分类表。
- Chrome 操作证据、脚本路径和输出 JSON。
- 可客户端落地的最小协议，或明确 `browser_playable_only` 的阻塞点。

android-source 回 product/architect/android：

- 若有可用 direct_full_audio，提供 Project Path、HEAD、tests/analyze、APK sha、小米 10 Pro 主路径自测证据。
- 若没有可用 direct_full_audio，更新 UI 分类和不可下载原因，不允许显示“完整”。

## Review 结果

- Reviewer Lane: architect
- Result: assigned
- Findings:
- Product 录制证明当前“完整”口径过粗，必须拆分为可验证分类。
- 真实浏览器可播不是完整下载完成标准。
- Product 已明确：歌曲海页面播放器实际边播音频可作为完整歌曲源，前提是能脚本化抓取、校验并完整播放；网盘下载不作为本任务目标。
- AM-016 仍可继续合入搜索可用性修复，但 AM-017 必须修正歌源分类和后续客户端展示。

## 2026-07-05 Source Research: gequhai play/38173

- Owner Lane: source-researcher
- Status: completed_for_handoff
- 样例：`https://www.gequhai.com/play/38173`（哎呀 / 王蓉）
- Chrome 用户态证据：
  - 播放器已播放，页面进度观察到 `00:02 / 03:36`。
  - Chrome resource/audio 资产出现 `M500000ybLMu1RZ65O.mp3`。
  - 下载歌曲按钮为夸克：`https://pan.quark.cn/s/c62e929dc2d3`，归类 `external_pan_link`。
- 脚本证据：
  - Script: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/scripts/probe_gequhai_38173.js`
  - JSON: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/script/gequhai-38173-probe-result.json`
  - Report: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/reports/am017-gequhai-38173-direct-audio.md`
  - Chrome summary: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/chrome/gequhai-38173-chrome-summary.json`
  - Chrome screenshot: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/chrome/gequhai-38173-playing.png`
- 最小协议：
  - GET `/play/{id}`，保留 cookie jar。
  - 若首次返回 403 + JS 自跳转同页，低频等待后同 cookie jar 重试一次；不提交验证码、不高频重试。
  - 解析 `window.play_id`、`window.mp3_title`、`window.mp3_author`、`window.mp3_cover`、`#content-lrc2`。
  - POST `/api/music`，body `id=<play_id>&type=0`，带 `Origin`、`Referer`、`X-Requested-With: Http`、`X-Custom-Header: Key` 和同一 cookie jar。
  - 使用 `result.data.url` 作为 CDN 音频 URL。
  - 对 CDN 音频 URL 做 HEAD/Range/播放时不要带 gequhai 页面 referer。
- 校验结果：
  - `/api/music`: `code=200`，返回 CDN mp3 URL。
  - HEAD no-referer: `200 audio/mpeg`，`Content-Length=3468831`，`Accept-Ranges=bytes`。
  - Range no-referer: `206 bytes 0-8191/3468831`，读取 `8192` bytes。
  - Range with gequhai referer: `403`，因此最终音频请求必须禁用 gequhai referer。
  - 歌词来源：页面 `#content-lrc2`，样例 87 行。
  - 封面来源：`window.mp3_cover` / `.aplayer-pic`，`https://img2.kuwo.cn/star/albumcover/120/25/73/1950245592.jpg`。
- 分类：
  - `play/38173`: `direct_full_audio`，可交 android-source 做 provider PoC。
  - 夸克按钮：`external_pan_link`，不得作为下载完成路径。
  - 持续页面 403 / 无 `play_id`: `security_or_defender`。
  - API 非 200: `play_url_unavailable`。
  - CDN 非音频或无 Range: `non_audio_content` / `range_not_supported`。
- Android handoff:
  - 新 provider 可命名 `source_gequhai_player_audio` 或沿用 `source_gequhai` 但 capability 必须为 `direct_full_audio`。
  - `ResolvedMusic.sourceAttempts` 记录 page、api、media_validation 三段。
  - `clientReady=true/canCacheAudio=true` 仅在 HEAD/Range 通过后返回。
  - 音频校验和播放请求不能附带 gequhai page referer；API 请求需要 gequhai referer 和 cookie jar。

## 2026-07-05 Architect Kickoff

- Reviewer Lane: architect
- Result: assigned_to_android_source
- Research Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017`
- Client Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017_android_source`
- Client Work Branch: `feature/1.0.2/AM-20260705-017-gequhai-player-audio-poc`
- Client Base: `origin/release/1.0.2=32d183c8c2038000f4f6e42c60b72125021a5cae`
- Owner:
  - `source-researcher` 已交第一样例 Chrome 用户态证据、脚本化协议和 `direct_full_audio` 结论。
  - `android-source` 立即进入客户端 PoC 实现。
  - `android-streaming` 在客户端实现后复核边下边播 gate。
- Immediate source-researcher gate:
  - 第一样例固定为 `https://www.gequhai.com/play/38173`，目标歌曲为《哎呀 / 王蓉》。
  - 必须从页面播放器实际请求链路获取完整音频流，不能使用夸克网盘、口令下载或“下载到电脑”网盘路径。
  - 必须输出歌词和封面来源，说明是否来自页面 DOM、内联脚本、接口或播放器 metadata。
  - 必须区分 `browser_playable_only`、`audition_quality_only`、`external_pan_link`、`site_download_with_password`、`unavailable_removed`、`security_or_defender` 和 `direct_full_audio`。
  - Chrome 可播只能证明 `browser_playable_only`；只有播放器实际完整音频流通过 HEAD/Range/长度/内容类型校验，才可标 `direct_full_audio`。
- Required research evidence:
  - Chrome DevTools / performance / network 证据：页面 URL、播放器请求、media URL 或接口、headers、Range 行为、content-type、content-length。
  - 低频脚本路径和 JSON 输出，不能高频压测第三方站点。
  - `https://www.gequhai.com/play/38173` 的歌词和封面解析结果。
  - 至少覆盖任务单列出的样例：哎呀、黑夜传说、外婆、一丝不挂、稻香，并给分类表。
  - 如果可脚本化 direct audio 成立，给 android-source 的最小协议必须包含请求参数、必要 headers/cookie、URL 过期、失败分类和缓存安全 gate。
- Client implementation gate:
  - android-source 只能把 `direct_full_audio` 展示为完整可播/可下载。
  - 任何网盘、试听品质、Chrome-only、口令下载、安全验证、无权播放都不得写正式缓存。
  - 若接入客户端，必须有小米 10 Pro 主路径自测：搜索、点击完整音频、media session、part 增长、download_complete、缓存转正、歌词/封面展示。

## 2026-07-05 Architect Review of Gequhai 38173 Evidence

- Reviewer Lane: architect
- Result: accepted_for_client_poc
- Evidence:
  - Report: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/reports/am017-gequhai-38173-direct-audio.md`
  - JSON: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/script/gequhai-38173-probe-result.json`
  - Script: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/scripts/probe_gequhai_38173.js`
- Accepted facts:
  - `https://www.gequhai.com/play/38173` 可通过页面 GET + cookie + `POST /api/music` 脚本化拿到 CDN mp3。
  - 页面可解析 `play_id`、标题、歌手、歌词 `#content-lrc2` 和封面 `window.mp3_cover`。
  - CDN 音频 HEAD `200 audio/mpeg`、`Content-Length=3468831`、`Accept-Ranges=bytes`；Range `206 bytes 0-8191/3468831`。
  - 最终 CDN HEAD/Range/播放不能带 gequhai referer；带 referer 403，应归类为 `referer_forbidden_retry_without_referer` 并无 referer 重试。
  - 页面 `下载歌曲` 仍是夸克网盘，必须保留 `external_pan_link` fail closed，不作为完成路径。
- Android-source implementation requirements:
  - 新增或扩展 `source_gequhai` 为播放器音频 provider，内部 capability 标记为 `direct_full_audio` / `direct_audio` / `clientReady=true` / `canCacheAudio=true` 仅在 HEAD/Range/长度 gate 全部通过后成立。
  - 低频请求：GET 页面；必要时只允许一次同 cookie retry；POST `/api/music` 使用页面 cookie 和 required headers；最终 CDN 音频校验和播放不得带 gequhai referer。
  - 解析并落地歌词/封面：lyrics source `gequhai:page:#content-lrc2`，cover source `gequhai:page:window.mp3_cover`。
  - 失败分类：`security_or_defender`、`play_url_unavailable`、`referer_forbidden_retry_without_referer`、`non_audio_content`、`range_not_supported`、`external_pan_link`。
  - 小米 10 Pro 主路径自测必须覆盖：搜索/打开哎呀、点击完整音频播放、media session、first_byte_ms、part 增长、download_complete_ms、正式缓存转正、歌词/封面显示或 metadata 证据、夸克不写缓存。
- Android-streaming review requirements:
  - 首声早于完整下载完成。
  - Range/206 或等价渐进读取成立。
  - 取消/失败不写正式缓存。
  - `download_complete` 后正式缓存转正。
  - LRU 只清 transient，不误删正式缓存。

## 2026-07-05 Source Research Review of Android PoC

- Reviewer Lane: source-researcher
- Result: changes_requested
- Reviewed Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017_android_source`
- Reviewed HEAD: `d84080fd5358fe1a732d55cfdb347b5312cf2559`
- Accepted:
  - 主链路与歌曲海协议方向一致：GET `/play/38173` 解析 `play_id`、歌词和封面，POST `/api/music` 获取 CDN URL，CDN HEAD/Range 使用 no-referer。
  - `direct_audio/canCacheAudio=true` gate、夸克不进入完成路径、边下边播与缓存转正方向正确。
  - source-researcher 抽跑 `flutter test --no-pub test/music_resolver_test.dart test/music_controller_test.dart test/widget_test.dart` 通过，`flutter analyze --no-pub` 无问题，`git diff --check origin/release/1.0.2..HEAD` 通过。
- Finding:
  - P2 协议忠实性：`_fetchPage` 在首次 403 防护响应和 retry 200 响应之间没有合并 cookie jar，最终只把最后一次 `response.cookies` 传给 `/api/music`。研究脚本要求 GET 页面 cookie jar 贯穿页面重试和 API 请求；当前实现可能导致 Chrome 可播但客户端在防护重试路径偶发失败。
  - P3 非阻塞：页面夸克链接当前只检测明文 `pan.quark.cn`，`window.mp3_extra_url` 编码夸克 evidence 可能不会记录为 `external_pan_link`，但未进入完成路径，不阻塞缓存安全。
- Required fix:
  - android-source 在 `lib/src/data/gequhai_player_audio_resolver.dart` 合并首次页面 GET、403 retry GET 的 cookie jar，并把合并后的 Cookie header 传给 `/api/music`。
  - 补测试覆盖：首 GET=403 defender + Cookie A，retry GET=200 + Cookie B，POST `/api/music` 同时带 A/B，且 CDN HEAD/Range 仍不带 gequhai referer。
  - P3 可顺手解码或记录 `window.mp3_extra_url` 为 `external_pan_link` evidence，但不要扩大 AM-017 范围。

## 2026-07-11 Source Research Re-review of Android PoC

- Reviewer Lane: source-researcher
- Result: accepted
- Reviewed Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017_android_source`
- Reviewed HEAD: `b306932` (`AM-20260705-017 preserve gequhai retry cookies`)
- Research Evidence:
  - Script: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/scripts/probe_gequhai_38173.js`
  - JSON: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/script/gequhai-38173-probe-result.json`
  - Report: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/reports/am017-gequhai-38173-direct-audio.md`
  - Chrome screenshot: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/chrome/gequhai-38173-playing.png`
  - HEAD/Range headers: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/script/probe-gequhai-audio-head.headers`, `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-017/evidence/script/probe-gequhai-audio-range.headers`
- Accepted:
  - P2 已闭合：`GequhaiPlayerAudioResolver._fetchPage` 已把首次页面 GET 和 403 retry GET 的 cookies 合并为 jar，并把合并后的 cookie header 传给 `/api/music`。
  - 新增测试 `gequhai retry carries merged page cookies to api but not CDN media` 覆盖首 GET=403 defender + Cookie A、retry GET=200 + Cookie B、POST `/api/music` 同时带 A/B，且 CDN HEAD/Range 不带 gequhai referer。
  - P3 已顺手补齐：`window.mp3_extra_url` 会 URL decode 后识别夸克 `external_pan_link` evidence；仍不进入完成路径。

## 2026-07-11 Active Request Convergence

- Result: verified / superseded_by_AM-20260711-004
- Replacement Request: `AM-20260711-004 歌曲海完整搜索下载边播主链路`
- 关闭原因：AM-017 是歌曲海 `play/38173` 单样例 PoC 与 cookie jar 协议修正；AM-004 已基于同一协议扩展到 `外婆`、`一丝不挂`、`稻香`、`哎呀` 四首完整音频，并覆盖搜索、点击播放、边下边播、歌词封面、缓存转正、`东方财富` fail closed 与无 PREVIEW/网盘完成路径。
- 后续不再基于 AM-017 单样例做实现或验收；任何歌曲海完整源问题进入 AM-004 后续 bugfix 或新 request。
  - 主协议忠实：GET 页面 cookie/play_id/歌词/封面，POST `/api/music` 带 Origin/Referer/X-Requested-With/X-Custom-Header/cookie jar，最终 CDN no-referer HEAD/Range/长度 gate 后才 `direct_audio/canCacheAudio=true`。
- Verification:
  - `/Users/huangqi/AIHome/tools/flutter/bin/flutter test --no-pub test/music_resolver_test.dart test/music_controller_test.dart test/widget_test.dart` = 113 passed。
  - `/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze --no-pub` = No issues found；命令期间 Flutter 自身尝试 fetch tags 因本地代理不可用输出网络提示，但 analyze 结果通过。
  - `git diff --check origin/release/1.0.2..HEAD` = clean。
- Handoff:
  - source-researcher 接受 AM-017 歌曲海 `play/38173` 客户端协议实现。
  - 后续由 architect/android-source/android-streaming 基于 HEAD `b306932` 和小米 10 Pro evidence 做最终合入/边下边播 gate；source-researcher 无需继续拦截。

## 2026-07-11 Android Streaming Review of Cookie Jar Fix

- Reviewer Lane: android-streaming
- Result: accepted
- Reviewed HEAD: `b306932`
- Spec Review Result: accepted
  - 本轮只影响页面重试 cookie jar 与 `external_pan` evidence 解码。
  - `source_gequhai` direct audio、Range gate、transient streaming、缓存转正和 UI 语义均未改变。
  - 上一轮小米 10 Pro `/tmp/am017-device-evidence/gequhai-player-audio/` 合法完整音频边下边播证据仍适用，无需为纯失败路径窄改重复完整装机。
- Code Quality Review Result: accepted
  - 新增 resolver test 覆盖 403 defender retry 时 `guard`/`session` cookie 合并给 `/api/music`。
  - 最终 CDN HEAD/Range 仍不带 referer，并保持 resolved `directAudio/canCacheAudio=true`。
  - targeted suite 138 passed，`flutter analyze --no-pub` no issues，diff-check/conflict marker clean。

## 2026-07-11 Android Owner Review of Cookie Jar Fix

- Reviewer Lane: android
- Result: accepted
- Reviewed HEAD: `b306932d03e1eedbe96fd50dafe0f95805b0eab4`
- Workflow: superpowers-v1
- Spec Review Result: accepted
  - 403 首响应 Cookie A 与 retry 200 Cookie B 会合并到 page cookie jar，并传给 `/api/music`。
  - CDN HEAD/Range 仍只走 no-referer `_mediaHeaders`。
  - 编码夸克链接只作为 `external_pan` evidence，不进入 `direct_audio/canCacheAudio` 完成路径。
- Code Quality Review Result: accepted
  - 新增 `_mergeCookies` 与 `_cookieHeaderFromJar` 范围清晰。
  - 测试覆盖 retry cookie 合并、API headers、CDN no-referer 和 Gequhai 完整音频正向链路。
  - 未扩大到其它 source/cache/UI 逻辑。
- Verification:
  - Review gate OK。
  - `flutter test --no-pub test/music_resolver_test.dart --plain-name 'gequhai retry carries merged page cookies to api but not CDN media'` = 1 passed。
  - `flutter test --no-pub test/music_resolver_test.dart test/music_cache_test.dart test/progressive_audio_cache_test.dart test/music_controller_test.dart test/widget_test.dart` = 138 passed。
  - `flutter analyze --no-pub` = no issues。
  - `git diff --check d84080fd5358fe1a732d55cfdb347b5312cf2559..HEAD` = clean。
  - APK sha256 `4eebeed8803576266d0e2456e47a0fb11a083eaff58284d3ec4d85a7852b068a`。
  - 上一轮小米 10 Pro 完整音频证据仍可沿用：本轮只改 page/API cookie 传递和 encoded Quark evidence，不改变 UI、播放、streaming gate、缓存转正、歌词/封面写入正向路径。
