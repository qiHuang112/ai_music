# 来听 UI 改动代码评估与实机确认（2026-10-09）

## 评估范围与结论

本次为开发者代码自查，不替代固定 reviewer 的独立 review。评估当前 77 实机 debug 1.0.3/10187，相对于本轮 UI 改版前 debug10180 的实际源码快照，而非当前 Git HEAD。工作区包含此前未提交功能改动，不能把 git diff 全部当作本次 UI 改动。

本轮最终差异集中在 4 个 UI 源文件，覆盖 9 个页面。核对范围内未发现阻塞性问题。播放、下载、匹配、缓存和队列底层实现未因本轮 UI 调整改变；播放入口将“停止”替换为“当前队列”是用户明确要求的功能入口调整。

## 按源文件评估

| 文件 | 最终保留的改动 | 影响与核对结果 |
|---|---|---|
| lib/src/presentation/player_page.dart | 正在播放、歌词详情；五个底部播控共用；收藏／热评移至进度上方 | 原控制器动作与来源、加歌单入口保留；内容可滚动，进度与播控固定底部；短横屏将操作移入滚动内容，需注意与竖屏位置不同。歌词点击跳转、自动跟随保留，仅移除显式“回到当前句”入口。 |
| lib/src/presentation/settings_page.dart | 设置首页分组、6 个子页背景和并发卡片、语言行焦点修复 | 设置项及保存逻辑保留；两个并发入口进入同一设置页。进入子页前解除旧焦点，透明悬停避免语言行返回后看似永久选中；键盘焦点反馈保留。窄屏／大字号的值行改为上下排布。 |
| lib/src/presentation/app_theme.dart | 公共 MusicSurfaces 主题扩展、静态渐变背景、轻量颜色调整 | 白／黑皮肤统一取色；渐变局部使用；无新增持续装饰动画。公共次要文字色会影响其他页面文字观感，其他页面结构不变。 |
| lib/src/presentation/app_update_page.dart | 设置中的更新入口移除左图标，徽标和箭头整理 | AppUpdatePage 本身未改版；当前版本、更新时间、红点与检查行为保留。启动时已有检查，不依赖入口滚动到可见。 |

## 范围验证方法

10180 Dart kernel 源码表中可对比的 88 个生产文件，4 个有差异，另 84 个一致。两个未进入该源码表的当前生产文件 chart_playlist_importer.dart 与 prefetch_retry.dart 未以 kernel 快照证明，但与本轮已保存的源码哈希记录一致。scope.json 与 4 份独立差异文件保存在截图目录。

首页、歌单、下载、热评等页面已恢复改版前源结构，不保留此次完整重设计。截图图册包含这些页面作为回退确认。

## 验证证据与限制

- 当前 10187 构建此前完整测试 735 项通过，静态分析与 diff 检查通过；本次仅截图及文档整理，没有重新修改产品源码或重复全量测试。
- 实机确认浅色／黑色的播放器、歌词、设置，以及全部 6 个设置子页可以进入；当前队列、热评入口此前实机验证通过。
- 77 仍为 debug 1.0.3/10187；未安装 191、未发布 release。截图结束恢复白色主题，播放保持暂停。未修改音源、品质、并发、语言、地址；未清缓存或删除数据。
- 截图是当前已安装实机包的真实窗口截图，保留系统栏及镜像窗口边框。鼠标箭头、悬停提示和个别灰色焦点反馈来自镜像操作，不是新增 UI 元素。
- 本次无 release 性能测量，不能凭截图或测试宣称流畅度提升；最终视觉效果待用户逐页确认。

## 页面截图

### 01 正在播放

改动页面：收藏和热评移到进度条上方，五个播控固定底部。

![01 正在播放](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/01-player-light.png)

### 02 歌词详情

改动页面：居中歌词、轻渐变；保留原顶部和底部五个播控。

![02 歌词详情](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/02-lyrics-light.png)

### 03 设置首页·上半部

改动页面：分组卡片与公共主题。

![03 设置首页·上半部](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/07-settings-top.png)

### 03 设置首页·下半部

同一页面：更多设置与更新入口。

![03 设置首页·下半部](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/14-settings-bottom.png)

### 04 默认下载品质

改动页面：背景视觉；原选择与保存逻辑保留。

![04 默认下载品质](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/08-download-quality.png)

### 05 音乐源

改动页面：背景视觉；当前 Auto 为手机原设置。

![05 音乐源](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/09-music-source.png)

### 06 并发设置

改动页面：并发归组；两个滑块范围和保存逻辑保留。

![06 并发设置](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/10-concurrency.png)

### 07 语言

改动页面：背景视觉；首页语言行焦点问题已修复。

![07 语言](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/11-language.png)

### 08 换肤

改动页面：背景视觉；支持白色与黑色。

![08 换肤](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/12-theme.png)

### 09 局域网音乐库

改动页面：背景视觉；地址与同步行为保留。

![09 局域网音乐库](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/15-lan-library.png)

### 10 黑肤·正在播放

主题对照。

![10 黑肤·正在播放](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/17-player-dark.png)

### 11 黑肤·歌词

主题对照。

![11 黑肤·歌词](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/18-lyrics-dark.png)

### 12 黑肤·设置

主题对照。

![12 黑肤·设置](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/16-settings-dark.png)

### 13 首页

恢复到改版前结构，无底部三个 Tab。

![13 首页](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/06-home-restored.png)

### 14 音乐库／我的歌单

恢复到改版前结构。

![14 音乐库／我的歌单](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/20-library-restored.png)

### 15 歌单详情

恢复到改版前结构。

![15 歌单详情](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/05-playlist-restored.png)

### 16 下载管理

恢复到改版前结构。

![16 下载管理](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/19-downloads-restored.png)

### 17 歌曲热评

恢复到改版前结构。

![17 歌曲热评](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/04-comments-restored.png)

### 18 当前播放队列

原队列页面，播放器和歌词页最右按钮进入。

![18 当前播放队列](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/03-queue.png)

### 19 检测更新

页面本身未重排，仅设置入口调整。

![19 检测更新](/Users/huangqi/AIHome/projects/ai_music/build/device-check/2026-10-09-ui-confirmation/13-update-reference.png)

