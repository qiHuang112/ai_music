# AM-20260806-001 拉玛泽音频重制与文件夹歌单同步

Status: self_tested
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
Implementation Plan: docs/superpowers/plans/2026-08-06-lan-folder-playlist-sync.md
Companion Implementation Plan: docs/superpowers/plans/2026-08-06-lamaze-audio-redesign.md
Required Skills: writing-plans, test-driven-development, systematic-debugging, ai-music, ai-music-team-ops, verification-before-completion
TDD Mode: required
TDD Exception: none
TDD Exception Review: not_applicable
Baseline Commit: eb23a64e34a8e59ddd71f8012ec695bee9e3e360
Head Commit: 57180ef9712a46fdb861dd6f01e0b31ddebdc973
Red Evidence: folderPath、lanFolderKey、LanFolderPlaylistMerger、采样乐器渲染和交付校验测试均先确认因目标接口/行为缺失而失败；音频最终校验测试初始因缺少 guidanceStyle、SoundFont 来源校验与响度检查失败。
Green Evidence: python3 -m unittest discover -s tool -p 'test_*.py' 通过 30 项；flutter test --no-pub 通过 156 项；flutter analyze --no-pub 为 0 issue；release APK 构建成功。
Targeted Tests: flutter test --no-pub test/lan_sync_use_case_test.dart 通过 14 项；音频生成、MIDI、SoundFont、LAN 服务和交付校验专项测试包含在 30 项 Python 测试中。
Self Test Evidence: Windows Python 3.9 服务清单 59 首、无重复 ID，4 个稳定 Lamaze ID 的 folderPath 均为 Lamaze 且 MP3 SHA 与本机一致；小米 10 Pro 全新安装 1.0.0-lan.2+2102 后完成同步、歌词、播放、重复同步和断服离线播放。
Baseline Freshness Evidence: git merge-base HEAD eb23a64e34a8e59ddd71f8012ec695bee9e3e360 保持任务基线；工程为独立完整 clone，分支基于 2026-06-24 v1.0.0 验收快照且未修改原脏工作区。
Scope Diff Evidence: eb23a64..57180ef 共 30 个文件，集中于 LAN 文件夹歌单、Flutter 同步/UI/测试、音频生成校验与任务文档；git diff --check 通过。
Product Main Path Evidence: 小米 10 Pro 从下载管理点击扫描并同步，首次显示新增 59、失败 0、新建 1 个歌单；首页 Lamaze 显示 4 首；进入歌单播放慢呼放松并显示逐行歌词；重复同步显示新增 0、跳过 59；停止 192.168.31.57:8787 后切换播放宫缩浪潮成功，随后服务已恢复。
Spec Review Result: accepted
Code Quality Review Result: pending_independent_review

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
- 2026-08-06 type=status lane=product summary=用户复核书面规格后回复“开干”，规格正式批准并进入测试先行实施。
- 2026-08-06 type=status lane=android summary=音频与局域网歌单两份实施计划已完成，采用当前会话内联执行。
- 2026-08-06 type=status lane=android summary=用户批准 45 秒采样乐器试听后生成 4 首完整版，交付校验与 Windows 原子替换通过。
- 2026-08-06 type=status lane=android summary=小米 10 Pro 已重装 1.0.0-lan.2+2102；首次同步、Lamaze 四首歌单、重复同步、歌词播放和断服离线播放均通过。

## 相关提交

- `35d39ee`：设计与实施计划。
- `1647a68`、`e786055`、`35dcf31`、`0195f50`、`990dce6`、`7a08461`：文件夹清单、歌单持久化、合并和同步结果。
- `c7659ee`、`d2551cd`、`1100aab`、`2109699`：直接动作口令、采样乐器、试听和完整音频交付。
- `57180ef`：最终静态分析整理。

## 版本与发布

- Target Version: 1.0.0-lan.2+2102
- Release Tag: not_created
- Android APK: /Users/huangqi/AIHome/output/lamaze_guide/AI-Music-1.0.0-lan.2+2102-release.apk
- APK SHA-256: 8f3a47ad1dadc0fef02ff0df0be0593ee5ae7064c10b8b18dd09f1dd0a923ba0
- Push Status: not_requested

## Review 结果

- Reviewer Lane: architect
- Result: owner_self_tested_pending_independent_review
- Android Findings: owner 自查未发现 P0/P1；独立 architect review 尚未执行，本分支未合入或推送。
- iOS Findings: 本任务不涉及 iOS 宿主改动
- HarmonyOS Findings: 本任务不涉及 HarmonyOS 宿主改动
- Architect Findings: pending
- Notes: 本轮按用户授权完成独立分支、APK、Windows 服务和小米 10 Pro 验收；未连接任何小米 17 Pro，未合入主线或推送远端。
