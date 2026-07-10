# AI Music Codex 协同账本

这个目录是 AI Music 多个 Codex 对话的项目账本，用来记录任务流转、责任归属、提交来源、review 结论和关键决策。它不是完整聊天归档。

## 语言规则

- AI Music 相关的线程对话、任务派发、状态汇报、review 结论、复盘记录默认都用中文。
- 只有代码符号、路径、命令、commit trailer 字段名、固定状态值可以保留英文。
- 如果用户没有特别要求英文，不要用英文写协同账本正文。

## 信息来源

- Codex 原始聊天记录继续保存在本机 Codex 存储里，只作为需要深挖时的黑匣子回放来源。
- 本目录是日常协同、定责、任务状态和 commit 归属的主入口。
- 不要把完整聊天原文粘进仓库，只记录简短中文摘要、threadId、requestId、commitId、负责人 lane 和 review 结果。

本机已知的原始记录位置：

- `/Users/huangqi/.codex/session_index.jsonl`
- `/Users/huangqi/.codex/sessions/`
- `/Users/huangqi/.codex/shell_snapshots/`

## 团队操作系统入口

- 全员必须先读 `docs/codex_collab/operating-system.md`，再处理 AI Music 任务。
- 该文件是 2026-06-25 团队复盘后的固定执行规则，覆盖唯一 owner、状态机、等待 SLA、回传契约、合入推送、token 治理和知识沉淀。
- 如果聊天里的临时习惯和 `operating-system.md` 冲突，以 `operating-system.md` 为准；如果产品有新的管理口径，先更新该文件和对应 request，再同步各 lane。

## 硬规则脚本入口

在继续靠聊天解释规则之前，优先运行脚本检查：

```bash
python3 docs/codex_collab/tools/team_ops.py validate-message --file /tmp/ai-music-message.txt
python3 docs/codex_collab/tools/team_ops.py validate-message --file /tmp/ai-music-message.txt --request-file docs/codex_collab/requests/AM-YYYYMMDD-NNN.md
python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-YYYYMMDD-NNN.md
python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate <design|start|review|merge|close>
python3 docs/codex_collab/tools/team_ops.py scan --root /Users/huangqi/AIHome/ai_music --legacy-ok
```

- 跨 lane 消息先过 `validate-message`，避免缺 owner、缺回传、无效等待或广播无关 lane。
- 新 Superpowers request 的消息使用 `--request-file` 绑定任务上下文；旧 request 不强制迁移成双 review 消息，避免打断当前收口。
- 新建或更新任务单先过 `validate-request`，避免任务没有版本、分支、独立工程路径和唯一 owner。
- 2026-07-11 及以后新建的 request 使用 `Workflow: superpowers-v1`，并在设计、开工、review、合入和关闭前运行对应 `validate-workflow` 门禁。
- 架构师巡检和合入前运行 `scan --legacy-ok`；旧账只作为迁移提醒，新任务必须按硬规则补齐。

## Superpowers 适配

- 新功能先用 `brainstorming` 明确设计，再用 `writing-plans` 写可执行计划；Product 已给出明确设计和实施指令时，可以把该指令记录为批准，不额外制造等待。
- Bug 先用 `systematic-debugging` 找根因；功能、修复和重构默认使用 `test-driven-development`。
- 开发完成后先做规格符合性 review，再做代码质量 review；两个结论都 accepted 才能进入合入门禁。
- 所有完成声明使用 `verification-before-completion` 提供新鲜命令输出、HEAD/commit 和设备或包证据。
- 两个以上独立任务按 `dispatching-parallel-agents` 思路并行分配给独立 lane/独立工程；共享文件或共享状态的任务串行。
- AI Music 不采用 `using-git-worktrees`；继续执行独立 clone/`Project Path` 规则。
- 完整设计见 `docs/superpowers/specs/2026-07-11-ai-music-team-workflow-design.md`。

## 工作流

1. 架构师 lane 在 `requests/` 下创建或更新任务单。
2. 架构师根据 `lanes.md` 把任务分派给一个或多个负责人 lane。
3. 负责人 lane 在自己的可写范围内实现、排查或验证。
4. 任何 lane 一旦产生提交或准备提交，都要更新任务摘要，并主动通知架构师 review。
5. 架构师 review 后，必须按实际影响范围分类 findings，只通知确实涉及的 lane。
6. 架构师根据分类结果，把需要回改的问题分别分发给对应 lane；不要广播无关 lane，也不要让用户手动复制粘贴 review 结果。
7. 架构师在 `reviews.md` 记录 review 结果，并更新任务状态。
8. 任何进入提交历史的改动，都要在 `changes.md` 里记录 request、lane、thread 和 review 归属。
9. 开发和 review 过程中遇到的可复用问题，要沉淀到 `knowledge/` 下对应 lane 的知识小仓库。
10. 新功能、修复或可交互体验达到“可以让用户试”的状态时，负责人 lane 或架构师必须及时通知 product lane，也就是当前产品会话。
11. 功能闭环后，owner lane 可以先本地提交并发给架构师 review；架构师 review 通过且 owner 自测通过后，架构师可以直接合入主分支并推送，不再等待 product 逐次确认。
12. 任何 lane 发出 `task`、`review_request`、`review_result`、`status` 询问或等待对方回应后，如果 10 到 15 分钟没有反馈，应主动追问一次，确认对方是否正在工作、是否卡住或是否漏回消息；不要让任务静默卡住。
13. 任何需要对方处理的消息，必须在 `next_action` 写清：谁下一步做什么、完成后回给谁、回传什么证据；被等待方完成后必须主动回到指定 lane。
14. 不允许所有人停着等 product 催。只要任务未闭环，owner lane 和 architect lane 都有推进责任：能继续排查就继续排查，能自测就自测，能 review 就 review；如果卡住，必须主动发 `blocker` 写清卡点、已尝试动作和需要谁决策。
15. 产品体验细节反馈是迭代输入，不是默认停工许可。除非明确是 P0/P1、架构风险、数据风险或发布风险，否则 owner lane 应继续推进可维护、可扩展的实现，并把小修小改进入回改队列。
16. 沟通必须控制 token 成本：稳定事实写入任务单或知识库，聊天只写新增事实、当前判断和下一步；不广播无关 lane，不重复复述长背景。
17. UI lane 当前处于 onboarding，只负责熟悉 APP 页面、截图体验和 UI 建议；product 未明确要求 UI 验收或 UI 开发时，不加入自动化 review 流程。
18. 开发任务日常迭代只跑和改动点直接相关的 targeted tests、局部 `analyze` 或必要设备验证；不要每次小改都跑全量测试。准备发架构师 review、合入、发版，或改动风险跨模块时，再跑全量测试。
19. 研究任务可以并行启动，不因某个 P1 bug 阻塞全部团队；研究员 lane 只做调研、脚本、skill 和方案沉淀，客户端实现仍交给对应开发 lane。
20. 研究员命名统一使用 `AI music-xxx研究员`，对应 lane 使用 `xxx-researcher`；不要再使用“杠研究员”。

## 自驱闭环与成本控制规则

- 每个任务必须有唯一 owner。协作 lane 只能辅助，不能让责任在多个对话之间漂移。
- 推荐状态收敛路径：`assigned -> in_progress -> self_tested -> review_requested -> accepted|changes_requested -> merged -> notified -> verified`。
- `ready_to_try` 只表示可体验，不等于 `accepted`；`accepted` 必须包含架构师 review 通过和 owner 自测通过。
- `blocked` 必须可行动，写清卡点、已尝试路径、需要谁决策或支持；不能只写“等一下”“继续看看”。
- `in_progress` 必须持续产生新增证据、新假设、新排除项或新提交；如果连续两轮没有实质进展，架构师要拆小、换 owner 或裁决方向。
- `review_requested` 超过 10 到 15 分钟没有结论，owner lane 要追 architect；`changes_requested` 超过 10 到 15 分钟没有回改进展，architect 要追 owner。
- 同一问题两轮 review 打回后，架构师必须给出最小可接受标准，不能继续泛泛要求“再看看”。
- 架构师可以在 P0/P1 blocker 时临时兜底实现，但不能长期替开发 lane 写业务代码；兜底后必须把维护权和复盘责任交回 owner lane。
- 每条跨线程消息都要满足一个检查：是否推动了实现、验证、合入、发布或决策。如果没有，就不要发送。
- 每个活跃 lane 的短复盘只写三件事：完成了什么、卡在哪里、下一步谁做什么。

## 版本与推送规则

- 每个 request 必须登记 `Target Version`、`Work Branch`、`Project Path`、`Base Branch` 和 `Merge Branch`。历史任务里的 `Worktree Path` 只作为旧账兼容字段。
- 当前冻结版本只允许已登记任务、bugfix 和验收修复进入；新增功能默认进入下一版本。
- 功能闭环定义：实现完成、owner 自测通过、必要自动化测试通过、架构师 review accepted、没有 blocker。
- 测试闭环分阶段执行：开发中以 targeted tests 为主；`review_request` 前或合入前再补全量测试。若只完成局部自测，消息里必须写清已跑测试和待补测试。
- 满足闭环条件后，架构师可以直接合入目标分支并推送远端；不再等待 product lane 逐次确认推送。
- 推送前必须确认提交范围只包含本 request 或本次版本账本改动，不能混入其它 lane 的脏改、临时构建产物或未验收改动。
- 需要发版时，由 reviewer/architect 打版本 tag，基于 tag 构建 Android release 包；release 包成功后再 push release 分支、main 和 tag。
- 推送成功后更新 `versions.md`、`changes.md` 和任务单状态，并给 product lane 发送 `status` 或 `demo_ready`，写清最终 commit、tag、远端分支、APK/HAP 路径和体验状态。product 将直接验证最新包；如有问题再反馈新 bug。
- 如果推送失败，按 blocker 回报具体原因，例如认证失败、远端有新提交、rebase 冲突或网络不可达。

## 分支与多工程规则

- 主目录 `/Users/huangqi/AIHome/ai_music` 只作为 `main` 稳定主线和产品验收入口，不作为多人日常开发目录。
- 版本分支使用 `release/x.y.z`，例如 `release/1.0.0`、`release/1.0.1`。
- 单需求开发分支使用 `feature/x.y.z/AM-YYYYMMDD-NNN-short-name`，并从对应 `release/x.y.z` 创建。
- 紧急修复分支使用 `hotfix/x.y.z/AM-YYYYMMDD-NNN-short-name`，从对应 tag 或 release 分支创建。
- 新任务不再使用 `git worktree` 做并行开发；每个 lane 或专项任务使用独立仓库克隆/独立工程目录，例如 `/Users/huangqi/AIHome/projects/ai_music_<lane_or_request>`。
- 每个 lane 只在分配给自己的完整工程目录里开发，不在主目录切分支，不复用其它 lane 的 stash、依赖缓存、构建产物或设备安装包。
- 每个 feature 分支只服务一个 request，不允许跨 request 混合提交。
- 架构师负责创建 release 分支、分配 request 独立工程目录、review feature 分支、合入 release 分支和处理跨 lane 冲突。
- 每次开发、review、合入前，owner 必须先整合已合入主分支或目标 release 的内容，回传当前 `HEAD`、基线 commit 和防回退检查结果；旧基线可能回退已合入功能时，架构师必须打回。
- 开发 lane 遇到冲突时先停止开发，向架构师发送 `blocker`，说明冲突文件、目标分支和 request；不得强行覆盖或使用破坏性 git 命令。
- 旧 `docs/codex_collab/worktrees.md` 仅保留历史记录；新任务以 `docs/codex_collab/operating-system.md` 的多仓库/多工程并行规则为准。

## 体验同步规则

- 任何 lane 完成一个可体验功能、修复一个用户明确反馈的问题，或准备让用户验证交互时，都要给 product lane 发送 `demo_ready` 消息。
- `demo_ready` 不等于代码最终合入；如果只是临时构建、待 review 版本或有已知限制，必须在 `summary` 和 `next_action` 里写清楚。
- 架构师 review 通过、或 review 后认为某个版本已经可以先体验时，也要主动通知 product lane。
- 典型场景：
  - 鸿蒙播控中心修好暂停恢复、封面、歌名歌手、播放模式、点赞同步后，通知 product lane 体验。
  - 安卓完成排序、拖拽、歌单、本地删除、批量处理等公共 Dart 业务后，通知 product lane 体验。
  - iOS 完成 IPA、签名、宿主能力或 Apple 平台体验改进后，通知 product lane 体验。
- 通知 product lane 时要写明：能体验什么、在哪个平台体验、需要执行什么命令或安装什么包、还有哪些已知问题。
- 不要让用户自己追问“好了没”；功能能试时，负责人 lane 要主动同步。
- UI lane 需要体验包时，不自行占用设备或安装；由 product/architect 协调 android、ohos 或 ios lane 提供安装支持。默认优先 Android 或 HarmonyOS，如果对应 lane 忙，再找另一个平台支持。

## Beta / QA / Release Manager 规则

- Beta 快速体验和 Release 正式收口分离。owner 修完可先用 Beta 包给 QA 验证，不必每次小改都等待完整 release 流水线。
- QA lane 只做安装、验收清单、截图/录屏/日志和 pass/fail/blocker 回传，不写业务代码、不合并推送。
- Release Manager lane 在 architect accepted 后负责合入、构建、推送、tag、包 sha/manifest 归档和 demo_ready，不替 owner 修业务 bug。
- Android Beta 默认使用小米 10 Pro；Android 调试时设备归 Android，Beta 包已安装或 Android 空闲时交给 QA。
- 小米 10 Pro 是 Android 开发验证机，日常调试默认直接安装 debug 包；如设备上已有 release 包或异签名旧包，owner 可在记录测试目的和清数据影响后卸载旧包再装 debug 包，不为同签覆盖反复阻塞。release 包只用于发版收口或 product/architect 明确要求的验收。
- 客户端日志是正式 bug 分析证据：Debug/Beta 详细、Release 克制；设置页导出日志，本机服务接收日志上传。

## 研究员并行规则

- `source-researcher` 负责歌源下载链路调研，先脚本跑通，再沉淀 skill，最后交 Android 公共 Dart 落地。
- `playlist-researcher` 负责歌单推荐/热榜来源调研。
- `streaming-researcher` 负责边下边播技术方案调研。
- `xiaoai-researcher` 负责小爱同学唤醒和指定播放能力调研。
- `qa-researcher` 负责完整产品回归清单、UI 截图巡检和证据模板调研。
- 研究员可以并行启动；但调研第三方外部资源时必须低频、串行、克制，不做高并发压测。
- 研究员输出必须落到 `knowledge/<researcher-lane>/`，并尽量沉淀为 skill 或脚本，不能只停留在聊天总结。

## 设备分层规则

- 小米 17 Pro 是 product lane / 主管验收设备，不是开发 lane 默认自测设备。
- 开发 lane 自测默认使用小米 10 Pro 或其它明确分配给开发测试的设备。
- 未经 product lane 明确许可，开发 lane 不应连接、安装、覆盖或用小米 17 Pro 做坐标点击、媒体控件验证等自测。
- review `demo_ready` 或 `review_request` 时，架构师要检查设备使用是否合规；自测证据默认应来自开发测试设备，产品验收证据才来自小米 17 Pro。
- 如果产品明确要求安装到小米 17 Pro，消息里必须写清楚授权来源、安装内容、是否覆盖用户数据和验收入口。

## Review 分发规则

- 有人提交或准备提交后，owner lane 必须给架构师发送 `review_request`。
- `review_request` 必须包含 HEAD/commit、targeted tests 和 owner 自测证据；用户可感知功能还必须带产品主路径自测。
- 架构师发出 review 结论后，必须主动回传给 owner lane；如果当前环境没有线程投递工具，要在当前会话明确输出可转发的 `review_result`，并在后续可投递时补发。
- 架构师或任一 lane 等待对方处理 review、task、status 或 blocker 时，10 到 15 分钟没有反馈就主动追问一次。追问只确认状态和 blocker，不要重复施压或广播无关 lane。
- 架构师 review 必须按平台和责任边界拆分结果，只发给实际相关 lane：
  - 公共 Dart 业务、Android、测试、Android 打包问题发给 `android` lane。
  - iOS 宿主、签名、IPA、CocoaPods、Apple 能力问题发给 `ios` lane。
  - HarmonyOS 宿主、ArkTS、HAP、鸿蒙音频插件问题发给 `ohos` lane。
  - 架构决策、任务拆分、账本规则问题由 `architect` lane 自己处理。
- 不涉及 Android/公共 Dart 的任务，不要通知 `android` lane。
- 不涉及 iOS 的任务，不要通知 `ios` lane。
- 不涉及 HarmonyOS 的任务，不要通知 `ohos` lane。
- 鸿蒙典型流程是 `ohos -> architect review -> ohos`：鸿蒙 lane 写完并提交或准备提交后，立刻给架构师发 `review_request`；架构师 review 完，如果问题只涉及鸿蒙，就直接把结果发回鸿蒙 lane，不找安卓或 iOS。
- 如果 review 没有问题，架构师要回传 `review_result`，并把任务状态更新为 `accepted`。
- `review_result` 必须分别写清 `Spec Review Result` 和 `Code Quality Review Result`，不能只写笼统的“review 通过”。
- 如果 review 有问题，架构师要给对应 lane 发送 `review_result` 或 `task`，写清楚 priority、文件位置、问题原因和期望修复。
- 开发 lane 修完后，再次请求架构师 review，直到 `accepted`。
- 每条 `review_result`、`task`、`handoff` 或 `blocker` 必须写清回传路径。例如“修完后请回 architect lane，带 commit、测试结果、设备验证和是否需要安装 product 设备”；不要只写“我等你”或“继续处理”。
- 架构师完成 review、合并、推送、打包或安装后，也必须主动回传给 owner lane 和 product lane；不能只在架构师线程结束。
- `accepted` 前，如果 owner lane、architect lane 或依赖 lane 超过 10 到 15 分钟没有新状态，等待方必须主动追问；如果连续追问仍无进展，架构师要改为明确 `blocked` 或重新分配 owner，不能让任务挂起到 product 再来催。

## 知识沉淀规则

- 每个 lane 都有自己的知识小仓库，位于 `knowledge/<lane>/`。
- 开发、排障、构建、安装、review 过程中，只要遇到可复用问题，就要用中文沉淀下来。
- 适合沉淀的内容包括：问题现象、根因判断、关键命令、排查路径、最终解决方案、验证方式、注意事项、相关 request/commit/thread。
- 不要记录完整聊天原文、token、证书密码、profile 私密信息、设备个人隐私或一次性无复用价值的噪声。
- 后续新招的鸿蒙、iOS、安卓或架构师 lane，应先读 `knowledge/README.md` 和自己 lane 的知识库。

## 跨线程消息格式

跨线程消息使用下面的紧凑结构。字段名保留英文便于检索，字段内容必须用中文：

```text
type: task|status|demo_ready|review_request|review_result|handoff|blocker
request: AM-YYYYMMDD-NNN
workflow: superpowers-v1  # 新工作流可显式填写；或 validate-message 传 --request-file
lane: product|android|ios|ohos|architect|ui|qa|release-manager|source-researcher|playlist-researcher|streaming-researcher|xiaoai-researcher|qa-researcher
thread: <codex-thread-id>
status: proposed|assigned|in_progress|review|ready_to_try|accepted|blocked
summary: <中文事实摘要>
next_action: <中文下一步>
```

Review 分发消息建议在 `summary` 里标明目标平台和优先级，例如：

```text
type: review_result
request: AM-YYYYMMDD-NNN
lane: android
thread: 019ee41d-647e-7250-bb01-f1ae81098696
status: assigned
summary: 安卓/公共 Dart review 有 1 个 P2，需要修复返回键状态判断。
next_action: 修改 MusicController.hasSearchState，并补测试后再次请求架构师 review。
```

`next_action` 必须包含回传对象和回传内容，推荐格式：

```text
next_action: 请 android lane 修复上述 P1；完成后回 architect lane，带 release/debug 对比、flutter test/analyze、release APK 路径、sha256、小米 10 Pro 或小米 17 Pro 的 dumpsys/logcat 验证摘要。
```

## Commit Trailer

AI Music 的提交如果和某个任务有关，提交信息里要加责任归属 trailer：

```text
Request: AM-YYYYMMDD-NNN
Lane: android|ios|ohos|architect|source-researcher|playlist-researcher|streaming-researcher|xiaoai-researcher|qa-researcher
Thread: <codex-thread-id>
Reviewed-by-lane: architect|android|ios|ohos|none
```

只有很小的文档或账本维护改动，才可以使用 `Reviewed-by-lane: none`。
