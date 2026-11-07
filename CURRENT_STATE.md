# AI Music 当前状态

更新于 2026-11-07（Duo 侧边导航、歌词／待播分栏和原生折线适配完成；iOS 27.1 模拟器构建与播放验证通过，未发布）。本文件只保留固定字段：改动时就地更新字段，“最近进展”只留 3 条；开发、自测、验收与 review 细节写在[工作日志](docs/worklog/README.md)，2026-10-26 之前的长条目见[历史条目](docs/worklog/state-history.md)。代码状态以 Git 为准。

## 正式版本

- Android：1.0.4／10269，源码 `4504319`。[GitHub Release](https://github.com/qiHuang112/ai_music/releases/tag/v1.0.4-10269) 与局域网 latest 一致（18195572 字节，SHA256 `22260b9e…`）。
- Mac：GitHub 1.0.4／10269 Universal（ad-hoc 签名，未公证）；局域网仍为 1.0.4／10268 桌面优化版。下载与核验见 [Mac 记录](docs/macos.md)。
- iOS：未发布。

## 环境

- 唯一工作目录：`/Users/huangqi/CodexProject/laiting-studio/repos/ai-music`，分支 `main`。
- Xcode：默认 `/Applications/Xcode-27.1.app`（27A9275），iOS 27.1 SDK / 模拟器可用，Flutter Xcode 检查通过；旧 26.5 保留于 `/Applications/Xcode.app`。见[升级记录](docs/worklog/2026-11-07.md)。
- 开发技能真实源位于本仓库 `.agents/skills/ai-music-developer/`，与代码一起版本管理，工作室及 Claude 共用相对入口。本轮仅本地提交，不连接或推送远端。
- 本地依赖（2026-10-26 从 AIHome 迁入，勿删）：Flutter SDK `/Users/huangqi/ClaudeProject/tools/flutter`；OHOS SDK `/Users/huangqi/CodexProject/laiting-studio/toolchains/flutter-ohos`；发布归档与局域网更新服务 `/Users/huangqi/ClaudeProject/releases/ai_music/`（LaunchAgent `com.qi.ai.music.android-updates` 从这里运行，含全部历史包与诊断日志）。迁移记录见[旧工作区盘点](docs/legacy-workspaces.md)。
- 局域网更新服务：`http://192.168.31.167:8788`（`/api/v1/update/android`、`/api/v1/update/macos`），后台约 60 秒自动镜像 GitHub 最新 Android Release。
- 开发手机 77：无线 ADB `192.168.31.77:41049`（2026-10-20 更新）。
- 仓库 `qiHuang112/ai_music` 公开；main 由维护者维护，合作者 `wangtangji29-ctrl` 在 `ui-vinyl` 等非 main 分支开发。
- 发布分三档，见[开发 skill](.agents/skills/ai-music-developer/SKILL.md) 开头的表；push main 会生成新正式版本。

## 进行中

- iPhone Duo：本轮界面和原生保留区域适配已完成，26 项定向测试及 Duo 模拟器真实歌曲播放／折叠／切歌验证通过；待用户体验和 Duo 真机后台／锁屏／分屏验证。见[适配范围](docs/iphone-duo.md)。

## 最近进展

- 2026-11-07 参考 QQ 音乐与 Apple Music 完善侧栏、歌词／待播、半折叠及矮外屏布局；Xcode 27.1 模拟器构建、安装和实际播放验证通过 → [适配记录](docs/iphone-duo.md)
- 2026-11-07 升级 Xcode 27.1，安装 iOS 27.1 组件，Duo 模拟器启动/展开和 Flutter Xcode 检查通过 → [日志](docs/worklog/2026-11-07.md)
- 2026-11-06 Duo 播放器分栏、窗口变化状态保持和歌词溢出修复，31 项相关测试通过；未生成 Duo 安装包 → [日志](docs/worklog/2026-11-06.md)
