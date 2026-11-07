# AI Music 当前状态

更新于 2026-11-07（iOS 导航改为 UIKit 原生壳：系统 Tab 栏／导航栏／菜单承载 Flutter 内容，Duo 自动竖栏；Duo 内屏与 iPhone 18 Pro 模拟器验证通过，体验版已装到用户 Duo 真机待解锁试用；已提交并以 [skip ci] 推送 main，未发版）。本文件只保留固定字段：改动时就地更新字段，“最近进展”只留 3 条；开发、自测、验收与 review 细节写在[工作日志](docs/worklog/README.md)，2026-10-26 之前的长条目见[历史条目](docs/worklog/state-history.md)。代码状态以 Git 为准。

## 正式版本

- Android：1.0.4／10269，源码 `4504319`。[GitHub Release](https://github.com/qiHuang112/ai_music/releases/tag/v1.0.4-10269) 与局域网 latest 一致（18195572 字节，SHA256 `22260b9e…`）。
- Mac：GitHub 1.0.4／10269 Universal（ad-hoc 签名，未公证）；局域网仍为 1.0.4／10268 桌面优化版。下载与核验见 [Mac 记录](docs/macos.md)。
- iOS：未公开发布；个人体验版 1.0.4／8267（源码 `bf87f9e`）已装到用户 iPhone Duo / iOS 27.2（启动待用户解锁），签名有效至 2026-11-14。

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

- iPhone Duo／iOS：导航改用 UIKit 原生壳（`MusicShell.swift` + `native_shell.dart`），系统绘制 Tab 栏、导航栏、返回、菜单，Duo 上自动竖栏；analyze 无问题，定向测试与全量测试（除一条基线已失败用例）通过；Duo 内屏横向与 iPhone 18 Pro 模拟器实查通过，Duo 外屏姿态与真机待用户试用；迷你播放器改 `UITabAccessory` 与普通 iPhone 大标题待后续；已提交推送 `bf87f9e`（[skip ci]，未发版）。见[适配范围](docs/iphone-duo.md)。

## 最近进展

- 2026-11-07 iOS 导航改为 UIKit 原生壳（系统 Tab／导航栏／菜单），Duo 内屏与 iPhone 18 Pro 模拟器验证通过，体验版已装到 Duo 真机 → [日志](docs/worklog/2026-11-07.md)
- 2026-11-07 Duo 侧栏重做为系统竖栏样式并修正播放器背景接缝，测试与模拟器外屏验证通过，内屏待复查 → [日志](docs/worklog/2026-11-07.md)
- 2026-11-07 修正 Duo 右侧留白，28 项定向测试及模拟器验证通过；随后按用户要求安装个人体验版到 Duo 真机并成功启动 → [适配记录](docs/iphone-duo.md)
