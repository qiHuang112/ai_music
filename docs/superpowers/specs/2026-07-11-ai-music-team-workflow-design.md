# AI Music Superpowers 团队工作流设计

Created: 2026-07-11
Owner Lane: architect
Source Lane: product
Status: approved_for_implementation

## 目标

把 AI Music 现有的固定 lane、版本分支、多仓库并行、设备分层和主动推进规则，与 Superpowers 的规格先行、计划先行、TDD、系统化调试、双阶段 review、完成前验证组合成一套可执行工作流。最终目标不是增加文档，而是让不完整任务无法开工、缺证据任务无法 review、缺双 review 任务无法合入、已闭环任务无法静默停住。

本次 Product 指令同时要求“给出方案并实施”，视为对本设计范围的直接批准，不增加一次等待审批的停顿。

## 保留与替换

保留 AI Music 已有规则：

- Product 管方向和优先级，Architect 管拆分、review、合入和发布，开发 lane 管实现与自测。
- 每个 request 一个唯一 owner；独立任务使用独立仓库/工程目录。
- 主目录只作为稳定主线、账本和产品验收入口。
- reviewer accepted 且 owner 自测通过后，由 Architect 主动合入和推送，不等待 Product 再次催办。
- 小米 10 Pro 是开发验证机，小米 17 Pro 是 Product 验收机。

吸收 Superpowers 的核心约束：

- 功能和行为变更先形成设计规格，再形成可以逐项执行的计划。
- 新功能、修复和重构默认使用 RED-GREEN-REFACTOR；研究、纯文档或生成代码需要显式记录例外。
- Bug 修复先复现、找根因、写失败测试，再改生产代码。
- Review 拆成“规格符合性”和“代码质量”两个独立结论，二者都通过才算 accepted。
- 所有完成、修复、可体验和可合入声明必须带当前 HEAD、命令和新鲜验证证据。
- 独立问题并行，不独立或共享文件的任务串行；每个专项 lane 只接收最小上下文和明确回传契约。

明确不采用：

- 不采用 Superpowers 的 `using-git-worktrees` 作为 AI Music 并行方案。它与 Product 已确定的多仓库规则冲突；本项目统一使用独立 clone/Project Path。
- 不采用“每次完成都等待人类选择是否合入”。AI Music 已授权在硬门禁通过后由 Architect 自动合入、推送并通知 Product。
- 不把每一个微小问题都变成长规格。P2/P3 窄修复可以使用同一 request 下的短设计和短计划，但仍需根因、测试和验证证据。

## 四道硬门禁

### 1. Design Gate

进入开发前必须明确：目标、非目标、验收场景、风险等级、用户是否可感知、所需技能和设计文档。功能需求使用 `brainstorming`；Bug 使用 `systematic-debugging` 先完成复现和根因记录；研究任务写明调研协议、访问频率和停止条件。

### 2. Start Gate

必须有可执行计划、独立 Project Path、Work Branch、Merge Branch、Baseline Commit 和任务拆分。计划中的每个任务都必须有明确文件范围、测试动作、预期结果和回传证据。并行前由 Architect 检查文件所有权和共享状态；会修改同一文件或同一状态机的任务不能并行写代码。

### 3. Review Gate

Owner 发 `review_request` 前必须提交：

- 当前 HEAD 和基线；
- RED、GREEN、回归测试证据，或经过 Architect 接受的 TDD 例外；
- Bug 的复现、根因和最小假设验证；
- targeted tests、analyze/build 结果；
- 用户可感知功能的产品主路径自测；
- 变更范围和防回退检查。

Reviewer 先给规格符合性结论，再给代码质量结论。任一结论不是 accepted，任务进入 `changes_requested`，由同一 owner 回改并复审。

### 4. Merge Gate

合入前必须满足：规格 review accepted、代码质量 review accepted、全量或风险匹配的完整验证通过、无阻塞 finding、基线仍是目标 release 的最新已合入状态、提交范围干净。满足后 Architect 必须直接合入和推送；10 分钟内不能执行时必须发可行动 blocker。

## 任务类型策略

| Work Type | 必需流程 | 允许例外 |
| --- | --- | --- |
| feature | design + plan + TDD + 双 review + 主路径自测 | 无默认例外 |
| bugfix | 系统化复现/根因 + 失败测试 + 单一修复 + 双 review | 无测试框架时可用一次性复现脚本 |
| refactor | 行为基线测试 + 小步重构 + 双 review | 不得顺带改变业务行为 |
| research | 低频脚本/浏览器证据 + 可复现实验 + handoff 协议 | 不要求客户端 TDD，但脚本必须有可复验结果 |
| process | 规则设计 + 脚本测试 + 自检 | 不要求 App 真机测试 |
| release | 合入结果验证 + 构建/签名/包 SHA + 安装证据 | 不替业务 owner 修代码 |

## 并行模型

- Architect 只把互不依赖、文件范围不重叠、设备资源不冲突的任务并行派发。
- 一个功能计划中的强依赖任务使用串行 owner；多个独立子系统可分配给专项 lane 并行。
- 每个 lane 的消息只包含当前 task brief、接口约束、Project Path、目标分支和回传契约，不复制整段聊天历史。
- 任务进度以 request 和计划勾选为恢复地图；线程压缩或重启后从账本恢复，不重复派发已完成任务。

## 可执行接口

统一使用：

```bash
python3 docs/codex_collab/tools/team_ops.py validate-message \
  --file /tmp/ai-music-message.txt \
  --request-file docs/codex_collab/requests/AM-YYYYMMDD-NNN.md
python3 docs/codex_collab/tools/team_ops.py validate-workflow \
  docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate design
python3 docs/codex_collab/tools/team_ops.py validate-workflow \
  docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate start
python3 docs/codex_collab/tools/team_ops.py validate-workflow \
  docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate review
python3 docs/codex_collab/tools/team_ops.py validate-workflow \
  docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate merge
python3 docs/codex_collab/tools/team_ops.py validate-workflow \
  docs/codex_collab/requests/AM-YYYYMMDD-NNN.md --gate close
```

`scan` 会对标记为 `Workflow: superpowers-v1` 的任务按当前状态自动选择门禁。`validate-message --request-file` 只对绑定的新工作流 request 启用新增的 HEAD/测试/自测和双 review 消息约束；旧 request 不传上下文时保持兼容。2026-07-11 及以后新建的 request 必须使用该工作流；旧 request 不批量改写，但继续开发时应迁移。

## 成功标准

- 新任务缺设计或计划时脚本失败。
- Bug 缺根因或 RED 证据时不能送 review。
- Review 缺规格/质量双结论时不能合入。
- accepted 后缺合入、推送和 Product 通知时不能关闭。
- 现有旧任务不因为迁移债务阻塞，但新任务不能使用 legacy 规则逃逸。
- 组员收到一次规则同步后，后续依靠 skill 和脚本执行，不再靠 Product 重复提醒。
