# AM-20260711-005 Plan：歌曲海搜索与边下边播主链路回归

## Debugging Strategy

Use systematic debugging before implementation. Do not patch symptoms until each bug has a minimal reproduction and failing test or script.

## Phase 1：Source Research Evidence

- Use Chrome user-state and low-frequency scripts for:
  - `剩下的果实`
  - `周杰伦`
  - `周杰伦的外婆`
  - `黄蓉的哎呀`
  - Known good controls: `外婆`、`一丝不挂`、`稻香`、`哎呀`
- For each query record:
  - search URL/request
  - search result title/artist/detail URL/play_id
  - lyrics source and cover source
  - `/api/music` request headers/cookies
  - CDN HEAD status/content-type/content-length
  - Range 206 status and total length
  - external pan evidence, if present, as non-completion path

## Phase 2：Android RED Tests

- Add controller/streaming test for online seek:
  - start progressive playback
  - simulate seek into already downloaded or range-supported middle
  - verify player resumes instead of `playback_load_failed`
- Add resolver test for:
  - download-valid but stream-invalid URL/header mismatch
  - `剩下的果实` search response parsing or miss chain
  - artist-only query returns high-confidence artist result list
  - natural language `周杰伦的外婆` and `黄蓉的哎呀` parsing remains valid
- Add UI/controller tests proving only full playable results expose play/download actions.

## Phase 3：Implementation

- Fix at source:
  - normalize search query modes: title, artist-only, artist + title natural language.
  - keep candidate confidence strict; do not expose low-confidence completion rows.
  - unify streaming and download validation headers where legitimate.
  - fix Range proxy/player seek handling so seeked playback can continue.
- Preserve safety:
  - preview/pan/html/defender/low_confidence fail closed.
  - failed stream/download must not write formal cache.

## Phase 4：Device Verification

- Build debug APK from the independent Project Path.
- Install to Xiaomi 10 Pro.
- Record:
  - seek during online streaming and continued playback.
  - HTTP-error sample before/after behavior.
  - query screenshots/XML for `剩下的果实`、`周杰伦`、`周杰伦的外婆`、`黄蓉的哎呀`.
  - media_session and logcat evidence.
  - cache index/audio/lrc/artwork evidence.

## Phase 5：Review

- Android owner: public Dart boundary, tests, APK, device evidence.
- source-researcher: protocol fidelity and no server pressure.
- android-streaming: seek/range/cache consistency.
- QA: product matrix pass/fail/blocker.
- Architect: merge/push after accepted gates.

