# Superpowers QA 验收证据门禁

Request: AM-20260711-001
Lane: qa-researcher
Thread: 019f2fdd-e1e5-79c2-8a19-dd385fd20398
Created: 2026-07-11
Status: active

## 目标

把 QA/UI 验收从“我装了、我试了、看起来通过”改成可重复执行、可复核、可升级的证据包。任何声明“验证完成、测试通过、可体验、可发布”之前，都必须能回答：

- 验的是哪个包：包路径、sha256、versionName/versionCode、commit 或 tag。
- 在哪台设备验：平台、型号、deviceId、系统版本、网络和音源前置。
- 做了什么动作：从哪个入口开始，点击/输入/等待/切换了什么。
- 预期是什么：产品口径或任务验收标准对应的结果。
- 实际是什么：用户可见结果、日志结果、系统播控或缓存状态。
- 证据在哪里：截图、录屏、App 日志、平台日志、诊断目录。

只写“已安装”“测试通过”“截图见附件”“功能 OK”不算有效验收。

## QA Review Gate

QA 或 UI 交付验收结论前，先自查下面的 gate。缺任一项时，结论只能是 `blocked` 或 `partial`，不能写 `pass`。

| Gate | 必填内容 | 不合格示例 |
| --- | --- | --- |
| 包证据 | `package`、`sha256`、`versionName/versionCode`、`commit` | 只写“已安装最新版” |
| 设备证据 | `platform`、`device`、`deviceId`、系统版本、网络/音源前置 | 只写“安卓真机” |
| 动作链 | 入口、动作、数据、等待时间、结束条件 | 只写“试了搜索播放” |
| 预期/实际 | 每一步的 expected 和 actual | 只写“正常” |
| 可见证据 | 关键页面截图；动态链路录屏 | 只有文字描述 |
| 日志证据 | App 日志；Android `logcat/dumpsys` 或 HarmonyOS `hilog/hidumper` | 失败但无日志 |
| 结论 | `pass`、`fail`、`blocker` 三选一，并写原因 | “基本可以” |
| 回传路径 | 回给哪个 lane、谁处理下一步、带什么证据 | “继续跟进” |

## Research Evidence 模板

研究型 QA 资产或清单交付时使用。它不要求真实包 sha，但必须说明这是 `research/process`，并给出依据和可执行模板路径。

```text
Research Evidence
request: AM-YYYYMMDD-NNN
lane: qa-researcher
work_type: research|process
artifact:
source_docs:
- docs/codex_collab/operating-system.md
- docs/superpowers/specs/2026-07-11-ai-music-team-workflow-design.md
review_gate:
- validate-message: pass|fail + 命令/输出摘要
- review-evidence: pass|fail|not_applicable + 原因
result:
handoff:
```

## 真机验收证据模板

Beta、RC、产品验收或 UI 截图巡检统一使用下面字段。字段可以扩展，但不能删掉包、设备、动作、预期、实际和证据路径。

```text
QA Evidence
request:
related_request:
platform: Android|HarmonyOS|iOS|macOS
package:
sha256:
versionName:
versionCode:
commit:
build_type: debug|beta|release|hap|ipa
device:
deviceId:
os_version:
network:
music_source_url:
tester:
test_time:

scenario:
preconditions:
steps:
  1. action:
     expected:
     actual:
     evidence:
  2. action:
     expected:
     actual:
     evidence:

result: pass|fail|blocker
failure_level: P0|P1|P2|P3|none
screenshots:
recordings:
app_logs:
platform_logs:
diagnostics_path:
notes:
next_action:
```

## 可重复清单写法

每个验收场景写成表格，避免把自然语言体验感受当作测试步骤。

| 字段 | 写法 |
| --- | --- |
| 场景 | 用户目标，例如“从热榜播放一首歌” |
| 前置 | 包、设备、账号/权限、网络、缓存状态、音乐源 |
| 动作 | 可重复的点击/输入/等待步骤 |
| 预期 | 任务单或产品口径里的可观察结果 |
| 实际 | 真机看到的 UI、播放器、系统播控、文件或日志状态 |
| 证据 | 截图、录屏、日志和诊断目录 |
| 判定 | `pass/fail/blocker` |

示例：

| 场景 | 前置 | 动作 | 预期 | 实际 | 证据 | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| 下载后立即播放 | Android Beta 包已安装，网络可用，目标歌未缓存 | 搜索歌曲，点击结果行，等待下载完成并自动播放 | 播放页和 mini player 显示同一歌曲，系统 media session 为 playing，缓存索引写入音频 | `<填写真机结果>` | `<截图/录屏/logcat/诊断路径>` | pass/fail/blocker |

## 截图/录屏/日志字段

- 截图命名：`<request>_<platform>_<page>_<state>_<step>.png`
- 录屏命名：`<request>_<platform>_<scenario>_<result>.mp4`
- App 日志：包含 `resolver`、`metadata`、`playback`、`download`、`cache`、`mediaSession`、`uiAction`、`platformBridge`。
- Android 平台日志：失败时至少提供 `logcat`；播控类提供 `dumpsys media_session`。
- HarmonyOS 平台日志：失败时至少提供 `hdc hilog`；播控类提供 `hidumper -s AVSessionService` 的 session/controller 关键字段。
- 诊断目录：建议放在 `artifacts/<request>/<platform>/<yyyyMMdd-HHmm>/` 或任务单指定目录。

## pass / fail / blocker 判定

- `pass`：动作链全部执行，预期和实际一致，截图/录屏/日志能支撑结论。
- `fail`：包能安装、场景能执行，但实际行为不符合预期；必须给稳定复现步骤、失败级别和证据路径。
- `blocker`：无法完成验证或主流程不可继续，例如包无法安装、启动崩溃、设备锁定且无替代设备、音源服务不可达、系统权限/签名阻塞、核心入口缺失。

不能把 `blocker` 写成“测试失败”。`blocker` 的 next_action 必须写清谁解锁前置条件、解锁后回给谁、带什么证据。

## 失败升级规则

- P0：启动崩溃、包不可安装、主流程全断、数据破坏、无法回退；立即回 architect、owner lane 和 product。
- P1：搜索/下载/播放/歌词/封面/播控中心核心链路不可用；回 architect 和对应 owner lane，product 同步风险。
- P2：明确功能缺陷但有绕行路径，例如状态刷新延迟、单个入口失败、截图/UI 状态误导；回 owner lane 和 architect。
- P3：文案、对齐、截图美观、非阻断体验建议；回 UI/product 进入后续优化队列。

升级消息必须包含：包 sha、设备、动作、预期、实际、截图/录屏/日志路径和建议 owner。没有证据时先补证据，不要先广播结论。

## 交付前命令

研究或流程资产交付前至少运行：

```bash
python3 docs/codex_collab/tools/team_ops.py validate-message --file /tmp/ai-music-message.txt
python3 tool/check_review_evidence.py --allow-missing-apk /tmp/ai-music-review-evidence.txt
```

真实包验收、Beta、RC 或 `demo_ready` 交付前不允许使用 `--allow-missing-apk`，必须提供包 sha 和设备 target。
