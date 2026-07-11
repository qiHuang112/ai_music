# AM-20260625-003 滑动动效、播放队列与搜索单击优化

Status: in_progress
Owner Lane: android
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Target Version: 1.1.0
Base Branch: release/1.1.0
Work Branch: feature/1.1.0/AM-20260625-003-swipe-queue-search-ux
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260625-003_android_swipe_queue_search
Merge Branch: release/1.1.0
Created: 2026-06-25
Updated: 2026-07-11

## 目标

- 把左右滑动切歌升级为类似 ViewPager/Banner 的跟手动效。
- 在播放详情页提供当前播放列表入口，让用户能看清切歌队列和顺序。
- 首页搜索结果单击改为“下载并播放”，右侧下载按钮保留“只下载”。

## 范围

- 包含：公共 Flutter UI、MusicController/AudioHandler 暴露队列、跳到队列项播放、相关 widget/controller 测试。
- 包含：UI lane 对播放列表入口和滑动动效提供体验建议与验收辅助。
- 不包含：播放队列拖拽重排、播放队列持久化策略重做、平台原生宿主改动。

## 验收标准

- mini player 和播放详情页左右滑有跟手位移、吸附/回弹、切换动画；单曲/空队列轻微回弹，不误切。
- Slider、播放按钮、歌词点击不触发滑动切歌。
- 播放详情页右上角有“当前播放列表”入口；底部 sheet 展示队列、当前曲高亮、序号、歌名、歌手；点击队列项跳转播放。
- 搜索结果行单击：未缓存时下载完成立即播放，已缓存时直接播放；右侧下载按钮只下载不播放；下载中重复点击不重复任务。

## 消息记录

- 2026-06-25 type=task lane=product summary=产品要求滑动像 ViewPager/Banner 一样丝滑，并新增当前播放列表展示与搜索结果单击下载并播放。
- 2026-06-25 type=task lane=android summary=已分派给 Android owner 实现滑动动效、播放队列 sheet 和搜索结果单击下载并播放，要求回传测试、APK sha、截图和改动范围。
- 2026-06-25 type=task lane=ui summary=已分派 UI assist 确认队列入口、sheet 信息层级、ViewPager/Banner 反馈和截图验收点。
- 2026-06-25 type=task lane=architect summary=已通知 architect 巡检 worktree/branch、跟进回传、review 后合入推送。
- 2026-06-25 type=status lane=architect status=assigned summary=架构师已从最新 integration `main=926a351` 创建干净 worktree `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260625-003`，分支 `feature/1.0.1/AM-20260625-003-swipe-queue-search-ux`；实际 Base/Merge 按当前 1.0.1 集成主线记录为 `main`。
- 2026-06-25 type=status lane=ui status=acknowledged summary=UI 建议确认默认方案：播放详情页右上角放队列按钮并打开底部 sheet，mini player 不挤新按钮；sheet 展示当前队列、当前曲高亮、序号、歌名、歌手，点击跳播。review 时要求 Android 回传播放页队列入口、sheet 当前曲高亮、长列表滚动、ViewPager/Banner 跟手滑动和单曲回弹截图证据。
- 2026-06-25 type=status lane=android status=ready_to_try summary=Android 已将滑动切歌动效增强版安装到小米 10 Pro 开发机 `192.168.31.76:5555`，release 包 sha256 `4e33b489ae54bca66a1b451ef9c934dba7a98ebd3c224542a8c43953a02c5619`；当前等待 architect review。
- 2026-06-25 type=changes_requested lane=product summary=产品验收滑动动效不满意：触发切歌后页面滑到一半又回弹到中间，但歌曲已变成下一首；要求切歌完成时当前页继续滑出，下一首/上一首从另一侧接入，只有未过阈值或不能切歌时才回弹。
- 2026-06-25 type=task lane=product summary=产品明确开发验证机调试策略：小米 10 Pro 等开发机可直接卸载 release 包后安装 debug 包，不要为了 release 同签覆盖、沙盒命令或权限申请反复阻塞；只有小米 17 Pro 验收机或真实敏感数据清理才回 product 确认。
- 2026-06-25 type=status lane=android status=ready_to_try summary=Android 已按反馈修正滑动动效：成功切歌旧页继续滑出、新页从另一侧滑入，单曲或不可切歌才回弹；小米 10 Pro 已安装 release 包，APK sha256 `0411b0f050c3c1c6234bf24b5c5bf9af8d9e612f5c17cd67dbd9b5b881ddafcd`；当前等待 architect review。
- 2026-07-11 type=task lane=architect status=in_progress summary=Architect 按 Product 巡检重新分配 AM-20260625-003，不等待 AM-20260623 cache-first 修复。独立工程 `/Users/huangqi/AIHome/projects/ai_music_AM-20260625-003_android_swipe_queue_search` 已基于 `origin/release/1.1.0=45b302d48649330446d381b8593c50e22b9099f5` 创建，分支 `feature/1.1.0/AM-20260625-003-swipe-queue-search-ux`；Android 负责最小回归/回改与小米 10 Pro 录屏证据。

## 相关提交

- pending

## 版本与发布

- Target Version: 1.0.1
- Release Tag: pending
- Android APK: pending
- Push Status: not_ready

## Review 结果

- Reviewer Lane: architect
- Result: changes_requested
- Android Findings: 滑动完成动画语义错误：成功切歌不应回弹，应平滑滑出并接入下一首/上一首。
- iOS Findings: 不适用
- HarmonyOS Findings: 不适用
- Architect Findings: pending
- Notes: 公共 Dart/UI owner 为 android；UI lane assist，不直接改代码。

## 2026-07-11 Active Request Convergence

- Result: partially_covered_still_active_as_swipe_verification
- Covered By:
  - 当前播放队列入口与 bottom sheet 已由 AM-20260711-003 Library First UI 覆盖。
  - 搜索结果点击完整音频下载并播放、下载按钮只下载、无 PREVIEW 完成路径已由 AM-20260711-004 + AM-20260711-003 覆盖。
- Remaining Scope:
  - 滑动切歌动效仍需在 release/1.1.0 包上做真实设备回归：成功切歌旧页滑出、新页接入；未过阈值或单曲/空队列才回弹。
  - Slider、播放按钮、歌词点击、当前队列按钮不得误触横滑切歌。
  - 手势区需避开 Android/OHOS 系统边缘返回区；保持 48px 触控目标。
- Owner / Project:
  - Owner Lane: `android`
  - Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260625-003_android_swipe_queue_search`
  - Branch: `feature/1.1.0/AM-20260625-003-swipe-queue-search-ux`
  - Base: `origin/release/1.1.0=45b302d48649330446d381b8593c50e22b9099f5`
  - Device: 小米 10 Pro；跨端差异需要 OHOS 时再回 `ohos` 线程。
- Acceptance Samples:
  - 使用歌曲海完整音频缓存队列：`外婆`、`一丝不挂`、`稻香`、`哎呀`。
  - 录屏必须覆盖：播放详情页左滑/右滑成功切歌、单曲回弹、歌词区域纵向滚动不触发切歌、当前队列 sheet 打开后不被横滑手势误触。
  - 回传：APK sha、HEAD、targeted widget/player tests、录屏路径、关键帧截图和 `media_session` metadata 切换日志。
