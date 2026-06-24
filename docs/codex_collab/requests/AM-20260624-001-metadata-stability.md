# AM-20260624-001 歌词封面稳定加载

Status: assigned
Owner Lane: android
Source Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Target Version: 1.0.1
Priority: P2 start after AM-20260624-002 or when architect confirms capacity
Base Branch: main
Work Branch: lane/android
Worktree Path: /Users/huangqi/AIHome/projects/ai_music_android
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

## Review 结果

- Reviewer Lane: architect
- Result: assigned
- Android Findings: Android lane 按本任务单实现，不混入 1.0.0 release 收口。
- iOS Findings: iOS lane 先做验证支持，等待 Android pipeline 完成后再验平台风险。
- HarmonyOS Findings: 暂不涉及。
- Architect Findings: 架构师只做 review/合并/发布，不直接写本任务公共 Dart 业务。
