# iOS/通用 metadata provider 风险调研

## 背景

- Request: `AM-20260624-001`
- Lane: `ios`
- Thread: `019ee563-42df-7de0-9c64-0a771f243f6a`
- 范围：歌词、封面 provider 的 iOS/通用风险支持调研。
- 边界：不直接修改公共 Dart 业务；后续 metadata pipeline 仍由 Android/公共 Dart lane 实现，iOS lane 负责平台验证、ATS、真机能力和必要兜底评估。

## 结论

第一版推荐先做“低风险、可降级、不会影响播放”的补全链路：

1. 先使用已有缓存、已解析歌词、同目录 `.lrc` 和当前音源候选字段。
2. BuguYY/FLAC 只作为当前音源的 metadata 字段来源，不做音频源 fallback。
3. 本地音频内嵌封面优先作为离线兜底，Flutter 可先评估 `audio_metadata_reader`；iOS 真机不稳定时再补 AVFoundation MethodChannel。
4. 封面网络兜底优先 iTunes Search API。
5. 歌词网络兜底优先 LRCLIB，先接受英文/国际曲更稳定，中文命中要按 miss TTL 缓存。
6. LrcAPI 和 MusicBrainz/Cover Art Archive 只放低优先级或实验开关，不建议第一版默认强依赖。
7. 网易、QQ、酷我等非官方直连不建议第一版接入。

## Provider 对比

| Provider | 适合字段 | 中文歌 | 英文歌 | 无专辑/同名歌 | 速度与国内网络 | 合规/稳定风险 | 第一版建议 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BuguYY | `picurl`、`getdown.picurl`、少量 `lrc/about` | 歌曲命中较好，歌词字段不稳定 | 一般 | 依赖标题/歌手，`about` 容易误判 | 受 VPN/代理/DNS 影响明显 | 非官方源，字段语义不稳定 | 已接入源内补全；不跨源 fallback |
| FLAC | `picurl`、`lrc/lyric/about` | 可作为第二源字段 | 一般 | 同名歌需保留来源候选 | 可能遇到 SafeLine/网络拦截 | 非官方源，接口稳定性一般 | 已选中该源时使用字段 |
| 本地音频标签 | 内嵌封面、artist/title/album | 取决于文件标签 | 取决于文件标签 | 不依赖网络，适合无专辑 | 本地最快 | 插件格式覆盖和 iOS 文件权限需验证 | 推荐第一版接入封面兜底 |
| iTunes Search API | 封面、专辑名、发行信息 | 中文歌可命中部分曲库 | 英文歌较稳定 | 同名歌必须评分匹配 | HTTPS，速度通常可接受 | Apple 官方 API，但封面版权只适合展示/缓存 URL | 推荐第一版封面兜底 |
| LRCLIB | `syncedLyrics/plainLyrics` | 覆盖不确定 | 英文/国际曲较好 | 需要 artist/title/duration 评分 | 国内网络需超时与降级 | 开源服务，需遵守 API 规则 | 推荐第一版歌词兜底 |
| LrcAPI | 歌词、封面 URL | 中文覆盖可能较好 | 一般 | 模糊匹配易误命中 | 公共实例可能慢、TLS/连接不稳 | GPL-3.0，自建/数据源合规需评估 | 不建议默认强依赖 |
| MusicBrainz + CAA | 元数据、发行封面 | 中文可搜但映射复杂 | 英文较好 | 无专辑时需先找 recording/release | 需要限流，CAA 可能 307 到 archive.org | 官方开放库，1 req/sec 限制，封面 404/503 常见 | 低优先级兜底/后台补全 |

## 字段可信度

- BuguYY：`picurl` 可作为封面候选；`getdown.picurl` 应作为 `geturl` 没有封面时的兜底。`about` 只能弱可信，必须过滤“暂无歌词”“歌词获取失败”、HTML、只有时间戳、过短文本和明显元数据。
- FLAC：`picurl` 可作为封面候选；`lrc/lyric` 中等可信；`about` 同样需要过滤。
- 本地音频标签：内嵌封面最适合做离线封面兜底；title/artist/album 可用于 provider 二次匹配，但不能覆盖用户当前搜索结果。
- iTunes：`artworkUrl100` 适合作封面展示，可按 URL 规则请求更大尺寸；结果必须按 title、artist、album、duration 评分，不能只取第一条。
- LRCLIB：`syncedLyrics` 优先，`plainLyrics` 次之；纯文本歌词能否展示需要产品确认。
- LrcAPI：`/api/v1/lyrics/single` 和 `/api/v1/cover/music` 可做补充，但公共实例不应阻塞主流程。
- MusicBrainz/CAA：MusicBrainz ID 和发行信息可信；CAA `front` 命中时封面可信，但 404 不代表歌曲不存在，只代表该 release 没有封面。

## Miss TTL 建议

| 失败类型 | 建议 miss TTL |
| --- | --- |
| BuguYY 歌词字段为空或“获取失败” | 6-24 小时 |
| BuguYY/FLAC 网络连接中断、TLS、代理问题 | 10-30 分钟 |
| iTunes 无匹配或评分低 | 7 天 |
| iTunes 网络超时/5xx | 1 小时 |
| LRCLIB 无匹配 | 7 天 |
| LRCLIB 超时/连接失败 | 1-6 小时 |
| LrcAPI 无匹配 | 24 小时 |
| LrcAPI TLS/5xx/公共实例不可用 | 1-6 小时 |
| MusicBrainz 无 recording/release 映射 | 7 天 |
| CAA `404` 无封面 | 30 天 |
| CAA `503`、限流或超时 | 6-24 小时 |

Miss TTL 应按 provider、title、artist、album、duration 维度缓存，避免每次进页面重复请求失败源。

## Android/公共 Dart 实现必须避开的坑

- 不要把 metadata provider 做成音频源 fallback。BuguYY 当前选中时只请求 BuguYY；FLAC/FC 不应因为歌词/封面失败而自动参与音频搜索。
- 网络 provider 必须短超时、低并发、可取消，不能阻塞播放、下载和搜索主流程。
- 晚返回结果不能覆盖当前曲，也不能用空结果覆盖已有封面/歌词。
- provider 结果要记录 `source`、`status`、`updatedAt`、`missUntil`，便于排查和手动刷新。
- 同名歌、翻唱、现场版、粤语/国语版本要做评分匹配，至少使用 title、artist、album、duration；没有专辑时降权但不要直接失败。
- 纯文本歌词是否展示需要产品确认；如果当前 UI 只适合 timed LRC，`plainLyrics` 要单独标记。
- MusicBrainz 必须设置明确 `User-Agent` 并遵守 1 request/sec；不能在列表滚动时批量打爆。
- 失败文案不要暴露底层 URL、TLS、HTTP header、代理细节；用户侧只提示“歌词/封面暂未获取到，可稍后重试”。

## iOS 侧待验证

- 验证 `audio_metadata_reader` 在 iOS 真机读取 MP3/FLAC 内嵌封面、ID3、Vorbis comment 的成功率；失败时评估 AVFoundation 兜底。
- 验证封面 `artUri` 使用网络 URL、本地缓存文件 URL 时，锁屏和控制中心是否都能显示。
- 验证后台音频期间 metadata 补全不会触发不必要的后台网络行为；后台音频权限不等于后台抓取 metadata 的长期许可。
- ATS 继续优先 HTTPS；当前 iOS 工程全局明文放开只是开发/兼容策略，未来 TestFlight/App Store 需要收敛为 `NSAllowsLocalNetworking` 加必要域名例外。
- 如果引入 iTunes、LRCLIB、MusicBrainz、CAA，iOS 需在 VPN/无 VPN、蜂窝/无线网络下分别验证超时和失败文案。

## 不建议第一版接入

- 网易、QQ、酷我等非官方客户端接口直连：版权、反爬、接口变动和封号风险高。
- LrcAPI 公共实例作为默认强依赖：公共实例可能慢或不稳定，且自建服务涉及 GPL-3.0 与数据源合规评估。
- Cover Art Archive 作为高优先级在线封面：链路较长、可能跳转 archive.org，404/503 常见，适合后台低频兜底。
- iOS 后台长期自动补全：会把简单 metadata 补全变成后台任务/网络策略问题，第一版应以前台触发和缓存为主。

## 参考链接

- [LrcAPI 文档：歌词接口](https://docs.lrc.cx/docs/APIv1/lyrics/)
- [LrcAPI 文档：封面接口](https://docs.lrc.cx/docs/APIv1/cover/)
- [LrcAPI GitHub](https://github.com/HisAtri/LrcApi)
- [LRCLIB API 文档](https://lrclib.net/docs)
- [LRCLIB GitHub](https://github.com/tranxuanthang/lrclib)
- [Apple iTunes Search API](https://performance-partners.apple.com/search-api)
- [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API)
- [Cover Art Archive API](https://musicbrainz.org/doc/Cover_Art_Archive/API)
