# AM-20260622-002 安卓播控收藏与随机短听跳过

- Request: AM-20260622-002
- Owner lane: android
- Architect lane: architect
- Product lane: product
- Status: pushed
- Target Version: 1.0.0
- Base Branch: release/1.0.0
- Work Branch: main 迁移前已完成
- Worktree Path: /Users/huangqi/AIHome/ai_music
- Merge Branch: release/1.0.0
- Created: 2026-06-22
- Updated: 2026-06-22

## 背景

产品提出两个 Android / 公共 Dart 播放体验需求：

- Android 系统播控中心 compact 左侧改为点赞/取消点赞，并与 App 内收藏状态同步。
- 随机播放时，如果用户在 10 秒内手动切歌，则该歌曲在当前随机轮次里临时降权或排除，直到本轮歌曲都被切过一次再释放；不能删除真实列表、歌单或队列数据。

## 验收口径

- Android 真机系统播控 compact 左侧必须实际显示收藏/取消收藏入口。
- P0：Android 系统播控中心必须有 4 个槽位，顺序为收藏/取消收藏、上一首、播放/暂停、下一首；4 个槽位必须真机可见且可点，不能只用单测证明。
- 点击系统播控收藏入口必须回到 Dart 业务并同步 App 收藏状态；App 内收藏状态变化后，通知栏图标状态也要同步。
- 随机短听跳过只影响 shuffle 模式下的手动 next。
- 顺序播放、单曲循环、列表循环、自动播下一首不应被短听跳过策略影响。
- 随机顺序要稳定，不能每次手动 next 重新洗牌。
- 短听排除只影响当前随机轮次，不修改真实播放队列、歌单或缓存列表。
- 修复 accepted 前，必须提供 Android 开发测试设备真机验证结果，而不只给 Dart 单测。小米 17 Pro 是 product lane / 主管验收设备，未经 product lane 明确许可不能作为开发自测或安装设备。

## Review 记录

2026-06-22 首轮代码 review 曾按 Dart 单测和静态结构判断为 accepted；产品真机验收后确认两个功能都未达到验收，因此撤回 accepted 结论，改为 changes_requested。

2026-06-22 第二轮复审结论仍为 changes_requested。`MediaAction.rewind` 承载收藏槽位的 Android workaround 可以继续沿这个方向验证，但当前随机修复把 `just_audio` 内建 shuffle 关闭后，只保证手动 `skipToNext()` 走 Dart planner；自然播放到下一首仍可能按原始队列顺序前进，导致“随机播放”本身退化。下一版需要保证 shuffle 模式下手动 next 和自动播下一首都符合随机播放语义，同时只有 10 秒内手动 next 触发短听排除。

2026-06-22 第三轮复审结论仍为 changes_requested。自动播完重定向到 `ShuffleSkipPlanner.nextAfterCompleted()` 的方向正确，但 `_manualTargetIndex` 仍有状态泄漏风险：手动 seek/恢复到当前同一 index 时，`currentIndexStream` 可能不会发出 index 变化事件，标记无法清理；下一次自然播放到其它 index 时会被误判成手动跳转，绕过自动随机重定向。需要让手动标记可可靠清理，并补 handler 层或真机多曲证据。

2026-06-22 第四轮复审代码方向通过，但验收证据仍不足，状态保持 changes_requested。`PlaybackIndexTracker` 已覆盖 `_manualTargetIndex` 残留边界，`MediaAction.rewind` 收藏槽位方向可继续；当前缺口是没有提供多曲开发测试设备上的随机短听实测证据。accepted 前仍需证明 shuffle 模式自然播下一首不顺序化、10 秒内手动 next 会临时排除当前曲、10 秒后手动 next 不排除当前曲、自动播下一首不触发短听排除。

2026-06-22 第五轮复审仍为 changes_requested。产品最新槽位口径已满足：系统播控只发布 3 个 controls，左侧为收藏 custom action，中间播放/暂停，右侧下一首，Stop 不再发布到系统播控；App 内 stop 仍保留。多曲自然播完随机证据也有进展：小米 10 Pro 临时 4 首缓存下，media session 队列 size=4，自然播完从 Alpha 跳到 Gamma，不是顺序 Beta。剩余验收缺口是手动 next 短听排除没有真机/开发机证据；MIUI raw key 不稳定可以不作为阻塞，但需要换可控方式验证 App 内或系统播控 next。

2026-06-22 产品补充截图后推翻上一条槽位判断，P0 验收改为 4 槽位：收藏/取消收藏、上一首、播放/暂停、下一首。此前 3 controls 或挤掉上一首的实现不符合产品预期。下一轮必须在真机系统播控中心证明 4 个槽位顺序正确且可点，重点验证 custom 收藏 action 能固定到第 1 槽，上一首保留在第 2 槽。

2026-06-22 第六轮复审：4 槽位代码和小米 10 Pro 证据通过，但任务整体仍保持 changes_requested，原因是随机短听的手动 next 真机证据仍缺失。当前实现发布完整 controls 顺序为收藏/取消收藏、上一首、播放/暂停、下一首，compact indices 为 `[0, 2, 3]`，Stop 不进入系统播控；小米 10 Pro 通知栏实际显示四按钮且收藏状态可切换。自然播完随机不顺序化也已有证据。剩余验收只要求补 10 秒内手动 next 会临时排除当前曲的开发设备证据。

2026-06-22 第七轮复审 accepted。AM-002 两个功能闭环均有开发设备证据：小米 10 Pro 系统播控四槽位为收藏/取消收藏、上一首、播放/暂停、下一首，收藏点击后通知 custom action 和 App 收藏状态同步；临时多曲缓存验证自然播完不顺序化；使用 App 内下一首按钮在 10 秒内连续手动 next 后，active item 序列未立即回到短听跳过的歌曲，直到本轮剩余候选走完，满足短听排除验收。测试与 analyze/build 均由 android lane 报告通过。

2026-06-22 产品继续调整 Android 播控中心逻辑：点赞/收藏从左边改到右边；右侧原来点赞的位置改成切换播放模式。该口径和当前 accepted 的 4 槽位顺序“收藏/取消收藏、上一首、播放/暂停、下一首”存在冲突，也可能超过 Android/MIUI 系统播控可稳定承载的槽位数量。AM-002 状态从 accepted 调整为 clarification_needed；android lane 不应继续凭猜测实现，必须先提交槽位方案、系统能力判断和小米 10 Pro 截图/`dumpsys media_session` 依据。

2026-06-22 android lane 确认暂停 AM-002 当前回归提交和 AM-003 后续闭环，并给出系统能力判断：小米 10 Pro/MIUI 已验证系统播控卡片可稳定展示 4 个主槽位，audio_service 旧式 compact indices 最多 3 个，但展开系统卡片可按 controls 顺序展示 4 个。若产品同时要求播放模式、上一首、播放/暂停、下一首、收藏/取消收藏，则是 5 个动作，超出当前已验证稳定主槽位。android lane 建议保留上一首/播放暂停/下一首/收藏四个核心动作，把播放模式放到 App 内播放器或后续扩展入口；如果产品坚持播放模式进主槽，则必须牺牲上一首或下一首。架构师判断需要回 product 澄清后再实现。

2026-06-22 android lane 还定位到一个未提交小回归修复：收藏/取消收藏时 `syncControlState` 复用旧 `updatePosition` 但刷新 `updateTime`，导致系统进度条短暂回跳；修复方向是在同步 controls 时同时带当前 `position` / `bufferedPosition` / `speed` / `queueIndex`。该修复已由 android lane 报告通过 test/analyze，并在小米 10 Pro 验证收藏/取消收藏不会回跳；但它尚未提交，需要随最终槽位方案一起 review，不能先混入已 blocked 的 AM-002。

2026-06-22 product 确认：如果 Android 系统播控中心只有 4 个槽位，就先不改槽位逻辑；此前“点赞从左边改到右边、右边改成播放模式”的新槽位需求暂缓/撤回。AM-002 回到已验证的 4 槽方案：收藏/取消收藏、上一首、播放/暂停、下一首。后续 review 不再要求播放模式重排，只聚焦收藏点击导致播控进度条跳变的回归修复，以及既有 4 槽位和随机短听逻辑不回退。

2026-06-22 第八轮复审 accepted。产品撤回槽位重排后，本轮只看收藏/取消收藏导致系统播控进度条跳变的回归修复。`MusicAudioHandler.syncControlState()` 现在同步控件状态时同时写入当前 `updatePosition`、`bufferedPosition`、`speed` 和 `queueIndex`，避免 `PlaybackState.copyWith` 刷新 `updateTime` 但沿用旧 position 造成 Android 系统重算进度跳变；测试覆盖了收藏控件同步保留当前播放快照，并断言系统收藏 action 不触发 `loadQueue`、恢复位置或 seek。android lane 已提供小米 10 Pro 开发机证据：收藏前后 position 自然前进，active item 和 queue size 不变，未使用小米 17 Pro。既有 4 槽位和随机短听验收口径不回退。

2026-06-22 android lane 在版本/worktree 新规落地前已按架构师 accepted 范围提交并推送 `74b8bea`：收藏/取消收藏只刷新控制按钮状态，同时保留当前 `position`、`bufferedPosition`、`speed`、`queueIndex` 快照，避免 Android 播控中心进度条因为旧 position + 新 updateTime 发生跳变。`flutter analyze` 和全量 `flutter test` 通过；小米 10 Pro 开发机验证通知栏收藏/取消收藏可切换、播放 media id/queue 不变、进度只自然前进；未使用小米 17 Pro。后续任务按新规使用 release/feature worktree 和 product 确认后推送。

## 当前问题

- Android 系统媒体控件 compact slot 规则没有被真机验证。`PlaybackState.controls` 中包含 custom action，不等于系统通知 compact 左侧一定展示且可点击。
- 收藏 custom action 的 Dart 单测只验证 handler 回调，不证明 Android 通知点击可以触达 `customAction`。
- 随机短听跳过的 planner 单测只证明策略类行为，不证明 `just_audio` 原生 shuffle / queue index 不会覆盖手动 next 策略。
- 没有区分真机手动 next、通知栏 next、耳机/系统媒体键 next、自动播下一首这些入口。

## Blocker 定位

2026-06-22 android lane 回报初步定位：

- Android 13+ 系统媒体控件对 compact slots 有特殊策略，普通 `MediaControl.custom` 不一定按 `androidCompactActionIndices` 占据 compact 左侧。更稳方案是使用系统会进入 slot 的标准 `MediaAction.rewind` 承载收藏图标，并在 Dart `MusicAudioHandler.rewind()` 中切收藏。
- 随机短听跳过虽然在 Dart `skipToNext()` 中实现，但当前 shuffle 模式仍调用 `just_audio.setShuffleModeEnabled(true)` 和 `_player.shuffle()`，真机手动下一首可能仍被内建 shuffle 行为影响。修复方向是 shuffle 模式只发布 AudioService shuffle 状态，不启用 just_audio 内建 shuffle，由 Dart planner 统一决定手动下一首。
- AM-20260622-003 已暂停并 stash 未提交改动，android lane 回到 AM-20260622-002 提交 `d8c4dfb` 排查。

## 下一步

- android lane 暂停 AM-20260622-003，先回到 AM-20260622-002。
- 先复盘为什么单测和 review 通过但真机无效，并把可复用经验沉淀到 `docs/codex_collab/knowledge/android/`。
- 修复后先在小米 10 Pro `192.168.31.76:41325` 或其它开发测试设备安装验证；只有 product lane 明确许可时，才允许安装到小米 17 Pro。
- 重新请求 architect review 时，必须附 Android 开发测试设备媒体控件截图或日志摘要、收藏回调链路证据、shuffle 手动 next 证据、`flutter test` / `flutter analyze` 结果。
- 2026-06-22 设备口径更正：上一轮 review_request 中小米 17 Pro 安装/自测描述不作为 android lane 自测证据。AM-20260622-002 当前开发自测证据只以小米 10 Pro `192.168.31.76:41325` 为准。
- 下一版需要补充多曲开发测试设备证据，至少证明：shuffle 模式自然播下一首不是固定队列顺序；10 秒内手动 next 会临时排除当前曲；10 秒后手动 next 不排除当前曲；自动播下一首不触发短听排除。
- 需要补充 `_manualTargetIndex` 边界测试：手动恢复/跳转到当前 index 后，自然播下一首仍会走自动随机重定向，而不是被 stale 手动标记放行成顺序播放。
- 第四轮代码复审后剩余动作：无需继续围绕 tracker 结构改代码，优先补多曲开发测试设备证据。若小米 10 Pro 缓存歌曲不足，可在开发设备准备至少 3 首本地缓存，或使用其它明确分配给开发测试的设备；不要使用小米 17 Pro。
- 第五轮后剩余动作：无需围绕槽位口径继续改代码；请补手动 next 多曲证据，证明 10 秒内手动 next 会临时排除当前曲。MIUI `KEYCODE_MEDIA_*` 不稳定时，可以使用 App 内下一首按钮坐标、可控调试日志、测试钩子或其它开发设备方案，但不能使用小米 17 Pro。
- 最新 P0：重新调整系统播控 4 槽位顺序，必须保留上一首。下一次 review_request 需要提供小米 10 Pro 或其它开发测试设备截图/录屏/日志，证明 4 个槽位真机可见且可点。
- 第六轮后剩余动作：不需要继续改系统播控槽位；只补手动 next 短听排除证据。可以通过 App 内下一首按钮、可控日志、测试钩子或其它开发测试设备验证；不要使用小米 17 Pro。
- 第七轮 accepted 后动作：已由 android lane 在新版本/worktree 规则正式落地前完成提交推送，最终提交为 `74b8bea`。
- 最新 clarification_needed：android lane 先不要提交/推送 AM-002。请先给出候选槽位方案并说明 Android/MIUI 系统限制：
  - 方案 A：播放模式、上一首、播放/暂停、收藏/取消收藏，放弃下一首。
  - 方案 B：播放模式、上一首、播放/暂停、下一首、收藏/取消收藏，需要证明系统播控能稳定容纳 5 个动作，否则不可按此实现。
  - 方案 C：保留当前 4 槽“收藏、上一首、播放/暂停、下一首”，另找 App 内或展开态承载播放模式。
  - 如果 4 槽系统无法同时容纳播放模式、上一首、播放/暂停、下一首、收藏 5 个动作，必须回 product lane 决定取舍。
- 回 product 澄清建议：优先推荐“上一首、播放/暂停、下一首、收藏/取消收藏”作为 Android 系统主卡片 4 槽；播放模式放到 App 内播放器页或后续扩展入口。若 product 仍要求播放模式进入系统主卡片，需要明确从上一首、下一首、收藏三者里牺牲哪一个。
- 最新 product 决策：播放模式重排暂缓/撤回，继续使用已验证的 4 槽“收藏/取消收藏、上一首、播放/暂停、下一首”。第八轮进度条跳变修复已通过架构师 review 并由 android lane 推送为 `74b8bea`。后续新增/收尾任务必须使用 `release/x.y.z` 与独立 worktree，不再在主目录继续开发。
