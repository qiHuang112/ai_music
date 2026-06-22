# 主动追问规则

## 背景

协同过程中，架构师或某个 lane 发出 `review_request`、`review_result`、`task`、`handoff`、`status` 询问后，如果只被动等待，对方漏看或卡住时任务会静默停住。AM-20260622-002 review 中已经出现过 review 结论没有及时回到 android lane 的问题。

## 规则

- 发出任务、review、状态询问或等待某个 lane 回应后，10 到 15 分钟没有反馈，应主动追问一次。
- 追问内容要短，只确认对方是否正在工作、是否卡住、是否漏回消息。
- 追问只发给相关 lane，不广播无关 lane。
- 如果当前环境没有线程投递工具，要在当前会话明确输出可转发消息，并在后续可投递时补发。
- 架构师发出 review 后，要把 review 结果主动回传给 owner lane，不能只更新账本或只回复产品会话。

## 推荐消息

```text
type: status
request: AM-YYYYMMDD-NNN
lane: <target-lane>
thread: <target-thread-id>
status: in_progress
summary: 我这边在等待你对上一条 review/task/status 的反馈，已超过 10 到 15 分钟。请确认是否正在处理、是否卡住或是否漏回。
next_action: 如果正在处理，请回报当前进展和预计下一步；如果卡住，请说明 blocker；如果已完成，请发 review_request/status。
```
