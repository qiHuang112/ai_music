# Android ADB 搜索源自测流程

## 背景

AM-20260622-003 需要恢复 `flac.music.hi.cn` 资源源，并验证 `Auto` 模式会同时搜索布谷歪歪和 FLAC，再合并展示两个来源的结果。产品指定验收关键词必须是中文 `黑夜传说`，用于确认布谷歪歪无结果时 FLAC 结果仍能进入候选列表。

## 设备分层

- 开发自测默认使用小米 10 Pro 或其它明确分配的开发测试设备。
- 小米 17 Pro 是产品/主管验收设备，只有产品明确要求安装时才连接和安装。
- 不要把设备锁屏密码、个人凭据或一次性端口写入仓库文档。

## 构建与安装

```bash
cd /Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
../tools/flutter/bin/flutter build apk --debug

adb devices -l
adb -s <device-id> install -r -d build/app/outputs/flutter-apk/app-debug.apk
adb -s <device-id> shell monkey -p com.qi.ai.music -c android.intent.category.LAUNCHER 1
```

## 输入中文搜索词

优先使用 ADB keyboard 或系统输入法直接输入中文；如果设备不支持 `adb shell input text` 输入中文，可手动输入，但日志摘要必须写清楚实际 query 是 `黑夜传说`。

```bash
adb -s <device-id> shell input tap <search-field-x> <search-field-y>
adb -s <device-id> shell input text 黑夜传说
adb -s <device-id> shell input tap <search-button-x> <search-button-y>
```

如果 `input text` 中文失败，可用复制粘贴法：

```bash
adb -s <device-id> shell am broadcast -a clipper.set -e text '黑夜传说'
adb -s <device-id> shell input keyevent KEYCODE_PASTE
```

如果设备不支持 `cmd clipboard`、未安装 ADBKeyboard，且第三方 IME 安装被系统限制，`adb shell input text` 只能作为拼音/英文兜底，不能证明中文 query。此时需要手动输入中文，或在开发机临时启用可信的 ADB 输入法后再跑自动化；不要把这种限制误判成搜索源失败。

## 抓 resolver 日志

```bash
adb -s <device-id> logcat -c
adb -s <device-id> logcat -v time | grep -E 'AI Music\\]\\[resolver\\]|I/flutter'
```

实现里 `_logResolver` 同时写 `dart:developer` 和 `print`。部分 MIUI 设备不会稳定输出 `developer.log`，但 debug 包的 `print` 会以 `I/flutter` 进入 logcat。

期望能看到类似日志：

```text
[AI Music][resolver] search query="黑夜传说" source=auto
[AI Music][resolver] auto buguyy query="黑夜传说" count=0
[AI Music][resolver] auto flac query="黑夜传说" count=...
[AI Music][resolver] auto merged query="黑夜传说" buguyy=0 flac=... count=...
[AI Music][resolver] search done query="黑夜传说" source=auto count=... candidateSources=flac
```

再补一个两个源都可能有结果的关键词，例如 `晴天` 或 `周杰伦`。期望日志里 `auto buguyy` 与 `auto flac` 都有请求和数量，最终 `candidateSources` 同时包含 `buguyy,flac` 或 `flac,buguyy`。

## 验证清单

- 设置页 `音乐源` 有 `自动 / Auto`、`布谷歪歪 / BuguYY`、`FLAC / flac.music.hi.cn`。
- `Auto` 模式搜索任意关键词时，布谷歪歪和 FLAC 都会参与搜索；某个源失败时，只要另一个源有结果仍可展示。
- 搜索结果左侧来源标记显示真实来源，例如布谷歪歪为 `布谷`、FLAC 为 `FLAC`；副标题不再显示搜索源名称。
- 点候选后 resolve/download 按候选真实 `source=flac` 分派。
- `BuguYY` 单源模式不触发 FLAC 日志。
- FLAC 候选若带 `pic_url`、`cover` 等封面字段，搜索列表和缓存条目应能保留封面；下载后会主动触发 metadata 管线，优先写入源站歌词/旁路 `.lrc`，再用 LRC API 兜底。
- 如果下载失败，记录错误详情和是否为 HTTP、证书、反爬或音频校验失败。
