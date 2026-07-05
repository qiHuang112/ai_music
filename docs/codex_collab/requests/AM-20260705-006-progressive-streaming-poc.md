# AM-20260705-006 安卓边下边播 Range 代理 PoC

Status: review
Owner Lane: android-streaming
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Target Version: 1.0.2
Base Branch: origin/main
Work Branch: feature/1.0.2/AM-20260705-006-progressive-streaming-poc
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260705-006
Worktree Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260705-006
Merge Branch: release/1.0.2
Created: 2026-07-05
Updated: 2026-07-05

## 目标

实现本地 HTTP Range 代理和渐进 `.part` 临时文件 PoC，验证 Android debug/beta 形态下边下边播可行性。PoC 不默认替换现有 `downloadOrReuse` 正式下载缓存链路，不让半文件进入缓存索引、收藏或歌单。

## 边界

- 正式缓存仍保持完整下载、音频校验通过、rename、写索引。
- 渐进缓存只写 `.progressive-*.part` 临时文件。
- 代理 URL 使用 `/audio/<session-token>`，新 session 会让旧 URL 返回 `410 Gone`，未知 token 返回 `404 Not Found`。
- 上游 `text/html`、JSON、XML、JavaScript content-type 会在写 `.part` 前失败；普通 `text/plain` 或缺失 content-type 必须通过首包 audio magic，伪装 audio 的 HTML/JSON 首包会失败。
- 上游已连接但首包超过 `firstByteTimeout` 时返回 `504 Gateway Timeout`，不继续挂住播放器请求。
- 只有完整下载后才允许通过 `adoptCompleteDownload` 转正为正式缓存记录。
- 已确认小米 10 Pro 在线；当前 PoC 尚未接入播放器 UI，真机出声耗时需在下一步集成后补测。本地 targeted tests 记录代理首字节耗时。
- 旧 worktree 仅作为补丁来源，不作为合入来源；本文件记录的新合入候选路径是 Project Path。

## 当前证据

- 基线 commit: `origin/main@f7d28a15c0e54668e55f9118a969964b46fab90f`。
- `test/progressive_audio_cache_test.dart` 覆盖 206、416、旧 URL 410、未知 token 404、弱网取消不入索引、上游失败 502 回退、首包超时 504 回退、非音频 content-type/首包拒绝、缺失 content-type 但首包 magic 允许、complete 后缓存转正。
- `flutter analyze --no-pub lib/src/data/music_cache.dart lib/src/data/progressive_audio_cache.dart test/progressive_audio_cache_test.dart` 通过。
- `flutter test --no-pub test/progressive_audio_cache_test.dart` 通过。
