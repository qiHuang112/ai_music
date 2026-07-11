# AM-20260711-002 真实截图 Product Design Audit

Request: AM-20260711-002
Workflow: superpowers-v1
Lane: ui
Thread: 019ef1d2-d6ec-79d3-9225-fb4169680228
Status: self_tested_design_audit
Date: 2026-07-11

## 结论

本轮 audit 已改用当前真实截图证据，不再沿用 AM-007/010 历史截图。此前基于历史截图生成的 ImageGen 草稿无效，不对 Product 展示，也不计入 3 套视觉方向成果。

当前可以进入 Product 选择视觉方向前的 ideation 阶段，但本轮按 Product 指令只输出 3 套 `390x844` ImageGen 提示词，不生成图片、不改业务代码。

## 采用证据

Android 当前包：

- Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-016`
- HEAD: `b306932d03e1eedbe96fd50dafe0f95805b0eab4`
- APK SHA256: `ae5da6fbeacbef9876062d6220b7d627987bf04a99a1280649be8bda734266f3`
- Device: Xiaomi 10 Pro `192.168.31.76:41563`
- Screenshot dir: `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`
- Summary: `/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/summary.md`

HarmonyOS 当前包：

- HAP: `/Users/huangqi/AIHome/projects/ai_music_ohos/build/ohos/hap/entry-default-signed.hap`
- HAP SHA256: `9065d4d37c10c37be845f7c1c0a3561593f15234cf4a46535da2e1772f856abb`
- Source HEAD: `48d0b5c`
- Device: `ALN-AL00`, `OpenHarmony-6.1.0.115`, `1260x2720`
- Screenshot dir: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/screenshots/`
- Constraints: `/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/ohos-platform-constraints.md`

## 四条路径 Audit

### 1. 首页 / 本地资产 / 热榜发现

采用截图：

- Android: `01-home-initial.png`, `08-home-with-mini-player.png`, `14-home-favorite-clean.png`, `16-home-hotlist-playlist.png`
- HarmonyOS: `AM-20260711-002_ohos_192-168-31-53_home_current_00.png`, `AM-20260711-002_ohos_192-168-31-53_home_mini_player_04.png`

现状：

- 首页主路径清楚：标题、搜索、下载、歌单、设置、收藏、自建歌单、热榜发现都在首屏或首屏附近。
- 本地资产优先级符合产品边界，热榜发现没有挤掉收藏和自建歌单。
- 有播放后 mini player 固定底部，Android/OHOS 都能承接“回到播放页”。

问题：

- P2 信息层级偏平：收藏、自建歌单、热榜发现卡片视觉权重接近，首页缺一个“当前播放/最近播放/本地资产概览”的音乐产品焦点。
- P2 加入热榜歌单后，“热榜歌单”和“热榜发现”相邻时语义接近，需要设计上区分“已保存资产”和“发现入口”。
- P3 顶部三个图标入口依赖图标理解，下载、歌单、设置在新用户眼中偏工具栏。
- P3 OHOS 顶部状态栏更高，标题区域不能继续上推；底部 mini player 必须为手势条预留空间。

设计约束：

- 首页必须保留“搜索 + 本地资产 + 发现”三段式。
- mini player 不应遮挡本地资产或热榜入口。
- 热榜发现必须继续标明“发现/搜索匹配”，不能暗示直接播放第三方音频。

### 2. 搜索 / 下载 / 缓存结果

采用截图：

- Android: `02-search-daoxiang-results.png`, `03-current-after-t9.png`, `04-after-daoxiang-search.png`, `19-aiya-t9-candidate.png`
- HarmonyOS: `AM-20260711-002_ohos_192-168-31-53_search_focus_02.png`, `AM-20260711-002_ohos_192-168-31-53_search_results_06.png`

现状：

- 搜索框主入口明确，搜索结果列表有来源/格式/下载按钮。
- 当前包保留系统输入法，真实用户路径比 ADB Keyboard 更可信。
- HarmonyOS 和 Android 都显示键盘常驻时搜索结果可见，但可见区域明显被压缩。

问题：

- P1 搜索结果在键盘弹出时可视区域过小，列表和下载按钮需要更清楚的“当前状态/可操作”层级。
- P2 Android 中文搜索受系统输入法候选限制，本轮未拿到干净中文完整音频结果页；设计稿不能依赖理想输入状态。
- P2 FLAC / 未通过完整音频校验等失败原因直接塞进 subtitle，信息长且难扫读。
- P3 右侧下载按钮是可点主操作，但在长文案行里视觉弱，容易被当成普通状态图标。

设计约束：

- 搜索结果行建议三层：标题、歌手/来源/音质、状态 chip；下载/播放动作独立为 44px 以上触控目标。
- 键盘弹出时至少保留 4 到 5 条结果的可读区域。
- 失败原因要短文本化，例如“不可下载”“需完整音频校验”“已缓存”，详情再二级展开。

### 3. 播放详情 / 歌词 / mini player / 队列入口

采用截图：

- Android: `06-playing-mini-from-download-manager.png`, `07-player-detail.png`, `10-player-detail-lyrics.png`, `11-player-current-queue.png`, `12-player-bottom-left-entry.png`
- HarmonyOS: `AM-20260711-002_ohos_192-168-31-53_home_mini_player_04.png`, `AM-20260711-002_ohos_192-168-31-53_player_lyrics_05.png`

现状：

- 播放页是当前最有音乐产品感的页面：封面、标题歌手、歌词、进度、控制区完整。
- 歌词高亮可见，播放控制触控面积充足。
- mini player 在两个平台都可见，并能承接播放状态。

问题：

- P1 Android `11-player-current-queue.png` 实际打开的是新建歌单 bottom sheet，不是队列 sheet；说明播放页右上“歌单/队列/加入歌单”入口语义容易混淆，当前无法作为队列设计通过证据。
- P2 播放页封面很大，歌词和控制区在小屏/高状态栏平台接近底部手势区域，OHOS 尤其需要保留下边距。
- P2 mini player 使用占位唱片图标时产品质感弱；有封面时应尽量显示缩略图。
- P3 停止按钮和播放模式按钮与上一首/下一首同权，层级可以更清楚。

设计约束：

- 队列入口和加入歌单入口必须视觉区分：队列是当前播放上下文，加入歌单是收藏/整理动作。
- 播放页改版必须保证歌词、进度、主播放按钮在首屏同时可见。
- mini player 需要保留上一首/播放暂停/下一首和安全区，不可压缩为只剩一个播放按钮。

### 4. 歌单 / 收藏 / 热榜 / 下载管理 / 设置

采用截图：

- Android: `05-download-manager.png`, `13-home-after-favorite.png`, `15-hotlist-detail.png`, `17-settings-or-current.png`, `18-settings-music-source.png`
- HarmonyOS: `AM-20260711-002_ohos_192-168-31-53_favorites_03.png`

现状：

- 下载管理结构完整：正在下载、最近任务、搜索、已缓存音乐、排序。
- 设置页信息详尽，音乐源状态描述能解释 Auto、BuguYY、FLAC、歌曲海、Kuwo 等能力。
- 收藏页和自建歌单复用列表模型，当前播放、收藏、加入歌单、更多操作都在行内。

问题：

- P1 Android 当前 `15-hotlist-detail.png` 仍有竖向 `overflowed by 4.0 pixels` debug 条。该问题在当前 b306932 截图中真实存在，不能按旧回改说明视为已消失；需要后续 owner 确认是否当前 release 仍未吸收修复。
- P2 下载管理和设置页偏系统列表/工程列表，和播放页音乐产品质感割裂。
- P2 设置音乐源说明很长，但信息价值高；视觉上应变为状态列表或分组，而不是大段灰字。
- P3 收藏/歌单行右侧动作多，长标题时容易拥挤；多选、更多、收藏、加入歌单应有更明确模式区分。

设计约束：

- 热榜详情必须给封面/排名列固定高度，避免 leading overflow。
- 下载管理可以保持高密度，但要用状态 chip、进度条和错误摘要提高扫读性。
- 设置页优先保持系统可信感，不需要做成强运营视觉。

## 跨端约束

- Android 小米 10 Pro 截图尺寸为 1080x2340，OHOS 截图尺寸为 1260x2720；设计稿用 `390x844` 只作为方向图，不能直接当像素验收基准。
- OHOS 顶部状态栏更高，搜索页和播放页不能把核心信息贴近顶部。
- Android/OHOS 系统键盘高度都很大，搜索结果设计必须在键盘常驻时仍可扫读。
- OHOS 底部手势条明显，mini player 和播放控制要保留下边距。
- 两端都以深色主题为主，本轮缺浅色主题和字体缩放证据。

## 可行动问题清单

- P1: 当前 b306932 Android 热榜详情仍出现 `overflowed by 4.0 pixels` debug 条。建议 android-discovery/architect 确认 AM-010 overflow 修复是否进入 `release/1.0.2@b306932`，并补无 overflow 截图。
- P1: 队列截图缺失且当前证据打开的是新建歌单 sheet。建议 Android owner 补采真正队列 bottom sheet，或 architect 明确当前版本暂无队列入口。
- P2: 搜索结果在键盘常驻时状态/动作层级不足。后续设计应先处理搜索行结构。
- P2: 首页本地资产与发现区缺统一信息架构。建议 Product 在 3 套方向中选择“本地优先 / 播放优先 / 发现优先”的主策略。
- P3: 下载管理、设置、收藏/歌单行需要后续统一 token 和 row pattern。

## 三套 ImageGen 提示词

### 方向 A：Library First / 本地资产优先

用途：稳健升级当前结构，最少改变用户路径。

Prompt:

```text
Create exactly one 390x844 mobile app home screen mockup for AI Music, direction name "Library First". Use the current real screenshots as product context: Android b306932 home/search/player/screens and HarmonyOS home/search/player screenshots. Do not copy debug overlays, status artifacts, or old historical screenshots. Dark-first Chinese mobile music app UI. Keep the real IA: top title "搜音乐", search field "歌手或歌曲", top icon actions for downloads, playlists, settings, a local library section "我的音乐", cards for "收藏" and "自建歌单", a saved hotlist playlist entry when present, a "热榜发现" discovery card, and a bottom mini player when music is playing. Make local library and current playback the strongest hierarchy; hotlist is secondary discovery and must say it is for discovery/search matching, not direct third-party playback. Visual style: mature Material 3 music product, deep green-black background, teal brand primary #7DDAD1, subtle warm accent #E7C56A, 14px card radius, readable Chinese typography, compact but premium cards, stable safe areas for Android and HarmonyOS, no bottom tab bar unless it clearly improves the home structure, no marketing hero, no feature-explainer copy. Include realistic content from evidence: 收藏 1首 or 2首, 自建歌单 qi, 热歌榜 QQ音乐 更新 2026-07-10, top songs ANGEL(天使), 阴天, 怎么能, mini player "十年 / 陈奕迅" or "哎呀 / 王蓉". Output only the single UI mockup.
```

### 方向 B：Now Playing Hero / 当前播放优先

用途：强化音乐产品质感，把播放状态作为首页锚点。

Prompt:

```text
Create exactly one 390x844 mobile app home screen mockup for AI Music, direction name "Now Playing Hero". Use current Android b306932 and HarmonyOS screenshots as factual context, not old historical screenshots. Design a dark Chinese mobile music home screen where the current playing song is the first visual anchor: album artwork, song title, artist, one lyric line, compact progress, and play/pause control are visible near the top or upper middle, while preserving the existing search entry "歌手或歌曲", local library cards "收藏" and "自建歌单", hotlist discovery "热榜发现", and top actions for downloads, playlist/library, settings. The app is a real tool, not a landing page. Keep all controls plausible in Flutter Material style; no oversized decorative gradients, no abstract orbs, no unreadable text. Must respect HarmonyOS constraints: generous top safe area, bottom gesture area, mini player or player hero not too close to bottom, keyboard/search route can still work. Use deep green-black surfaces, teal primary, warm accent only for discovery tags, real album-art mood from player screenshots, 14-16px radii, high contrast Chinese typography. Make the saved/local library still visible without scrolling too far. Output only the single UI mockup.
```

### 方向 C：Discovery Mix / 发现与管理并重

用途：面向热榜、歌单推荐和后续运营扩展，但不压过本地主路径。

Prompt:

```text
Create exactly one 390x844 mobile app home screen mockup for AI Music, direction name "Discovery Mix". Base the concept on current real evidence from Android release/1.0.2 b306932 and HarmonyOS screenshots. Dark-first Chinese mobile music product UI. The home screen should combine search, local music, and discovery: title "搜音乐", search field, top action icons, compact "我的音乐" assets, a stronger "热榜发现" card with QQ音乐 source, update date 2026-07-10, top ranked songs, and a clear saved "热榜歌单" asset when present. Hotlist must look like recommendation metadata, not a direct-play/download-all service; include copy like "榜单用于发现，播放通过 AI Music 搜索匹配" in a concise way. Include a bottom mini player for "十年 / 陈奕迅" with previous, play/pause, next controls and safe-area spacing. Visual style should be refined, editorial but still app-like: deep green-black background, album artwork thumbnails, teal primary actions, warm gold discovery label, compact rank chips, no debug overflow, no excessive empty right side, no marketing layout, no bottom nav unless necessary. Ensure search and list rows would remain readable when Android/OHOS keyboard appears. Output only the single UI mockup.
```

## 后续

Product 可在主会话用以上三套提示词独立生成恰好 3 张图供选择。选定后，UI lane 再进入设计细化、token 定稿和 image-to-code/开发 handoff。
