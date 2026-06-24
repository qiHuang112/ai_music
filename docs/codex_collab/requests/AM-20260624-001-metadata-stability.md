# AM-20260624-001 歌词封面稳定加载

Status: assigned
Owner Lane: android
Assist Lane: ios validation support, architect review
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.1
Priority: P2 start after AM-20260624-002 or when architect confirms capacity
Base Branch: main
Work Branch: feature/1.0.1/AM-20260624-001-metadata-pipeline
Worktree Path: /Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260624-001
Merge Branch: main
Created: 2026-06-24
Updated: 2026-06-24

## 目标

- 在 Android lane 主责下实现公共 Dart 层的歌词和封面稳定加载方案。
- 提高已下载歌曲、历史缓存歌曲、FLAC/BuguYY 搜索结果的歌词与封面命中率。
- 播放链路必须先可播放，metadata 补全只能后台低并发执行，不能阻塞播放、下载状态和搜索结果可用性。

## 责任边界

- Android lane 是实现 owner，负责公共 Dart 业务、测试、小米 10 Pro 自测和知识沉淀。
- Architect lane 只做方案 review、边界把关、合并发布和冲突裁决；不长期直接实现公共 Dart 业务。
- iOS lane 已提供平台风险清单，等 Android pipeline 实现后再做 iOS 验证；除非验证发现 iOS-only 限制，否则不提前改 iOS 宿主。
- ohos lane 只在 HarmonyOS HAP 验证或鸿蒙平台侧 metadata/AVSession 问题出现时参与。
- 本任务可与 AM-20260624-002 并行：Android lane 专注 metadata pipeline；ohos lane 负责播放状态持久化。Android 不等待 ohos 完成才开工。
- `/Users/huangqi/AIHome/projects/ai_music_android` 保留为旧 AM-003/历史现场，不作为 AM-001 开发目录；Android 不得把 AM-001 混入该脏 worktree。

## 范围

包含：

- 公共 Dart metadata pipeline。
- 歌词和封面字段级独立补全，互不阻塞。
- metadata cache schema 兼容旧缓存。
- 下载完成、播放当前曲、启动加载缓存后的低并发后台补全。
- 播放页“暂无歌词/无封面”自动尝试恢复和手动重新获取入口。
- miss TTL、手动 retry 绕过 TTL、成功结果不被空结果覆盖。
- Android 小米 10 Pro 开发机自测和 `docs/codex_collab/knowledge/android/` 知识沉淀。

不包含：

- HarmonyOS P1 串歌修复。
- Android 系统播控槽位或随机播放策略。
- Android release 播控热修 `46ce92d` 的文件和验证链路，除非发现直接回归；不得修改 `android/app/src/main/res/raw/keep.xml`、`android/app/src/main/AndroidManifest.xml`、`android/app/src/main/kotlin/com/qi/ai/music/MainActivity.kt` 或 `test/release_config_test.dart`。
- 1.0.0 已发布功能的回写，除非作为 bugfix 经 architect 确认。
- 未经 architect/product 确认的新音源、非官方高风险歌词源或自建服务。
- 第一版默认不新增本地音频标签读取依赖；如 Android 认为必须引入 `audio_metadata_reader` 或同类依赖，先发方案变更给 architect review。

## Provider 顺序

- 缓存 metadata。
- 当前搜索候选或 resolved 结果里的 `coverUrl`、已解析 LRC、原始歌词字段。
- 本地旁路 `.lrc`。
- 同源补全：BuguYY `search/geturl/getdown`，FLAC `search/getUrl`。
- 封面兜底：iTunes Search API 优先；MusicBrainz/Cover Art Archive 仅低优先级后台兜底。
- 歌词兜底：LRCLIB 优先；LrcAPI 或现有 LrcAPI provider 作为低优先级兜底。
- 最后记录空结果和字段级 miss TTL。

## 缓存策略

- 歌词和封面字段分开缓存：`lyrics` 与 `artworkUri` 互不覆盖。
- miss TTL 也分字段保存，避免歌词 miss 阻挡封面补全，或封面 miss 阻挡歌词补全。
- 成功结果不能被空结果覆盖。
- 手动“重新获取歌词/封面”必须绕过 TTL，但不得重新下载音频。
- provider 超时或失败只记录可读日志，不影响播放。

## 验收标准

- 搜索并下载 `黑夜传说`，FLAC 候选能展示封面和歌词；下载后播放页可显示或后台补全歌词/封面。
- BuguYY 常规歌曲如果 search/resolved 已有封面，播放时复用已有 metadata，不重复调用网络封面 provider。
- 历史缓存缺歌词/封面时，进入播放页后自动补一次；用户点击“重新获取歌词/封面”能绕过 miss TTL。
- 断网、provider 超时、返回失败文案时不阻塞播放，不裸露底层 URL/TLS 错误给用户。
- 多首歌快速切换时，晚返回的 metadata 不覆盖当前歌曲。
- Android 小米 10 Pro 自测通过；小米 17 Pro 只在 product 授权时安装验收包。

## 测试要求

- `flutter test` 全量通过。
- `flutter analyze` 通过。
- 单测覆盖 provider 顺序、字段级 merge、成功不被空结果覆盖。
- 单测覆盖 lyrics/artwork 分离 miss TTL 和手动 retry bypass TTL。
- Widget 或 controller 测试覆盖播放页自动补全、手动重新获取和失败提示。
- Android lane 在小米 10 Pro 上记录 logcat 验证 provider 命中、miss、TTL、cache write、manual retry。

## 消息记录

- 2026-06-24 type=coordination_request lane=product summary=产品要求 Android 先和 architect 沟通方案，再实现封面和歌词稳定加载。
- 2026-06-24 type=plan_review_request lane=android summary=Android lane 提交 metadata pipeline 方案草案，等待 architect 确认边界。
- 2026-06-24 type=review_result lane=architect summary=方案方向接受，切回 Android lane 主责实现；第一版不新增音频标签读取依赖，除非另发方案变更 review。
- 2026-06-24 type=coordination_request lane=product summary=P1 release 播控由架构师备援推进时，其它 lane 不能空转；metadata pipeline 继续 Android 主责，iOS 做 provider/平台风险验证支持。
- 2026-06-24 type=status lane=android summary=Android lane 已确认 P1 hotfix 归属复核，并准备转入 metadata pipeline。架构师确认 P1 已 accepted/可归档后，Android 可以正式开 AM-20260624-001。
- 2026-06-24 type=blocker lane=android status=worktree_blocked_plan_ready summary=Android lane 判断 `/Users/huangqi/AIHome/projects/ai_music_android` 存在旧 AM-003 脏现场，不应混入 AM-001。架构师已从 `origin/main` 创建专属 worktree `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260624-001` 和分支 `feature/1.0.1/AM-20260624-001-metadata-pipeline`。
- 2026-06-24 type=review_request lane=ios status=review summary=iOS lane 补充 metadata provider 风险调研并写入 `docs/codex_collab/knowledge/ios/2026-06-24-metadata-provider-risk.md`。架构师 review 接受：第一版推荐已有源字段、本地内嵌封面、iTunes 封面、LRCLIB 歌词；LrcAPI 和 MusicBrainz/CAA 低优先级或实验开关；网易/QQ/酷我非官方直连不建议第一版默认接入。

## Review 结果

- Reviewer Lane: architect
- Result: assigned
- Android Findings: Android lane 可以在 `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260624-001` 正式开工 AM-20260624-001；完成后回 architect lane，带 commit、`flutter test --no-pub`、`flutter analyze --no-pub`、小米 10 Pro metadata 自测、provider 命中/TTL/cache 日志摘要。不得混入 AM-20260624-002 播放状态持久化或 Android release 播控热修文件。实现时必须避开 iOS 风险调研列出的坑：metadata provider 不得变成音频源 fallback；网络 provider 必须短超时、低并发、可取消；晚返回结果不能覆盖当前曲或用空结果覆盖成功值；MusicBrainz/CAA 不做高优先级默认依赖；网易/QQ/酷我非官方直连不进入第一版默认链路。
- iOS Findings: iOS provider 风险调研 accepted，并已同步到知识库。Android pipeline 完成后，请 architect handoff iOS lane，带实现 commit、测试结果、provider 列表、是否使用本地音频标签读取、是否缓存本地封面、需要 iOS 真机验证的点；iOS 重点验证 ATS、本地 file URI、锁屏/控制中心封面和后台音频期间 metadata 更新。
- HarmonyOS Findings: 暂不涉及。
- Architect Findings: 架构师只做 review/合并/发布，不直接写本任务公共 Dart 业务。
