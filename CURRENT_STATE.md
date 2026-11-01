# AI Music 当前状态

更新于 2026-11-01（同仓迁入来听工作室，建立本地提交基线，未构建或发布）。本文件只保留固定字段：改动时就地更新字段，“最近进展”只留 3 条；开发、自测、验收与 review 细节写在[工作日志](docs/worklog/README.md)，2026-10-26 之前的长条目见[历史条目](docs/worklog/state-history.md)。代码状态以 Git 为准。

## 正式版本

- Android：1.0.4／10269，源码 `4504319`。[GitHub Release](https://github.com/qiHuang112/ai_music/releases/tag/v1.0.4-10269) 与局域网 latest 一致（18195572 字节，SHA256 `22260b9e…`）。
- Mac：GitHub 1.0.4／10269 Universal（ad-hoc 签名，未公证）；局域网仍为 1.0.4／10268 桌面优化版。下载与核验见 [Mac 记录](docs/macos.md)。
- iOS：未发布。

## 环境

- 唯一工作目录：`/Users/huangqi/CodexProject/laiting-studio/repos/ai-music`，分支 `main`。
- 开发技能真实源位于本仓库 `.agents/skills/ai-music-developer/`，与代码一起版本管理，工作室及 Claude 共用相对入口。本轮仅本地提交，不连接或推送远端。
- 本地依赖（2026-10-26 从 AIHome 迁入，勿删）：Flutter SDK `/Users/huangqi/ClaudeProject/tools/flutter`；OHOS SDK `/Users/huangqi/CodexProject/laiting-studio/toolchains/flutter-ohos`；发布归档与局域网更新服务 `/Users/huangqi/ClaudeProject/releases/ai_music/`（LaunchAgent `com.qi.ai.music.android-updates` 从这里运行，含全部历史包与诊断日志）。迁移记录见[旧工作区盘点](docs/legacy-workspaces.md)。
- 局域网更新服务：`http://192.168.31.167:8788`（`/api/v1/update/android`、`/api/v1/update/macos`），后台约 60 秒自动镜像 GitHub 最新 Android Release。
- 开发手机 77：无线 ADB `192.168.31.77:41049`（2026-10-20 更新）。
- 仓库 `qiHuang112/ai_music` 公开；main 由维护者维护，合作者 `wangtangji29-ctrl` 在 `ui-vinyl` 等非 main 分支开发。
- 发布分三档，见[开发 skill](.agents/skills/ai-music-developer/SKILL.md) 开头的表；push main 会生成新正式版本。

## 进行中

- 暂无。

## 最近进展

- 2026-10-25 合作者 Mac 重设计合入 main，CI 首次同时发布 Android＋Mac 正式 1.0.4／10269 到 GitHub → [日志](docs/worklog/2026-10-25.md)
- 2026-10-25 Mac 桌面优化版 1.0.4／10268 用户验收，局域网发布 → [日志](docs/worklog/2026-10-25.md)
- 2026-10-21 热评合并与缓存收藏修复，Android 正式 1.0.4／10268 → [日志](docs/worklog/2026-10-21.md)
