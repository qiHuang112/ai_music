# 旧工作区盘点

2026-10-26 用户决定只保留 `/Users/huangqi/ClaudeProject/ai_music` 作为唯一工作目录。本页记录迁移时对 `/Users/huangqi/AIHome` 的盘点结果：哪些已并入本仓库、哪些仍是外部依赖、哪些只是历史。

## 已并入本仓库

- 原正式目录 `AIHome/projects/ai_music` 的 main（含 10269 发布记录、三档发布规则、状态页瘦身、签名相对路径）已快进合入，本仓库与它的提交一致。
- 签名：`android/ai_music_release.jks` 与 `android/key.properties`（相对路径 `storeFile=ai_music_release.jks`）在本目录，均被 gitignore。证书 SHA256 `f05004de…48464843`。
- 发布证据 `build/release-evidence/` 已复制（gitignore，约 460K）。`build/review/`（约 508M 旧审查快照）未复制。
- 开发 skill 仍在 `.agents/skills/ai-music-developer/`，并以符号链接 `.claude/skills/ai-music-developer` 供 Claude Code 直接调用，两边只维护一份。

## 已迁入 ClaudeProject 的本地依赖（2026-10-26）

| 路径 | 作用 |
|---|---|
| `/Users/huangqi/ClaudeProject/tools/flutter` | Flutter SDK 3.44.2，原 `AIHome/tools/flutter`；`android/local.properties`、iOS 生成配置和 skill 命令已改指这里 |
| `/Users/huangqi/ClaudeProject/releases/ai_music/` | Android／Mac 全部历史正式包、局域网更新服务 `update-service/`、诊断日志，原 `AIHome/releases/ai_music`；LaunchAgent `com.qi.ai.music.android-updates` 已改为从这里运行 `192.168.31.167:8788` |

迁移后局域网 Android 10269、Mac 10268 均完整下载核验，大小与 SHA256 一致。`AIHome/tools/flutter_ohos`（鸿蒙版 Flutter）未被本仓库引用，没有迁移。

## 历史副本（2026-10-26 已删除）

按用户要求删除，均不可恢复：

- `AIHome/projects/ai_music_*` 共 62 个目录：7 月多角色／多 lane 流程按需求单开的 clone 和 worktree，推送过的分支仍在 GitHub。
- `AIHome/ai_music`：7 月的旧主目录，含废弃流程的调研笔记和 9 个未推送的流程文档提交。
- `AIHome/ai_music_android_native`：Kotlin／Compose 原生重写（AM-20260726-001），没有 GitHub 远端，代码已不存在。
- `AIHome/projects/ai_music`：原正式目录，提交已全部并入本仓库。
- `AIHome/worktrees/ai_music`：6 月的 28 个旧 worktree，约 2.3G。

2026-10-26 另将 `AIHome/backups/ai_music`、`AIHome/backups/ai-music-ios`、`AIHome/output/` 下的 ai_music 截图／调试产物、歌源探测缓存与 `lamaze_guide`（拉玛泽音频交付物、早期 LAN 版 APK 与源码包）移入废纸篓 `~/.Trash/AIHome-ai_music-leftovers-20261026`（约 3.4G），清空废纸篓后不可恢复。

随后 `evidence/AM-20260726-001-*`（原生重写证据）、`output/native-unified*.diff`、`output/mi10-*.png`（手机截图）也移入同一废纸篓目录。AIHome 中已无 AI Music 相关文件。

## Codex 侧配置

- 仍有效的只有本仓库的 `ai-music-developer` skill。`~/.codex/config.toml` 中登记过的 `ai-music`、`ai-music-team-ops`、`create-agile-project-team`、superpowers 系列（brainstorming、executing-plans、dispatching-parallel-agents、finishing-a-development-branch）、`harmonyos-development`、`project-workteam` 均已 disabled 且文件已删除，只剩名称。
- Codex 自动化 `ai-music-native-epic`（原生重写监督，15 分钟心跳）状态为 PAUSED。
- `~/.codex/config.toml` 与 `ai-music-unattended.config.toml` 的项目信任路径仍是 AIHome；如果继续用 Codex，需要补上本目录。

## 2026-11-01 承接更正

本仓库已整体迁入 `/Users/huangqi/CodexProject/laiting-studio/repos/ai-music`；ClaudeProject 旧入口仅指向同一 checkout。OHOS local.properties 与 hvigor 插件实际仍依赖原 SDK，故已将其完整迁到 `/Users/huangqi/CodexProject/laiting-studio/toolchains/flutter-ohos` 并修正本地配置及插件链接；上文“未引用”是旧盘点结论，不再作为现状依据。17 条失效 worktree 登记已保存到来听工作室忽略的 `.local/retirement-evidence/app-stale-worktrees` 后精确解除，历史分支未变。AIHome 根冲突及 a705 独有资料由项目总管另行保全；未在本工程恢复或合并。标准 Flutter、发布服务和归档仍在有效 ClaudeProject 共享位置。本次未构建、安装或发布。
