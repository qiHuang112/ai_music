# AI Music iOS 宿主工程

这个目录是 Flutter AI Music 应用的 iOS 宿主工程。它只负责 Apple 平台相关的事情：启动 Flutter、注册插件、声明 iOS 能力、签名、打包、真机安装。

共享产品逻辑在 Dart 层，也就是 `lib/src/`。搜索源、播放规则、下载、缓存修复、歌单、设置状态、UI 状态，都不要在 Swift 里重新实现。

## 职责边界

- `Runner/AppDelegate.swift` 启动 Flutter 宿主，并把生成的插件注册到隐式 Flutter engine。
- `Runner/SceneDelegate.swift` 是 UIKit scene 生命周期入口，由 Flutter scene delegate 接管窗口。
- `Runner/Info.plist` 声明 iOS 运行能力，例如后台音频、本地网络用途、音乐源需要的 ATS 例外。
- `Runner.xcodeproj` 和 `Runner.xcworkspace` 负责签名、Build Phases、Swift Package/CocoaPods 集成、Archive 设置。
- `../tool/build_ios_ipa.sh` 是命令行导出 IPA 的主流程。

## 不要放到 iOS 里的内容

- 音乐搜索、源兜底、源内重试、候选排序。
- 播放队列、下载状态、缓存元数据、歌单逻辑。
- Flutter 页面状态、本地化文案、Widget 行为。

这些属于 Flutter 公共层，应由跨端应用同学在 `lib/src/` 修改，避免 Android 和 iOS 逻辑分叉。

## 当前 iOS 能力

- Bundle ID：`com.qi.ai.music`。
- 最低系统版本：iOS 13。
- 后台音频：`UIBackgroundModes` 包含 `audio`。
- 本地网络弹窗：`NSLocalNetworkUsageDescription` 说明音乐源访问用途。
- ATS：开启 `NSAllowsArbitraryLoads` 和 `NSAllowsLocalNetworking`，因为部分音乐源和本地源使用 HTTP。
- 当前分发方式：Personal Team 的 development 签名。App Store、TestFlight、Ad Hoc 需要对应 Apple Developer 账号能力。

## 构建与安装

始终使用项目旁边的 Flutter SDK：

```bash
cd /Users/huangqi/AIHome/ai_music
/Users/huangqi/AIHome/tools/flutter/bin/flutter pub get
```

为已注册设备构建 development IPA：

```bash
IOS_EXPORT_METHOD=development ./tool/build_ios_ipa.sh
```

输出目录：

```text
build/ios/ipa/
```

真机安装前确认：

- iPhone 已开启开发者模式。
- 手机已在设置里信任 Apple Development profile。
- Xcode 的 `Runner` target 已选择正确 Team。
- `ios/Flutter/Generated.xcconfig` 指向 `/Users/huangqi/AIHome/tools/flutter`，不要指到 `tools/flutter_ohos`。

## 给朋友安装的包

`AI Music.ipa` 是当前开发账号和已注册设备使用的签名包，不是通用安装包。

朋友如果不在这个 profile 里，需要使用可重签 IPA，并通过 AltStore、SideStore 或 Sideloadly 用朋友自己的 Apple ID 重签安装。iOS 不能像 Android APK 一样在 Files 里点开任意 IPA 直接安装。

## 常见问题

- `In iOS 14+ debug mode...`：手机上装的是 Debug 版。请安装 release/profile 包或导出的 IPA。
- `profile has not been explicitly trusted`：在 iPhone 设置里进入“通用 > VPN 与设备管理”，信任开发者 profile。
- `Developer Mode required`：在“隐私与安全性”里开启开发者模式，然后重启手机。
- `FLUTTER_ROOT` 指到 `tools/flutter_ohos`：运行 `/Users/huangqi/AIHome/tools/flutter/bin/flutter clean`，再从本项目执行 `pub get`。
- Android 上 BuguYY 正常但模拟器/Mac 异常：先检查本机 VPN、代理和 DNS。iOS 模拟器共享 Mac 网络路径。
- codesign 出现 `errSecInternalComponent`：在钥匙串里允许 `codesign` 使用 Apple Development 私钥，或刷新 key partition list。

## 验证命令

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze
/Users/huangqi/AIHome/tools/flutter/bin/flutter test
/Users/huangqi/AIHome/tools/flutter/bin/flutter build ios --release
```
