# AM-20260726-001 Rapid Delivery V2 Bootstrap Requirement

Status: user_approved_bootstrap
Workflow: ai-music-rapid-delivery-v2
Native Baseline: 96093aa771e3a89ff11d523ed99fcacfeaa9b8ee
Primary Platform: Android Native
Created: 2026-07-26

## 用户目标

以 Android Native 为唯一正式开发主线，解除歌曲海单点依赖，并把 Flutter
已验收的播放器、歌词、进度和加载体验作为 Compose 强制等价合同。团队以用户
可见垂直链路衡量进度，不以测试数、review 数或文档数替代可体验结果。

## P1 验收

1. **公开多 Provider 准入：**歌曲海保留为 Provider A，并至少接入一个第二
   Provider；只允许普通 Chrome 用户路径可访问的公开来源。每源并发最多 1、
   全局最多 2，同源间隔至少 1.5 秒、每轮研究最多 20 请求；验证码、登录、
   防护、付费、DRM、网盘和试听均不得绕过或进入正式结果。
2. **聚合搜索与分页：**歌名、歌手和自然语言查询经结构化后聚合至少两个
   Provider；结果展示前必须通过真实标题/艺人/时长、音频 MIME、正长度及
   Range `206`/total 校验。同歌去重并保留备用来源；首屏最多 12 条，加载更多
   以 6-12 条原子批次发布，剩余不足 6 条时一次发布并正确结束 cursor。
3. **完整音乐闭环：**真实完整音频可首声早于完整下载，未下载区前向/后向
   seek 后继续播放；下载原子转正式缓存并可本地复用。当前来源失效时可用同歌
   已验证备用源续播；失败、取消、HTML、错误匹配不得污染缓存。歌词、封面、
   队列和 MediaSession metadata 必须正确。
4. **Flutter UX 等价：**Compose 播放页、歌词页和加载状态必须与 Flutter
   已验收状态逐项对照。三行歌词预览、完整歌词跟随/手动滚动两秒恢复/行 seek
   保留；进度控件使用 4dp 轨道、14dp 拖拽点、40dp 触控高度、24dp 水平边距，
   同时显示已播放、已缓冲和未加载状态，seek 等待不得整页转圈。
5. **候选与证据：**至少两个公开 Provider、完整搜索/播放/边播 seek/下载
   转正/歌词封面队列/失败隔离，以及 fresh tests、AndroidTest compile、lint、
   assemble、集中 review、Flutter/Compose 同状态对照和 evidence manifest
   全部通过后，才允许一次小米 10 Pro 功能候选安装并通知用户。完整真实页面
   接线后再允许一次最终 UI 候选安装。

## 非目标

- 不修改 Flutter 业务或 UI；Flutter 仅作为行为、视觉合同和紧急回退版本。
- 不追平 iOS 或 HarmonyOS；两者只保留接口兼容研究。
- 不创建新的窄 request，不把单一 Provider 故障升级为全 Epic 阻断。
- 不展示未实现控件，不使用假数据、测试注入或 APK 外 helper 完成验收。

## 执行约束

- 开发在自身任务内管理四条互斥完整 clone：公开歌源、聚合分页、Flutter UX
  等价、自动化证据。共享装配只由统一集成 clone 修改。
- 任一切片完成立即集成；15 分钟没有新增事实即收窄或替换执行者。
- 中间 APK 禁止安装；普通编辑、测试、构建、loopback、ADB debug 操作自动执行。
- 负责人只负责派工、冲突裁决、集中 review、精确 stage、commit 和 push。

## 用户批准证据

源任务 `019f4ed4-106e-7860-875d-a32f81629e4e` 于 2026-07-26 明确要求：
“PLEASE IMPLEMENT THIS PLAN: AI Music 原生版全速交付计划”。本文件是该计划的
可执行 bootstrap 抽取；Product 只需固化语义 revision 和不超过五条验收，不得
缩回歌曲海单源或把 Flutter UX 降级为参考。
