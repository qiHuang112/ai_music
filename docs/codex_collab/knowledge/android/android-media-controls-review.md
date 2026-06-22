# Android 系统播控 review 注意事项

## 背景

AM-20260622-002 曾出现 Dart 单测和静态 review 通过，但产品真机验收失败：Android 系统播控 compact 左侧收藏没有按预期出现或生效，随机播放 10 秒内手动切歌的短听跳过也没有真实生效。

## 经验

- `PlaybackState.controls` 和 `androidCompactActionIndices` 只说明 Dart/audio_service 侧发布了什么，不等于 Android 系统媒体控件会按同样 slot 展示。
- Android 13+ 系统媒体控件对 compact slots 有系统策略，普通 `MediaControl.custom` 不一定可靠占据旧式 compact 三按钮，但完整 `PlaybackState.controls` 顺序仍会影响展开播控卡片。
- 如果产品要求四槽位，要同时说明完整 controls 顺序和旧式 compact 三按钮取舍。AM-20260622-002 的最终方案是完整 controls 发布“收藏、上一首、播放/暂停、下一首”，旧式 compact 使用 `[0,2,3]` 优先显示“收藏、播放/暂停、下一首”。
- 随机播放策略不能只测 planner。只要底层播放器仍启用原生 shuffle，手动 next 就可能被播放器内部顺序覆盖。
- 需要区分 App 内按钮、系统通知按钮、系统媒体键、耳机键和自动播下一首；这些入口可能走不同调用路径。

## Review 门槛

- 播控中心相关功能必须提供 Android 真机截图、录屏或日志摘要。
- 收藏按钮必须证明系统点击能回到 Dart 业务，并同步 App 收藏状态和通知图标状态。
- 随机短听跳过必须证明在真机手动 next 下生效，并说明自动播下一首不受影响。
- 单测仍然需要，但不能替代系统媒体控件真机验证。

## 设备分层

- 小米 10 Pro 是 Android lane 默认开发验证设备，适合做 ADB、日志、安装和复现。
- 小米 17 Pro 是产品/主管验收设备，只有产品明确要求安装或验证时才连接使用。
- 发送 review_request 时要区分“开发自测证据”和“产品验收证据”，不能把验收机当作自测机。
- 写 ADB 自测脚本或知识库时，不要记录设备密码、个人隐私或一次性连接细节。
