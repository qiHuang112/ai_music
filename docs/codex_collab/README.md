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
11. 功能闭环后由负责人 lane 或架构师直接推送远端，不再等产品会话单独确认。

## 闭环推送规则

- 功能闭环定义：实现完成、必要测试通过、架构师 review accepted、体验包已安装或验证入口已明确、没有 blocker。
- 满足闭环条件后，owner lane 应直接把对应提交推送到远端；如果 owner lane 没有推送能力或发现分支/远端冲突，架构师负责协调并推动。
- 推送前必须确认提交范围只包含本 request 的改动，不能混入其它 lane 的脏改、临时构建产物或未验收改动。
- 推送成功后更新 `changes.md` 和任务单状态，并给 product lane 发送 `status` 或 `demo_ready`，写清楚最终 commit、远端分支和体验状态。
- 如果推送失败，按 blocker 回报具体原因，例如认证失败、远端有新提交、rebase 冲突或网络不可达。

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

## Review 分发规则

- 有人提交或准备提交后，owner lane 必须给架构师发送 `review_request`。
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
- 如果 review 有问题，架构师要给对应 lane 发送 `review_result` 或 `task`，写清楚 priority、文件位置、问题原因和期望修复。
- 开发 lane 修完后，再次请求架构师 review，直到 `accepted`。

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
lane: product|android|ios|ohos|architect
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

## Commit Trailer

AI Music 的提交如果和某个任务有关，提交信息里要加责任归属 trailer：

```text
Request: AM-YYYYMMDD-NNN
Lane: android|ios|ohos|architect
Thread: <codex-thread-id>
Reviewed-by-lane: architect|android|ios|ohos|none
```

只有很小的文档或账本维护改动，才可以使用 `Reviewed-by-lane: none`。
