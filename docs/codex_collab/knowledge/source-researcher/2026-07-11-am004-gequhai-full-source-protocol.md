# AM-20260711-004 歌曲海完整音频协议复核

Created: 2026-07-11
Owner Lane: source-researcher
Request: AM-20260711-004

## Product 指定流程

Product 截图指定以歌曲海为唯一当前完成路径：

1. 访问搜索页：`https://www.gequhai.com/s/外婆`。
2. 点击搜索结果第一条：`外婆 / 周杰伦`。
3. 进入详情页：`https://www.gequhai.com/play/6330`。
4. 页面播放器进度条证明站内正在边播。
5. 页面提供 `下载歌词` 和 `下载歌曲`；下载歌曲弹层中的 `试听品质（不推荐）` 对应页面播放器实际 mp3。
6. 夸克网盘按钮只记录为 `external_pan_link`，不作为客户端下载完成。

## Chrome 用户态复核结果

Chrome 打开 `https://www.gequhai.com/s/%E5%A4%96%E5%A9%86` 后，搜索结果表中第一条为：

- title: `外婆`
- artist: `周杰伦`
- link: `/play/6330`

打开 `https://www.gequhai.com/play/6330` 后，页面内联字段包含：

- `window.mp3_id = 6330`
- `window.mp3_title = 外婆`
- `window.mp3_author = 周杰伦`
- `window.mp3_cover = https://img2.kuwo.cn/star/albumcover/120/30/97/4276557883.jpg`
- `window.mp3_extra_url` 解码后为夸克链接，只能作为 `external_pan_link` evidence。
- `#content-lrc2` 包含歌词文本，外婆样例约 166 行。

## 最小接口协议

### 搜索

请求：

```text
GET https://www.gequhai.com/s/<urlencoded keyword>
```

解析：

- 结果行标题链接指向 `/play/<id>`。
- 标题和歌手来自同一行。
- 只接受标题、歌手高置信匹配；低置信、错艺人、非歌曲关键词不进入完整播放候选。

### 详情

请求：

```text
GET https://www.gequhai.com/play/<id>
```

要求：

- 使用 cookie jar。
- 若出现一次安全页或 403 retry，沿用同一 cookie jar 低频重试一次。
- 解析 `window.play_id`、`window.mp3_title`、`window.mp3_author`、`window.mp3_cover`、`window.mp3_extra_url`、`#content-lrc2`。

### 音频 URL

页面脚本 `static/js/play.js` 中的核心逻辑：

```text
POST https://www.gequhai.com/api/music
headers:
  X-Requested-With: Http
  X-Custom-Header: Key
  Content-Type: application/x-www-form-urlencoded; charset=UTF-8
body:
  id=<window.play_id>&type=0
cookies:
  page cookie jar
```

成功响应：

```json
{"code":200,"data":{"url":"https://...mp3","is_while_url":false},"msg":"ok!"}
```

### 媒体校验

对 `data.url` 做媒体校验：

```text
HEAD <cdn-url>
Range GET bytes=0-8191 <cdn-url>
```

验收条件：

- HEAD 返回 `200`。
- `Content-Type` 为 `audio/*`，样例为 `audio/mpeg`。
- `Content-Length` 为正数；若 HEAD 不给长度，则 Range total 必须为正数。
- Range 返回 `206 Partial Content`，且 `Content-Range` total 为正数。
- CDN 音频请求不要带歌曲海页面 referer；历史样例带 referer 会 403。

## 外婆样例脚本证据

低频脚本按上述协议复核 `play/6330`：

- API 返回 CDN mp3 URL。
- HEAD: `200 OK`，`Content-Type: audio/mpeg`，`Content-Length: 3913543`。
- Range: `206 Partial Content`，读取 `8192` bytes，`Content-Range` total 为 `3913543`。
- 歌词：页面 `#content-lrc2`。
- 封面：`window.mp3_cover`。

## 多样例脚本证据

2026-07-11 已按低频串行策略复核 AM-004 多样例，证据文件：

- 脚本：`/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/scripts/probe_gequhai_am004_samples.js`
- 汇总 JSON：`/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/evidence/script/gequhai-am004-multisample-result.json`
- 报告：`/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/reports/am004-gequhai-multisample-status.md`
- 原始 headers/html/bin：`/Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/evidence/script/`

可进入客户端完整结果的样例：

| query | selected | play | media validation | lyrics | cover | classification |
| --- | --- | --- | --- | --- | --- | --- |
| 外婆 | 外婆 / 周杰伦 | `/play/6330` | HEAD 200 `audio/mpeg` length 3913543; Range 206 `bytes 0-8191/3913543` | 83 lines | ok | `direct_full_audio` |
| 一丝不挂 | 一丝不挂 / 陈奕迅 | `/play/434800` | HEAD 200 `audio/mpeg` length 3877617; Range 206 `bytes 0-8191/3877617` | 52 lines | ok | `direct_full_audio` |
| 稻香 | 稻香 / 周杰伦 | `/play/333` | HEAD 200 `audio/mpeg` length 3576668; Range 206 `bytes 0-8191/3576668` | 48 lines | ok | `direct_full_audio` |
| 哎呀 | 哎呀 / 王蓉 | `/play/38173` | HEAD 200 `audio/mpeg` length 3468831; Range 206 `bytes 0-8191/3468831` | 87 lines | ok | `direct_full_audio` |

失败样例：

- `东方财富`：搜索返回 200，但 `candidates=0`，分类为 `no_search_match`。客户端必须 fail closed，不显示可播放行，不写正式缓存。

`window.mp3_extra_url` 解码规则与页面 JS 一致：

```text
atob(value.replace(/#/g, "H").replace(/%/g, "S"))
```

当前多样例解码结果均为夸克链接，只能作为 `external_pan_link` evidence，不能作为完整音频、边下边播或正式缓存路径。

## 客户端分类

- `source_gequhai` + `direct_audio` + `canCacheAudio=true`：只有搜索、详情、API、HEAD、Range 全部通过才成立。
- `external_pan_link`：夸克链接，只展示证据或不可下载原因，不写正式缓存。
- `security_or_defender`：页面安全验证或 retry 后仍失败。
- `play_url_unavailable`：`/api/music` 非 200、无 URL 或字段异常。
- `non_audio_content`：HEAD/Range 非音频。
- `range_not_supported`：Range 非 206 或 total 非正数。
- `low_confidence_match`：标题/歌手不匹配，不展示完整播放行。

## Android 落地门禁

- 搜索结果只输出 `source_gequhai` 且已通过完整音频校验的候选。
- 结果行点击即下载并播放，下载按钮只做下载，不播放。
- 边下边播使用 transient proxy；首字节时间必须早于完整下载完成时间。
- 完成后转正式缓存，写入 `_cache_index.json`、mp3、lyrics、cover metadata。
- 失败或取消不进入下载列表，不写正式缓存。
- 小米 10 Pro 证据必须包含搜索、播放、media session、first_byte_ms、part 增长、download_complete_ms、缓存转正、歌词/封面。
