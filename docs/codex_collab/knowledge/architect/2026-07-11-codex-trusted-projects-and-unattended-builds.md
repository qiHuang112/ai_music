# Codex 受信任目录与 AI Music 无人值守测试/构建

Created: 2026-07-11
Owner Lane: architect
Related Request: AM-20260711-001

## 结论

AI Music 本机可以使用三层配置减少或消除项目内测试/构建的逐次授权：

1. Codex 受信任项目目录：`/Users/huangqi/.codex/config.toml`
2. Codex execpolicy prefix 规则：`/Users/huangqi/.codex/rules/default.rules`
3. 显式无人值守 profile：`/Users/huangqi/.codex/ai-music-unattended.config.toml`

项目内测试、分析、构建和账本校验应优先走这些入口。涉及本机 socket、网络、ADB/HDC、系统设置、设备安装、Keychain/codesign 或第三方站点探测时，仍按 Codex 当前安全策略和设备归属授权执行，不能把项目 trust 当成系统权限绕过。

## 已配置路径

`/Users/huangqi/.codex/config.toml` 当前包含：

```toml
[projects."/Users/huangqi/AIHome"]
trust_level = "trusted"

[projects."/Users/huangqi/AIHome/ai_music"]
trust_level = "trusted"

[projects."/Users/huangqi/AIHome/projects"]
trust_level = "trusted"
```

`/Users/huangqi/.codex/rules/default.rules` 已包含 AI Music 常用前缀，例如：

```text
prefix_rule(pattern=["python3", "docs/codex_collab/tools/team_ops.py"], decision="allow")
prefix_rule(pattern=["/bin/zsh", "-lc", "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn /Users/huangqi/AIHome/tools/flutter/bin/flutter test"], decision="allow")
prefix_rule(pattern=["/bin/zsh", "-lc", "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn /Users/huangqi/AIHome/tools/flutter/bin/flutter analyze"], decision="allow")
prefix_rule(pattern=["/bin/zsh", "-lc", "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn /Users/huangqi/AIHome/tools/flutter/bin/flutter build apk"], decision="allow")
prefix_rule(pattern=["/bin/zsh", "-lc", "unset NODE_OPTIONS; OHOS_FLUTTER_BIN=/Users/huangqi/AIHome/tools/flutter_ohos/bin/flutter OHOS_CODESIGN=true tool/build_ohos_hap.sh"], decision="allow")
```

`/Users/huangqi/.codex/ai-music-unattended.config.toml` 当前包含：

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

推荐无人值守 Codex CLI 入口：

```bash
/Applications/ChatGPT.app/Contents/Resources/codex -p ai-music-unattended exec -C /Users/huangqi/AIHome/projects/<project> "<prompt>"
```

## 验证输出

配置解析：

```text
$ /Applications/ChatGPT.app/Contents/Resources/codex --strict-config -p ai-music-unattended exec --help >/tmp/ai-music-unattended-exec-help.txt && echo "codex exec strict-config profile OK"
codex exec strict-config profile OK
```

项目内命令：

```text
$ cd /Users/huangqi/AIHome/projects/ai_music_AM_TEAM_AUDIT
$ python3 docs/codex_collab/tools/team_ops.py validate-request docs/codex_collab/requests/AM-20260711-003-library-first-ui.md
OK
```

配置项检查：

```text
trusted /Users/huangqi/AIHome: OK
trusted ai_music: OK
trusted projects parent: OK
unattended approval never: OK
unattended danger full access: OK
team_ops prefix allow: OK
flutter test prefix allow: OK
```

## 使用边界

- 可无人值守：Flutter tests、Flutter analyze、Android APK build、OHOS HAP build、`team_ops.py` 门禁、常规 git 只读检查。
- 需继续按安全策略授权或回 blocker：ADB/HDC 设备操作、局域网端口、第三方站点请求、Browser/Chrome/Computer Use 控制、系统输入法/锁屏/通知栏、Keychain/codesign/profile、删除用户或设备数据。
- 如果 Codex 平台或 workspace 管理策略禁止某个动作静默执行，不要把它写成已完成；回 `blocker`，写清唯一可行的用户级设置或授权入口。
