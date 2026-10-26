# 旧工作区盘点

2026-10-26 用户决定只保留 `/Users/huangqi/ClaudeProject/ai_music` 作为唯一工作目录。本页记录迁移时对 `/Users/huangqi/AIHome` 的盘点结果：哪些已并入本仓库、哪些仍是外部依赖、哪些只是历史。

## 已并入本仓库

- 原正式目录 `AIHome/projects/ai_music` 的 main（含 10269 发布记录、三档发布规则、状态页瘦身、签名相对路径）已快进合入，本仓库与它的提交一致。
- 签名：`android/ai_music_release.jks` 与 `android/key.properties`（相对路径 `storeFile=ai_music_release.jks`）在本目录，均被 gitignore。证书 SHA256 `f05004de…48464843`。
- 发布证据 `build/release-evidence/` 已复制（gitignore，约 460K）。`build/review/`（约 508M 旧审查快照）未复制。
- 开发 skill 仍在 `.agents/skills/ai-music-developer/`，并以符号链接 `.claude/skills/ai-music-developer` 供 Claude Code 直接调用，两边只维护一份。

## 仍在 AIHome 的外部依赖（不能删）

| 路径 | 作用 |
|---|---|
| `AIHome/tools/flutter` | Flutter SDK，`android/local.properties` 与 skill 命令都指向它 |
| `AIHome/releases/ai_music/` | Android／Mac 全部历史正式包、局域网更新服务 `update-service/`、诊断日志；LaunchAgent `com.qi.ai.music.android-updates` 从这里运行 `192.168.31.167:8788` |
| `AIHome/ai_music/android/ai_music_release.jks` | 签名文件的另一份副本（与本目录相同） |

要彻底离开 AIHome，需要先迁移 Flutter SDK 并改 `local.properties`，再迁移 releases 目录并重新部署 LaunchAgent（`tool/deploy_macos_update_server.py`）。目前不做。

## 历史副本（不再使用）

- `AIHome/projects/` 下约 65 个 `ai_music_*` 目录：7 月多角色／多 lane 流程按需求单（AM-2026xxxx）各开的 clone 和 worktree，分支多为 `feature/`、`release/1.x`、`codex/…`，大部分已推到 GitHub 对应分支。
- `AIHome/ai_music`：7 月的旧主目录，含 9 个未推送的流程文档提交和约 100 个未跟踪的调研笔记（`docs/codex_collab/knowledge`、`requests`、`docs/superpowers`）。这些属于已废弃的流程；当前功能事实以 `docs/*.md` 功能文档为准。
- `AIHome/ai_music_android_native` 及 `projects/ai_music_android_native_*`：7 月的 Kotlin／Compose 原生重写（AM-20260726-001），**没有 GitHub 远端**，约 64 个提交只存在本机。当前主线是 Flutter，原生方案已停止。

## Codex 侧配置

- 仍有效的只有本仓库的 `ai-music-developer` skill。`~/.codex/config.toml` 中登记过的 `ai-music`、`ai-music-team-ops`、`create-agile-project-team`、superpowers 系列（brainstorming、executing-plans、dispatching-parallel-agents、finishing-a-development-branch）、`harmonyos-development`、`project-workteam` 均已 disabled 且文件已删除，只剩名称。
- Codex 自动化 `ai-music-native-epic`（原生重写监督，15 分钟心跳）状态为 PAUSED。
- `~/.codex/config.toml` 与 `ai-music-unattended.config.toml` 的项目信任路径仍是 AIHome；如果继续用 Codex，需要补上本目录。
