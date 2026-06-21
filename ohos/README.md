# AI Music HarmonyOS 架构说明

AI Music 的 HarmonyOS 目标采用“Flutter 业务层 + HarmonyOS 壳 + vendored 音频插件”的结构。产品逻辑、页面、缓存和播放队列仍在 Dart 层维护；`ohos/` 只承载 HarmonyOS 工程壳、权限、资源和 FlutterAbility 入口；原生音频能力放在 `third_party/just_audio_harmonyos`。

## 目录分层

- `lib/`：Flutter 业务代码。`main.dart` 在 HarmonyOS 上绕过 `audio_service` 后台服务，直接创建 foreground-only `MusicAudioHandler`。
- `lib/src/platform/platform_detection.dart`：集中识别 OpenHarmony/HarmonyOS 平台，避免散落的字符串判断。
- `ohos/`：HarmonyOS 应用壳。`entry/src/main/ets/entryability/EntryAbility.ets` 只负责启动 FlutterEngine 并注册插件。
- `third_party/just_audio_harmonyos/`：vendored `just_audio_harmonyos` 插件。AI Music 的本地缓存播放、资源释放和预加载修复都在这里维护。
- `tool/build_ohos_hap.sh`：本机一键构建 HAP 的入口，统一设置 OpenHarmony Flutter SDK、DevEco/Hvigor/ohpm 环境、Dart define 和签名开关。

## 启动链

1. `EntryAbility` 继承 `FlutterAbility`，创建 FlutterEngine。
2. `GeneratedPluginRegistrant` 注册 `just_audio_harmonyos` 和 `audio_session_harmonyos`。
3. Dart `main.dart` 读取 `AI_MUSIC_DISABLE_AUDIO_SERVICE`，并结合 `isOpenHarmonyPlatform` 决定是否跳过 `AudioService.init()`。
4. HarmonyOS 当前使用 foreground-only `MusicAudioHandler`，避免 `audio_service` 后台插件缺失导致启动失败。
5. `MusicAudioHandler` 继续通过 `just_audio` Dart API 驱动平台播放器。

## 应用数据目录

HarmonyOS 不允许应用在 `/storage/Users/currentUser` 下创建 `.ai_music` 这类隐藏目录。AI Music 的缓存、设置和歌单数据必须留在应用沙箱中：

```text
/data/storage/el2/base/haps/entry/files/ai_music
```

`tool/build_ohos_hap.sh` 会通过 `AI_MUSIC_SUPPORT_DIR` 显式传入该路径；如果没有走脚本，`lib/src/platform/app_storage.dart` 也会在识别到 HarmonyOS 时直接使用同一个沙箱目录，不再先依赖 `path_provider`。

## 播放链

1. Dart `just_audio` 通过 `com.ryanheise.just_audio.methods` 初始化平台播放器。
2. `JustAudioOhosPlugin` 持有 `MainMethodCallHandler`，在 engine restart/destroy/detach 时异步释放播放器。
3. `MainMethodCallHandler` 按 Dart player id 管理多个 `AudioPlayer`。
4. `AudioPlayer` 负责 MethodChannel/EventChannel 协议适配，把 Dart 的 load/play/pause/seek 映射到 `MediaAvPlayer`。
5. `MediaAvPlayer` 直接持有 HarmonyOS `AVPlayer`、`AVMetadataExtractor`、`AVSession`，并负责本地 file fd、下一首预加载、状态机回调和最终释放。

## 系统播控中心

HarmonyOS 不走 Android 的 `audio_service` 后台通知链路，系统播控中心由 vendored 插件里的 `AVSession` 直接驱动：

- `MediaAvPlayer` 创建并激活 `AVSession`，注册 play/pause/上一首/下一首/seek 系统命令。
- 创建 `AVSession` 后调用 `setExtras({'requireAbilityList': ['url-cast']})` 声明投播能力，并在 metadata 中设置 `ProtocolType.TYPE_DLNA | ProtocolType.TYPE_CAST_PLUS_STREAM`。
- `AVPlayer` 进入 initialized/prepared/playing/paused/completed/stopped/error/buffering 时，同步 `AVPlaybackState`、当前位置、缓冲位置、播放速度和当前曲目 id。
- 曲目切换和 metadata 读取完成后，同步 title/artist/duration；没有可靠封面 URI 时不发布 `mediaImage`。
- dispose、engine restart/detach 时必须注销命令回调并 deactivate/destroy session，避免系统播控中心残留旧状态。

## 预加载与资源所有权

`MediaAvPlayer` 是 HarmonyOS 播放生命周期的核心，当前约定如下：

- `avPlayer` 表示当前正在播放或准备播放的播放器。
- `pendingAvPlayerNext` 表示已经创建但还没有完成 `loadUri()` 的下一首播放器，不能被切歌逻辑接管。
- `avPlayerNext` 表示已经完成预加载、可以被升格为当前播放器的下一首播放器。
- `currentDataSrcFd` 和 `nextDataSrcFd` 分别跟随 current/next 播放器所有权迁移，reset/release/dispose 时必须关闭。
- `lifecycleGeneration` 用于让旧的异步初始化、预加载和加载回调自动失效，防止 dispose 或切歌后复活旧播放器。
- 下一首播放器升格为当前播放器时，必须先摘掉 next 回调，再挂 current 回调，避免同一个 `AVPlayer` 同时进入两套状态机。

## 构建与签名

常用本机构建命令：

```bash
OHOS_CODESIGN=true tool/build_ohos_hap.sh
```

脚本会传入 `AI_MUSIC_DISABLE_AUDIO_SERVICE=true` 和 `AI_MUSIC_SUPPORT_DIR=/data/storage/el2/base/haps/entry/files/ai_music`，让 HarmonyOS 构建明确绕过 `audio_service` 并使用应用沙箱目录。不传 `OHOS_CODESIGN=true` 时默认追加 `--no-codesign`，方便无签名环境做编译验证。

签名策略：

- 本机 `ohos/build-profile.json5` 可以保留 DevEco 写入的签名配置，方便一键 signed HAP。
- Git 中只保存无密钥的干净签名版本，不能提交证书路径、密码或证书材料。
- 本机通过 `git update-index --skip-worktree ohos/build-profile.json5` 保留签名字段，避免反复出现在 `git status`。

ohpm lock 策略：

- 提交 `ohos/oh-package-lock.json5`，锁住 registry 依赖。
- 不提交 `ohos/entry/oh-package-lock.json5` 和插件 `oh-package-lock.json5`，它们包含 Flutter SDK、pub-cache 或本机 HAR 相对路径。
- `tool/build_ohos_hap.sh` 每次构建前会清理这些 path-based lock，并由本机环境重新生成。

## 验证清单

改 HarmonyOS 相关代码后至少跑：

```bash
../tools/flutter/bin/flutter test --no-pub
../tools/flutter/bin/flutter analyze --no-pub
OHOS_CODESIGN=true tool/build_ohos_hap.sh
```

需要真机确认时：

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t LNG0223804000125 install -r build/ohos/hap/entry-default-signed.hap
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t LNG0223804000125 shell aa start -d 0 -a EntryAbility -b com.qi.ai.music
```

HAP 构建后如需继续用标准 Flutter 开发，运行：

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn ../tools/flutter/bin/flutter pub get
```
