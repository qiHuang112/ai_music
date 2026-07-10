# AI Music Superpowers Team Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Superpowers 的设计、计划、TDD、调试、双 review 和完成前验证变成 AI Music 团队可执行的硬门禁。

**Architecture:** 以现有 `team_ops.py` 为唯一 CLI 入口，新增 `validate-workflow` 五阶段校验，并让 `scan` 根据 request 状态自动运行对应门禁。协同文档和任务模板定义同一组字段，现有多仓库规则保持不变。

**Tech Stack:** Python 3 标准库、`unittest`、Markdown 协同账本、Codex skills。

## Global Constraints

- 新任务使用独立仓库/工程 `Project Path`，不使用 git worktree。
- Product 不承担日常催办；硬门禁通过后 Architect 主动合入、推送和通知。
- 用户可感知功能必须有产品主路径自测证据。
- 研究任务保持第三方站点低频串行，不做压测。
- 不改写或回滚当前工作区中已有的用户改动。

---

### Task 1: 为工作流校验器建立失败测试

**Files:**
- Create: `docs/codex_collab/tools/test_team_ops.py`
- Modify: `docs/codex_collab/tools/team_ops.py`

**Interfaces:**
- Consumes: 现有 `validate_request_file`、`CheckResult`。
- Produces: `validate_workflow_file(path, gate)` 和 CLI `validate-workflow`。

- [ ] **Step 1: 写失败测试**

覆盖新 request 缺 `Workflow`、计划含占位符、Bug review 缺根因/RED、merge 缺双 review、close 缺合入推送通知证据。

- [ ] **Step 2: 运行测试确认 RED**

Run: `python3 -m unittest docs.codex_collab.tools.test_team_ops -v`

Expected: FAIL，因为 `validate_workflow_file` 和新门禁尚不存在。

- [ ] **Step 3: 实现最小校验器**

增加工作类型、风险等级、门禁字段、文档路径与占位符检查；旧 request 只做兼容，新 request 强制 `superpowers-v1`。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `python3 -m unittest docs.codex_collab.tools.test_team_ops -v`

Expected: PASS，0 failures。

### Task 2: 把门禁接入 scan 和消息契约

**Files:**
- Modify: `docs/codex_collab/tools/team_ops.py`
- Modify: `docs/codex_collab/tools/test_team_ops.py`

**Interfaces:**
- Consumes: `validate_workflow_file`。
- Produces: 状态到门禁映射、review_request 最小证据检查、review_result 双结论检查。

- [ ] **Step 1: 写失败测试**

覆盖 `review_request` 缺 HEAD/测试/自测时失败，`review_result` 缺规格或质量结论时失败，`scan` 能按状态选择门禁。

- [ ] **Step 2: 运行测试确认 RED**

Run: `python3 -m unittest docs.codex_collab.tools.test_team_ops -v`

Expected: 新测试 FAIL。

- [ ] **Step 3: 实现消息与 scan 门禁**

保持旧消息字段结构，新增完成声明的证据要求；只对 `Workflow: superpowers-v1` request 自动运行工作流门禁。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `python3 -m unittest docs.codex_collab.tools.test_team_ops -v`

Expected: PASS，0 failures。

### Task 3: 更新团队规则和任务模板

**Files:**
- Modify: `docs/codex_collab/operating-system.md`
- Modify: `docs/codex_collab/README.md`
- Modify: `docs/codex_collab/requests/README.md`
- Create: `docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md`

**Interfaces:**
- Consumes: 设计文档中的字段和门禁。
- Produces: 全员可读规则、可复制 request 模板和本次落地记录。

- [ ] **Step 1: 增加 Superpowers 适配章节**

写明四道门禁、任务类型例外、双阶段 review、多仓库替代 worktree、accepted 后自动合入。

- [ ] **Step 2: 扩展 request 模板**

加入 `Workflow`、`Work Type`、`Risk Level`、设计/计划路径和各类证据字段。

- [ ] **Step 3: 校验本次 request**

Run: `python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md --gate review`

Expected: PASS。

### Task 4: 更新项目 skill 并全员同步

**Files:**
- Modify: `/Users/huangqi/.codex/skills/ai-music-team-ops/SKILL.md`
- Modify: `docs/codex_collab/lanes.md`

**Interfaces:**
- Consumes: 已安装的 Superpowers skills 和 `team_ops.py`。
- Produces: 每个 AI Music 线程启动时可复用的 skill 路由和精简团队通知。

- [ ] **Step 1: 更新 skill 的必读与命令**

要求按任务类型使用 `brainstorming`、`systematic-debugging`、`writing-plans`、`test-driven-development`、`requesting-code-review`、`receiving-code-review`、`verification-before-completion`；明确禁用项目内 worktree 流程。

- [ ] **Step 2: 通过消息校验后同步相关 lane**

分别通知 Architect、开发 owner、研究员/QA/UI 适用规则；不使用 `lane: all`，不复制长背景。

### Task 5: 完成前验证

**Files:**
- Verify: all files above

**Interfaces:**
- Consumes: 全部实施结果。
- Produces: 可复现测试、门禁输出和差异清单。

- [ ] **Step 1: 运行单元测试**

Run: `python3 -m unittest docs.codex_collab.tools.test_team_ops -v`

Expected: PASS，0 failures。

- [ ] **Step 2: 运行脚本自检**

Run: `python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md`

Run: `python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md --gate review`

Run: `python3 docs/codex_collab/tools/team_ops.py scan --root /Users/huangqi/AIHome/ai_music --legacy-ok`

Expected: 新 request 和新门禁通过；旧账仅保留迁移 warning。

- [ ] **Step 3: 检查变更范围**

Run: `git diff --check`

Expected: 无输出。
