# Android Lane 知识库

这里沉淀公共 Dart 业务、Android、测试、Gradle、NDK、ABI、ADB 和发布包相关经验。

## 重点沉淀方向

- 公共 `lib/src/` 业务状态、缓存、播放、搜索和测试策略。
- Android 构建、签名、ABI、NDK、Gradle、release 包校验。
- ADB 连接、安装、启动、保数据覆盖、签名不一致处理。
- 和 iOS、HarmonyOS 共享 Dart 行为有关的边界判断。

## 经验条目

- [Android release APK 体积异常排查](android-release-apk-size.md)：定位 `libflutter.so` 未 strip 导致 arm64 release 包从约 9MB 膨胀到约 45MB，并记录构建、验证和发布口径。
