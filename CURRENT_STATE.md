# AI Music 当前状态

更新于 2026-11-08（安卓对齐 iOS 悬浮栏并发布 1.0.5／10270；其后修复播控条按压抖动，未推送）。本文件只保留固定字段：改动时就地更新字段，“最近进展”只留 3 条；开发、自测、验收与 review 细节写在[工作日志](docs/worklog/README.md)，2026-10-26 之前的长条目见[历史条目](docs/worklog/state-history.md)。代码状态以 Git 为准。

## 正式版本

- Android：1.0.5／10270，源码 `8c9a464`。[GitHub Release](https://github.com/qiHuang112/ai_music/releases/tag/v1.0.5-10270) 与局域网 latest 一致（18171712 字节，SHA256 `c6eb9184…`）。
- Mac：GitHub 1.0.5／10270 Universal（ad-hoc 签名，未公证，SHA256 `59d5380c…`）；局域网仍为 1.0.4／10268 桌面优化版。下载与核验见 [Mac 记录](docs/macos.md)。
- iOS：未公开发布；个人体验版 1.0.5／8268（`8c9a464` 加播控条按压去抖修复）已装到用户 iPhone Duo 并启动，签名有效至 2026-11-14。

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

- iPhone Duo／iOS：原生壳已提交（`bf87f9e`）；本轮按真机 13 条反馈继续：原生 `UIGlassEffect` 悬浮播控条（仅一级页、与 Tab 栏对齐、手机只留播放＋队列、按压态、条上横滑切歌）、播放页重排（更多菜单、信息行、裸图标控制行）、返回在 `willShow` 同步、`AppPageRoute` 0.35 s 过场＋`willShow` 提前同步安全区、一级页行内标题＋masthead、歌单详情系统标题、音乐库限宽、队列通底、下载页安全区、歌曲页竖屏填充、孔板网点封顶、局域网默认地址改 Mac；analyze 与定向测试通过，全量仅基线旧用例失败；模拟器验收通过、已装真机；已本地提交（`[skip ci]`），未推送。见[适配范围](docs/iphone-duo.md)。
- Android／iOS：悬浮玻璃 Tab 栏、一级页播控条、横滑只动歌曲、歌单打开不抖已随 1.0.5 发布；之后修复播控条按压抖动（去掉弹性缩放，改淡高亮，iOS 原生条同时去掉与外壳布局冲突的缩放变换），已装 Duo 与 77；随后把全部界面图标统一为 SF 风格的 `AppIcons`（77 已装 release 1.0.5／10277 开发证书，Duo 未装）；两项均本地提交未推送。

## 最近进展

- 2026-11-08 推送发布 1.0.5／10270（Android＋Mac Universal），CI 与产物核对通过、局域网已镜像；随后修复播控条按压抖动 → [日志](docs/worklog/2026-11-08.md)
- 2026-11-08 安卓对齐 iOS：Flutter 悬浮玻璃 Tab 栏（二级页常驻、沉浸页让开）、一级页播控条、底部安全区沉浸、横推过场，77 实机自测通过 → [日志](docs/worklog/2026-11-08.md)
- 2026-11-08 处理第二至九轮反馈：播放页顶栏菜单化／信息行／裸图标控制行、系统返回与 Flutter 退场同步、竖持顶部黑带（窗口遮挡内边距）、QQ 音乐式悬浮播控条（按压态、仅一级页、精简按钮、对齐 Tab 栏、条上横滑切歌）、竖栏常驻歌词／热评／队列入口、整块跟手切歌、竖持播放页不再超高、导航栏常驻去弹动、设置页安全区、宽屏布局、局域网默认地址 → [日志](docs/worklog/2026-11-08.md)
