# Lane 知识小仓库

这里记录各个 AI Music Codex lane 在开发、排障、构建、安装、review 过程中沉淀下来的可复用经验。

这不是完整聊天记录，也不是流水账。目标是让后续新加入的安卓、iOS、鸿蒙或架构师对话，能够快速继承前人踩过的坑、学过的命令和已经验证过的判断方法。

## 目录

- `product/`：产品反馈、用户场景、交互取舍、验收口径、优先级和后续测试/UI lane 招募记录。
- `android/`：公共 Dart、Android、测试、Gradle、NDK、ABI、ADB、发布包相关经验。
- `ios/`：iOS 宿主、Xcode、CocoaPods、签名、IPA、真机安装、Apple 平台能力相关经验。
- `ohos/`：HarmonyOS 宿主、ArkTS、HAP、DevEco、`hdc`、鸿蒙音频插件、系统播控相关经验。
- `architect/`：任务拆分、review 模式、跨 lane 分发、架构决策和协同机制经验。

## 什么值得沉淀

- 反复出现的问题。
- 第一次解决但以后大概率会再遇到的问题。
- 靠直觉不好判断、需要多步排查的问题。
- 新学到的命令、工具、日志路径、构建入口、设备操作。
- review 里形成的稳定判断标准。
- 会影响后续新人上手的隐性约定。

## 不要沉淀什么

- 完整聊天原文。
- 证书密码、token、账号凭据、私钥路径细节。
- 没有复用价值的一次性报错。
- 没验证过的猜测。可以记录“待验证”，但不要写成结论。

## 条目模板

```text
# YYYY-MM-DD 标题

Lane: product|android|ios|ohos|architect
Request: AM-YYYYMMDD-NNN 或 ad-hoc
Thread: <codex-thread-id>
Related Commit: <commit-sha 或 pending>

## 背景
- 这次要解决什么问题。

## 现象
- 用户看到什么、日志报什么、命令怎么失败。

## 排查过程
- 关键判断步骤。
- 关键命令。
- 走错的路和为什么排除。

## 根因
- 最终确认的问题原因。

## 解决方案
- 改了什么、怎么改、为什么这样改。

## 验证
- 跑了什么命令。
- 设备或构建结果如何确认。

## 后续复用
- 以后遇到类似问题应该先看哪里。
- 哪些坑不要再踩。
```
