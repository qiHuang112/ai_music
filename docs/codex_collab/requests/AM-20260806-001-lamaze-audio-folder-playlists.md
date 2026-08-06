# AM-20260806-001 拉玛泽音频重制与文件夹歌单同步

Status: proposed
Owner Lane: android
Source Thread: current-codex-task
Target Version: 1.0.0-lan.2+2102
Base Branch: v1.0.0
Work Branch: codex/lan-music-sync-v1.0.0
Project Path: /Users/huangqi/AIHome/projects/ai_music_lamaze_lan_sync
Merge Branch: codex/lan-music-sync-v1.0.0
Created: 2026-08-06
Updated: 2026-08-06
Workflow: superpowers-v1
Work Type: feature
Risk Level: P1
User Visible: yes
Design Doc: docs/superpowers/specs/2026-08-06-lamaze-audio-redesign-design.md
Companion Design Doc: docs/superpowers/specs/2026-08-06-lan-folder-playlist-sync-design.md
Implementation Plan: docs/superpowers/plans/2026-08-06-lamaze-audio-folder-playlists.md
Required Skills: writing-plans, test-driven-development, systematic-debugging, ai-music, ai-music-team-ops, verification-before-completion
TDD Mode: required
TDD Exception: none
TDD Exception Review: not_applicable
Baseline Commit: 76f5e4e7c48c12335d1b879886af45587bec0a31

## 目标

- 将 4 首拉玛泽音频重制为采样乐器原创轻音乐配低密度助产士式普通话女声。
- 让局域网中直接包含歌曲的文件夹与当前自建歌单一一对应，并将 `Lamaze` 文件夹中的 4 首歌曲归入同一歌单。

## 范围

- 包含：音频生成器、引导词、WAV/MP3/LRC/TXT/JSON 交付、Python 清单 `folderPath`、Flutter 清单模型、增量同步、歌单持久化、测试、Android release 包和小米 10 Pro 验证。
- 不包含：后台自动同步、完全镜像删除、上传、账号认证、WebDAV、SMB、基于宫口厘米数判断阶段、自行下达用力指令，以及未经再次授权的小米 17 Pro 操作。

## 验收标准

- 45 秒试听样片由用户确认后再批量生成 4 首完整音频。
- 音频无报幕、无吟唱、无明显程序合成杂质；背景为钢琴、弦乐和极淡空气铺底。
- 4 首稳定 ID 不变，文件规格和 SHA-256 验证通过。
- 安全 `folderPath` 能处理中文和嵌套路径；旧版 schema v1 清单仍可导入。
- 首次同步创建或复用文件夹同名自建歌单，重复同步幂等，原成员与顺序保留。
- 电脑端删除或移动文件不会自动删除手机歌曲或歌单成员。
- `E:\music\Lamaze\` 的 4 首歌曲同步后位于同一个 `Lamaze` 歌单。
- Python/Flutter 测试、`flutter analyze`、release 构建和小米 10 Pro 冒烟验证通过。

## 消息记录

- 2026-08-06 type=task lane=android summary=用户确认采样乐器原创编曲、低密度助产士式女声以及文件夹到自建歌单的安全增量映射。
- 2026-08-06 type=status lane=product summary=音频结构、LAN 歌单映射、兼容和删除策略已逐项确认通过。

## 相关提交

- 设计提交记录在本任务首次文档提交中。

## 版本与发布

- Target Version: 1.0.0-lan.2+2102
- Release Tag: not_created
- Android APK: not_built
- Push Status: not_ready

## Review 结果

- Reviewer Lane: architect
- Result: awaiting_implementation
- Android Findings: 尚未进入实现 review
- iOS Findings: 本任务不涉及 iOS 宿主改动
- HarmonyOS Findings: 本任务不涉及 HarmonyOS 宿主改动
- Architect Findings: 设计已获用户逐段批准，等待书面规格复核和实施计划
- Notes: 公共 Dart 与 Python 服务实现完成后需由 architect review；不向无关平台 lane 分发。
