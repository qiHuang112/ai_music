# Agent Lanes

这个文件把长期 Codex 对话登记成固定责任 lane。threadId 就是后续自动投递消息时的路由地址。

所有 lane 默认用中文对话、中文汇报、中文 review。路径、命令、代码符号和固定字段名可以保留英文。

| Lane | 线程标题 | Thread ID | 主要职责 | 可写范围 | 状态 |
| --- | --- | --- | --- | --- | --- |
| product | AIMusic-产品负责人 | `019f4ed4-106e-7860-875d-a32f81629e4e` | 最高优先级产品决策、用户反馈收口、需求澄清、体验验收、后续测试/UI lane 招募。旧线程 `019ee910-8747-71e3-9293-720273f9e61f` 仅作为历史 Source Thread / 归档引用，不作为当前回传入口。 | 产品需求、交互方案、验收标准、优先级、协同账本中的产品记录。默认不直接改业务代码。 | active |
| architect | AIMusic-架构师Reviewer | `019ee4b7-e7d2-7751-a4c4-150ede83c350` | 规划、拆任务、review、验收、跨 lane 冲突裁决。 | 协同账本、review 记录、架构决策。除非用户明确要求，否则不直接实现业务功能。 | idle |
| android | AIMusic-安卓开发 | `019ee41d-647e-7250-bb01-f1ae81098696` | 公共 Dart 业务逻辑、Android 行为、Android 打包发布、测试、Android 架构文档。 | `lib/src/`、`test/`、`android/`、Android 构建工具、公共业务文档。 | idle |
| ios | AIMusic-iOS开发 | `019ee563-42df-7de0-9c64-0a771f243f6a` | iOS 宿主工程、签名、IPA 打包、Apple 平台能力、iOS 文档。 | `ios/`、`tool/build_ios_ipa.sh`、iOS 相关 README。未 handoff 前不要改公共 Dart 业务。 | idle |
| ohos | AIMusic-鸿蒙开发 | `019ee7db-7cfc-7c41-9827-6b851ce89548` | HarmonyOS 宿主、ArkTS 代码、vendored 鸿蒙音频插件、HAP 构建、鸿蒙文档。 | `ohos/`、`third_party/just_audio_harmonyos/`、`tool/build_ohos_hap.sh`、鸿蒙平台适配。 | active |
| ui | AIMusic-UI体验设计 | `019ef1d2-d6ec-79d3-9225-fb4169680228` | 熟悉当前页面、整理 UI 现状、后续参与 UI 样式优化、截图体验和 UI 验收辅助。 | UI 体验报告、截图说明、UI 验收记录、`docs/codex_collab/knowledge/ui/`。未 handoff 前不要直接改业务代码。 | onboarding |

## 知识库

- `product` lane 维护 `docs/codex_collab/knowledge/product/`。
- `architect` lane 维护 `docs/codex_collab/knowledge/architect/`。
- `android` lane 维护 `docs/codex_collab/knowledge/android/`。
- `ios` lane 维护 `docs/codex_collab/knowledge/ios/`。
- `ohos` lane 维护 `docs/codex_collab/knowledge/ohos/`。
- `ui` lane 维护 `docs/codex_collab/knowledge/ui/`。
- 每个 lane 在解决可复用问题后，都要把过程、命令、根因、解决方案和验证方法沉淀到自己的知识库。
- `ohos` lane 处理 HarmonyOS / ArkTS / ArkUI / HAP / `hdc` / AVSession / 鸿蒙音频插件任务前，优先使用本机 `harmonyos-development` skill。

## 边界规则

- `product` lane 是产品意图和优先级最高入口；有需求冲突、体验取舍或验收口径不清时，先回到产品 lane 定方向。
- 公共 Flutter 业务行为默认归 `android` lane，因为当前公共 Dart 产品层由安卓开发维护。
- 平台宿主行为归各平台 lane，除非它改变了公共 Dart API 或跨端用户行为。
- `architect` lane 是默认调度和 review 入口。任何 lane 提交或准备提交后，都要先通知架构师 review。
- 任何 lane 做到“可以体验”的新功能或修复时，都要主动给 `product` lane 发送 `demo_ready` 通知；不要等用户追问进度。
- 架构师 review 通过或判断某个版本可以先体验时，也要把体验入口、平台、验证方式和已知限制同步给 `product` lane。
- 架构师 review 后，要按实际影响范围分类 findings，并只分发给相关 lane。
- 任何 lane 发出任务、review、状态询问或等待对方回应后，10 到 15 分钟没有反馈就主动追问一次，确认对方是否正在工作、卡住或漏回；不要无限被动等待。
- 架构师 lane 对已发出的 review/task/handoff 负有跟进责任，owner lane 长时间不回应时要主动追状态。
- 不允许所有 lane 停住等 product 催。任务未闭环时，owner lane 要主动推进实现/自测/review_request；architect lane 要主动推进 review/合入/推送/装包；遇到阻塞必须发 `blocker`，不能只保持 idle。
- 主目录 `/Users/huangqi/AIHome/ai_music` 只用于 `main` 稳定主线和产品验收；开发 lane 不在主目录日常开发或切分支。
- 架构师负责创建 `release/x.y.z` 和 request worktree，并在任务单里写清 `Target Version`、`Work Branch`、`Worktree Path`、`Base Branch` 和 `Merge Branch`。
- 开发 lane 只在自己分配的 worktree 开发，不复用其它 lane 的 stash，不把未 review 代码合入 release 分支。
- 功能 review accepted 且 owner 自测通过后，架构师可以直接合入目标分支并推送远端；推送后同步 product lane 验证最新包。
- 不涉及 Android/公共 Dart 时不要找 `android` lane；不涉及 iOS 时不要找 `ios` lane；不涉及 HarmonyOS 时不要找 `ohos` lane。
- 鸿蒙默认链路是 `ohos -> architect review -> ohos`，只有 review 发现公共 Dart、Android 或 iOS 影响时才通知其它 lane。
- 某个 lane 需要触碰另一个 lane 的范围时，必须在任务单里记录 handoff，并通知目标 lane。
- `ui` lane 当前只做熟悉、体验和 UI 建议；在 product 明确要求 UI 验收或 UI 开发前，不加入自动化 review 流程。
- `ui` lane 如果需要体验包，应向 product/architect 请求，由 android、ohos 或 ios lane 安装或提供包；优先使用 Android 或 HarmonyOS 体验入口，相关开发忙时可找另一个平台支持。
