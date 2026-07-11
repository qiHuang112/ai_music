# AM-20260711-004 Gequhai 多样例完整音频复核

Generated: 2026-07-11T09:58:37.343Z
Lane: source-researcher
Workflow: superpowers-v1

## Summary

- Policy: low_frequency_serial_search_detail_api_head_range
- Client eligible: 外婆/周杰伦, 一丝不挂/陈奕迅, 稻香/周杰伦, 哎呀/王蓉
- Fail closed: 东方财富:no_search_match

## Status Table

| query | selected | search | detail | audio | lyrics | cover | classification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 外婆 | 外婆/周杰伦 https://www.gequhai.com/play/6330 | status=200 candidates=8 | id=6330 play_id=62663653a1cb3bf1c96f56f49503382f title=外婆/周杰伦 | HEAD 200 audio/mpeg len=3913543; Range 206 bytes 0-8191/3913543 | 83 lines | ok | direct_full_audio |
| 一丝不挂 | 一丝不挂/陈奕迅 https://www.gequhai.com/play/434800 | status=200 candidates=8 | id=434800 play_id=2383d6b01663ca1ee6797fd62646136e title=一丝不挂/陈奕迅 | HEAD 200 audio/mpeg len=3877617; Range 206 bytes 0-8191/3877617 | 52 lines | ok | direct_full_audio |
| 稻香 | 稻香/周杰伦 https://www.gequhai.com/play/333 | status=200 candidates=8 | id=333 play_id=c26cace43a6d9616683cf0da1e7ebeac title=稻香/周杰伦 | HEAD 200 audio/mpeg len=3576668; Range 206 bytes 0-8191/3576668 | 48 lines | ok | direct_full_audio |
| 哎呀 | 哎呀/王蓉 https://www.gequhai.com/play/38173 | status=200 candidates=8 | id=38173 play_id=93cf9e948de1c7bed52757e816406eeb title=哎呀/王蓉 | HEAD 200 audio/mpeg len=3468831; Range 206 bytes 0-8191/3468831 | 87 lines | ok | direct_full_audio |
| 东方财富 | none | status=200 candidates=0 | not_reached | not_reached | not_reached | missing | no_search_match |

## Evidence

- JSON: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/evidence/script/gequhai-am004-multisample-result.json
- Raw headers/html/bin: /Users/huangqi/AIHome/projects/ai_music_AM-20260711-004/evidence/script

## Minimal Client Protocol

1. GET `/s/{keyword}` with a cookie jar; select only high-confidence title/artist matches.
2. GET `/play/{id}` with the same cookie jar; retry once only when a defender page sets cookies.
3. Parse `window.play_id`, `window.mp3_title`, `window.mp3_author`, `window.mp3_cover`, `window.mp3_extra_url`, and `#content-lrc2`.
4. POST `/api/music` with `id=<play_id>&type=0`, `Origin`, page `Referer`, `X-Requested-With: Http`, `X-Custom-Header: Key`, and the page cookie jar.
5. Validate final CDN with no gequhai referer: HEAD `200 audio/*` plus Range `206` and positive length/total.
6. Only `direct_full_audio` may enter client search results, transient streaming, or formal cache.

## Failure Classification

- `no_search_match` / `low_confidence_match`: do not display as a playable result.
- `external_pan_link`: Quark evidence only, never a completion path.
- `security_or_defender`: stop after one low-frequency retry.
- `play_url_unavailable`: API or page did not provide a usable player URL.
- `non_audio_content`: HEAD/Range did not return audio.
- `range_not_supported`: Range was not 206 or total was missing.
