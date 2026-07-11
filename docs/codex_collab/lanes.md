# Agent Lanes

这个文件把长期 Codex 对话登记成固定责任 lane。threadId 就是后续自动投递消息时的路由地址。

所有 lane 默认用中文对话、中文汇报、中文 review。路径、命令、代码符号和固定字段名可以保留英文。

| Lane | 线程标题 | Thread ID | 主要职责 | 可写范围 | 状态 |
| --- | --- | --- | --- | --- | --- |
| product | AIMusic-产品负责人 | `019f4ed4-106e-7860-875d-a32f81629e4e` | 最高优先级产品决策、用户反馈收口、需求澄清、体验验收、后续测试/UI lane 招募。旧线程 `019ee910-8747-71e3-9293-720273f9e61f` 仅作为历史 Source Thread / 归档引用，不作为当前回传入口。 | 产品需求、交互方案、验收标准、优先级、协同账本中的产品记录。默认不直接改业务代码。 | active |
| architect | AIMusic-架构师Reviewer | `019ee4b7-e7d2-7751-a4c4-150ede83c350` | 规划、拆任务、review、验收、跨 lane 冲突裁决。 | 协同账本、review 记录、架构决策。除非用户明确要求，否则不直接实现业务功能。 | idle |
| android | AIMusic-安卓开发 | `019ee41d-647e-7250-bb01-f1ae81098696` | 公共 Dart 业务逻辑、Android 行为、Android 打包发布、测试、Android 架构文档。 | `lib/src/`、`test/`、`android/`、Android 构建工具、公共业务文档。 | idle |
| android-source | AI Music-安卓歌源修复开发 | `019f2fef-a4bb-7891-98b6-5f8b0bf3b17b` | AM-20260705-009 歌源下载失败分类、URL 类型校验和短超时 fallback。 | 迁移到独立仓库/工程目录；旧 `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260705-009` 只可作为取补丁来源，合入前必须在最新主线独立工程重放。 | active |
| android-streaming | AI Music-安卓边下边播 PoC 开发 | `019f2fef-a708-75d1-9495-ffe6ae9883b4` | AM-20260705-006 本地 Range 代理/渐进缓存 PoC。 | 迁移到独立仓库/工程目录；旧 `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260705-006` 只可作为取补丁来源。 | active |
| android-discovery | AI Music-安卓热榜发现开发 | `019f2fef-a95e-7362-97a0-3b18f319acf1` | AM-20260705-007 热榜发现入口、provider、缓存和 UI 入口。 | 迁移到独立仓库/工程目录；旧 `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260705-007` 只可作为取补丁来源。 | active |
| android-voice | AI Music-安卓语音入口开发 | `019f2fef-aba0-7981-8a3c-1217f3bf0ad1` | AM-20260705-008 Android `MEDIA_PLAY_FROM_SEARCH` 与 DeepLink 指定播放入口。 | 迁移到独立仓库/工程目录；旧 `/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260705-008` 只可作为取补丁来源，合入前必须基于最新主线重建。 | active |
| ios | AIMusic-iOS开发 | `019ee563-42df-7de0-9c64-0a771f243f6a` | iOS 宿主工程、签名、IPA 打包、Apple 平台能力、iOS 文档。 | `ios/`、`tool/build_ios_ipa.sh`、iOS 相关 README。未 handoff 前不要改公共 Dart 业务。 | idle |
| ohos | AIMusic-鸿蒙开发 | `019ee7db-7cfc-7c41-9827-6b851ce89548` | HarmonyOS 宿主、ArkTS 代码、vendored 鸿蒙音频插件、HAP 构建、鸿蒙文档。 | `ohos/`、`third_party/just_audio_harmonyos/`、`tool/build_ohos_hap.sh`、鸿蒙平台适配。 | active |
| ui | AIMusic-UI体验设计 | `019ef1d2-d6ec-79d3-9225-fb4169680228` | 熟悉当前页面、整理 UI 现状、后续参与 UI 样式优化、截图体验和 UI 验收辅助。 | UI 体验报告、截图说明、UI 验收记录、`docs/codex_collab/knowledge/ui/`。未 handoff 前不要直接改业务代码。 | onboarding |
| qa | AIMusic-QA验证 | `pending_thread` | Beta 包安装、验收清单真机验证、截图/录屏/日志采集、pass/fail/blocker 回传。 | `docs/codex_collab/knowledge/qa/`、QA 验证记录、Beta 证据目录。不得改业务代码、不得合并推送。 | pending_thread |
| release-manager | AIMusic-发布经理 | `pending_thread` | accepted 后的合入、构建、推送、tag、包 sha/manifest 归档、demo_ready 通知和发布脚本维护。 | `tool/` 发布脚本、`docs/codex_collab/changes.md`、`versions.md`、release 证据。不得替 owner lane 修业务 bug。 | pending_thread |
| source-researcher | AI music-歌源研究员 | `019f2fdd-d8c5-7cf2-9b19-20c4856b466f` | `buguyy.top`、`flac.music.hi.cn` 等歌源搜索、解析、下载、歌词和封面链路调研；先脚本跑通，再沉淀 skill，再交客户端落地。 | `docs/codex_collab/knowledge/source-researcher/`、调研脚本方案、skill 草案和协议报告。不得直接改客户端业务代码。 | active |
| playlist-researcher | AI music-歌单推荐研究员 | `019f2fdd-da9b-79f0-b804-4e7790f213fa` | 网易云、QQ 音乐或替代公开来源的热榜/歌单推荐可用性调研，输出客户端推荐页方案和风险。 | `docs/codex_collab/knowledge/playlist-researcher/`、榜单来源调研报告和字段样例。不得直接改客户端业务代码。 | active |
| streaming-researcher | AI music-边下边播研究员 | `019f2fdd-dcdf-7e82-8698-94ec57d4d0c7` | Flutter、Android、HarmonyOS 边下边播能力调研，覆盖 HTTP range、临时文件、缓存一致性和播放器兼容。 | `docs/codex_collab/knowledge/streaming-researcher/`、验证脚本、技术方案和风险清单。不得直接改客户端业务代码。 | active |
| xiaoai-researcher | AI music-小爱同学研究员 | `019f2fdd-df14-7420-b468-5dd2f02d5596` | 小米小爱同学唤醒第三方 App、语音意图、播放指定歌曲/歌单接入路径调研。 | `docs/codex_collab/knowledge/xiaoai-researcher/`、官方文档依据、接入限制和 Android 落地方案。不得直接改客户端业务代码。 | active |
| qa-researcher | AI music-QA流程研究员 | `019f2fdd-e1e5-79c2-8a19-dd385fd20398` | 完整产品回归清单、自动化/半自动化验证路径、UI 截图巡检和日志证据模板调研。 | `docs/codex_collab/knowledge/qa-researcher/`、回归清单、证据模板和 UI 巡检路径。不得改业务代码。 | active |

## 知识库

- `product` lane 维护 `docs/codex_collab/knowledge/product/`。
- `architect` lane 维护 `docs/codex_collab/knowledge/architect/`。
- `android` lane 维护 `docs/codex_collab/knowledge/android/`。
- `android-source`、`android-streaming`、`android-discovery`、`android-voice` 的可复用经验统一沉淀到 `docs/codex_collab/knowledge/android/`，并注明具体 request/thread。
- `ios` lane 维护 `docs/codex_collab/knowledge/ios/`。
- `ohos` lane 维护 `docs/codex_collab/knowledge/ohos/`。
- `ui` lane 维护 `docs/codex_collab/knowledge/ui/`。
- `qa` lane 维护 `docs/codex_collab/knowledge/qa/`。
- `release-manager` lane 维护 `docs/codex_collab/knowledge/release-manager/`。
- 各研究员 lane 分别维护自己的 `docs/codex_collab/knowledge/<researcher-lane>/`。
- 每个 lane 在解决可复用问题后，都要把过程、命令、根因、解决方案和验证方法沉淀到自己的知识库。
- `ohos` lane 处理 HarmonyOS / ArkTS / ArkUI / HAP / `hdc` / AVSession / 鸿蒙音频插件任务前，优先使用本机 `harmonyos-development` skill。

## 边界规则

- 全员从 2026-07-11 起按 `Workflow: superpowers-v1` 执行新任务：功能先设计/计划，Bug 先根因调试，代码改动默认 TDD，review 分规格符合性和代码质量两步，完成声明先做新鲜验证。
- 每个 lane 开工前先读取 `/Users/huangqi/.codex/skills/using-superpowers/SKILL.md` 和任务类型对应 skill；AI Music 项目规则与上游 skill 冲突时，以 `docs/codex_collab/operating-system.md` 为准。
- `using-git-worktrees` 不用于 AI Music；所有开发 lane 继续使用各自独立仓库/工程 `Project Path`。
- Architect 在 `design/start/review/merge/close` 五个节点运行 `team_ops.py validate-workflow`；开发 lane 至少在开工和发 `review_request` 前运行对应门禁。
- `product` lane 是产品意图和优先级最高入口；有需求冲突、体验取舍或验收口径不清时，先回到产品 lane 定方向。
- 公共 Flutter 业务行为默认归 `android` lane，因为当前公共 Dart 产品层由安卓开发维护。
- 平台宿主行为归各平台 lane，除非它改变了公共 Dart API 或跨端用户行为。
- `architect` lane 是默认调度和 review 入口。任何 lane 提交或准备提交后，都要先通知架构师 review。
- 任何 lane 做到“可以体验”的新功能或修复时，都要主动给 `product` lane 发送 `demo_ready` 通知；不要等用户追问进度。
- 架构师 review 通过或判断某个版本可以先体验时，也要把体验入口、平台、验证方式和已知限制同步给 `product` lane。
- 架构师 review 后，要按实际影响范围分类 findings，并只分发给相关 lane。
- 每个任务必须有唯一 owner lane；协作 lane 只能辅助，不能让责任在多个 lane 之间漂移。
- owner lane 对任务闭环负责：实现、自测、证据、`review_request`、回改和最终同步都不能只停在状态汇报。
- owner lane 日常开发自测优先跑 targeted tests、局部 `analyze` 或必要设备验证；只有准备发架构师 review、合入/发版，或改动触及高风险共享链路时，才默认跑全量测试。
- 任何 lane 发出任务、review、状态询问或等待对方回应后，10 到 15 分钟没有反馈就主动追问一次，确认对方是否正在工作、卡住或漏回；不要无限被动等待。
- 发给其它 lane 的消息必须写清回传契约：谁做、做什么、完成后回给谁、带什么证据。
- 架构师 lane 对已发出的 review/task/handoff 负有跟进责任，owner lane 长时间不回应时要主动追状态。
- 不允许所有 lane 停住等 product 催。任务未闭环时，owner lane 要主动推进实现/自测/review_request；architect lane 要主动推进 review/合入/推送/装包；遇到阻塞必须发 `blocker`，不能只保持 idle。
- 产品体验细节、小修小改默认进入迭代或回改队列，不能成为开发 lane 停工理由；只有 P0/P1、架构风险、数据风险或发布风险可以阻塞主流程。
- 架构师可以临时兜底 P0/P1，但不能长期替开发 lane 实现；兜底完成后必须把维护权、复盘和后续任务交回对应 owner。
- 所有 lane 必须控制 token 成本：稳定事实写入任务单或知识库，线程消息只写新增事实、当前判断和下一步；不广播无关 lane。
- 主目录 `/Users/huangqi/AIHome/ai_music` 只用于 `main` 稳定主线、账本和产品验收；开发 lane 不在主目录日常开发或切分支。
- 新任务不再使用 `git worktree` 做并行开发；架构师负责创建或指定独立仓库/工程目录，并在任务单里写清 `Target Version`、`Work Branch`、`Project Path`、`Base Branch` 和 `Merge Branch`。
- 开发 lane 只在自己分配的独立工程目录开发，不复用其它 lane 的 stash、构建产物、依赖缓存或安装包，不把未 review 代码合入 release 分支。
- 每次开工、review、合入前，开发 lane 必须先整合最新 `origin/main` 或目标 release 已合入内容，防止漏功能和回退已合入体验。
- 功能 review accepted 且 owner 自测通过后，架构师可以直接合入目标分支并推送远端；推送后同步 product lane 验证最新包。
- 不涉及 Android/公共 Dart 时不要找 `android` lane；不涉及 iOS 时不要找 `ios` lane；不涉及 HarmonyOS 时不要找 `ohos` lane。
- 鸿蒙默认链路是 `ohos -> architect review -> ohos`，只有 review 发现公共 Dart、Android 或 iOS 影响时才通知其它 lane。
- 某个 lane 需要触碰另一个 lane 的范围时，必须在任务单里记录 handoff，并通知目标 lane。
- `ui` lane 当前只做熟悉、体验和 UI 建议；在 product 明确要求 UI 验收或 UI 开发前，不加入自动化 review 流程。
- `ui` lane 如果需要体验包，应向 product/architect 请求，由 android、ohos 或 ios lane 安装或提供包；优先使用 Android 或 HarmonyOS 体验入口，相关开发忙时可找另一个平台支持。
- `qa` lane 只接收 Beta 或 release candidate 验证任务。每次回传必须包含包 sha、versionCode、设备 target、验收清单结果、失败复现步骤、截图/录屏/日志路径。
- 小米 10 Pro 默认由 Android 开发和 QA 共享：Android 正在调试时设备归 Android；Beta 包已安装或 Android 空闲时交给 QA 验证。冲突由 architect 裁决。
- 小米 10 Pro 日常 Android 调试默认使用 debug 包；若 release 包或异签名旧包影响验证，Android owner 记录测试目的和清数据影响后可卸载旧包再装 debug 包，不为同签覆盖反复阻塞。release 包只用于发版收口或 product/architect 明确要求的验收。
- `release-manager` lane 在 architect accepted 后接手流水线，不替 owner 修业务；构建、证据或测试缺口必须回 owner lane，并写清完成后回 release-manager 的证据。
- 研究员 lane 负责调研、脚本验证、skill/方案沉淀和风险判断；默认不直接改客户端业务代码、不抢开发 lane owner。
- 研究任务可以并行启动，不等待 P1 bug 全部修完；但外部资源调研必须低频串行、避免高并发压测第三方服务。
- 研究员给出 accepted 方案后，由 architect 分配给 android、ohos、ios、ui、qa 或 release-manager 落地；研究员不绕过 review 直接合入。

## 团队操作系统

- 2026-06-25 起，全员执行 `docs/codex_collab/operating-system.md`。
- 这份规则优先级高于临时聊天习惯：没有唯一 owner、没有 next_action、没有回传证据的任务消息，都视为不完整。
- 架构师负责巡检执行情况；各开发 lane 不因为等待、体验小改或产品未追问而停止推进。
