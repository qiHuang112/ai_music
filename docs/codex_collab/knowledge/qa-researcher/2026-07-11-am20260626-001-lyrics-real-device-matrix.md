# AM-20260626-001 歌词真实设备回归 QA 矩阵

## 目标

对 Android 回传的 release/1.1.0 包做真实设备复核，确认旧歌词回归清单不再被 PREVIEW、URL、网页介绍或无时间轴文本误判为完成。

## 包与设备证据

Android 回传必须包含：

- Project Path、HEAD、base commit、APK path、APK sha256、versionCode/versionName。
- 设备 target、型号、安装时间、是否清数据、输入法状态。
- `flutter analyze --no-pub` 与相关 targeted tests 输出。
- 小米 10 Pro 截图/XML/logcat/cache index 证据目录。

## 必测歌曲矩阵

| 歌曲 | 期望证据 | Pass 标准 | Fail/Blocker 标准 |
| --- | --- | --- | --- |
| 坏孩子 | 搜索结果、候选来源、歌词链路、播放详情 | timed LRC 或结构化 miss chain | 无证据、用网页文本/URL/preview 冒充歌词 |
| 苦笑 | 同上 | 同上 | 同上 |
| 风度 | 同上 | 同上 | 同上 |
| 昆明晚安 | 同上 | 同上 | 同上 |
| 春雨里洗过的太阳 | 同上 | 同上 | 同上 |
| 一丝不挂 | 同上 | timed LRC 或明确 provider 结论 | 歌曲可播但歌词链路缺失未解释 |
| 外婆或稻香 | 正向对照 | 歌曲海完整音频、`.lrc`、播放详情歌词可见 | release/1.1.0 正向歌词路径回退 |

## 每首必须记录字段

- searchQuery
- selectedCandidate name/artist/source/platform/id
- result type：full_audio / cached / no_match / low_confidence / no_timed_lrc
- sourceAttempts 或 provider chain
- cache index row 与 `.lrc` path/line count
- 播放详情歌词截图/XML 或结构化 miss chain
- 是否出现 PREVIEW/试听/30s/网盘/HTML/防护页误入完成路径

## Pass / Fail / Blocker

- Pass：每首都有截图/XML/log/cache 或明确 miss chain；正向对照 `.lrc` 与播放详情歌词可见；无 PREVIEW/URL/网页介绍冒充歌词。
- Fail：候选可用但歌词不显示且无 miss chain；cache metadata 与 UI 不一致；错误 source 写入 cache；歌词行数/时间轴明显异常。
- Blocker：设备不可达、包未安装、搜索源不可用导致无法覆盖清单、Android 未提供 APK sha 或证据目录。

## 升级规则

Android 回传后，QA 在 10 到 15 分钟内给 pass/fail/blocker。若 Android 未回包或证据缺 APK sha、截图/XML、cache index、sourceAttempt，QA 直接回 blocker 给 architect 和 Android owner。
