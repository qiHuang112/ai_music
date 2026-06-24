# HarmonyOS Lane 知识库

这里沉淀 HarmonyOS 宿主、ArkTS、HAP、DevEco、`hdc`、鸿蒙音频插件和系统播控相关经验。

## 专项 Skill

- 鸿蒙 lane 处理 HarmonyOS、ArkTS、ArkUI、HAP、`hdc`、AVSession、`module.json5`、`oh-package.json5` 或鸿蒙音频插件任务前，优先使用本机 `harmonyos-development` skill。
- 本机安装路径：`/Users/huangqi/.codex/skills/harmonyos-development/SKILL.md`。
- 来源仓库：`DengShiyingA/harmonyos-ai-skill`；本机源码克隆：`/Users/huangqi/src/harmonyos-ai-skill`。
- 如果当前 Codex 会话识别不到新 skill，先重启 Codex 再继续鸿蒙开发。

## 重点沉淀方向

- `hdc` 设备命令、安装、启动、截图、日志、进程排查。
- DevEco/Hvigor/ohpm 构建、签名、HAP 产物、构建副作用清理。
- HarmonyOS 沙箱目录、权限、资源、显示名和图标。
- `third_party/just_audio_harmonyos` 的 AVPlayer、AVSession、预加载、回调 ownership。
- Flutter 公共层和鸿蒙平台层的边界。

## 经验条目

- [HarmonyOS AVSession 元数据与系统播控接入](avsession-metadata-controls.md)：记录系统播控中心 metadata、状态、按钮命令、HDC/hidumper 验证和回归排查经验。
- [HarmonyOS MediaSource 旧队列与预加载 ownership](media-source-cache-and-preload.md)：记录下载后立即播放、串歌、无声、旧 `mediaSources` 复用和预加载播放器释放相关排查经验。
