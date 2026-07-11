# AM-20260711-003 Library First 页面级实现规范

Request: AM-20260711-003
Design Request: AM-20260711-002
Workflow: superpowers-v1
Lane: ui
Thread: 019ef1d2-d6ec-79d3-9225-fb4169680228
Status: ready_for_android_red_tests
Date: 2026-07-11

## 目标

Product 已选定 `Library First / 我的音乐与继续播放优先` 方向。AM-003 的 UI 实现目标是把当前 Material 3 工程态页面升级为统一、清晰、有音乐产品质感的移动端体验，同时保持现有业务路径：

- 本地资产和当前播放为首页最强层级。
- 搜索是主入口，但服务于“找到完整音频并回到本地播放链路”。
- 热榜是次级发现，不暗示第三方直接播放、播放全部或下载全部。
- 播放页、mini player、列表当前播放态、系统播控必须语义一致。
- Android 和 HarmonyOS 都要保留安全区、键盘和底部手势空间。

本文件只给实现规范，不改业务代码。

## 输入基线

- 目标图：`/Users/huangqi/.codex/generated_images/019ee910-8747-71e3-9293-720273f9e61f/exec-99786479-d2fb-4fcb-a642-c7d25fbb2b74.png`
- AM-002 audit：`docs/codex_collab/knowledge/ui/2026-07-11-am002-real-screenshot-product-design-audit.md`
- QA matrix：`docs/codex_collab/knowledge/qa-researcher/2026-07-11-ui-product-design-regression-matrix.md`
- Android baseline screenshots：`/Users/huangqi/AIHome/output/AM-20260711-002-b306932-xiaomi10/screens/`
- OHOS screenshots/constraints：`/Users/huangqi/.codex/visualizations/2026/06/21/019ee7db-7cfc-7c41-9827-6b851ce89548/AM-20260711-002-ohos-design-facts/`
- Note: `library-first-ohos-implementation-notes.md` was referenced by Product but not found in current readable paths; this spec uses the OHOS constraints file above as the cross-platform source.

## Design Tokens

### Color

Use the existing brand seed `#0D9488` as the compatibility anchor, but expose named tokens for AM-003:

| Token | Value | Usage |
| --- | --- | --- |
| `am.bg.base` | `#07110F` | page background |
| `am.bg.surface` | `#111B18` | standard cards, search field |
| `am.bg.surfaceRaised` | `#182520` | mini player, now playing card |
| `am.bg.surfaceSubtle` | `#22312C` | list rows, empty cards |
| `am.brand.primary` | `#7DDAD1` | primary actions, progress, current lyric |
| `am.brand.primaryStrong` | `#2DD4BF` | active states only |
| `am.brand.discovery` | `#E7C56A` | discovery badges, not main CTA |
| `am.text.primary` | `#F3FAF8` | primary text |
| `am.text.secondary` | `#B9C8C4` | artist, subtitles |
| `am.text.muted` | `#7F918C` | metadata, disabled notes |
| `am.divider.subtle` | `#2A3834` | separators |
| `am.state.error` | `#FF6B6B` | errors |
| `am.state.warning` | `#FFD166` | stale/limited |

Rules:

- Do not turn the whole UI into one flat teal palette.
- Warm discovery color is only for discovery/rank/source metadata, not primary play/download.
- Disabled items must use both lower contrast and explanatory text.

### Typography

| Role | Size / Line | Weight | Notes |
| --- | --- | --- | --- |
| Page title | 32 / 40 | 700 | `搜音乐`, `正在播放` |
| Section title | 20 / 28 | 700 | `继续播放`, `我的音乐`, `QQ 热歌榜` |
| Card title | 17 / 24 | 650 | asset cards, hotlist cards |
| Row title | 16 / 23 | 600 | tracks/search results |
| Body | 15 / 22 | 400 | subtitles |
| Meta | 13 / 18 | 400 | source, quality, date |
| Chip | 12 / 16 | 600 | status chips |

Chinese long text must truncate after 1 line in rows; card subtitles may use 2 lines only when there is no trailing action cluster.

### Shape and Spacing

- Page horizontal padding: 20.
- Section top gap: 28.
- In-section gap: 12.
- Card radius: 14.
- Album art radius: 12 or 16.
- Search field radius: 16.
- Full-width button radius: 999.
- Mini player radius: 18 top corners, or floating 18 all corners if detached.
- Minimum interactive target: 48 x 48 logical px.
- Row min height: 72; dense rows may be 64 only if one trailing action.

## Home IA

Order for populated state:

1. Top safe area + title/action row.
2. Search field.
3. `继续播放` card if current track exists.
4. `我的音乐` asset list.
5. `QQ 热歌榜` / discovery cards.
6. Bottom mini player if current track exists and not using a full continue card interaction.

Order for empty/no current playback state:

1. Title/action row.
2. Search field.
3. `我的音乐` with empty asset cards.
4. `热榜发现` discovery card.
5. Empty mini player is hidden.

### Home Components

Top actions:

- Keep download, library/playlist, settings.
- Icons must have tooltip/semantics.
- Visual weight lower than search and `继续播放`.

Search:

- Placeholder: `歌手、歌曲或歌单`.
- Search button minimum 48 x 48.
- Search should remain visually primary but not dominate current playback card.

Continue card:

- Show only when current track exists.
- Content: album art 64 x 64, title, artist, progress, time text, play/pause button.
- The whole card opens player; play button toggles without navigating.
- If artwork missing, use neutral disc placeholder, not an error icon.

My Music asset rows:

- Use list rows rather than large empty cards when populated.
- Required rows: `收藏`, `自建歌单`, saved `热榜歌单` when exists.
- Asset rows show icon, title, count/preview, chevron.
- `热榜歌单` under `我的音乐` is an asset row; `热榜发现` remains discovery.

Discovery:

- Section title: `QQ 热歌榜` or `热榜发现`.
- Discovery card shows source/date/top 3 songs.
- Required boundary copy in concise form: `榜单用于发现，播放通过 AI Music 搜索匹配`.
- No play-all/download-all affordance.

Mini player:

- Height target: 76 plus bottom safe area.
- Includes artwork/thumb, title, artist, previous, play/pause, next, queue.
- Shows progress as 2px line at top or bottom of container.
- Must not cover home content; page bottom padding accounts for it.

## Search Result Row Pattern

Search page states:

- `idle`: search box + no old results.
- `loading`: 2px top progress + skeleton or loading row.
- `results`: rows with status chips.
- `empty`: readable empty state with retry/search edit.
- `error`: error summary + retry.

Row layout:

- Leading: source/quality chip circle or artwork placeholder, fixed 48 x 48.
- Main line: song title, max 1 line.
- Subline: artist + source + quality, max 1 line.
- Status line/chip: one short reason if needed.
- Trailing: one primary action button, fixed 48 x 48.

Status chips:

| State | Chip text | Action |
| --- | --- | --- |
| downloadable | `可下载` | download |
| cached | `已缓存` | play |
| playing | `播放中` | pause/equalizer state |
| downloading | `下载中` | progress/cancel |
| not_downloadable | `不可下载` | disabled details |
| needs_full_audio | `需完整音频` | disabled |
| source_limited | `来源受限` | disabled/details |

Keyboard constraints:

- With Android/OHOS keyboard visible, at least 4 result rows should remain scannable on a tall device.
- Do not rely on bottom-positioned primary buttons during search.
- Long failure reasons move to chip + optional detail sheet/snackbar; do not place full sentences in row subtitle.

No-preview rule:

- Product validation path must not show `试听`, `PREVIEW`, or `30s` as a playable/download-complete success state.
- If internal preview exists, label it as limited and never write it to formal cache.

## Player and Queue

### Player Detail

Order:

1. App bar: back, title `正在播放`, favorite, add-to-playlist.
2. Artwork.
3. Title/artist.
4. Lyrics preview.
5. Progress/time.
6. Controls.

Rules:

- Artwork should stay visible with lyrics and controls in first screen on Xiaomi 10 Pro and OHOS ALN-AL00.
- Keep a minimum 24 px visual gap above the bottom gesture area.
- Active lyric uses `am.brand.primary`; inactive lyrics use secondary text.
- Stop and mode controls are secondary; play/pause is primary.

### Queue Entry

AM-002 evidence showed queue/add-to-playlist confusion. AM-003 must separate:

- Queue/current playlist: icon `queue_music` or list icon, tooltip `当前队列`, opens queue bottom sheet.
- Add to playlist: icon `playlist_add`, tooltip `加入歌单`, opens add/create playlist sheet.

Queue bottom sheet:

- Drag handle.
- Header: `当前队列`, count.
- Current track highlighted with primary accent and `播放中` label.
- Row: index/artwork/title/artist/duration.
- Tap row jumps playback.
- Empty/single queue has explicit text.
- Sheet max height about 70 percent screen; respects bottom safe area.

## Library, Favorites, Custom Playlists

List row pattern:

- Leading play button 48 x 48, or checkbox in selection mode.
- Title 1 line.
- Subtitle 1 line: artist / size / source.
- Current playing row uses accent title and equalizer/play indicator.
- Trailing actions are capped at two visible icons plus overflow menu.

Modes:

- Normal: play, favorite, more.
- Selection: checkbox, app bar actions, no per-row action cluster.
- Reorder: drag handle, no favorite/more clutter.

Danger operations:

- Delete local music and delete playlist require confirmation.
- Destructive button uses error color only in dialog/action context, not as ambient page color.

## Hotlist

Home discovery card:

- Lower hierarchy than current playback and local assets.
- Shows source/date/top 3.
- Keeps discovery boundary copy.

Saved hotlist playlist:

- Appears under `我的音乐` as asset row `热榜歌单`.
- Subtitle example: `50 首 · QQ 音乐榜单`.

Detail page:

- Header: artwork 96 x 96, title, source/date.
- CTA: `加入歌单`; no play-all/download-all.
- Boundary copy below CTA.
- Row layout must avoid overflow: rank fixed 36, artwork fixed 40, text flexible, action fixed 48.
- Test with two-digit ranks, long titles, missing artwork.

P1 requirement:

- No Flutter debug overflow bars. AM-002 b306932 still showed `overflowed by 4.0 pixels`; AM-003 must include a screenshot proving this is gone.

## Download Manager

Sections:

- `正在下载`
- `最近任务`
- Search current list
- `已缓存音乐`

Row pattern:

- Leading 48 x 48 play/progress icon.
- Title 1 line.
- Subtitle: artist/source/size.
- Status chip for task state.
- Trailing delete/cancel fixed 48 x 48.

States:

- empty active tasks: low-emphasis info row.
- downloading: progress bar under subtitle.
- failed: chip `失败` + short reason.
- canceled: chip `已取消`.
- cached/playing: accent play indicator.

## Settings

Settings should stay utilitarian and trustworthy:

- Keep list layout.
- Group if needed: `外观`, `音乐源`, `诊断`.
- Each row shows title + current value.
- Music source rows show status chips: `可用`, `受限`, `不可下载`, `实验`.
- Long source explanation may wrap to 2 lines; avoid 4-line rows in main settings list.

## Safe Area and Platform Rules

Android:

- Preserve status bar space; do not place tap targets in status area.
- Keyboard visible state must be a first-class layout.
- Back behavior: search state clears before app exit.

HarmonyOS:

- Top status area is taller; keep title/search below it.
- Bottom gesture bar is visually prominent; mini player and player controls need extra bottom padding.
- Avoid left-edge horizontal gestures that conflict with system back.
- Keyboard can occupy about lower third of screen; search results must remain readable above it.

Cross-platform:

- Minimum touch target 48 x 48.
- No important information behind mini player.
- No single-color-only state; pair color with icon/text.

## QA Screenshot Naming

AM-003 evidence must use:

```text
AM-20260711-003_library-first_<platform>_<device>_<page>_<state>_<step>.png
AM-20260711-003_library-first_<platform>_<device>_<scenario>_<result>.mp4
```

Required compare screenshots:

- `home_empty_dark`
- `home_populated_dark`
- `home_mini_player`
- `search_keyboard_results`
- `search_full_audio_candidate`
- `search_not_downloadable_reason`
- `download_manager_active`
- `download_manager_cached`
- `player_detail_lyrics`
- `queue_sheet_current`
- `favorites_current_playing`
- `custom_playlist_reorder`
- `hotlist_home`
- `hotlist_detail_no_overflow`
- `settings_music_source`
- `accessibility_large_font_home`
- `ohos_home_safe_area`
- `ohos_player_safe_area`

Design QA fields must include:

```text
library_first_match: pass|fail|partial|not_checked
full_audio_verified: pass|fail|not_checked
preview_absent: pass|fail|not_checked
not_downloadable_reason_verified: pass|fail|not_checked
hotlist_overflow_free: pass|fail|not_checked
```

## Deviation List for Android RED Tests

Android can start RED tests from these expected failures against the current b306932 UI:

1. Home hierarchy does not yet match Library First target: missing `继续播放` card as strongest layer.
2. Search rows do not yet use structured status chips.
3. Keyboard-visible search needs guaranteed scannable result count.
4. Player page queue entry is not clearly separated from add-to-playlist.
5. True queue bottom sheet evidence is missing.
6. Hotlist detail still shows overflow debug bar in current evidence.
7. Download manager lacks unified task/status chip row pattern.
8. Settings music source rows are too long and need status chips/grouping.
9. Mini player lacks target-artwork/progress treatment in all states.
10. AM-003 screenshot package must prove no `PREVIEW/试听/30s` success path.

## Developer Confirmation Needed

Android:

- Confirm whether AM-003 scope includes adding/reworking a true current queue bottom sheet, or only separating existing add-to-playlist from queue affordance.
- Confirm full-audio sample(s) for RED/GREEN tests, e.g. `一丝不挂`, `稻香`, or task-owner selected stable source.
- Confirm whether hotlist overflow fix is already in AM-003 Project Path or must be included.
- Confirm route for status chips: UI-only presentation from existing resolver/download states, or new enum/state mapping needed.
- Confirm if mini player can show current artwork thumbnail from existing `MediaItem.artUri`.

OHOS:

- Confirm whether Flutter UI changes compile under current OHOS Flutter SDK.
- Confirm safe-area padding behavior for mini player and bottom sheets.
- Confirm keyboard-visible search layout after Android implementation, because OHOS keyboard height differs.

Product/Architect:

- Confirm whether target title remains `搜音乐` or adopts the target image title `音乐`.
- Confirm whether a bottom navigation bar is out of scope for AM-003; current spec assumes no bottom tab bar.
- Confirm whether Library First visual implementation targets 1.1.0 only, while AM-002 current screenshots remain 1.0.2 baseline.
