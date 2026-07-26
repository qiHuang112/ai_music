# AI Music Agent 团队自驱协作操作系统

> **历史兼容说明（2026-07-16）**
>
> 本操作系统用于解释 2026-06-25 至 2026-07-15 的旧多 lane 任务。当前新任务已经迁移到 `mobile-ai-music` 四角色敏捷团队，唯一入口和最高优先级规则为仓库根目录 `AGENTS.md` 与 `docs/codex_collab/teams/mobile-ai-music/team.json`。
>
> 下文的 Product/Architect/Dev/Platform/Researcher lane 不再是常驻组织结构。其能力分别并入产品、UX、开发、负责人四个角色；旧线程只保留历史证据，不得继续制造跨 lane 审批和等待。

Created: 2026-06-25
Owner Lane: architect
Source Lane: product
Status: active

这份规则用于把 AI Music 的多个 Codex 对话从“多线程聊天”变成“可持续交付系统”。它约束沟通、review、等待、合入、推送、知识沉淀和 token 使用，不记录具体业务细节。

## 0. 当前四角色持续敏捷规则（2026-07-19）

本节适用于当前 `mobile-ai-music` 四角色团队，优先于下文历史 lane 的阶段性停止、等待和回传表述。

- 默认动作是持续推进。测试通过、APK 构建、专项完成、80% 体验包、review accepted、stage、commit 或 push 都只是中间里程碑，不是停止条件。
- 只允许在三种情况下停止并把控制权回给用户：需求真正完成；必须由用户验收逻辑功能或完整 UI；最终真实 UI 已落地完成，需要用户验收。到达用户验收点时必须明确说明验收对象，其他阶段由团队自动继续。
- 产品把抽象需求收敛到足够开发后，开发逻辑和 UX 设计并行。UX 初稿可实施后，开发立即实现整体结构和主要视觉，不等待完整稿；后续 bug、边角状态和小 UI 差异继续自动闭环。
- 用户可直接与开发调整逻辑或 UI，也可直接找 UX 基于当前真机实现重做设计。UX 可以表达尚未实现的功能，但负责人必须在派发实现前检查冻结需求、技术能力、安全边界和现有业务规则，冲突只回传最小决策点。
- 所有直接沟通形成的用户可见变化都写入团队 discovery inbox，作为共享变更记录。产品和 UX 下一轮必须吸收、supersede 或标记不适用；负责人按最新意图检查冲突、同步开发，旧消息不得重新覆盖新决定。
- 设计稿通过与真实 UI 通过是两个不同事实：前者冻结视觉/交互目标，后者必须由最新安装包、真实设备关键状态和用户体验结论证明。设计稿批准不能代替真实落地 UI 验收。
- 负责人持续监督 Android Native 实现、构建、设备验证和证据闭环；规则或文档更新必须与开发并行，不得成为停工理由。

### 0.1 Android Native 事件驱动全速交付（2026-07-26）

- `/Users/huangqi/AIHome/ai_music` 继续作为团队管理根；唯一交付工程为 `/Users/huangqi/AIHome/ai_music_android_native`，当前集成分支 `codex/native-unified-epic-20260726`，冻结起点 `96093aa771e3a89ff11d523ed99fcacfeaa9b8ee`。
- 当前活跃工作流是 `ai-music-rapid-delivery-v2`，状态只允许 `active`、`integrating`、`candidate_ready`、`needs_user_acceptance`、`complete`。`superpowers-v1` 仅作历史/关闭谱系兼容，不得用于活跃 Epic。
- Flutter、旧歌源专项和小爱专项仅作历史来源、回退输入或 UX 等价合同；本轮不改 Flutter。HarmonyOS/iOS 只研究。新实现统一进入 Android Native Epic，不再为窄修复创建互相等待的小 request。
- 产品维护最多五条 P1 验收和历史替代关系；UX 维护 Flutter/Compose 同状态等价合同；开发作为统一集成者，在自己的持久任务内管理公开歌源低压研究及接入、多 Provider 聚合与分页、Flutter 播放/歌词/进度 UX 等价迁移、自动化与证据四条执行线。
- 四条执行线必须使用独立完整 clone 和互斥写集；公共构建、Manifest、应用装配、共享模型组装和最终冲突只由开发集成 clone 修改。任一切片完成即集成；15 分钟没有新事实就收窄或在同一任务内替换对应执行者。
- 公开来源只允许低压普通访问，不绕过验证码、防护、登录、付费或 DRM。单 Provider 最多 1 个并发、全局最多 2 个并发，同源请求间隔至少 1.5 秒，单轮最多 20 次请求；连续 3 次传输失败冷却 15 分钟，403、429 或防护页立即暂停该 Provider，其他执行线继续。
- 测试、lint、构建、review、commit 和 push 都触发下一动作，不是停点。普通 Gradle、ADB、loopback/socket、debug 构建和非破坏性安装由团队自行执行。
- 中间包不得安装。至少两个公开 Provider 通过严格完整音频准入，且 fresh tests/lint/build、完整搜索、聚合分页、Media3 播放、边播 seek、下载转正、歌词封面、队列、失败隔离和 evidence manifest 全通过后，只安装一次小米 10 Pro 功能候选进入用户逻辑验收；最终真实 UI 全接线后再安装一次进入真实 UI 验收。

### 0.2 模型继承规则（2026-07-26）

- 四个角色、开发子 Agent 和替换 Agent 均继承用户当前全局默认模型与思考强度；派工、续接、恢复和账本不显式指定或覆盖这些设置，除非用户明确要求任务级例外。
- 用户调整全局默认时，正在运行的任务继续执行，不因策略同步重启、暂停或重建；后续新 Agent 自动继承新默认。
- 模型或工具不可用时，owner lane 不能停工；应继续用当前可用能力推进，并在状态里只写清限制和补强计划，不自行改写用户的全局模型策略。

## 1. 核心原则

- 每个任务必须有唯一 owner lane；协作 lane 只能辅助，不能让责任漂移。
- Product 负责方向、优先级、体验取舍和最终验收，不负责日常催办。
- Architect 负责拆任务、定边界、review、冲突裁决、合入和发布推进，不长期替开发 lane 写业务代码。
- Dev/Platform lane 负责实现、自测、证据、review_request、回改和最终同步。
- Researcher lane 负责并行调研、脚本验证、skill/方案沉淀和风险判断，不直接抢开发 lane 的业务代码 owner。
- 当单一开发 lane 成为瓶颈时，architect/product 可以按独立仓库/工程目录拆出专项开发 lane；专项 lane 必须只在自己的完整工程目录开发，并把 review_request 回给 architect 和原 owner lane。
- 产品体验小改是迭代输入，不是停工许可；只有 P0/P1、架构风险、数据风险或发布风险可以阻塞主流程。
- 效率优先：P1 目标是“核心功能先可用、可装、可体验、可回滚”，P2 目标是“体验、覆盖率、跨端一致性和边界补齐”。P1 达到最小可用且无已知数据/架构破坏风险时，owner 自测通过后必须尽快 review/merge/push/装包，不得因为 P2 细节、全量截图或非必要权限等待而长期不合入。
- 做不到的功能必须尽快暴露核心问题：外部源不可用、协议变更、设备不可达、平台能力缺失、权限策略限制等都必须用 `blocker` 给出证据和可选路径；不得用“继续调研”“等待确认”掩盖目标不可达。

## 2. 状态机

任务必须沿着下面状态收敛：

```text
assigned -> in_progress -> self_tested -> review_requested -> accepted|changes_requested -> merged -> notified -> verified
```

- `ready_to_try` 只表示可体验，不等于完成。
- `accepted` 必须包含 owner 自测通过和架构师 review 通过。
- `merged` 必须说明 commit、分支、构建或验证方式。
- `blocked` 必须可行动：写清卡点、已尝试路径、需要谁决策或支持。
- 任务不得长期停在“定位中”“等反馈”“待确认”。连续两轮没有实质进展时，架构师必须拆小、换 owner 或裁决方向。

## 3. 跨 lane 消息契约

所有需要对方处理的消息必须包含：

```text
type: task|status|demo_ready|review_request|review_result|handoff|blocker
request: AM-YYYYMMDD-NNN
lane: <owner-or-target-lane>
thread: <target-thread-id>
status: <current-state>
summary: <新增事实，不复述完整历史>
next_action: <谁下一步做什么，完成后回给谁，带什么证据>
```

检查标准：

- 是否明确下一步 owner。
- 是否明确完成后回给谁。
- 是否明确需要回传什么证据。
- 是否推动实现、验证、review、合入、发布或决策。
- 如果以上都没有，不要发送。

## 4. 硬规则脚本

自然语言规则必须尽量收敛到脚本。AI Music 协作硬规则入口：

```bash
python3 docs/codex_collab/tools/team_ops.py validate-message --file /tmp/ai-music-message.txt
python3 docs/codex_collab/tools/team_ops.py validate-message --file /tmp/ai-music-message.txt --request-file docs/codex_collab/requests/AM-YYYYMMDD-NNN.md
python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-YYYYMMDD-NNN.md
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate active
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate integrating
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate candidate_ready
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate needs_user_acceptance
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate complete
python3 docs/codex_collab/tools/team_ops.py scan --root /Users/huangqi/AIHome/ai_music --legacy-ok
```

- 任何 lane 发送 `task`、`status`、`demo_ready`、`review_request`、`review_result`、`handoff`、`blocker` 前，先用 `validate-message` 检查消息。
- `Workflow: ai-music-rapid-delivery-v2` request 的消息必须追加 `--request-file <任务单>`，让消息门禁按活跃状态启用 HEAD、测试、自测和 review 约束；历史 request 不传该参数，避免迁移债务阻塞正在收口的任务。
- 任何 lane 创建或更新 request 后，先用 `validate-request` 检查任务单。
- Architect 每次巡检、review 收口或合入前，至少运行一次 `scan --legacy-ok`；新任务不得依赖 `legacy-ok` 通过。
- 如果脚本失败，先修消息或账本，再继续投递；如果暴露的是旧账迁移债务，把它记录为账本维护项，不要把新任务混进去。
- 脚本检查的是最低协作门槛，不替代真实实现、自测、review 和产品取舍。

### 4.1 Rapid Delivery v2 五状态

- 活跃 Epic 必须使用 `Workflow: ai-music-rapid-delivery-v2`；`superpowers-v1` 仅允许历史/关闭记录继续保留，不批量改写历史。
- `active`：目标、冻结起点、独立完整 clone、互斥写集、最多五条 P1 和执行 owner 已明确，执行线已启动。
- `integrating`：任一切片完成即进入统一工程，持续保留 HEAD、RED/GREEN、fresh targeted/full tests 和 scope diff 证据；finding 自动回到对应执行线。
- `candidate_ready`：至少两个公开 Provider 及完整业务闭环通过 fresh tests/lint/build、双 review 和 evidence manifest，才允许候选。
- `needs_user_acceptance`：只用于一次功能候选或最终真实 UI 候选已安装、必须由用户验收的合法停点。
- `complete`：需求与最终真实 UI 均已验收，合入、push、通知和知识沉淀全部完成。
- `systematic-debugging`、`test-driven-development`、双 review 和完成前验证继续作为内部工程方法，但不得制造额外审批层或中间停点。

## 5. 等待 SLA

- 等 review、等设备、等对方回复、等确认，都必须有等待方 owner。
- 等待超过 10 到 15 分钟，等待方主动追问一次，只确认是否在处理、是否卡住、是否漏回。
- 连续两次无结果，架构师必须升级为 blocker、重新分配 owner、拆小任务或裁决方向。
- 同一问题两轮 review 打回后，架构师必须给最小可接受标准。
- 当问题已经被收窄为单个 P1/P2 或很小的 final-gate 回改时，不能进入“等最终判断”的静默状态。架构师必须直接指定修复 owner，并要求修复方立刻回传新 HEAD、targeted tests、analyze 和是否需要重新装机；reviewer 只复核该窄变更，不重新扩大范围。
- 当窄回改已经被相关 reviewer accepted 后，架构师必须在 10 分钟内执行合入/推送/出包判断，或发 `blocker` 写清唯一剩余阻塞和下一步 owner；不得只停留在“等待 architect 最终判断”。

## 6. 合入与推送

- 功能闭环定义：实现完成、owner 自测通过、必要自动化测试通过、架构师 review accepted、没有 blocker。
- 满足闭环条件后，架构师可以直接合入目标分支并推送远端，不再等待 product 逐次确认。
- 推送后必须同步 product lane：commit、分支、tag 或包路径、验证方式、已知限制。
- 如果推送失败，按 blocker 回报具体原因。
- 最终合入 owner 默认为 architect。只要 owner 自测、必要 reviewer accepted、targeted tests/analyze 通过且没有 blocker，architect 不得继续等待 product、developer 或“更完整结论”；必须直接合入，或在 10 分钟内给出可行动 blocker。
- 对已经有真机正向证据的任务，后续窄 P1/P2 gate 修复如果只加固失败路径且不改变 UI/播放/缓存正向路径，默认不要求重新完整真机验收；由 architect 明确判断是否需要补装机。不得因为“是否重装”不明确而静默停工。

## 6.0 P1/P2 快速合入与授权测试边界

- P1/P2 分级由 product 目标和用户可用性决定：
  - P1：搜索、完整音频播放、下载、边下边播、缓存、歌词/封面主路径、安装包可体验、会导致用户“不能用”的回归。
  - P2：滑动手感、截图覆盖、视觉 P3、长尾歌曲覆盖、跨端一致性补测、非主路径文案和后续体验精修。
- P1 不等全量 P2。P1 最小闭环后，architect 必须推动 merge/push/体验包；P2 进入后续 request 或同 request 的 follow-up，不得阻塞用户拿到可用包。
- 开发 lane 不再因为普通 Codex 授权、sandbox socket、`127.0.0.1`、Flutter test 端口、ADB/HDC 常规调试、debug 包安装、输入法切换等日常验证事项等待 product 人工批准。能用受信任工程、unattended profile、已有设备授权或开发机默认权限处理的，owner 直接处理并记录命令/证据。
- 如果某个自动化测试因为本机 sandbox/socket/权限策略无法跑，owner 不能把任务停住等 product 授权；必须选择一条可执行路径：
  - 使用已配置的 AI Music unattended profile 或 approved prefix 重跑；
  - 改为更小的 targeted test / scoped analyze / 脚本证据；
  - 构建 debug 包交给 product 或 QA 真机体验，并明确哪些自动化证据缺失；
  - 若确属系统安全策略不可绕过，10 到 15 分钟内发 `blocker`，说明命令、失败输出、替代验证和需要谁处理。
- “测试直接让 product 来体验”的含义是：当自动化权限/环境阻塞不影响代码实现和可装包时，owner 先交付可体验包和明确已知风险，不把本地 test 授权当成合入前无限等待条件。不能因此省略 owner 主路径自测；owner 仍需提供能做到的最小证据。
- Review 要按风险收敛，不按完美主义扩散。P1 review 只拦 P0/P1/P2 阻塞问题；P3 和体验精修必须记录但默认不阻塞合入。连续两次 review 只剩 P3 时，architect 必须合入或明确拒绝理由。
- 每次合入困难超过 10 到 15 分钟，architect 必须回传当前卡点属于哪类：冲突、测试失败、权限/设备、证据不足、产品取舍、外部源不可达。不能只写“等待中”。

## 6.1 测试策略

- 开发过程中优先跑和本次改动直接相关的 targeted tests、局部 `analyze` 或必要的设备验证，不要每次小改都跑全量测试。
- 全量测试只在准备提交给架构师 review、准备合入/发版、或改动触及共享基础设施/跨模块风险较高时执行。
- `review_request` 必须写清已跑的 targeted tests；如果暂未跑全量测试，要说明计划在送 review 前或合入前补跑。
- 架构师 review 前可以要求补全量测试；但不应把日常开发阶段每次迭代都要求全量测试作为默认门槛。

### 6.1.0 Superpowers 开发纪律

- 功能、修复、重构默认执行 RED-GREEN-REFACTOR：先写失败测试并确认因目标行为缺失而失败，再写最小实现，再运行回归测试。
- Bug 必须先用 `systematic-debugging` 完成稳定复现、最近改动比对、数据链路追踪、单一根因假设和最小验证；没有根因证据不得直接改生产代码。
- `research`、纯文档、生成代码等不适合 TDD 的任务可以使用 `TDD Mode: not_applicable|exception`；`exception` 必须写原因并由 Architect 标记 `TDD Exception Review: accepted`。
- Owner 的自测不能代替 reviewer。Review 固定分两步：先检查规格符合性，再检查代码质量；两个结论都必须独立写入任务单。
- Reviewer 的建议先按 `receiving-code-review` 核对代码和产品口径，不能盲改；正确 finding 逐项修复并复测，不正确 finding 用代码和测试证据说明。
- 声称“修复、完成、通过、可体验、可合入”前，必须使用 `verification-before-completion` 重新运行能证明该声明的命令；历史输出和口头转述不算新鲜证据。

### 6.1.1 产品主路径自测硬规则

- 所有用户可感知功能在 `review_request`、`demo_ready` 或 `accepted` 前，owner 必须完成产品主路径自测；只跑单测、`analyze`、截图或 XML 不算完整自测。
- 搜索、播放、下载、歌源、缓存、播控中心、歌词封面、首页入口这类主流程，必须在开发验证机上从入口操作到结果闭环，至少覆盖“打开入口 -> 执行动作 -> 结果可用 -> 失败态合理”。
- 搜索/下载/播放类任务必须额外覆盖：
  - 搜索一个已知可完整播放的样例，例如当前版本的 `一丝不挂` 或 `稻香`。
  - 点击结果行或播放按钮，确认 App 内播放与系统 media session 进入播放态。
  - 如果本轮禁止试听或 preview，必须确认 UI 不出现 `试听/PREVIEW/30s` 完成路径。
  - 对不可下载来源，必须确认展示原因且不误写正式缓存。
  - 如果涉及缓存，必须确认缓存索引和音频文件变化符合预期。
- 设备、输入法、锁屏、安装、网络或第三方源波动导致无法自测时，owner 必须在 10 到 15 分钟内升级 `blocker`，不能把未完成主路径自测的包标记为可验收。
- reviewer 必须拒绝缺少产品主路径自测证据的 `review_request`；architect 不允许合入缺少主路径自测证据的用户功能。
- 自测证据要写“做了什么动作、预期是什么、实际是什么”，不要只写“已安装”“截图见附件”。

### 6.1.2 Codex 受信任目录与无人值守测试/构建授权

- AI Music 本机 Codex 配置优先使用受信任项目和持久 prefix 规则，目标是让项目内测试/构建可以无人值守执行，而不是每次等待人工点授权。
- 当前本机受信任目录配置在 `/Users/huangqi/.codex/config.toml`：
  - `[projects."/Users/huangqi/AIHome"] trust_level = "trusted"`
  - `[projects."/Users/huangqi/AIHome/ai_music"] trust_level = "trusted"`
  - `[projects."/Users/huangqi/AIHome/projects"] trust_level = "trusted"`
- 当前项目内命令前缀持久授权配置在 `/Users/huangqi/.codex/rules/default.rules`，覆盖 AI Music 常用 `team_ops.py`、Flutter test/analyze/build、Android debug build、OHOS HAP build 等命令前缀。
- 需要显式无人值守运行 Codex CLI 时，使用专用 profile `/Users/huangqi/.codex/ai-music-unattended.config.toml`。推荐形态：

```bash
/Applications/ChatGPT.app/Contents/Resources/codex -p ai-music-unattended exec -C /Users/huangqi/AIHome/projects/<project> "<prompt>"
```

- 该 profile 设置 `approval_policy = "never"` 与 `sandbox_mode = "danger-full-access"`，只用于 AI Music 受信任工程里的测试、构建、账本校验和 release 收口自动化；不要作为通用浏览、第三方站点探测或设备控制默认入口。
- 可预授权范围：项目目录内的只读检查、Dart/Flutter 单测、`flutter analyze`、Android debug/release 构建、OHOS HAP 构建、`team_ops.py validate-*`/`scan`、`git fetch/log/diff/check` 等不会修改系统状态的项目工作命令。
- 不自动视为已授权范围：本机 socket/端口监听、局域网/外网访问、ADB/HDC 设备安装和坐标点击、系统输入法/锁屏/通知栏操作、Keychain/codesign/profile 修改、删除用户数据、第三方歌源高频探测、Chrome/Browser/Computer Use 自动化。即使历史 `default.rules` 中已有个别 prefix 规则，也必须按当前任务安全策略、设备归属和用户授权执行；没有授权时 10 到 15 分钟内回 `blocker`，不能把安全策略当成已完成。
- 如果某个独立 Project Path 仍触发 Codex trust 提示，owner 可先确认它位于 `/Users/huangqi/AIHome/projects/`；仍提示时，把该具体路径加入 `/Users/huangqi/.codex/config.toml` 的 `[projects."<path>"] trust_level = "trusted"`，并在回传里写明新增路径和验证命令。
- 验证要求：每次调整授权配置后至少运行一次 `codex --strict-config -p ai-music-unattended exec --help` 或等价 Codex profile 解析检查，再运行一个项目内 `team_ops.py validate-*` 命令，回传原始输出摘要。

## 6.2 Beta、QA 与 Release Manager

- Beta 快速体验和 Release 正式收口分离。owner 修完可先产 Beta 包给 QA 验证。
- QA lane 只负责安装、验收清单、截图/录屏/日志和 pass/fail/blocker 回传；不写业务代码、不合并推送。
- QA 回传必须包含包 sha、versionCode、设备 target、清单结果、失败复现步骤、截图/录屏/日志路径。
- Release Manager lane 在 architect accepted 后负责合入、构建、推送、tag、包证据归档和 demo_ready；不替 owner 修业务 bug。
- Android Beta 默认使用小米 10 Pro；Android 调试时设备归 Android，Beta 包安装后或 Android 空闲时交给 QA。
- 小米 10 Pro 是 Android 开发验证机，日常调试默认直接安装 debug 包；如设备上已有 release 包或异签名旧包，owner 可在记录测试目的和清数据影响后卸载旧包再装 debug 包，不为同签覆盖反复阻塞。release 包只用于发版收口或 product/architect 明确要求的验收。
- 开发验证机（例如小米 10 Pro）遇到异签名旧包、旧数据或安装冲突时，默认由 owner 和 architect 处理：优先产出同签名包；无法同签时，记录旧包信息、测试目的和风险后可清理开发机旧测试包再安装验证，不再升级给 product 做日常决策。
- 产品验收机（例如小米 17 Pro）只用于最终体验或 product 明确授权的安装；不得用于日常调试、卸载、清数据或反复试错。
- 设备问题不能让任务静默停住。10 到 15 分钟内无法完成安装验证时，owner 必须给出替代证据（构建、manifest、日志、模拟器或另一台开发机）并同步下一步设备处理人。

## 6.3 并行研究员

- 研究员命名统一使用 `AI music-xxx研究员`，lane 使用 `xxx-researcher`。
- 研究任务可以和 P1 bugfix 并行启动；不允许所有人因为单个下载 bug 停住。
- 研究员只交付调研结论、验证脚本、skill 草案、风险清单和可落地方案；客户端代码由对应开发 lane 接手。
- 外部资源调研必须低频串行、克制访问，禁止高并发压测第三方服务。
- 研究结论必须沉淀到 `docs/codex_collab/knowledge/<researcher-lane>/`，并尽量形成 skill 或脚本，不停留在聊天总结。

## 6.5 反空转规则

- `可转发消息` 不等于已完成交接；只要线程投递工具可用，必须实际发送给目标 lane。
- 等 product 决策只允许用于真实产品取舍；实现路径、测试证据、工程目录、review 标准由 architect 默认决策。
- 如果 owner 进入等待状态，必须同时推进不依赖该等待的下一个动作；没有可推进动作时才发 blocker。
- 单一 lane 排队超过两个独立任务时，优先拆专项独立工程/专项线程并行推进。
- “所有 reviewer accepted 但 architect 未合入”视为流程 blocker，而不是普通等待。product 或任一 lane 发现该状态时，应直接催 architect 合入/推送/出包；architect 必须回 `merged`、`changes_requested` 或 `blocked` 三者之一。
- 每次出现“大家都停了”的复盘结论，必须把自然语言提醒沉淀为本文件或 `team_ops.py` 检查项；不能只在聊天里道歉或重复口头规则。
- 计划中有两个及以上互不依赖、文件范围不重叠、设备资源不冲突的任务时，Architect 必须并行分配；共享同一状态机或同一文件的任务必须串行，避免伪并行制造冲突。
- 并行 lane 只接收自己的 task brief、接口约束、Project Path 和回传契约；稳定背景引用设计/计划文件，禁止在每条消息里重复完整上下文。
- 任务进度以 request、计划勾选和 git commit 为恢复地图。线程压缩、重启或换 Agent 后，先读取账本，不得重新派发已完成 task。

## 6.7 多仓库/多工程并行规则

- 2026-07-05 起，不再把 `git worktree` 作为 AI Music 并行开发方案；新任务默认使用独立仓库克隆或独立工程目录，例如 `/Users/huangqi/AIHome/projects/ai_music_<lane_or_request>`。
- 主目录 `/Users/huangqi/AIHome/ai_music` 只作为稳定主线、账本和产品验收入口；开发 lane 不在主目录日常开发或切分支。
- 每个开发 lane 或专项任务拥有自己的完整工程目录，目录内包含独立 `.git`、依赖缓存、构建产物和设备安装包；不同 lane 不共享 stash、不共享 build 目录、不共享半成品包。
- 每次开始开发、rebase、review 前，owner 必须先把已合入主分支的内容整合进自己的工程：`git fetch origin` 后基于最新 `origin/main` 或目标 `release/x.y.z` 重建/rebase/cherry-pick 本任务改动。
- 任何 review_request 必须回传当前 `HEAD`、基线 commit、与 `origin/main` 或目标 release 的差异说明；如果基线落后且可能回退已合入功能，架构师必须 `changes_requested`。
- 架构师创建或分配任务时，任务单必须写 `Project Path`。历史 `Worktree Path` 只作为旧账兼容字段，不能作为新任务的默认做法。
- 合入前必须做“防回退检查”：确认本任务没有回退主分支已经合入的首页、搜索、metadata、播放状态、下载、播控中心等体验。检查方式至少包括 `git log --oneline origin/main..HEAD`、关键文件 diff、targeted tests 和必要真机验证。
- 如果旧任务仍在 `/Users/huangqi/AIHome/worktrees/`，不允许直接合入；必须先迁移到独立工程或在最新主线新工程中重放最小改动，再发 review。
- Superpowers 中的 `using-git-worktrees` 在 AI Music 项目内明确禁用。安装该 skill 只用于保持上游技能套件完整，不改变本项目的独立 clone/Project Path 规则。

## 6.6 客户端日志

- 客户端日志是正式 bug 分析证据，不再只靠 product 反馈猜问题。
- Debug/Beta 默认详细日志，Release 默认 warn/error 和关键 breadcrumb。
- 日志必须覆盖 resolver、metadata、playback、download、cache、mediaSession、uiAction、platformBridge 等关键链路。
- 日志保存在本地文件，支持导出和本机上传服务；日志要脱敏，不记录 token、cookie、完整私密路径或设备隐私。

## 7. Token 与死循环治理

- 稳定事实写入任务单、`changes.md`、`reviews.md` 或 `knowledge/`，聊天只写新增事实、当前判断和下一步。
- 不广播无关 lane，不重复复述长背景，不写泛泛“继续推进”。
- “定位中”必须每轮产生新证据、新假设、新排除项或新提交。
- “等待中”必须有超时追问。
- “review 中”必须有明确结果：`accepted`、`changes_requested` 或 `blocked`。
- 超过两轮无实质进展，默认进入流程复盘。

## 8. 每日短复盘

每个活跃 lane 每天只汇报三项：

```text
完成：<今天实际完成了什么>
卡点：<当前卡在哪里；没有卡点写“无”>
下一步：<谁做什么，完成后回给谁，带什么证据>
```

禁止长篇复述历史，禁止只写“继续推进”。

## 9. 知识沉淀

每个 lane 解决可复用问题后，沉淀到自己的 `knowledge/<lane>/`：

- 问题现象
- 根因判断
- 排查命令
- 验证方法
- 最终结论
- 下次如何避免

不要记录完整聊天原文、token、证书密码、账号信息、设备隐私或一次性噪声。

## 10. 巡检责任

- Architect 每天巡检活跃 request：是否有 owner、是否卡在等待、是否需要重分配、是否可以合入推送。
- Owner lane 对自己的 request 闭环负责：不能只报状态不推进。
- Product 只在方向、优先级、体验取舍和验收上介入；如果 product 被迫反复追问，视为团队流程失败，需要复盘。
