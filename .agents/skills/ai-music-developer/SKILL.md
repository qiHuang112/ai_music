---
name: ai-music-developer
description: Develop and self-test AI Music on phone 77; review only current changes and publish an existing verified release APK to LAN without routine CI, rebuilds, or repeated tests.
---

# AI Music developer

这是本项目开发、自测、增量审查和交付的唯一流程入口。用户2026-10-21要求缩短“走流程”：**增量review → 复用已有release APK → 局域网发布 → 一次下载核验**。该决定取代旧的强制提交推送、云端CI构建和镜像流程，旧文档不能重新成为前置条件。

## 工作边界

- 在 `/Users/huangqi/AIHome/projects/ai_music` 当前checkout的main开发。未经用户要求不切分支，不创建worktree、clone或替代工程；保留现有改动、源码、历史和用户数据。
- 修改前读取git状态、`CURRENT_STATE.md`及受影响功能文档；Flutter使用 `/Users/huangqi/AIHome/tools/flutter/bin/flutter`。
- 固定“AI music-代码 review”会话已归档，不恢复、不创建永久review角色。仅用户要求review或“走流程”时启动一个临时独立只读reviewer。
- 普通开发、修改skill、补记日志不自动发布。“走流程”按下列路径直接完成，不逐步索要确认。Git提交／推送、GitHub Release和CI另按明确请求处理，不绑到局域网交付。

## 开发与验收前完成

1. 在对应功能文档简短记录最新需求和失败场景；歌曲、音源、缓存或设备影响问题时，使用实际场景复现。
2. 修复后做与改动相称的定向检查；新风险或项目明确要求时才扩大测试。小范围UI修改不默认扩展功能测试。已有通过记录且源码未变时直接复用，不重复跑全量套件。
3. 完成一轮修复后再构建／归档，保留数据安装77，实机自测后交用户体验。已有匹配源码和交付身份的成品直接复用，不每次编辑后重编。安装或宿主机接口探针不冒充手机自测；77不可用或自测失败继续排查并如实说明，不改装191。
4. 留下实际APK路径、版本、哈希及源码记录供后续直接交付。用户要求独立体验包时保留独立身份，preview不能改名冒充正式包。验收后源码未变，不重复安装、自测、分析或全量测试。

## 增量独立review

1. 确定**本次尚未审过的改动**。通常只需git diff、少量新文件和受影响函数；已通过且未变的部分沿用结论。文档／日志更新不扩展成全仓库或历史发布审计。
2. 用基线、待审diff／文件及内容哈希简单固定目标，结果留在 `build/review/`。不例行打源码ZIP、复制整个工程、逐包扫描历史APK或重新核验未变的全部运行源码。
3. 用 `collaboration.spawn_agent`、`fork_turns: "none"` 启动一个全新临时reviewer，传入本skill、明确需求、**具体改动位置**、已有相关测试／手机证据和成品信息；不得再委派。
4. reviewer只读检查这些改动，以及确实需要的直接调用处／模型／持久化或异步分支。只报告本轮引入、可复现、有实际影响的问题，给出P级、最小路径行号、触发和影响；无问题返回 `No findings.`。不为例行审查重跑完整测试、审未改的CI／更新／签名脚本或检查整个GitHub仓库。
5. 直接核查已有测试／设备证据，只有具体疑点才跑定向探针。发现问题由开发修复，仅补变更部分的测试和复核；确实改变已装行为时才补手机检查。补记结果不重开review。reviewer不编辑、提交、推送、发布或操作手机。

## 复用成品并发布局域网

1. review通过后确认最终改动与所选APK的源码记录一致。**不重新构建、不重新分配版本号、不触发或等待CI，不调用 `push_and_publish_android.py` 的任一路径。** 也不自动git push间接触发构建；当前GitHub工作流仍监听main推送。
2. 从已有记录选正确正式包，只核对本次成品：`com.qi.ai.music`、名称“来听”、arm64 release不可调试、原可信证书、真实版本与大小／SHA256。可靠的已有核验结果直接复用；版本冲突看归档元数据和当前LAN指针，不逐个打开历史APK。旧源码包、debug或preview不能进入正式通道。
3. 若确实没有匹配源码及正式身份的包，立即简短说明缺哪个成品；仅补必要的正式包构建一次，不默默回到云端CI／整套测试。不因review、记录或发布阶段本身生成新包；不能实际只有preview却声称已有正式包。
4. 用现有发布工具校验归档该APK，原子切换LAN latest；保留旧包，失败保持旧latest。同版本同哈希已发布则直接核验，不重复发布。源码提交字段仅在确实匹配时记录，不为填字段强制提交推送或冒写HEAD。

   ```sh
   JAVA_HOME=/Users/huangqi/Library/Java/JavaVirtualMachines/openjdk-22.0.1/Contents/Home \
   python3 tool/publish_android_release.py \
     --apk /绝对路径/已存在的正式release.apk \
     --root /Users/huangqi/AIHome/releases/ai_music/android \
     --aapt /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/aapt \
     --apksigner /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/apksigner \
     --release-cert f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843 \
     --notes '本次实际更新说明'
   ```

5. 读取 `http://192.168.31.167:8788/api/v1/update/android`，完整下载指向的APK**一次**，比较版本、大小与SHA256。相同哈希的下载不再重复aapt／签名检查，不额外走GitHub下载和镜像核验。正式更新由用户从APP操作，不额外ADB安装，不操作191或发布iOS。
6. 工作日志只补一段实际结果，`CURRENT_STATE.md`更新当前版本；不为补记结果再审查／构建／发布。简短报告review结果、LAN版本与更新入口。

## 例外与节奏

- Mac任务在当前Mac自测，不套用77安装或APK步骤。各平台对外版本名／构建号统一，Mac不另起版本系列；本次Mac首版与Android正式版一致为1.0.4／10268。复用对应Mac release `.app`，用ditto保留签名／符号链接打ZIP，归档在 `releases/ai_music/macos/`，通过现有8788服务的 `/api/v1/update/macos` 和 `/releases/macos/文件.zip` 发布，Android指针保持。首版缺release成品时仅补必要本机构建；如仅有ad-hoc本地签名，明确未做Developer ID签名／Apple公证，不宣称已公证。
- 用户明确要求GitHub发布／CI时才启用原远端路径，核对对应提交与产物；它不是默认路径。只要求review就到审查结束。
- 发布工具、签名或更新链路**本身被改动**时，才对相应改动补专项检查。普通业务修复不重复审计未改的基础设施。
- 开始时说明实际下一步，有结果或阻碍时简短更新。无真实风险时不新增审批、仪式性快照、轮询或检查清单。已验收修改的收尾不能变成再次完整开发一轮。
