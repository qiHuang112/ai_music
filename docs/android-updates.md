# Android 局域网更新（2026-10-04）

用户确认只做 Android，不做 iOS/鸿蒙更新。设置显示真实安装版本和当前包构建时间，提供手动检测；启动和进入设置自动检测，发现新版时设置入口和更新行显示红点，安装新版后消失。用户2026-10-05最新约定：每次提交并推送成功后自动构建签名release并发布到Mac局域网，用户从APP更新。默认不再ADB安装。debug仅显示版本，不提示release安装；正式更新通道适用于已安装release的设备。

局域网更新服务提供 release APK 和版本信息；当前已部署在 Mac `192.168.31.167:8788`。用户点更新后下载，显示进度、取消及重试；完整性和包名/版本/签名校验后调起 Android 安装确认，不卸载旧应用。首次需允许本应用安装未知来源包。服务不可达需明确提示，不能报告已是最新。发布时先写完整包再原子更新版本信息，避免手机拿到半包。首次需要安装带更新功能的新版。

试用：新版红点→下载→取消/重试→系统安装；无新版、断网、损坏包、错误签名、低版本均不能误更新。安装后歌单、收藏、下载、设置保留。

## 发布与服务

默认服务地址 `http://192.168.31.167:8788`，与音乐同步服务8787分开；可在检测更新页面修改。只发布 arm64 release，版本比较使用 APK 内真实 `versionCode`。当前 split-per-ABI 构建会给 arm64 加2000，因此 `--build-number 8148` 的成品版本号实际为10148，发布脚本直接读取成品，不能用命令参数猜版本。

在 Mac 发布已签名包：

```sh
python3 tool/publish_android_release.py \
  --apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --root /Users/huangqi/AIHome/releases/ai_music/android \
  --aapt /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/aapt \
  --apksigner /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/apksigner \
  --release-cert f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843 \
  --notes '填写本次更新说明'
```

脚本在归档或切换latest之前验证显式配置的release证书SHA-256，拒绝未知/不同签名；同时拒绝debug、其它包名/ABI、低版本以及相同版本号但不同字节的包。发布目录包含不可变APK、`versions/<完整SHA-256>.json`和最新版指向`latest.json`。每次发布保留前一版和新版的元数据，不清除旧包；同样字节的包去重。历史版本不参与自动选择最新版，即使历史包版本号更高，也不改变当前发布指向。

原计划Windows31.57的SSH和服务端口均拒绝连接，用户要求直接部署后改用当前Mac。Mac部署/更新服务：

```sh
python3 tool/deploy_macos_update_server.py \
  --root /Users/huangqi/AIHome/releases/ai_music/android --port 8788
```

已注册`~/Library/LaunchAgents/com.qi.ai.music.android-updates.plist`，登录自动启动、进程退出自动恢复；服务脚本和日志位于`/Users/huangqi/AIHome/releases/ai_music/update-service`。Mac运行且在家庭网络时可用，休眠/关机时不可达；地址改变可在应用更新页修改。部署脚本不停止占用同一端口的其它服务。

浏览器打开`http://192.168.31.167:8788/`查看最新版与历史APK并下载；`/api/v1/releases/android`提供完整目录，`/api/v1/update/android`只提供当前release。现存包按包名/签名校验后归档64个不同文件（46debug、18release），包括77升级前8143及本轮10145/10146/10148。已丢失或未在本机保存的旧包无法恢复；原始文件也未删除。77已配置实际服务地址，最新release10148内置同一默认值。

后续debug/旧包使用以下归档命令，仅保留、不改变最新版；路径清单每行一个APK绝对路径：

```sh
python3 tool/archive_android_apks.py \
  --paths-file /path/to/apk-paths.txt \
  --root /Users/huangqi/AIHome/releases/ai_music/android \
  --aapt /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/aapt \
  --apksigner /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/apksigner \
  --trusted-cert f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843 \
  --trusted-cert e0eda7c40b0f8d5b67a03d8c21803e21c10d32f2b399216cfd56f14a12bb375d \
  --release-cert f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843
```

Windows恢复后若迁移：同步到`E:\ai_music_updates`时先复制APK和versions目录，最后替换`latest.json`。将`lan_update_server.py`、`android_release_archive.py`和`start_lan_update_server.ps1`放在服务脚本目录，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start_lan_update_server.ps1
```

服务需持续运行并允许家庭局域网访问8788，Windows启动脚本默认读取`E:\ai_music_updates`。接口`/api/v1/update/android`无已发布包返回204，有包返回版本、发布日期、说明、大小、SHA-256和下载地址。原子替换元数据后，手机下次检测即可发现新版。

2026-10-04：当前运行服务已发布release1.0.2/10148，SHA-256 `914c736276b390879161e892596c6f6066d952ef5591f910ba83d34b8bb0e86e`，17276016字节。Mac与77手机LAN读取元数据/历史目录及完整下载真实APK通过；SIGTERM后观察KeepAlive恢复，并继续提供10148。全量432项Flutter、分析/差异检查、服务器3项及归档发布2项测试通过。77保持debug10145，debug不接收release自动安装；新版本红点及系统覆盖安装仍需要release手机试用，191未操作。

2026-10-05：新增保留debug10149及10150，历史目录现在66个不同APK（48debug、18release）。最新77试用包为10150，release更新指向保持10148，191未操作；本轮数据与UI验证见当日工作日志。

2026-10-05 00:57：用户要求191安装最新版release，已通过37349保留数据覆盖1.0.2/10151并启动；永久归档补存旧8144及新10151，现68个不同APK（48debug/20release）。Mac当前最新版指向10151，17289424字节，SHA-256`13d702d90d3a59b66f4c13e67c35b48566ca9deb5282bc855902a880327bff87`，版本接口与完整HTTP下载哈希核对通过。77保持debug10150；本次通过ADB覆盖安装，未据此声称已验证应用内系统安装链路。

2026-10-05 09:38：来源入口/候选缓存/后面5首滚动预缓存与旧缓存切源歌词修复已保留数据交付191最终release1.0.2/10153，17303696字节，SHA-256`489c3126df65d597dec2fba9818147bc0dd6afb6d53ac84ecd5d4de5c3b11146`，证书一致、实际设备包哈希/首次安装时间/启动检查通过。Mac最新指向10153，HTTP完整下载核对通过，当前70个不同APK（48debug/22release），含中间10152；77仍debug10150，本轮未更新。手机锁屏，真实界面/音源体验待用户，未将ADB覆盖安装当成应用内系统安装链路验收。

2026-10-05交付规则纠正：默认仅77 debug，191 release必须由用户明确提出本次交付；不得沿用历史安装授权或因77不可用改装191。已构建/归档同源debug1.0.2/10154，当前历史71包（49debug/22release），归档前后latest.json完全一致。本轮未发布新release、未再操作191；77旧连接端口关闭，debug安装等待用户提供新端口。

2026-10-05 10:37：用户提供77连接端口39509，已保留数据安装debug1.0.2/10154，设备包哈希一致、387个JSON前后一致、首次安装时间保持，首页启动可见原歌单。历史仍71包；release指向10153未变，191未操作。

2026-10-05 10:47：弹窗溢出修复debug1.0.2/10155已保留数据交付77并永久归档；历史72包（50debug/22release），release的latest.json字节保持，无191操作。

独立review修复：重新检查期间候选暂不可操作；服务不可达、HTTP错误或元数据无效后清除旧候选及已下载安装引用，更新卡片与红点消失，错误仍可见，不误报最新；再次成功检查后才恢复。204撤回同时清理旧安装引用。发布命令必须传受信任release证书，错误签名不归档、不改变latest。


## 推送成功后自动构建发布（2026-10-05最新约定）

每次用户要求“提交/推送”，本地提交后统一执行：

```sh
python3 tool/push_and_publish_android.py
```

这是提交交付命令，按顺序执行Git push、确认远端main等于当前干净HEAD、签名release构建、证书校验、不可变归档、原子更新latest，以及局域网元数据和完整APK大小/哈希校验。版本号高于历史debug/release全部包；versionName读取源码pubspec.yaml声明（支持用户升版，不沿用旧latest版本名），arm64版本偏移由脚本处理。元数据记录sourceCommit；同一已发布提交再次执行只验证服务，不重复构建。它由后续开发/提交流程调用，并不是Git原生post-push钩子；手工裸git push不会触发。

若Git已经推送而构建或发布失败，修复本机问题后从同一干净提交重试：

```sh
python3 tool/push_and_publish_android.py --publish-only
```

推送失败不构建；构建失败、源码/远端变化或证书不符不切latest。局域网验证失败会报错，需检查服务。签名配置仅在本机被Git忽略的android/key.properties（0600）或AI_MUSIC_*环境变量中，不提交密码/私钥。服务地址为http://192.168.31.167:8788，Mac需开机且手机在同一局域网；APP检测后用户确认系统安装。默认不再由Codex通过ADB安装手机。
