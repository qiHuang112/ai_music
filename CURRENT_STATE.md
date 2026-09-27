# AI Music 当前状态

本文件只记录当前基线和记录入口；具体开发、自测、用户验收与独立 review 记录按日期存放在 [工作日志](docs/worklog/README.md)。代码状态以当前 Git 记录为准，不在日志中反复标注暂存、提交或推送状态。

- 唯一工程：`/Users/huangqi/AIHome/projects/ai_music`；工作分支：`main`。当前代码基线和工作区状态以实际 Git 记录为准；本轮搜歌单开发从 `75b7236` 开始。
- 产品基线：Flutter AI Music，包含 LAN 同步；旧 Android Native 迁移方案不是当前开发主线。当前协作规则以 [AGENTS.md](AGENTS.md) 为准。
- 最新开发验证：2026-09-27 搜歌单功能全量 Flutter 369 项通过，`flutter analyze --no-pub` 无问题，`git diff --check` 通过。新增首页双源混合歌单搜索、查看、新建/追加导入；试用反馈已调整为输入框左侧图标切换且下方保持原样，并隔离下载进度刷新、优化缓存索引和元数据完成后的重复扫描，详情见 [搜歌单](docs/playlist-search.md)。最新修正将完成的匹配结果移至“我的缓存列表→匹配歌单”，首页仅匹配进行时显示入口；自建歌单按近30天播放次数和最近使用排序，首页显示前4个，统计独立持久化。后台匹配、核对/分批导入与紧凑详情保留。独立review的跨任务共享歌曲误删、乱序失败误暂停两项问题已修复；reviewer复核完整369项及静态/差异检查通过，无新增阻断。修复包已交用户试用。
- 最近手机安装：2026-09-27 11:27:25 在77（Mi 10 Pro）保留数据安装本轮arm64 debug `1.0.1` / `8122`，本地/设备APK SHA-256同为 `dc6bf05178ce4ed6238a880d87aa235781385ef08a936feaa573a795d5fe8ef3`，首次安装时间和本次安装前后歌单文件校验未变，启动成功。8122包含review修复且启动正常，跨任务引用与乱序失败通过自动化回归；此前8121实机确认完成后首页入口隐藏、缓存列表“匹配歌单”恢复候选。排序、统计持久化和取消播放不重复计数通过自动化测试。此前已确认左侧图标切换及下方布局不变；下载性能优化已做通知/读取次数回归，实际流畅度待用户体验。191仍为此前 `75b7236` release8115；默认77 debug、191 release。
- 功能细节分别见 [截图导入](docs/screenshot-playlist-import.md)、[播放模式](docs/playback-modes.md)、[发现榜单](docs/discover-charts.md)；开发按 [开发专用 skill](.agents/skills/ai-music-developer/SKILL.md) 和 [工作流](docs/development-workflow.md) 执行，默认在当前工程的 `main` 工作，用户明确要求时可切换分支，但不创建 worktree。最终手机体验由用户验收。

按日记录：[2026-09-25](docs/worklog/2026-09-25.md) · [2026-09-26](docs/worklog/2026-09-26.md) · [2026-09-27](docs/worklog/2026-09-27.md)。拆分前的逐次原文保留在 Git 提交 `67f6e85` 的 `CURRENT_STATE.md` 中，需要追溯具体中间 APK 或测试结果时可查阅该版本。
