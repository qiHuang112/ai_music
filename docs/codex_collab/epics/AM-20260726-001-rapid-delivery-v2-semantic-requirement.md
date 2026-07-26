# AM-20260726-001 Rapid Delivery V2 Semantic Requirement R1

Status: user_approved
Workflow: ai-music-rapid-delivery-v2
Approval Evidence: bootstrap sha256:bfd213c5f8f42ea9715adcf35f00b57bf372038b620d95271b481133d79546a0
Primary Platform: Android Native
Native Frozen Start: codex/native-unified-epic-20260726@96093aa771e3a89ff11d523ed99fcacfeaa9b8ee

## 用户目标

以 Android Native 为唯一正式开发主线，解除歌曲海单点依赖，使用户能通过至少两个合法公开 Provider 稳定完成搜索、原子分页、完整音频播放、边播 seek、下载缓存、歌词封面和队列闭环；同时把 Flutter 已验收的播放器、歌词、进度和加载体验等价落到 Compose。进度以真实可体验垂直链路衡量，不以测试、review 或文档数量代替。

## 范围

- 合法公开 Provider 的低压准入、独立熔断、聚合、去重、备用来源和 cursor 分页。
- 完整音频校验、Media3 播放、边下边播 seek、下载转正式缓存及本地复用。
- 真实歌词、封面、队列和 MediaSession metadata。
- Flutter 已验收播放器、歌词、进度及加载状态到 Compose 的行为和视觉等价。
- 功能候选与最终真实 UI 候选的自动化、证据和真机门禁。

## P1 验收

1. **至少两个公开 Provider：**候选时至少两个相互独立的公开 Provider 各自能通过普通 Chrome 用户可达路径返回严格准入的完整音频，歌曲海保留为 Provider A 但只有健康时才计入数量；任一来源故障不得阻断其他来源。每源并发最多 1、全局最多 2、同源请求间隔至少 1.5 秒、单轮研究最多 20 次请求；连续 3 次传输失败冷却 15 分钟，遇到 `403`、`429`、验证码或防护页立即暂停该来源。不得绕过登录、防护、付费或 DRM，不得把网盘、试听、HTML、防护页或错误匹配作为结果。
2. **聚合搜索与原子分页：**歌名、歌手和自然语言查询结构化后聚合至少两个已准入 Provider；结果展示前校验真实标题、艺人、时长、音频 MIME、正长度及 Range `206`/total。同歌按稳定身份去重并保留已验证备用来源，单一来源失败不清空其他来源结果。首屏最多 12 条；每次加载更多只允许一次性发布 6-12 条去重后的合格结果，不逐条跳动，全部剩余不足 6 条时一次发布并正确结束各 Provider cursor。
3. **完整音乐闭环：**真实完整音频首声早于完整下载；用户向前或向后 seek 到尚未下载区域后可继续播放。下载完成后原子转为正式缓存并可离线复用；当前来源失效时可切换同歌已验证备用来源续播。失败、取消、HTML 和错误匹配不污染正式缓存。真实歌词、封面、动态队列和 MediaSession 标题、艺人、封面及播放状态与当前歌曲一致。
4. **Flutter UX 等价：**Compose 播放页、歌词页和加载状态与 Flutter 已验收状态逐项对照。保留三行歌词预览、完整歌词跟随、手动滚动两秒后恢复跟随和点行 seek；进度控件使用 4dp 轨道、14dp 拖拽点、40dp 触控高度和 24dp 水平边距，并同时区分已播放、已缓冲和未加载区间。seek 等待不得把整页替换为转圈，也不得展示尚未实现或不可用控件。
5. **候选与证据：**只有前四项在同一候选中贯通，且 fresh tests、AndroidTest compile、lint、assemble、集中 Spec/Code Quality review、Flutter/Compose 同状态对照和绑定本 revision 的 evidence manifest 全部通过，才允许一次 preserve-data 安装到小米 10 Pro 并通知用户进行功能验收；完整真实页面接线后再允许一次最终 UI 候选安装。验收不得使用假数据、测试注入、APK 外 helper 或直接构造 Media3 状态。

## 非目标

- 不修改 Flutter 业务或 UI；Flutter 只作为已验收行为/视觉合同和紧急回退版本。
- 不追平 iOS 或 HarmonyOS；两者仅保留接口兼容研究。
- 不创建新的窄 request，不因单一 Provider 故障暂停整个 Epic。
- 不以 Provider 数量放宽完整音频准入、版权/访问边界、缓存安全或真实设备证据要求。
- 不把设计稿 UI 验收写成真实代码 UI 验收，也不要求用户参与中间里程碑审批。

## 历史替代关系

- 本 semantic V2 R1 是当前唯一产品语义基线；bootstrap `bfd213c5f8f42ea9715adcf35f00b57bf372038b620d95271b481133d79546a0` 保留为用户批准证据，不再承担可变执行账本职责。
- semantic R2 `4ac5d1f892808c4fb3550bfbbdda66328407c64a8770942b2ada2d7601aa0628` 被本 revision 取代为历史。其 Back、edge-to-edge、中文 IME、失败隔离、缓存安全及歌词交互正向结论继续作为防回退证据，不再限制为歌曲海单源或旧 `3+3+2` 分页。
- semantic R1 `b8414836fa8ced7574f0463d497d2c22029828cc0e60c4c99771d93e734131ee` 和旧整文件快照 `005b75f7adf7814268a3df760bc1c3ffca4317cd32407a5f63cd1214169bdcc8` 仅保留历史追溯。
- Native `96093aa771e3a89ff11d523ed99fcacfeaa9b8ee` 是本轮冻结起点；旧候选 `f4afca41e047229a7ea57cb2e576b713ee8b093a` 的局部设备证据只作 lineage，不是 V2 候选验收。
- NCUX-20260726-R1/R2 与旧三图方向保留为历史 Native 增量；当前 UX 基线必须由 Flutter/Compose 同状态等价 revision 取代。Flutter、旧歌源窄任务、小爱专项、iOS 与 HarmonyOS 均不是本轮交付主线。
