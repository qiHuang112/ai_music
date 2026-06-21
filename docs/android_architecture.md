# AI Music Android 架构说明

本文档记录当前 Android 版 AI Music 的代码分层和主要数据流。后续改业务时，优先沿用这里的边界，避免把搜索、下载、缓存、播放和页面状态重新堆回同一个类里。

## 目标

- 手机端直接搜索、解析、下载并播放音乐，不依赖 Windows 本地服务。
- Android 系统播控、App 内播放器、歌词页共享同一套播放状态。
- 下载结果进入 App 私有长期缓存，索引、设置、歌单和歌词封面元数据都可恢复。
- 当前运行时只暴露布谷歪歪单源，`MusicDataSource` 类型仍保留未来扩展入口。

## 分层

### Domain

路径：`lib/src/domain`

领域层只放 App 自己的稳定模型，例如 `Track`、`PlaybackMode`、`TrackMetadata`、`LyricLine`。这里不直接依赖 `audio_service`、缓存 JSON 或第三方解析器返回结构。

### Data

路径：`lib/src/data`

数据层负责和外部世界打交道：

- `music_resolver.dart` 聚合在线解析器接口，当前主要入口是 `RemoteMusicResolver`。
- `buguyy_resolver.dart`、`flac_resolver.dart` 是具体来源实现。当前 UI 固定布谷歪歪，FLAC 作为保留能力存在。
- `music_cache.dart` 管音频下载、音频校验、缓存文件、`.lrc` 旁路文件和缓存索引。
- `lyrics_artwork.dart` 管歌词、封面、元数据缓存，以及歌词未命中半小时内不重复请求的内存缓存。
- `music_playlists.dart` 管收藏和自定义歌单持久化。
- `music_settings.dart` 管语言、主题和单源设置迁移。
- `json_file_store.dart` 是共享 JSON 读写工具，负责临时文件写入和损坏备份。

### Application

路径：`lib/src/application`

应用层承接业务流程，页面尽量只调用这里：

- `MusicController` 是 UI facade，持有页面需要观察的状态，并组合各个 use case。
- `DownloadUseCase` 负责“候选 -> 解析 -> 下载/复用缓存 -> 下载任务状态”。
- `LibraryUseCase` 负责缓存库、收藏、自定义歌单的快照和持久化变更。
- `PlaybackUseCase` 负责播放队列、重复点击同一首、播放模式和系统音频 handler 的交互。
- `MetadataUseCase` 负责当前歌曲歌词/封面元数据读取。
- `SettingsController` 负责设置读写。
- `music_mappers.dart` 放 domain 和播放/缓存模型之间的转换。
- `music_ui_message.dart` 放可本地化 UI 消息 code，页面层负责渲染中文/英文文案。

### Playback

路径：`lib/src/playback`

`MusicAudioHandler` 是 `audio_service` 与 `just_audio` 的适配层。系统通知栏、锁屏、耳机按键、App 内播放器都通过它同步播放队列、当前歌曲、进度、时长和播放模式。

### Presentation

路径：`lib/src/presentation`

页面层负责布局、交互和本地化渲染：

- `music_home_page.dart`：搜索首页、缓存/收藏/歌单入口、迷你播放器。
- `download_manager_page.dart`：进行中下载、最近任务、已缓存歌曲管理。
- `player_page.dart`：播放详情、歌词详情、进度拖动、播放模式。
- `settings_page.dart`：语言、主题、当前音乐源展示。
- `list_search.dart`、`playlist_actions.dart`：列表搜索和歌单操作复用组件。

## 主要流程

### 搜索并播放

1. 首页调用 `MusicController.search(query)`。
2. `MusicController` 为每次搜索分配 request id，旧请求晚返回时会被丢弃。
3. 用户点击播放候选时，`playCandidate` 先查缓存；没缓存则走 `downloadCandidate`。
4. `DownloadUseCase` 解析直链并调用 `CachedTrackStore.downloadOrReuse`。
5. 下载成功后刷新缓存库，`PlaybackUseCase.playTrack` 用当前可见列表建立播放队列。
6. `MusicAudioHandler.loadQueue` 将队列交给 `just_audio`，同时发布给系统播控。

### 下载缓存

1. 下载任务用候选的来源、平台、id、链接、歌名和歌手生成稳定 task id。
2. `CachedTrackStore` 用 `source/platform/id/quality` 等信息生成 cache id，避免同名歌曲误复用。
3. 下载先写 `.download-*.tmp`，音频校验通过后再 rename 成正式文件。
4. 缓存索引写入通过 `JsonFileStore`，索引损坏时备份坏文件，避免静默吞掉用户库。

### 歌词和封面

1. 播放歌曲变化时，`MusicController` 触发 `MetadataUseCase.load`。
2. `TrackMetadataRepository` 先读元数据缓存，再依次尝试候选封面、解析结果内歌词、旁路 `.lrc`、布谷歪歪歌词、LRC API。
3. 如果歌词未命中，会在内存中记录 30 分钟 miss TTL；冷启动后会重新尝试。
4. 歌词页手动滚动只预览中线时间，不 seek；只有点击某句歌词才跳转。

### 设置

1. 设置持久化在 `MusicSettingsStore`。
2. 旧的 `auto/flac/buguyy` source 设置都会迁移为 `buguyy`。
3. 语言和主题立即更新 `MusicController` 状态，UI 通过 `AppStringsScope` 和主题重建。

## 维护约定

- 新增业务流程时优先加 use case，不直接把逻辑写进页面。
- 页面只展示状态和触发动作，不直接读写缓存 JSON、不直接访问解析器。
- 第三方解析接口变化时优先改 data 层解析器和 mapper。
- 播放队列相关行为统一走 `PlaybackUseCase`，避免系统播控和 App 内播放器走两套规则。
- 需要用户可见文案时先加 `MusicUiMessageCode` 或 `AppStrings`，不要在业务层拼固定中文/英文。
- 之后本项目提交信息使用中文。
