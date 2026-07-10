# AM-20260711-001 基于 Superpowers 重构团队工作流

Status: pushed
Owner Lane: architect
Source Thread: 019ee910-8747-71e3-9293-720273f9e61f
Target Version: process
Base Branch: main
Work Branch: process/AM-20260711-001-superpowers-team-workflow
Project Path: /Users/huangqi/AIHome/ai_music
Merge Branch: main
Created: 2026-07-11
Updated: 2026-07-11
Workflow: superpowers-v1
Work Type: process
Risk Level: P1
User Visible: no
Design Doc: docs/superpowers/specs/2026-07-11-ai-music-team-workflow-design.md
Implementation Plan: docs/superpowers/plans/2026-07-11-ai-music-team-workflow.md
Required Skills: using-superpowers, writing-plans, test-driven-development, verification-before-completion, ai-music-team-ops
TDD Mode: required
TDD Exception: none
Baseline Commit: f988dc0a0ce52cee82667bea88751c67344aaf0b
Head Commit: aadb2b837d1e865ab9bf39d5033fe7740a86ed2f
Root Cause Evidence: docs/superpowers/specs/2026-07-11-ai-music-team-workflow-design.md
Red Evidence: 初始门禁测试得到 3 failures/9 errors；兼容回改得到 2 failures/2 errors；requestId 与文件名绑定测试分别先失败，证明错误任务单或伪装标题可绕过门禁
Green Evidence: python3 -m unittest docs.codex_collab.tools.test_team_ops -v 运行 16 tests，结果 OK
Targeted Tests: python3 -m unittest docs.codex_collab.tools.test_team_ops -v，16 passed
Self Test Evidence: validate-request、validate-workflow review gate、legacy/new message context 均返回 OK；ai-music-team-ops quick_validate 返回 Skill is valid；~/.codex/config.toml 已解析确认 multi_agent=true
Product Main Path Evidence: not_applicable
Baseline Freshness Evidence: 干净合入目录 /Users/huangqi/AIHome/projects/ai_music_AM-20260711-001_merge 基于 origin/main=f7d28a15 重放 280ff3b，生成 aadb2b8
Scope Diff Evidence: aadb2b8 仅包含 Superpowers 设计/计划/request、team_ops 与测试、操作系统、README、lanes、request 模板和 QA gate 资产；未混入业务代码
Spec Review Result: accepted
Code Quality Review Result: accepted
Full Verification Evidence: python3 -m unittest docs.codex_collab.tools.test_team_ops -v 运行 16 tests，结果 OK；py_compile、validate-request、validate-workflow --gate review、skill quick_validate、TOML 解析和 git diff --check 均通过
Blocking Findings: none
Merge Evidence: aadb2b837d1e865ab9bf39d5033fe7740a86ed2f 已在干净合入目录基于 origin/main=f7d28a15 cherry-pick，并解决 README 规则段冲突
Push Evidence: git push origin main 成功，远端 main 从 f7d28a1 推进到 aadb2b8
Product Notification Evidence: architect 在当前 thread 019ee4b7-e7d2-7751-a4c4-150ede83c350 回 product/owner，带提交、推送和验证证据
Knowledge Evidence: docs/superpowers/specs/2026-07-11-ai-music-team-workflow-design.md; docs/codex_collab/knowledge/qa-researcher/2026-07-11-superpowers-qa-evidence-gate.md

## 目标

- 安装 Superpowers 技能套件，并把适合 AI Music 的方法变成团队硬规则和脚本门禁。

## 范围

- 包含：设计/计划/TDD/根因调试/双 review/完成前验证、任务模板、脚本测试和全员同步。
- 不包含：业务功能修改、App 打包、设备安装、使用 git worktree。

## 验收标准

- 新 request 缺设计、计划或证据时，`team_ops.py` 在对应门禁返回失败。
- Bug 缺根因与 RED 证据时不能进入 review。
- 缺规格和代码质量双 review 时不能合入。
- accepted 后缺合入、推送和通知证据时不能关闭。
- 相关 lane 收到精简中文通知，并知道完成后回传给谁、带什么证据。

## 消息记录

- 2026-07-11 type=task lane=architect summary=Product 要求安装 Superpowers 并将其重构为 AI Music 团队硬工作流。
- 2026-07-11 type=team_rule lane=xiaoai-researcher summary=小爱调研保持暂停优先级；后续恢复必须按 Superpowers research 流程执行，区分本地 Intent 可测能力与小米开放平台审核能力，不把受限 PoC 宣称为完整产品能力。规则已沉淀到 `docs/codex_collab/knowledge/xiaoai-researcher/2026-07-11-superpowers-pause-resume-rule.md`。
- 2026-07-11 type=status lane=qa-researcher summary=QA researcher 已沉淀 Superpowers QA 验收证据门禁，要求包 SHA、设备、动作、预期、实际、截图/录屏/日志和失败升级规则齐全后才能声明 pass 或可发布；模板路径 `docs/codex_collab/knowledge/qa-researcher/2026-07-11-superpowers-qa-evidence-gate.md`。
- 2026-07-11 type=status lane=ui summary=UI 已确认 Superpowers 工作流；后续只在 product 明确要求 UI 设计或规格符合性验收时介入，回传设计文档、验收场景、截图路径、规格符合性结论和 P 级建议，未 handoff 前不直接改业务代码。
- 2026-07-11 type=status lane=ios summary=iOS 已确认 Superpowers 工作流；后续 iOS 宿主、签名、IPA 和 Apple 平台能力任务在开工前执行 start gate，review_request 前执行 review gate，并回传 HEAD、基线、RED-GREEN 或批准例外、targeted tests、构建/签名/设备自测和 scope diff。

## 相关提交

- aadb2b837d1e865ab9bf39d5033fe7740a86ed2f

## 版本与发布

- Target Version: process
- Release Tag: not_applicable
- Android APK: not_applicable
- Push Status: pushed

## Review 结果

- Reviewer Lane: architect
- Result: accepted
- Android Findings: not_applicable
- iOS Findings: not_applicable
- HarmonyOS Findings: not_applicable
- Architect Findings: 规格符合性 accepted；代码质量 accepted。两轮 P2 已关闭：`validate-message` 已通过 `--request-file` 绑定 request 上下文，仅对 `Workflow: superpowers-v1` 启用新消息门禁；同时校验消息 `request:`、request 文件一级标题 requestId、request 文件名前缀三者一致，避免传错 request 文件绕过或误用门禁。
- Notes: 进入 merge gate。当前为 process-only 工作流和脚本规则改动，不修改 App 业务代码或 release 分支；合入前仍需确认提交范围只包含本 request 相关文档、脚本、测试和本机 skill 同步。

## 2026-07-11 Architect Review

- Spec Review Result: accepted
- Code Quality Review Result: changes_requested
- Finding:
  - P2 `docs/codex_collab/tools/team_ops.py:236`：`validate_message_text` 无 request 上下文，却全局要求所有 `review_result` 同时包含规格符合性和代码质量结论。这与设计文档“旧 request 不批量改写、现有旧任务不因为迁移债务阻塞”的成功标准冲突，会误挡 AM-017 这类仍在收口的旧任务 review_result。
- Required fix:
  - 方案 A：为 `validate-message` 增加可选 `--request-file`，只在该 request `Workflow: superpowers-v1` 时启用双结论硬校验；未传 request 时保留兼容或降级为 warning。
  - 方案 B：要求消息显式携带 `workflow: superpowers-v1` 后才启用双结论校验。
  - 补测试：legacy/non-workflow review_result 可以通过；superpowers review_result 缺规格或代码质量仍失败；AM-20260711-001 自身 review_result 必须通过。
- Verification reviewed:
  - `python3 -m unittest docs.codex_collab.tools.test_team_ops -v` 12 passed。
  - `python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md` OK。
  - `python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md --gate review` OK。
  - `git diff --check` 无输出。

## 2026-07-11 P2 回改

- `validate-message` 新增可选 `--request-file`；只有绑定的 request 标记 `Workflow: superpowers-v1`，或消息显式填写该 workflow 时，才启用 HEAD/测试/自测、双 review 和完成证据门禁。
- 未传 request 上下文的 legacy review_request/review_result 保持原兼容校验，不阻塞 AM-017 等正在收口的旧任务。
- 新增 2 个 legacy 兼容测试，并把新工作流消息测试改为显式传 request context；总计 14 tests passed。
- README、operating-system 和 ai-music-team-ops skill 已同步 `--request-file` 使用方式。

## 2026-07-11 QA Researcher Evidence Gate

- Owner Lane: qa-researcher
- Status: self_tested
- Knowledge Evidence: `docs/codex_collab/knowledge/qa-researcher/2026-07-11-superpowers-qa-evidence-gate.md`
- Scope:
  - 研究/流程资产交付使用 `Research Evidence` 模板，写清 work_type、artifact、source_docs、review_gate、result 和 handoff。
  - Beta、RC、产品验收或 UI 截图巡检使用 `QA Evidence` 模板，必须包含包路径、sha256、versionName/versionCode、commit、设备、动作链、预期/实际、截图、录屏、App 日志、平台日志和诊断路径。
  - `pass/fail/blocker` 判定和 P0-P3 失败升级规则已固定；缺证据时不能写 pass。
- Handoff:
  - 后续 QA/UI 交付前按该模板回传 review gate、清单路径、证据模板和失败升级规则。
  - 真实包验收、Beta、RC 或 `demo_ready` 不允许使用 `--allow-missing-apk` 规避包 sha 和设备 target。

## 2026-07-11 Architect Re-review of P2 Compatibility Fix

- Spec Review Result: accepted
- Code Quality Review Result: changes_requested
- Reviewed:
  - `validate-message` 已支持 `--request-file`，并能只对 `Workflow: superpowers-v1` request 启用 HEAD/测试/自测、双 review 和完成状态证据门禁。
  - legacy review_request/review_result 无 request 上下文时保持兼容。
  - 新增/更新测试已覆盖 legacy 兼容和 superpowers 缺证据失败场景；`python3 -m unittest docs.codex_collab.tools.test_team_ops -v` = 14 tests passed。
- Finding:
  - P2 `docs/codex_collab/tools/team_ops.py:209`：`--request-file` 读取任务单后没有校验消息 `request:` 与 request 文件名或任务单标题是否匹配。调用方可以给 `request: AM-20260711-001` 的消息传入旧 request 文件，从而把 superpowers 消息门禁降级为 legacy；也可能误传别的 superpowers request 导致错误门禁。这使“绑定任务上下文”的 P2 仍未完全关闭。
- Required fix:
  - 当 `--request-file` 存在时，从文件名提取 `AM-...` request id，并校验其等于消息 `request:`；不一致时报错。
  - 补测试：request/message mismatch 必须失败；message/request-file 匹配的 superpowers review_result 仍要求规格符合性和代码质量；legacy 无上下文消息仍兼容通过。
- Verification reviewed:
  - `python3 -m unittest docs.codex_collab.tools.test_team_ops -v` = 14 tests passed。
  - `python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md` = OK。

## 2026-07-11 P2 Request Context Binding 回改

- 新增 `parse_request_id`，从 request 文件一级标题解析真实 requestId。
- `validate-message --request-file` 会校验消息 `request:` 与任务单 requestId 完全一致；不匹配或无法解析时立即失败。
- 显式 `workflow: superpowers-v1` 与 request 文件 workflow 使用 OR 合并，不能再通过传 legacy 文件降低门禁。
- 新增消息/request mismatch 与标题/文件名 mismatch 失败测试；完整测试 16 passed，legacy 无上下文兼容测试和 superpowers 双 review 测试继续通过。

## 2026-07-11 Architect Final Re-review

- Spec Review Result: accepted
- Code Quality Review Result: accepted
- Reviewed:
  - `validate-message --request-file` 会从 request 文件一级标题解析 requestId，并要求文件名前缀、标题 requestId、消息 `request:` 三者一致；不一致时报错。
  - 消息显式 `workflow: superpowers-v1` 与任务单 `Workflow: superpowers-v1` 使用 OR 语义，不能再通过传 legacy 文件降级 superpowers 消息门禁。
  - legacy 无上下文 review_request/review_result 仍保持兼容，不阻塞 AM-017 等未迁移旧任务收口。
  - 新工作流 review_request/review_result 仍强制 HEAD/测试/自测和规格符合性/代码质量双 review 证据。
- Verification:
  - `python3 -m unittest docs.codex_collab.tools.test_team_ops -v` = 16 tests passed。
  - `python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md` = OK。
  - `python3 docs/codex_collab/tools/team_ops.py validate-workflow docs/codex_collab/requests/AM-20260711-001-superpowers-team-workflow.md --gate review` = OK。
  - `git diff --check` = no output。
- Decision:
  - accepted_pending_merge。下一步执行 merge gate，确认提交范围后合入/push 或给唯一 blocker。
