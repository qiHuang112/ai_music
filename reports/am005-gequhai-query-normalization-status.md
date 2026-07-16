# AM-005 歌曲海 query normalization 复核

- JSON: `/Users/huangqi/AIHome/projects/ai_music_AM-20260711-005_gequhai_search_streaming/evidence/script/am005-query-normalization/gequhai-am005-query-normalization-result.json`
- Policy: `low_frequency_serial_requests_no_pan_download_no_concurrency`
- Started: `2026-07-11T15:33:34.479Z`
- Finished: `2026-07-11T15:34:21.553Z`

## 结论表

| raw query | 结论 | 可进入客户端完整结果 | 关键 normalized 链路 | 说明 |
| --- | --- | --- | --- | --- |
| 周杰伦 | client_ready_artist_only_high_confidence | 是，作为歌手列表候选 | raw: 晴天/周杰伦/detail 326/api_play_id 1ef8ce2bf714ee0e2f5e324bf5ce9128 | HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。 |
| 周杰伦的外婆 | client_ready_high_confidence | 是 | title-only: 外婆/周杰伦/detail 6330/api_play_id b637c92af5e51c7be477f49196133caa | HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。；raw query 为 no_search_match |
| 黄蓉的哎呀 | client_ready_title_exact_artist_near_match_requires_explanation | 可展示但需解释/保留真实 artist | title-only: 哎呀/王蓉/detail 38173/api_play_id e4e22b6e45697d4d1e50d8457f6df475 | HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。；raw query 为 no_search_match |
| 剩下的果实 | client_ready_high_confidence | 是 | raw: 剩下的果实/小羊/detail 5553349/api_play_id 14089f6714f41221c328d485d1922f42 | HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。 |

## 每条 query 的候选与失败链

### 周杰伦

- raw `周杰伦`: direct_full_audio；HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。
  - selected: title=`晴天`, artist=`周杰伦`, detail=`https://www.gequhai.com/play/326`, detail_id=`326`, api_play_id=`1ef8ce2bf714ee0e2f5e324bf5ce9128`, confidence=`0.86`, reason=`artist_exact_list_candidate`
  - media: HEAD=`200`, Range=`206`, total=`4317292`, lyricsLines=`63`, cover=`present`
  - candidates: 1.晴天/周杰伦 play/326 c=0.86 artist_exact_list_candidate; 2.青花瓷/周杰伦 play/553 c=0.86 artist_exact_list_candidate; 3.七里香/周杰伦 play/329 c=0.86 artist_exact_list_candidate

### 周杰伦的外婆

- raw `周杰伦的外婆`: no_search_match；没有满足 title/artist 置信阈值的候选。
- title-only `外婆`: direct_full_audio；HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。
  - selected: title=`外婆`, artist=`周杰伦`, detail=`https://www.gequhai.com/play/6330`, detail_id=`6330`, api_play_id=`b637c92af5e51c7be477f49196133caa`, confidence=`1`, reason=`title_artist_exact`
  - media: HEAD=`200`, Range=`206`, total=`3913543`, lyricsLines=`83`, cover=`present`
  - candidates: 1.外婆/周杰伦 play/6330 c=1 title_artist_exact; 2.外婆的澎湖湾/任贤齐 play/22301 c=0 no_title_match; 3.外婆的澎湖湾/卓依婷 play/16907 c=0 no_title_match
- artist-title-space `周杰伦 外婆`: direct_full_audio；HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。
  - selected: title=`外婆`, artist=`周杰伦`, detail=`https://www.gequhai.com/play/6330`, detail_id=`6330`, api_play_id=`d0e0c5be313dd4a38d1b8413252859e4`, confidence=`1`, reason=`title_artist_exact`
  - media: HEAD=`200`, Range=`206`, total=`3913543`, lyricsLines=`83`, cover=`present`
  - candidates: 1.外婆/周杰伦 play/6330 c=1 title_artist_exact; 2.我的地盘+七里香+借口+外婆+将军+搁浅+乱舞春秋+困兽之斗+园游会+止战之殇/周杰伦 play/4643 c=0 no_title_match; 3.外婆 (Live)/周杰伦 play/22303 c=0 no_title_match

### 黄蓉的哎呀

- raw `黄蓉的哎呀`: no_search_match；没有满足 title/artist 置信阈值的候选。
- title-only `哎呀`: direct_full_audio；HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。
  - selected: title=`哎呀`, artist=`王蓉`, detail=`https://www.gequhai.com/play/38173`, detail_id=`38173`, api_play_id=`e4e22b6e45697d4d1e50d8457f6df475`, confidence=`1`, reason=`title_artist_exact`
  - media: HEAD=`200`, Range=`206`, total=`3468831`, lyricsLines=`87`, cover=`present`
  - candidates: 1.哎呀哎呀 (DJ阿卓版)/大黑&王小胖 play/1030937 c=0 no_title_match; 2.哎呀/王蓉 play/38173 c=1 title_artist_exact; 3.哎呀/李荣浩 play/68689 c=0.65 title_exact_artist_missing_or_mismatch
- artist-title-space `黄蓉 哎呀`: no_search_match；没有满足 title/artist 置信阈值的候选。

### 剩下的果实

- raw `剩下的果实`: direct_full_audio；HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。
  - selected: title=`剩下的果实`, artist=`小羊`, detail=`https://www.gequhai.com/play/5553349`, detail_id=`5553349`, api_play_id=`14089f6714f41221c328d485d1922f42`, confidence=`1`, reason=`title_artist_exact`
  - media: HEAD=`200`, Range=`206`, total=`4153855`, lyricsLines=`29`, cover=`present`
  - candidates: 1.剩下的果实 (cover: 糖糖) (Live)/陈玖术 play/5553351 c=0 no_title_match; 2.剩下的果实/小羊 play/5553349 c=1 title_artist_exact; 3.剩下的果实/慢四 play/5553343 c=1 title_artist_exact

## 客户端最小协议建议

- 对 `artist的title` 先解析为 `artistHint` + `titleQuery`，歌曲海 search 只发 `titleQuery`；raw query miss 不能直接判源站无歌。
- 对纯歌手 query 允许按 artist-only 列表召回；每个可操作候选仍必须通过详情 artist 校验和 media gate，不能把合集/错歌手低置信行当完成路径。
- 候选详情页必须重新校验 `mp3_title/mp3_author/play_id`；`artistHint` 与真实 artist 精确一致才是高置信自动完整结果。
- `黄蓉的哎呀` 只能作为 `title_exact_artist_near_match`：展示真实 `哎呀/王蓉` 并保留纠错说明，不得把 artist 写成 `黄蓉`。
- 完整结果仍需 page -> `/api/music` -> CDN no-referer HEAD 200 audio -> Range 206 audio/totalLength 正数；夸克只作 evidence，不进入完成路径。
