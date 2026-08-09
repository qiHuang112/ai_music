# AM-20260806-001 拉玛泽音频重制与文件夹歌单同步

Status: accepted
Owner Lane: android
Source Thread: current-codex-task
Target Version: 1.0.0-lan.2+2102
Base Branch: v1.0.0
Work Branch: codex/lan-music-sync-v1.0.0
Project Path: /Users/huangqi/AIHome/projects/ai_music_lamaze_lan_sync
Merge Branch: codex/lan-music-sync-v1.0.0
Created: 2026-08-06
Updated: 2026-08-09
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
Head Commit: 22e9a96f17b5d3259894fd5d2d2456f5e5bd2c2a
Red Evidence: folderPath、lanFolderKey、LanFolderPlaylistMerger、采样乐器渲染和交付校验测试均先确认因目标接口/行为缺失而失败；CosyVoice 正式版先确认旧系统语音、SoundFont 和混音契约失败；限幅器回归测试先复现默认自动补偿导致 0.0 dBFS；Windows UTF-8 校验回归测试先确认缺少显式编码而失败。
Green Evidence: python3 -m unittest discover -s tool -p 'test_*.py' 通过 61 项；flutter test --no-pub 通过 156 项；flutter analyze --no-pub 为 0 issue；arm64 release APK 构建成功。
Targeted Tests: flutter test --no-pub test/lan_sync_use_case_test.dart 通过 14 项；音频生成、MIDI、CosyVoice/VSCO 来源绑定、LF 哈希清单、安全说明、封面、响度、LAN 服务和交付校验专项测试包含在 61 项 Python 测试中。
Self Test Evidence: 用户批准第一个 CosyVoice SFT 中文女声试听后，在 Windows 隔离 Python 3.10/CUDA 环境生成四首正式版；交付校验 status=passed、trackCount=4，WAV 为 48 kHz/24-bit，MP3 为 192 kbps，最高真峰值 -1.5 dBTP；Windows Python 3.9 服务清单 59 首、无重复 ID，4 个稳定 Lamaze ID 的 folderPath 均为 Lamaze 且 MP3 SHA 与 Mac 备份一致；小米 10 Pro 增量更新 4 首后完成歌单、歌词、重复同步和断服离线播放。
Baseline Freshness Evidence: git merge-base HEAD eb23a64e34a8e59ddd71f8012ec695bee9e3e360 保持任务基线；工程为独立完整 clone，分支基于 2026-06-24 v1.0.0 验收快照且未修改原脏工作区。
Scope Diff Evidence: 97a4933..22e9a96 共 9 个文件，集中于 CosyVoice SFT 正式生成、VSCO 正式编曲、混音限幅、来源绑定、交付校验及测试计划；git diff --check 通过；Flutter 客户端和 Python LAN 协议无新增改动。
Product Main Path Evidence: 小米 10 Pro 从下载管理点击扫描并同步，显示新增 0、更新 4、跳过 55、失败 0；首页 Lamaze 仍为 4 首；进入歌单播放慢呼放松并显示逐行歌词；重复同步显示新增 0、更新 0、跳过 59、失败 0；停止 192.168.31.57:8787 后切换播放宫缩浪潮成功并显示歌词，随后服务已恢复。
Spec Review Result: accepted
Code Quality Review Result: accepted
Full Verification Evidence: Python 61 项、Flutter 156 项、flutter analyze、arm64 release 构建、Windows 加强交付校验、Mac 标准 shasum 26/26、小米 10 Pro 增量/幂等/歌词/断服离线主路径均通过。
Blocking Findings: none

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
- 2026-08-09 type=status lane=android summary=用户批准第一个 CosyVoice SFT 女声试听；四首正式版已通过 Windows 暂存校验并增量更新到小米 10 Pro，重复同步和断服离线播放通过。
- 2026-08-09 type=status lane=android summary=架构初审提出 LF 哈希清单、安全说明与封面、响度范围、实际来源绑定四项门禁；均以测试先行修复，Windows 成品通过加强校验，Mac 可直接执行标准 shasum 校验 26 项。
- 2026-08-09 type=review_result lane=architect summary=窄复核 31b1dcc..22e9a96 通过，规格符合性 accepted、代码质量 accepted、Blocking Findings none。

## 相关提交

- `35d39ee`：设计与实施计划。
- `1647a68`、`e786055`、`35dcf31`、`0195f50`、`990dce6`、`7a08461`：文件夹清单、歌单持久化、合并和同步结果。
- `c7659ee`、`d2551cd`、`1100aab`、`2109699`：直接动作口令、采样乐器、试听和完整音频交付。
- `57180ef`：最终静态分析整理。
- `31b1dcc`：CosyVoice SFT 正式生成、VSCO 轻音乐编曲、限幅与交付校验。
- `22e9a96`：固定 LF 交付记录并加强安全文案、封面、响度与实际来源校验。

## 版本与发布

- Target Version: 1.0.0-lan.2+2102
- Release Tag: not_created
- Android APK: /Users/huangqi/AIHome/output/lamaze_guide/AI-Music-1.0.0-lan.2+2102-release.apk
- APK SHA-256: b0c92e08b58790d0f5126239680daf4c65f0f468865518df29a960c404266d28
- Push Status: not_requested

## Review 结果

- Reviewer Lane: architect
- Result: accepted
- Android Findings: owner 自测通过；四首稳定 ID 原位更新，Lamaze 歌单、重复同步、逐行歌词和断服离线播放无回退。
- iOS Findings: 本任务不涉及 iOS 宿主改动
- HarmonyOS Findings: 本任务不涉及 HarmonyOS 宿主改动
- Architect Findings: 初审四项门禁已由 22e9a96 逐项关闭；窄复核确认规格符合性与代码质量 accepted，Blocking Findings none。
- Notes: 本轮按用户授权完成独立分支、APK、Windows Python 服务、CosyVoice SFT 正式音频和小米 10 Pro 验收；未连接任何小米 17 Pro，未合入主线或推送远端。
