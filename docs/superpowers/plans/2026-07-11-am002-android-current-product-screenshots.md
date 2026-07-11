# AM-20260711-002 Android 当前产品现状截图采集计划

## Project

- Project Path: `/Users/huangqi/AIHome/projects/ai_music_AM-20260705-016`
- Base Branch: `release/1.0.2`
- Baseline Commit: `32d183c8c2038000f4f6e42c60b72125021a5cae`
- TDD Mode: `not_applicable`，本任务只采集产品现状证据，不改代码。

## Steps

1. 运行 workflow start gate。
2. 确认 `origin/release/1.0.2` 是否为最新已合入 1.0.2 功能基线。
3. 构建 debug APK，记录路径和 sha256。
4. 连接小米 10 Pro，确认不使用小米 17 Pro。
5. 关闭 ADB Keyboard 或切回系统输入法。
6. 安装 debug APK，启动 App。
7. 按真实用户路径截图：首页空态、搜索结果、下载中与完成、mini player、播放详情、歌词、当前队列、收藏、自建歌单、热榜、下载管理、设置。
8. 汇总截图目录、操作路径、设备 target、APK sha 和已知限制。
9. validate-message 后同步 UI、architect 和 product。

## Verification

- `git rev-parse HEAD`
- `git status --short --branch`
- `shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk`
- `adb devices -l`
- `adb shell dumpsys package com.qi.ai.music`
- 截图目录清单和每张截图的操作路径说明。
