# AM-20260718-001 AI Music UI Product Design 优化

Status: historical_fallback
Owner Lane: mobile-ai-music-developer
Assist Lane: mobile-ai-music-product, mobile-ai-music-ux
Source Thread: 019f6b0e-972c-7eb1-91cd-a43cdbfa7d1e
Product Return Thread: 019f6b0e-a150-7892-aec8-d8aa8314d802
Target Version: 1.3.0
Base Branch: release/1.2.0
Work Branch: feature/1.3.0/AM-20260718-001-ui-product-design
Project Path: /Users/huangqi/AIHome/projects/ai_music_AM-20260718-001_ui_product_design
Merge Branch: release/1.3.0
Created: 2026-07-18
Updated: 2026-07-18
Workflow: superpowers-v1
Work Type: feature
Risk Level: P2
User Visible: yes
Design Doc: docs/superpowers/specs/2026-07-18-am001-ui-product-design-requirement.md
UX Brief: docs/superpowers/specs/2026-07-18-am002-ui-product-design.md
Implementation Plan: docs/superpowers/plans/2026-07-18-am002-ui-optimization.md
Required Skills: create-agile-project-team role, product-design:image-to-code, test-driven-development, ai-music, ai-music-team-ops, verification-before-completion
TDD Mode: required
TDD Exception: none
TDD Exception Review: not_applicable
Baseline Commit: 2af08045fa897a26d9fb6cf4b65a23ef0a0c89c3
Head Commit: 2af08045fa897a26d9fb6cf4b65a23ef0a0c89c3 plus unstaged working-tree implementation
Requirement Revision: sha256:84d154ca65202bb56eb828b2473fa3e86bc429edbf7bb1207af80d2d102dbc51 user_approved_from_DISC-0010
UX Revision: visual-set:d2d25d37782fde27c649d08f7df6d9390a0db7a59bc894caa14e463fd2e3dbd3+spec:b1d5c4e71aff2ec89d1186240f7f760f5f83d81020153ccffe86fb3bc392c95f user_approved_three_screen_set
UX User Approval: accepted
Gate 2 Core Experience Approval: ready_for_user_experience pending_user_verdict
Gate 3 UX Approval: accepted_by_user
Development Status: superseded_by_AM-20260726-001_android_native
Discovery Evidence: DISC-0010 product=integrated and ux=integrated; the user-approved three-screen set supersedes the single Library First image, invalid early draft, Search Focus, and style-explorer A/C. DISC-0011 product=integrated and ux=integrated; continuous iteration separates mockup approval from implemented-UI acceptance and routes future business capabilities through product confirmation without stopping compatible development.
Root Cause Evidence: not_applicable_design_task
Research Evidence: home/library/discovery `docs/design/am-20260718-001/approved/user-approved-home-library-discovery.png` sha256 `790007848a9521b7e96ea90b4e08360ee60987f594316b868e79c15dfd6a3d27`; search/results/keyboard `docs/design/am-20260718-001/approved/user-approved-search-results-keyboard.png` sha256 `0013211aaf8110b6a90d4acdd1dd6d8e85e1c98bde543905f8167e88f486bbbb`; full-player/queue `docs/design/am-20260718-001/approved/user-approved-player-queue.png` sha256 `268ef7db1cece8b41f605b2acb7105a83047c33a5ef3dc5ed745f70b5818691b`; approved manifest sha256 `d2d25d37782fde27c649d08f7df6d9390a0db7a59bc894caa14e463fd2e3dbd3`; UX spec sha256 `b1d5c4e71aff2ec89d1186240f7f760f5f83d81020153ccffe86fb3bc392c95f`; developer handoff sha256 `aacfdbf64a8eabb6c42c3dbdb154ec27d7d2772a861870d9055f4163b75d58e7`; package README sha256 `b26d96987c4c32d7fd5fbd4d04ef28562ee35217815249cdcf6b57e4d560affc`; design QA checklist sha256 `c340b1784a59b442cdce0affe4b6e6d36f976757509db7ad144763f013849649`.
Red Evidence: not_applicable_until_implementation
Green Evidence: not_applicable_until_implementation
Targeted Tests: developer 74/74 passed; lead fresh full 312/312 passed and analyze 0 on 2026-07-19
Self Test Evidence: Xiaomi 10 Pro installed debug APK; local APK and freshly pulled device base.apk SHA-256 `b84cf888031134c0016026186f139cee41ccbd7dc360fc2f079359f2c64a8570`; lastUpdateTime `2026-07-19 15:19:10`; Sogou IME preserved.
Product Main Path Evidence: `/Users/huangqi/AIHome/projects/ai_music_AM-20260717-001_multi_source_search_aggregation/evidence/qa-am001-multi-source-20260717/r3-failure-retention-coldplay-clean-32040770.png`; `/Users/huangqi/AIHome/projects/ai_music_AM-20260717-001_multi_source_search_aggregation/evidence/qa-am001-multi-source-20260717/r3-final-empty-32040770.png`
Baseline Freshness Evidence: `origin/release/1.2.0@2af08045fa897a26d9fb6cf4b65a23ef0a0c89c3`; independent clone created at the registered Project Path.
Scope Diff Evidence: pending_design_artifacts_only
Spec Review Result: pending
Code Quality Review Result: pending
Full Verification Evidence: `/Users/huangqi/AIHome/output/AM-20260718-001-demo-ready-20260719-xiaomi10/final-verification`; lead fresh full tests 312 passed, analyze no issues, APK/device SHA matched, and final3 home/search/player/queue screenshots were visually inspected. `design-qa.md` records escaped display text, keyboard inset, and neutral lyrics-state fixes.
Blocking Findings: none_active; prior Flutter UX findings remain historical input for the Android Native Compose slice in AM-20260726-001.
Merge Evidence: pending
Push Evidence: pending
Product Notification Evidence: Validated product handoff sent to the lead return thread on 2026-07-18 with the frozen requirement revision and DISC-0010 evidence paths.
Knowledge Evidence: `docs/superpowers/specs/2026-07-18-am001-ui-product-design-requirement.md`; `docs/codex_collab/knowledge/mobile-ai-music-product/continuous-requirement-iteration-protocol.md`; `docs/codex_collab/knowledge/mobile-ai-music-ux/continuous-iteration-protocol.md`.

## 目标

> 2026-07-26：本 Flutter 任务已由 `AM-20260726-001` Android Native 统一 Epic 替代，只保留设计、测试和回退证据，不再继续实现或形成验收等待链。

- 在保留现有搜索、播放和完整音频业务能力的前提下，基于当前小米 10 Pro 真机效果优化核心使用链路的信息层级、歌曲状态扫描和搜索到播放反馈。
- UX 使用 Product Design 产出可直接交给开发实现和验收的设计修订；设计通过后再拆出开发实现，本任务不抢先改 UI。

## 范围

- 包含：首页与搜索入口、搜索输入、聚合结果列表、mini player、播放详情，以及这些页面之间的现有导航与反馈。
- 包含：搜索初始与输入、首批加载、已有结果继续追加、单来源失败但保留结果、最终无结果、可播放与下载等真实关键状态。
- 包含：以 `release/1.2.0` 可运行页面和小米 10 Pro 截图/XML/logcat 为输入的 Product Design 审计、至少一套主方向设计稿和逐页对照。
- 包含：可实施的视觉 tokens、组件与图标行为、触控区域、安全区、软键盘遮挡、长文本、小屏适配、开发 handoff 和设计 QA 清单。

## 非目标

- 不改变完整音频准入、来源选择与熔断、搜索匹配与分页数量、缓存、下载、边下边播、seek、歌词或播放队列业务规则。
- 不新增来源设置、来源标签、播放模式或与当前核心链路无关的新页面和功能。
- 不由产品预设配色、排版或组件形态；具体视觉方向由 UX 基于真实审计使用 Product Design 决定。
- 本任务不包含 Flutter 业务实现、安装包交付、stage、commit、merge 或 push。
- 不回滚或重开已合入的 AM-20260717-001。

## 验收标准

1. UX 审计明确引用当前真机截图、可运行页面及对应 XML/logcat，指出可复核的层级、扫描、反馈或适配问题，不以泛化竞品建议代替真实现状。
2. 交付至少一套完整主方向设计稿，并对首页/搜索入口、搜索结果、mini player 和播放详情给出当前态与目标态逐页对照，核心路径可以连续评审。
3. 搜索首批加载、已有结果追加、单来源失败保留结果、最终空态和播放中状态均有明确视觉与交互定义；状态切换不隐藏已有可用结果，也不改变现有业务判定。
4. 设计规范明确间距、字号、色彩、组件、图标、最小触控区域、安全区、软键盘、长文本和小屏约束，开发无需猜测关键尺寸或状态行为。
5. UX 回传设计稿路径、UX revision/hash、开发 handoff 和设计 QA 清单；负责人确认设计符合本 requirement 后，才进入后续实现工作项。

## 工作流边界

- DISC-0010 是本任务的最新用户输入；产品与 UX 在各自下一轮必须读取并以证据 acknowledge。
- 产品只收敛用户目标、非目标和至多五条验收，不替 UX 输出视觉稿。
- UX 是当前 owner，必须显式使用 Product Design；可读取并操作注册 Project Path，但不得 stage、commit 或 push。
- 设计稿 UI 验收与真实落地 UI 验收是两道不同门：前者冻结可实施视觉、交互和状态规范；后者以小米 10 Pro 最新安装包的真实页面、关键状态和用户 Gate 2 体验结论为准。设计稿获批不等于真实 UI 已验收，反之真实 UI 也不得偏离冻结业务边界。
- 产品和 UX 每轮先读取直接用户与开发沟通的 discovery；最新明确用户意图合并到 requirement/UX revision 与验收，冲突的旧意图明确 superseded。无新意图时不因文档或阶段结论暂停开发。
- 开发在冻结 requirement/UX revision 兼容范围内持续推进、修复和采证；只有新的业务规则、超出批准视觉目标的体验变化或需要重新用户验收的冲突才触发 revision 重绑或用户澄清。普通文档补充、设计 QA 回改和非阻塞边角项不构成停工理由。
- UX 可以提出当前尚未具备的未来能力，但必须标注为提案及其依赖，不能伪装成当前可用控件。涉及业务规则、权限、数据来源、搜索、缓存、播放、下载或队列契约的提案先进入产品需求确认并更新验收；纯视觉与现有能力交互增量继续并行。

## 消息记录

- 2026-07-18 type=status lane=mobile-ai-music-developer status=review_requested summary=用户确认 AM-20260717-001 可提交，并新增 DISC-0010，要求 UX 使用 Product Design 基于真机效果产出优化稿，再交开发实现。
- 2026-07-18 type=status lane=mobile-ai-music-lead status=proposed summary=AM-20260717-001 已先行 accepted、merged、pushed；新增 UI 范围另立 AM-20260718-001，不回滚旧单。
- 2026-07-18 type=handoff lane=mobile-ai-music-product status=proposed summary=Product integrated DISC-0010，并冻结一页需求 R1 与 5 条验收；要求 UX Product Design revision 绑定该 requirement，设计 accepted 后再派开发实现。
- 2026-07-18 type=status lane=mobile-ai-music-ux status=in_progress summary=UX revision 2bfbdad3 已提交用户设计评审；用户是第一审核人，当前未批准，负责人不得触发开发派工或实现。
- 2026-07-18 type=status lane=mobile-ai-music-lead status=in_progress summary=流程按 create-agile-project-team 当前状态机更正：Gate 2 核心体验和 Gate 3 UX 均由用户本人把关；负责人不得代签。UI 方向冻结后的普通 bug、边角状态和小 UI 调整由团队自动闭环，重大业务或 UX 变更才返回对应用户 Gate。
- 2026-07-19 type=status lane=mobile-ai-music-ux status=ux_user_approved summary=用户批准旧绘画线程原图为唯一 canonical visual target，SHA-256 为 14e19e2a；style-explorer A/C 与旧 mockups 均 superseded。
- 2026-07-19 type=review_result lane=mobile-ai-music-lead status=accepted summary=可实施性 review accepted；按 R1 排除批准图中新增底部导航/页面，只实现视觉语言和现有业务入口，开发进入 core_in_progress。
- 2026-07-19 type=status lane=mobile-ai-music-ux status=correction summary=call_Bx/019ef1d2 经历史追溯确认为无效早期草稿；正式用户批准方向更正为 Library First，visual SHA-256 为 3bfdf0ee，旧目标与旧负责人 review 结论均 superseded。
- 2026-07-19 type=review_result lane=mobile-ai-music-lead status=accepted summary=更正后的 Library First visual、UX spec 与 handoff SHA 已核验；authorization 重新绑定 3bfdf0ee，开发可按最终冻结包恢复实现。
- 2026-07-19 type=status lane=mobile-ai-music-ux status=user_approved_revision_supersedes_previous summary=用户明确要求三张 Product Design 效果图成套实现；单张 Library First 授权及所有更早目标失效。
- 2026-07-19 type=review_result lane=mobile-ai-music-lead status=accepted summary=三图 approved manifest d2d25d37 与 UX spec b1d5c4e7 已核验并重新绑定 Gate 3；仅实现现有业务能力对应的视觉与交互，不新增图中未批准的路由、分类过滤、歌词翻译或停止业务规则。
- 2026-07-19 type=demo_ready lane=mobile-ai-music-lead status=ready_to_try summary=三图 UI 80% 包已 preserve-data 安装小米 10 Pro；负责人 fresh 311 tests、analyze、APK/device SHA 和四页真机证据复核通过，Gate 2 等待用户本人体验结论。
- 2026-07-19 type=demo_ready lane=mobile-ai-music-lead status=ready_to_try summary=更新包修复文字转义、键盘遮挡 mini player 和歌词错误暴露；负责人 fresh 312 tests、analyze、final3 截图及 b84cf888 APK/device SHA 复核通过，本条 supersedes 上一体验包。
- 2026-07-19 type=review_result lane=mobile-ai-music-ux status=changes_requested summary=final3 Design QA 提出 DQ-01 至 DQ-04 四组 P1、语义本地化和 coherent DQ-10；负责人核验视觉偏差成立并合并为一次回改。队列清空/删除/重排无现有 handler API，按冻结非业务范围不实现虚假控件，作为最小 UX 边界冲突单独校正。
- 2026-07-19 type=status lane=mobile-ai-music-ux status=accepted summary=DQ-04 supported-controls 口径已校正；clear/remove/row-menu/reorder 从本轮 P1 撤下，DQ-04 仅保留现有能力支持的封面、当前播放指示和行层级，冻结 requirement/UX revision 不变。

## Review 结果

- Reviewer Lane: mobile-ai-music-lead
- Result: pending
- Spec Findings: pending
- Code Quality Findings: not_applicable_design_only
- Notes: 设计 accepted 仅冻结 UX revision，不自动表示 Flutter 实现完成。
