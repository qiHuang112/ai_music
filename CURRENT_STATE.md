# AI Music 当前状态

更新于 2026-11-10（安卓首开抖动、点当前歌打开播放页、歌词时间轴、Tab 栏玻璃罩；Android／Mac／iOS 1.0.6／10275 已发布）。本文件只保留固定字段：改动时就地更新字段，“最近进展”只留 3 条；开发、自测、验收与 review 细节写在[工作日志](docs/worklog/README.md)，2026-10-26 之前的长条目见[历史条目](docs/worklog/state-history.md)。代码状态以 Git 为准。

## 正式版本

- Android：1.0.6／10275，源码 `0afd54b`，GitHub Release 已发布，原签名，局域网已镜像。
- Mac：GitHub 1.0.6／10275 Universal（ad-hoc 签名，未公证）；局域网 Mac 指针未修改。
- iOS：GitHub 1.0.6／10275 unsigned arm64 IPA，需自行重签安装；Duo 真机仍是 10274 源码的个人签名 Release 8269。[下载页](https://github.com/qiHuang112/ai_music/releases/tag/v1.0.6-10275)。

## 环境

- 唯一工作目录：`/Users/huangqi/CodexProject/laiting-studio/repos/ai-music`，分支 `main`。
- Xcode：默认 `/Applications/Xcode-27.1.app`（27A9275），iOS 27.1 SDK / 模拟器可用，Flutter Xcode 检查通过；旧 26.5 保留于 `/Applications/Xcode.app`。见[升级记录](docs/worklog/2026-11-07.md)。
- 开发技能真实源位于本仓库 `.agents/skills/ai-music-developer/`，与代码一起版本管理，工作室及 Claude 共用相对入口。本轮仅本地提交，不连接或推送远端。
- 本地依赖（2026-10-26 从 AIHome 迁入，勿删）：Flutter SDK `/Users/huangqi/ClaudeProject/tools/flutter`；OHOS SDK `/Users/huangqi/CodexProject/laiting-studio/toolchains/flutter-ohos`；发布归档与局域网更新服务 `/Users/huangqi/ClaudeProject/releases/ai_music/`（LaunchAgent `com.qi.ai.music.android-updates` 从这里运行，含全部历史包与诊断日志）。迁移记录见[旧工作区盘点](docs/legacy-workspaces.md)。
- 局域网更新服务：`http://192.168.31.167:8788`（`/api/v1/update/android`、`/api/v1/update/macos`），后台约 60 秒自动镜像 GitHub 最新 Android Release。
- 开发手机 77：Mi 10 Pro（序列号 `6595e6a1`），无线 ADB 现为 `192.168.31.78:38015`（2026-11-08 更新，端口会变）。
- 仓库 `qiHuang112/ai_music` 公开；main 由维护者维护，合作者 `wangtangji29-ctrl` 在 `ui-vinyl` 等非 main 分支开发。
- 发布分三档，见[开发 skill](.agents/skills/ai-music-developer/SKILL.md) 开头的表；push 只跑 `ci.yml` 检查，正式发版手动启动 `android-release.yml`（2026-11-08 起；2026-11-09 起复用 Check、按改动只并行打受影响平台，未实跑验证）；77 自测包用 `tool/build_android_selftest.py`，号段 60000 起。

## 进行中

- iPhone Duo／iOS：原生壳已提交（`bf87f9e`）；本轮按真机 13 条反馈继续：原生 `UIGlassEffect` 悬浮播控条（仅一级页、与 Tab 栏对齐、手机只留播放＋队列、按压态、条上横滑切歌）、播放页重排（更多菜单、信息行、裸图标控制行）、返回在 `willShow` 同步、`AppPageRoute` 0.35 s 过场＋`willShow` 提前同步安全区、一级页行内标题＋masthead、歌单详情系统标题、音乐库限宽、队列通底、下载页安全区、歌曲页竖屏填充、孔板网点封顶、局域网默认地址改 Mac；analyze 与定向测试通过，全量仅基线旧用例失败；模拟器验收通过、已装真机；已本地提交（`[skip ci]`），未推送。见[适配范围](docs/iphone-duo.md)。
- Android／iOS：悬浮玻璃 Tab 栏、一级页播控条、横滑只动歌曲、歌单打开不抖已随 1.0.5 发布；之后修复播控条按压抖动（去掉弹性缩放，改淡高亮，iOS 原生条同时去掉与外壳布局冲突的缩放变换），已装 Duo 与 77；界面图标统一为 `AppIcons`：试过 SF 线性风格后按用户意见改回 Material 圆角统一，Duo 侧栏歌词按钮改用歌词图形；侧栏不显示指向当前页的入口、暂停时切歌即播放、随机播放上一首按已听顺序回退（77 装 release 1.0.5／10279 开发证书，Duo 已装）；已推送 main（`[skip ci]`，未打包，正式版仍为 1.0.5／10270）。

## 最近进展

- 2026-11-10 修复安卓搜索框一点键盘就收起（1.0.5 起：键盘弹起时页面外层结构变化导致输入框重建），77 装 60025 自测通过，未推送 → [日志](docs/worklog/2026-11-10.md)
- 2026-11-09 播放页／歌单首开抖动（根因 Skia 首次着色器编译，启动空闲时预热，184→33 ms）、点正在播放的歌打开播放页、手机歌单固定行高定位、纯文本歌词按原曲取网易云带时间轴歌词；随后安卓悬浮 Tab 栏可按住拖动（玻璃罩边缘动态模糊、越近两端胶囊越宽、弹簧吸附）；77 装 60019 自测通过；已推送并发布 1.0.6／10275 → [日志](docs/worklog/2026-11-09.md)
- 2026-11-09 Duo 三处适配：竖栏放得下时不再用“…”（菜单展开、常驻入口按空位）、分屏播控条不压竖栏、展开竖持标题与系统栏同行；模拟器（外屏横持／展开竖持／分屏）验证，Duo 真机验收通过，已推送并发布 1.0.6／10274 → [日志](docs/worklog/2026-11-09.md)
