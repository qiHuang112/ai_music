# Android release APK 体积异常排查

## 背景

2026-06-24，产品反馈 Android release 包从早期几 MB 膨胀到 arm64 专用包约 45MB，安装后系统占用 300MB+。排查目标是确认是否为业务资源膨胀、ABI 配置问题、产物类型差异，还是构建链路把未裁剪 native 符号打进包。

## 结论

根因是 Android release APK 打入了未 strip 的 Flutter engine：

- 异常包：`lib/arm64-v8a/libflutter.so` 未压缩 `163,761,776` bytes，zip 后约 `41,712,342` bytes，`file` 显示 `with debug_info, not stripped`。
- 正常旧包：`lib/arm64-v8a/libflutter.so` 未压缩 `11,579,920` bytes，zip 后约 `5,407,825` bytes，`file` 显示 `stripped`。
- 两者 BuildID 相同：`dbac22aadb80e480bb438af805083393e8a064e7`，说明不是 Flutter engine 版本不同，而是同一 engine 是否裁剪符号不同。
- 手动执行 `llvm-strip --strip-unneeded` 后，当前 `libflutter.so` 从约 156MB 降到约 11MB，gzip 后约 5.4MB，和旧包一致。

本次异常与 Dart 业务、assets、Kotlin 代码、FLAC 源、歌词/封面功能无关。assets 总量只有约 0.4MB，最大头明确是 `libflutter.so`。

## 触发条件

本机存在两个 NDK 目录：

- `/Users/huangqi/Library/Android/sdk/ndk/27.0.11718014`：完整可用，含 `source.properties` 和 `llvm-strip`。
- `/Users/huangqi/Library/Android/sdk/ndk/27.0.12077973`：目录不完整，只有空壳或缺少关键文件。

当 `android/app/build.gradle.kts` 临时写成：

```kotlin
ndkVersion = "27.0.12077973"
```

AGP/Gradle 的 `stripReleaseDebugSymbols` 没有真正裁剪 Flutter engine，最终 APK 保留 `with debug_info, not stripped` 的 `libflutter.so`，导致 arm64 单包约 45MB。

恢复为本机完整 NDK：

```kotlin
ndkVersion = "27.0.11718014"
```

后重新构建，arm64 release 包恢复到约 9MB。

## 验证命令

查看 APK 最大文件：

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | sort -nr | head -20
```

抽取并检查 `libflutter.so`：

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk \
  lib/arm64-v8a/libflutter.so > /private/tmp/ai_music_libflutter.so
file /private/tmp/ai_music_libflutter.so
```

正常输出应包含：

```text
stripped
```

如果输出包含：

```text
with debug_info, not stripped
```

则 release 包不合格，不能发布。

检查 Flutter engine jar：

```bash
unzip -l /Users/huangqi/AIHome/tools/flutter/bin/cache/artifacts/engine/android-arm64-release/flutter.jar \
  | grep libflutter.so
```

手动验证 strip 后理论大小：

```bash
tmp=/private/tmp/ai_music_apk_size
mkdir -p "$tmp"
unzip -p /Users/huangqi/AIHome/tools/flutter/bin/cache/artifacts/engine/android-arm64-release/flutter.jar \
  lib/arm64-v8a/libflutter.so > "$tmp/libflutter-current.so"
cp "$tmp/libflutter-current.so" "$tmp/libflutter-current-stripped.so"
/Users/huangqi/Library/Android/sdk/ndk/27.0.11718014/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip \
  --strip-unneeded "$tmp/libflutter-current-stripped.so"
ls -lh "$tmp"/libflutter-current*.so
file "$tmp/libflutter-current-stripped.so"
```

## 正确构建口径

产品验收 Android release 包当前使用 arm64 专用 APK：

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
/Users/huangqi/AIHome/tools/flutter/bin/flutter build apk \
  --release \
  --target-platform android-arm64
```

验收前必须检查：

- APK 大小约 9MB，而不是 45MB 或 130MB。
- `lib/arm64-v8a/libflutter.so` 是 `stripped`。
- 产物只包含目标 ABI 的 Flutter engine；当前仍可能包含少量其它 ABI 的 `libdartjni.so`，但体积很小，不是主因。

## GitHub Release 建议

- 给产品或手动安装：上传 arm64 专用 APK，例如 `ai-music-v1.0.0-android-arm64.apk`。
- 给应用商店：优先上传 AAB，让商店按设备拆分 ABI。
- 不建议上传通用 APK 作为默认安装包，因为通用包会包含多个 ABI，体积明显更大。
- 不要把未 strip 的 45MB APK 或包含多 ABI 的 100MB+ 通用 APK当作正式 release。

## 安装后占用说明

如果 APK 内 native lib 未 strip，安装后系统需要解压/优化巨大 native 库，应用占用可能膨胀到 300MB+。修复后 APK 约 9MB，安装占用应显著下降；如果用户设备仍显示较大占用，需要区分：

- App 本体。
- 数据目录中的歌曲缓存、封面、歌词和 SQLite/JSON 索引。
- 系统安装优化缓存。

## 后续治理

- `android/app/build.gradle.kts` 不要随手改到本机未完整安装的 NDK 版本。
- 如果 Flutter 或插件提示需要更高 NDK，先通过 SDK Manager 正式安装完整 NDK，再改 `ndkVersion`。
- Android release 构建脚本应加入体积 gate：如果 arm64 APK 大于 15MB，或 `file libflutter.so` 不包含 `stripped`，直接失败。
- Kotlin Gradle Plugin / Built-in Kotlin 警告不是本次体积主因，后续单独治理，不阻塞当前包体积修复。
