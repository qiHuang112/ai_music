# AI Music 当前状态

本文件只记录当前基线和记录入口；具体开发、自测、用户验收与独立 review 记录按日期存放在 [工作日志](docs/worklog/README.md)。代码状态以当前 Git 记录为准，不在日志中反复标注暂存、提交或推送状态。

- 唯一工程：`/Users/huangqi/AIHome/projects/ai_music`；工作分支：`main`。当前代码基线可用 `git rev-parse HEAD` 核实；2026-09-27 本次整理前，本地和 `origin/main` 均为 `67f6e85`，工作区干净。
- 产品基线：Flutter AI Music，包含 LAN 同步；旧 Android Native 迁移方案不是当前开发主线。当前协作规则以 [AGENTS.md](AGENTS.md) 为准。
- 最新一次完整代码验证：2026-09-27 独立 review 所报主源故障被空备用结果掩盖的问题已修复并复核，Flutter 328 项测试通过，`flutter analyze --no-pub` 无问题，`git diff --check` 通过。本轮 debug 8114 已安装到 77 手机且用户功能验收通过；本次 review 修复尚未进入 8114 手机包，候选排序不代表完整音频已验证。
- 最近一次手机安装：2026-09-27 09:04:26 在 77 开发手机（Mi 10 Pro）保留数据覆盖安装 OCR 纠错 arm64 debug `1.0.1`（versionCode `8114`）；本地及设备 APK SHA-256 均为 `7d2aab604f93c455ef47f4b07e852966bc1768554825eb6814d58b4eb2f862a9`，启动成功。用户确认后续 77 默认 debug、191 默认 release。191 本轮未操作；此前 release 4102。实机两图 14/14 全部默认选中，用户点名三首均选到对应艺人；低置信和版本差异只作 UI 提示，QQ 原序号识别分支保持且回归通过；详见当日工作日志。
- 功能细节分别见 [截图导入](docs/screenshot-playlist-import.md)、[播放模式](docs/playback-modes.md)、[发现榜单](docs/discover-charts.md)；开发按 [开发专用 skill](.agents/skills/ai-music-developer/SKILL.md) 和 [工作流](docs/development-workflow.md) 执行，默认在当前工程的 `main` 工作，用户明确要求时可切换分支，但不创建 worktree。最终手机体验由用户验收。

按日记录：[2026-09-25](docs/worklog/2026-09-25.md) · [2026-09-26](docs/worklog/2026-09-26.md) · [2026-09-27](docs/worklog/2026-09-27.md)。拆分前的逐次原文保留在 Git 提交 `67f6e85` 的 `CURRENT_STATE.md` 中，需要追溯具体中间 APK 或测试结果时可查阅该版本。
