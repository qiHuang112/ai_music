# AM-20260626-001 歌词真实设备回归

Status: in_progress
Owner Lane: android
Assist Lane: qa verification, ios provider risk support, architect review
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.1.0 verification
Priority: P1
Base Branch: release/1.1.0
Work Branch: verification/1.1.0/AM-20260626-001-lyrics-real-device-regression
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260626-001_android_lyrics_regression
Merge Branch: not_applicable_verification
Created: 2026-06-26
Updated: 2026-07-11

## 目标

修复并验证 product 反馈的真实歌曲无歌词回归：`坏孩子`、`苦笑`、`风度`、`昆明晚安`、`春雨里洗过的太阳`、`一丝不挂`。

## Owner 职责

- Android lane 负责公共 Dart metadata/provider/cache/UI 刷新修复。
- Android lane 必须先自测，不再等待 product 用验收机反馈来猜问题。
- 修复完成后产出 Beta 包并给 QA 验证。
- QA lane 独立复测同一清单，回 pass/fail/blocker 和证据。
- Architect lane 做 P1 gate、review、合入裁决。

## 验收标准

每首歌必须有：搜索词、候选来源、candidate id/platform/source、provider chain、metadata cache 写入结果、播放页截图或日志结论。

如果真实无 timed LRC，必须给完整 miss chain 和后续 provider 方案；不能把 URL、歌名纯文本、无时间轴介绍误判为“有歌词”。

## QA 验证

- QA Gate: `docs/codex_collab/knowledge/qa-researcher/2026-07-11-am20260626-001-lyrics-real-device-matrix.md`
- 默认设备：小米 10 Pro `192.168.31.76:5555`。
- QA 使用 Android 提供的 Beta manifest 和 APK sha。
- QA 运行 `tool/collect_android_diagnostics.sh --device 192.168.31.76:5555` 采集证据。
- QA 回传必须包含包 sha、versionCode、设备 target、清单逐项结果、截图/日志路径。

## Review 结果

- Reviewer Lane: architect
- Result: pending
- Findings: pending

## 2026-07-11 Active Request Convergence

- Result: still_active_as_real_device_regression
- Covered By:
  - AM-20260711-004 已证明歌曲海正向样例 `外婆`、`一丝不挂`、`稻香`、`哎呀` 可写 `.lrc` 与 cache metadata。
  - AM-20260711-003 已证明播放详情歌词入口在 Android 小米 10 Pro 可达。
- Remaining Scope:
  - 原始回归清单仍未按 release/1.1.0 做完整真实设备复测：`坏孩子`、`苦笑`、`风度`、`昆明晚安`、`春雨里洗过的太阳`、`一丝不挂`。
  - 对每首歌必须明确：搜索词、命中的 source/candidate、是否完整音频、歌词 provider/sourceAttempt、cache metadata、播放详情歌词截图或结构化 miss chain。
  - 如果歌曲海无高置信候选或无 timed LRC，应显示/记录结构化原因，不得用 PREVIEW、网页文本介绍或 URL 当作歌词完成。
- Owner / Project:
  - Owner Lane: `android`
  - Assist: `qa-researcher` 提供矩阵模板；`ohos` 仅在 Android 通过后做跨端 spot check。
  - Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260626-001_android_lyrics_regression`
  - Branch: `verification/1.1.0/AM-20260626-001-lyrics-real-device-regression`
  - Base: `origin/release/1.1.0=45b302d48649330446d381b8593c50e22b9099f5`
  - Device: 小米 10 Pro；如进入 QA，则使用 QA 矩阵模板回传包 sha、截图、日志和 pass/fail/blocker。
- Acceptance Samples:
  - 必测旧清单：`坏孩子`、`苦笑`、`风度`、`昆明晚安`、`春雨里洗过的太阳`、`一丝不挂`。
  - 回归对照：歌曲海正向 `外婆` 或 `稻香` 至少一首，证明 release/1.1.0 歌词正向路径未回退。
  - 证据必须包含：APK sha、HEAD、设备、搜索结果 XML/截图、播放详情歌词截图、cache index/`.lrc` 文件、resolver/sourceAttempt 日志。

## 2026-07-11 Reassignment

- Architect 已按 Product 巡检并行分配，不等待 AM-20260623 cache-first 修复完成。
- 独立工程 `/Users/huangqi/AIHome/projects/ai_music_AM-20260626-001_android_lyrics_regression` 已基于 `origin/release/1.1.0=45b302d48649330446d381b8593c50e22b9099f5` 创建。
- Android/QA 必须按真实设备清单回传 `坏孩子`、`苦笑`、`风度`、`昆明晚安`、`春雨里洗过的太阳`、`一丝不挂` 的 pass/fail/blocker；若某首无高置信完整音频或无 timed LRC，必须给结构化 miss chain，不得用 PREVIEW、URL、网页介绍或无时间轴文本当作歌词完成。
- 2026-07-11 QA gate 已绑定：`docs/codex_collab/knowledge/qa-researcher/2026-07-11-am20260626-001-lyrics-real-device-matrix.md`。Android 未在 10 到 15 分钟内回 APK sha、设备、截图/XML、cache index、`.lrc`、resolver/sourceAttempt 时，architect 追 Android owner；QA 收到包后按矩阵给 pass/fail/blocker。
