# 协同决策记录

## 2026-06-21：完整聊天原文不进 Git

决策：不要把完整 Codex 聊天原文提交进 AI Music 仓库。

原因：原始聊天很长、很吵，可能包含工具输出或本地敏感上下文。仓库里只记录简短摘要、threadId、requestId、commitId 和 review 结果。

## 2026-06-21：用 Lane 和 Thread 做责任归属

决策：Git author 不足以代表真实责任人，责任追溯以 `Request + Lane + Thread` 为准。

原因：多个 Codex lane 可能通过同一个本地账号提交代码。

## 2026-06-21：公共 Dart 默认归安卓 Lane

决策：`lib/src/` 下的公共 Flutter 业务代码默认归 `android` lane，除非架构师明确另行分配。

原因：安卓 lane 当前负责公共产品行为和测试；iOS 和鸿蒙 lane 主要负责各自宿主、平台能力和打包链路。

## 2026-06-21：AI Music 协同默认使用中文

决策：AI Music 的线程对话、任务派发、状态汇报、review 结论和复盘记录默认使用中文。

原因：用户需要直接阅读和复盘协同过程。代码符号、路径、命令和固定字段名可以保留英文，但解释和结论必须用中文。

## 2026-06-21：提交后先由架构师 Review，再按实际影响范围分发

决策：任何 lane 提交或准备提交后，先通知架构师 review。架构师 review 完后，把结果按实际影响范围分类，并只分发给相关 lane。

原因：用户不应该在多个对话之间复制粘贴 review 结果，也不应该让无关 lane 被噪声打扰。架构师负责统一验收、拆分责任和派发回改任务，开发 lane 只处理自己职责范围内的问题。

## 2026-06-21：不广播无关 Lane

决策：不涉及 Android/公共 Dart 的任务不要通知安卓；不涉及 iOS 的任务不要通知 iOS；不涉及 HarmonyOS 的任务不要通知鸿蒙。

原因：减少无关上下文，提高每个 lane 的专注度和复盘质量。

## 2026-06-21：鸿蒙提交默认走闭环 Review

决策：鸿蒙代码写完后，`ohos` lane 立刻找架构师 review；架构师 review 完如果只涉及鸿蒙，就直接把结果发回 `ohos` lane。

原因：鸿蒙平台问题通常只需要鸿蒙 lane 修复，不应该默认拉安卓或 iOS 参与。

## 2026-06-21：每个 Lane 维护自己的知识小仓库

决策：每个 lane 在解决可复用问题后，都要把过程沉淀到 `docs/codex_collab/knowledge/<lane>/`。

原因：开发过程中的排障路径、命令、踩坑和验证方法，对后续复盘和新开发者上手很重要。以后新增鸿蒙开发、iOS 开发或其它 lane 时，可以先读对应知识库继承经验。

## 2026-06-21：可体验功能必须主动通知产品

决策：任何 lane 完成可体验的新功能、用户反馈修复或交互验证版本后，都要主动向 `product` lane 发送 `demo_ready` 消息。架构师 review 通过或判断可以先体验时，也要同步产品。

原因：产品会话是用户体验验收入口。鸿蒙播控中心、安卓排序/歌单/批量处理、iOS 打包或平台能力等功能做到可试用时，不能等用户追问，必须及时说明体验入口、平台、验证方法和已知限制。

## 2026-06-22：功能闭环后自动推送远端

决策：一个功能闭环后，后续不再等待用户单独说“推送”。owner lane 或架构师应自行完成远端推送，并把最终 commit 和推送结果同步给 product lane。

闭环标准：实现完成、必要测试通过、架构师 review accepted、体验安装或验证入口明确、没有 blocker。

原因：产品不应该承担提交流转提醒职责。推送是工程闭环的一部分，应该由负责 lane 和架构师自动收口，避免功能已经验完但代码长期停在本地。

状态：已被 2026-06-22 的“版本冻结、确认后推送和 release tag”决策替代。后续不再自动推送远端。

## 2026-06-22：版本冻结、确认后推送和 release tag

决策：AI Music 引入版本概念。当前版本冻结后不再新增功能，后续新增功能进入下一版本。功能 review accepted 后可以先本地提交，但远端 push 必须等待 product lane 明确确认。

原因：项目已进入快速迭代期，需要让 product lane 能掌握每个版本新增了多少功能、哪些功能已验收、哪些功能已推送，并避免未确认改动直接进入远端主线。

规则：

- 每个 request 必须记录 `Target Version`。
- 当前冻结版本只接收已登记任务、bugfix 和验收修复。
- 新增功能默认进入下一版本。
- 状态 `accepted_pending_push` 表示已 review accepted 且可本地提交，但仍等待 product 确认远端推送。
- product 确认后，由 reviewer/architect 在 release 分支打 tag，基于 tag 构建 Android release 包；release 包成功后再 push release 分支和 tag。
- 当前只发布 Android release 包，使用 `tool/build_android_release.sh`。

状态：已被 2026-06-24 的“review accepted 后架构师直接合入并推送”决策替代。后续不再等待 product 逐次确认推送。

## 2026-06-24：Review Accepted 后架构师直接合入并推送

决策：功能实现完成后，只要同时满足架构师 review accepted 和 owner lane 自测通过，架构师即可直接合入目标分支并推送远端，不再等待 product lane 每次验收后转达推送。

原因：项目已进入快速迭代，逐次等待 product 确认推送会降低效率。product lane 后续直接验证最新包；如果发现问题，再按新 bug 或回改需求同步给团队。

规则：

- owner lane 完成实现、自测和必要自动化测试后，发 `review_request` 给架构师。
- 架构师 review accepted 后，确认提交范围干净、测试通过、无 blocker，即可合入目标分支并推送。
- 推送后必须主动通知 product lane，写清最终 commit、远端分支、安装包路径、已安装设备和可验证范围。
- 如果需要 release 包或 tag，由架构师按版本规则打 tag、构建 Android release 包并推送 tag。
- product 验证最新包后如发现问题，重新进入 bug_report / changes_requested 流程。

## 2026-06-24：任务未闭环时禁止全员停等 Product 催促

决策：任何未闭环任务都必须由 owner lane 和 architect lane 主动推进，不允许所有人停在 idle、等待、定位结论或待投递状态，直到 product 再次催促。等待 review、等待设备、等待其它 lane、等待合入或等待推送时，10 到 15 分钟没有新反馈就必须主动追问；如果无法继续推进，必须发 `blocker`。

原因：AI Music 现在以可用 App 为目标快速迭代，product 不应该承担流程催办和状态追踪成本。团队必须自己闭环：修复、验证、review、合入、推送、装包、通知 product。

规则：

- owner lane 不能只完成定位报告；根因明确后要继续推动修复，除非明确 blocker。
- architect lane 不能只更新任务单；需要跟进 owner lane 到 review、合入、推送和安装。
- 依赖其它 lane 时，等待方负责 10 到 15 分钟后主动追问。
- 如果连续无进展，架构师必须重新分配 owner、拆分任务或标记 blocked。
- product lane 只验收最新包和反馈问题，不负责日常催办。

## 2026-06-22：多开发并行使用 git worktree

决策：主目录 `/Users/huangqi/AIHome/ai_music` 只作为 `main` 稳定主线和产品验收入口，不再作为多个 lane 共用的日常开发目录。开发 lane 必须在架构师分配的独立 worktree 中开发。

原因：多个 lane 共用一个工作区会互相覆盖未提交改动、stash、分支状态、构建产物和设备安装包。`git worktree` 可以让每个版本和 request 拥有独立目录，降低冲突和误操作风险。

规则：

- 版本分支使用 `release/x.y.z`。
- 单需求分支使用 `feature/x.y.z/AM-YYYYMMDD-NNN-short-name`。
- 紧急修复分支使用 `hotfix/x.y.z/AM-YYYYMMDD-NNN-short-name`。
- 每个 request 必须记录 `Work Branch`、`Worktree Path`、`Base Branch` 和 `Merge Branch`。
- 架构师负责创建 release worktree、分配 request worktree、review 和合并。
- 开发 lane 不在主目录切分支，不复用其它 lane 的 stash，不把未 review 代码合入 release。
