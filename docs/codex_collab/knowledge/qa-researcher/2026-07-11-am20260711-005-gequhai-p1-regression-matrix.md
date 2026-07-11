# AM-20260711-005 歌曲海完整搜索/下载/边下边播 P1 回归矩阵

Request: AM-20260711-005
Workflow: superpowers-v1
Lane: qa-researcher
Thread: 019f2fdd-e1e5-79c2-8a19-dd385fd20398
Created: 2026-07-11
Status: waiting_for_android_apk_and_evidence
Work Type: qa_matrix

## 目标

为 AM-005 准备可重复、可复核的产品验收矩阵。Product 只接受完整能播资源；`PREVIEW`、`试听`、`30s`、网盘、HTML、防护页、低置信候选、非音频响应和未验证 Range 的资源都不能当作完成。

QA 收到 Android APK 后，逐项复核：

- 包路径、sha256、versionName/versionCode、commit、Project Path、baseline。
- 设备 target、系统版本、网络、音乐源设置、缓存前置。
- 搜索结果是否只展示歌曲海完整可播放候选。
- 点击结果是否边下边播，且首声早于完整下载完成。
- 下载按钮是否只下载，不误触播放。
- seek 到已下载区和未下载区时的播放、buffering、Range 行为。
- 正式缓存转正是否只发生在完整验证通过后。
- HTTP 失败样例是否 fail closed，且不写正式缓存。
- 截图、录屏、logcat/dumpsys、App 诊断、cache 文件和 `_cache_index.json` 是否互相一致。

## 当前等待项

Android owner 需先提供：

```text
Project Path:
baseline:
HEAD:
package:
sha256:
versionName/versionCode:
device target:
deviceId:
osVersion:
network:
musicSource:
evidence directory:
diagnostics/log path:
```

如果 Android 10 到 15 分钟内未提供 APK 或证据目录，QA 不继续空等，应回 product/architect 催 owner 补齐 `package/sha/device/evidence directory`。

## 证据目录与命名

推荐目录：

```text
artifacts/AM-20260711-005/
  android/
    xiaomi10/
      manifest.txt
      screenshots/
        00_package_device/
        01_search_full_audio/
        02_download_only/
        03_progressive_playback/
        04_seek_range/
        05_cache_promotion/
        06_http_failure_fail_closed/
      recordings/
      logs/
        app/
        logcat/
        dumpsys_media_session/
      cache/
        before/
        during/
        after/
      diagnostics/
      per_case.tsv
```

截图命名：

```text
AM-20260711-005_android_xiaomi10_<song_slug>_<scenario>_<state>_<step>.png
```

录屏命名：

```text
AM-20260711-005_android_xiaomi10_<scenario>_<song_slug>_<result>.mp4
```

`manifest.txt` 必填：

```text
request: AM-20260711-005
package:
sha256:
versionName:
versionCode:
commit:
projectPath:
baseline:
device:
deviceId:
osVersion:
network:
musicSource:
tester:
testTime:
diagnosticsPath:
cacheBeforePath:
cacheAfterPath:
```

## 必测样例矩阵

| 样例 | 搜索词 | 目标 | 必填候选/source | 必填播放/下载证据 | 必填缓存/日志证据 | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| 剩下的果实 | `剩下的果实` | 验证完整搜索与低频候选选择 | title、artist、playId/detailUrl、source=`source_gequhai`、confidence、sourceAttempt | 搜索截图/XML；点击后播放页/mini player/media session；如无完整候选，必须 empty/fail reason | provider chain、HEAD/Range、cache index 或 no-cache reason | pass/fail/blocker |
| 周杰伦 | `周杰伦` | 艺人泛搜不能把低置信行当完成 | 所有可见行必须可完整播放；记录被过滤的低置信/非歌曲原因 | 搜索结果截图/XML，不能出现 PREVIEW/网盘/HTML 完成路径 | filtered reasons、无正式缓存污染 | pass/fail/blocker |
| 周杰伦的外婆 | `周杰伦的外婆` | 自然语言 query 仍命中 `外婆 / 周杰伦` 或结构化空态 | candidate 必须 title=`外婆`、artist=`周杰伦`，或明确 no_match | 搜索、播放、media session、歌词/封面可见 | sourceAttempt、first_byte_ms、download_complete_ms、cache index | pass/fail/blocker |
| 黄蓉的哎呀 | `黄蓉的哎呀` | 错艺人/歧义 query 不能误判王蓉为黄蓉精确匹配 | 若展示 `哎呀 / 王蓉`，必须标明非精确/由用户确认；自动完整播放需满足产品允许口径 | 搜索结果与点击行为录屏；低置信不得自动写正式缓存 | low_confidence_match 或 user_confirmed evidence | pass/fail/blocker |
| 外婆 | `外婆` | 正向完整能播主路径 | `外婆 / 周杰伦 / play/6330` 或 Android 回传当前有效 id | 首声、播放、seek、下载完成、歌词/封面 | HEAD 200 audio、Range 206、part 增长、cache promotion | pass/fail/blocker |
| 一丝不挂 | `一丝不挂` | 正向完整能播主路径 | `一丝不挂 / 陈奕迅` | 同上 | 同上 | pass/fail/blocker |
| 稻香 | `稻香` | 正向完整能播主路径 | `稻香 / 周杰伦` | 同上 | 同上 | pass/fail/blocker |
| 哎呀 | `哎呀` | 正向完整能播主路径 | `哎呀 / 王蓉` | 同上 | 同上 | pass/fail/blocker |
| HTTP 失败样例 | owner 提供或拦截样例 | 非音频、403、HTML、防护页、Range 非 206 必须 fail closed | sourceAttempt 包含失败类型：`security_or_defender`、`play_url_unavailable`、`non_audio_content`、`range_not_supported`、`audio_validation_failed` | UI 显示不可完成或空态，不出现可播放完成态 | 无 formal mp3、无 `_cache_index` 正式条目、日志有 failure reason | pass/fail/blocker |

## 主路径步骤

每个正向样例按同一动作链执行。

1. 清理缓存或记录当前缓存状态，导出 `cache/before`。
2. 打开首页搜索入口，输入搜索词。
3. 截搜索结果和 UI XML；确认没有 `PREVIEW`、`试听`、`30s`、网盘、HTML、防护页、低置信完成路径。
4. 记录首个目标 candidate：`title/artist/playId/detailUrl/source/confidence/sourceAttempt/urlType/canCacheAudio`。
5. 点击结果行；预期为下载并播放。
6. 录屏到首声出现，记录 `tap_time`、`first_byte_ms`、`playing_time`、`mediaSession state`。
7. 在完整下载前观察 `.part` 或 transient cache 增长；记录至少两次 size。
8. 执行 seek：先 seek 已下载区，再 seek 未下载区；记录 position、buffering、Range/HTTP 状态和用户可见状态。
9. 等待完整下载完成；记录 `download_complete_ms`、formal cache mp3、歌词、封面、`_cache_index.json`。
10. 返回首页/mini player/下载管理，确认歌曲可继续播放且状态不是 preview。
11. 导出 `cache/after`、App 日志、logcat、`dumpsys media_session`。

## 下载按钮步骤

1. 搜索目标正向样例。
2. 点击结果行旁下载按钮，不点击整行。
3. 预期：进入下载任务或下载完成，但不自动开始播放。
4. 实际需记录：mini player、media session、下载管理、cache index。
5. 若下载按钮触发播放，判定 `fail P1`，除非产品明确要求变更。

## HTTP 失败与 fail-closed 步骤

Android owner 可通过测试 fixture、debug flag、代理、断网或服务端真实失败样例提供失败路径；QA 只复核证据，不要求自己改代码制造失败。

每个失败样例必须证明：

- UI 不出现可播放/可下载完成态。
- App 不写正式 mp3、歌词或 `_cache_index.json` 成功条目。
- 日志能看到明确失败分类。
- 失败后重新搜索正向样例仍可播放，证明失败没有污染 resolver/cache。

## 单样例证据模板

```text
AM-005 QA Evidence
request: AM-20260711-005
scenario:
songOrQuery:
expectedResult:

package:
sha256:
versionName:
versionCode:
commit:
projectPath:
baseline:

device:
deviceId:
osVersion:
network:
musicSource:

candidate:
  title:
  artist:
  playId:
  detailUrl:
  source:
  confidence:
  sourceAttempt:
  urlType:
  canCacheAudio:

httpGate:
  apiStatus:
  headStatus:
  contentType:
  contentLength:
  rangeStatus:
  contentRange:
  failureReason:

progressivePlayback:
  tapTime:
  firstByteMs:
  playingTime:
  mediaSessionState:
  partSizeSamples:
  seekDownloadedArea:
  seekUndownloadedArea:
  downloadCompleteMs:

cache:
  before:
  partPath:
  formalAudioPath:
  lyricsPath:
  artworkPath:
  cacheIndexEntry:
  noCacheReason:

uiEvidence:
  searchScreenshot:
  playerScreenshot:
  downloadManagerScreenshot:
  recording:
  uiXml:

logs:
  appLog:
  logcat:
  dumpsysMediaSession:
  diagnosticsPath:

actual:
result: pass|fail|blocker
failureLevel: P0|P1|P2|P3|none
nextAction:
```

## pass / fail / blocker 标准

`pass`：

- 包、sha、设备、commit、baseline、证据目录齐全。
- 正向样例可搜索到完整歌曲海候选，且没有 PREVIEW/网盘/HTML/防护页/低置信完成路径。
- 点击结果行首声早于完整下载完成；media session 为 playing，position 递增。
- seek 已下载区/未下载区行为可解释，未下载区允许短暂 buffering，但不得崩溃或跳到错误歌曲。
- 完整下载后才写 formal mp3、歌词/封面 metadata 和 `_cache_index.json`。
- HTTP 失败样例 fail closed，不写正式缓存，失败后正向样例仍可播放。

`fail`：

- UI 把 PREVIEW、网盘、HTML、防护页、非音频或低置信候选当作完成。
- 正向样例无完整播放、media session 不进入 playing、首声晚于或等于完整下载完成却声称边下边播。
- seek 导致错误歌曲、崩溃、永久卡死或缓存污染。
- HTTP 失败样例写入正式缓存或显示完成。
- candidate/source、日志、cache index 与截图互相矛盾。

`blocker`：

- Android 未提供 APK sha、设备 target、证据目录或 diagnostics。
- 包无法安装、启动崩溃、搜索/播放主路径不可进入。
- 设备锁定、网络不可用、音乐源不可达，且 10 到 15 分钟内无替代证据。
- 日志/截图/录屏/cache 证据缺失导致 QA 无法复核。

## 回传摘要模板

```text
type: status
request: AM-20260711-005
lane: product|architect|android
thread: <target-thread-id>
status: verified|failed|blocked
summary: QA 已按 AM-005 矩阵复核 Android APK：正向完整能播 <n>/4，搜索歧义 <n>/4，边播 seek <pass/fail/blocker>，HTTP fail-closed <pass/fail/blocker>；包 sha <sha>，设备 <device>，证据目录 <path>。
next_action: <失败时写 owner 修哪条链路、哪首歌/哪个 query、预期实际、截图/录屏/log/cache 路径；通过时写 product/architect 可进入体验或 release gate。>
```
