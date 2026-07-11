# 2026-07-11 Active Request Convergence

Lane: architect
Request: AM-TEAM-AUDIT
Thread: 019ee4b7-e7d2-7751-a4c4-150ede83c350
Related Commit: pending

## 背景

Product 扫描主账本后发现一批旧 request 仍停在 `assigned`、`review`、`changes_requested`、`blocked` 或 `accepted_pending_merge`，容易让团队误以为核心歌源和 UI 仍未闭环，或继续在已经被替代的旧方案上空转。

当前事实：

- AM-20260711-004 歌曲海完整搜索、下载、边下边播主链路已推送到 `release/1.1.0`。
- AM-20260711-003 Library First UI 已推送到 `release/1.1.0`。
- `origin/release/1.1.0` 当前收口 HEAD 为 `45b302d48649330446d381b8593c50e22b9099f5`。

## 收敛决策

### 已关闭或被覆盖

- `AM-20260711-001`：Superpowers 工作流规则已在 `main` 生效，标记 `verified`。后续流程规则缺口另开 process request。
- `AM-20260711-002`：Android/OHOS 截图采集已被 AM-20260711-003 UI audit 与 design-qa 消费，标记 `verified`。
- `AM-20260705-017`：歌曲海单样例 PoC 已被 AM-20260711-004 主链路覆盖，标记 `verified / superseded_by_AM-20260711-004`。
- `AM-20260705-013`：22a5 guarded provider 不再作为当前完整音频路径，保留 fail-closed 研究价值，标记 `verified / superseded_by_AM-20260711-004`。

### 继续保留为真实验证任务

- `AM-20260623-003`：HarmonyOS 下载完成后立即播放与缓存状态刷新仍需 release/1.1.0 HAP 真机验证。
- `AM-20260625-003`：队列入口和搜索点击已由 AM-003/004 覆盖；滑动切歌跟手动效仍需 release/1.1.0 真机录屏验证。
- `AM-20260626-001`：歌曲海正向歌词路径已覆盖部分样例；原歌词回归清单仍需 release/1.1.0 小米 10 Pro 真机复测。

## 下一批真正要做

1. OHOS lane：基于 `/Users/huangqi/AIHome/projects/ai_music_ohos` 出 1.1.0 HAP，使用 ALN-AL00 验证 `外婆`、`一丝不挂`、`稻香`、`哎呀` 下载完成后立即播放有声、AVSession、cache index、mp3/lrc 和歌词封面 metadata。
2. Android lane：基于 `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-003` / 最新 `origin/release/1.1.0` 验证播放详情横滑切歌动效，录屏覆盖成功切歌、未过阈值回弹、歌词纵向滚动不误触、队列 sheet 不误触。
3. Android lane + QA researcher：基于 release/1.1.0 对 `坏孩子`、`苦笑`、`风度`、`昆明晚安`、`春雨里洗过的太阳`、`一丝不挂` 做歌词真实设备回归；每首必须有 provider chain、cache metadata、播放页歌词截图或结构化 miss chain。

## 验证

- `team_ops.py scan --legacy-ok` 用于确认 active 列表收敛。
- 被更新的 Superpowers request 单独运行 `validate-request` 和对应 `validate-workflow`。
- 旧 request 仍可有 legacy warning；本轮目标是不让已覆盖旧任务继续占用 active 状态。
