# Worktree 管理手册

AI Music 使用 `git worktree` 隔离多个版本和多个 lane 的开发。主目录 `/Users/huangqi/AIHome/ai_music` 只用于 `main` 稳定主线和产品验收，不再作为多人共用开发目录。

## 目录约定

```text
/Users/huangqi/AIHome/ai_music
  main 稳定主线 / 产品验收入口

/Users/huangqi/AIHome/worktrees/ai_music/release-1.0.0
  release/1.0.0 当前版本收口

/Users/huangqi/AIHome/worktrees/ai_music/release-1.0.1
  release/1.0.1 下一版本集成

/Users/huangqi/AIHome/worktrees/ai_music/android-AM-20260622-003
  单 request 开发 worktree
```

## 创建流程

1. 架构师从干净 `main` 创建版本分支和版本 worktree。
2. 架构师为 request 分配 `Target Version`、`Base Branch`、`Work Branch`、`Worktree Path` 和 `Merge Branch`。
3. owner lane 从 `release/<version>` 创建自己的 feature worktree。
4. owner lane 只在自己的 feature worktree 开发、测试和提交。
5. review accepted 后，架构师把 feature 合入对应 `release/<version>`。
6. product 确认推送后，架构师在 release 分支打 tag、构建 Android release 包、push release 分支和 tag。
7. release 发布后再合入 `main`。

## 命名规则

- 版本分支：`release/x.y.z`
- 需求分支：`feature/x.y.z/AM-YYYYMMDD-NNN-short-name`
- 热修分支：`hotfix/x.y.z/AM-YYYYMMDD-NNN-short-name`
- worktree 目录：`/Users/huangqi/AIHome/worktrees/ai_music/<lane>-AM-YYYYMMDD-NNN`

## 冲突规则

- 冲突不在主目录解决，只在 feature 合入 release 时解决。
- 开发 lane 遇到冲突时先停止开发，向架构师发 `blocker`，写清冲突文件、request、目标分支和当前 worktree。
- 架构师解决冲突时优先保留目标版本已 accepted 的行为。
- 如果两个需求都改同一体验，回 product lane 决定优先级。
- 冲突解决后，相关 lane 必须重新跑对应测试。

## 禁止事项

- 禁止开发 lane 在 `/Users/huangqi/AIHome/ai_music` 主目录日常开发或切分支。
- 禁止多个 lane 共用同一个 request worktree。
- 禁止复用别人的 stash。
- 禁止跨 request 混合提交。
- 禁止把未 review 代码合入 release。
- 禁止用 `git reset --hard`、`git checkout --` 等破坏性命令覆盖他人改动。

## 空间管理

- worktree 占空间时，优先清理对应 worktree 的 `build/` 和 `.dart_tool/`。
- 不删除源码目录，不删除未合并分支。
- 构建产物不作为冲突依据，冲突只看 tracked files。

