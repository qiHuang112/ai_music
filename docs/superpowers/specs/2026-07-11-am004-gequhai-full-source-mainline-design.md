# AM-004 Gequhai Full Source Mainline Design

## Problem

The current user-visible build can show search results that are not complete playable songs. Product requires a strict mainline: every visible search result must be a complete playable and downloadable Gequhai song, with lyrics, artwork, progressive playback, and final cache promotion.

## Root Cause

Legacy providers mixed four different states into one user-facing result list: browser-only playback, external pan links, preview snippets, and verified complete audio. This let the UI show songs that could not be played, downloaded, or progressively cached in the app.

## Product Requirements

- Use Gequhai as the current primary source.
- Search through Gequhai, open the detail page, read lyrics and artwork from the page, call `/api/music`, validate the returned mp3, and use that full audio for playback.
- Search results must only show complete playable songs.
- No iTunes preview, `PREVIEW`, `30s`, external pan, HTML, defender page, or non-downloadable BuguYY/FLAC row may appear as a completion path.
- Clicking a result means download and play; the download button means download only.
- Progressive playback must start before the whole file has downloaded and must promote to formal cache when complete.

## Proposed Architecture

- Add or narrow `source_gequhai` as the only user-visible online search provider for this recovery task.
- Implement a Gequhai provider pipeline: search page -> detail page -> API music URL -> media HEAD/Range validation -> resolved direct audio with lyrics and artwork.
- Keep resolver and cache fail-closed: only validated direct audio may enter transient streaming or formal cache.
- Keep UI simple during recovery: if no complete Gequhai result exists, show an empty state or structured failure reason instead of showing disabled source rows.

## Interfaces

- `GequhaiSearchProvider.search(keyword)` returns candidates with `title`, `artist`, `playId`, `detailUrl`, `source=source_gequhai`.
- `GequhaiPlayerAudioResolver.resolve(candidate)` returns `ResolvedMusic` only when detail, API, HEAD, and Range gates pass.
- `ResolvedMusic.lyrics` comes from page `#content-lrc2`.
- `ResolvedMusic.artworkUrl` comes from `window.mp3_cover`.
- `ResolvedMusic.canCacheAudio` is true only for validated full audio.
- `MusicController.playCandidate(candidate)` starts transient streaming, then promotes completed audio to formal cache.

## Failure Behavior

- Low title/artist confidence: hide from complete results and record `low_confidence_match`.
- Quark or other pan link: record `external_pan_link`, never cache.
- Defender or blocked page: record `security_or_defender`, never cache.
- API without usable URL: record `play_url_unavailable`.
- Non-audio HEAD/Range: record `non_audio_content`.
- Missing or invalid length/range total: record `audio_validation_failed`.

## Verification

- Unit tests cover search parsing, detail parsing, cookie jar, `/api/music` headers, media validation, lyrics/artwork extraction, fail-closed cases, and UI result filtering.
- Controller tests cover click-to-download-and-play, download-only button, transient streaming, cache promotion, and failure not writing cache.
- Xiaomi 10 Pro main path covers `外婆`, `一丝不挂`, `稻香`, `哎呀`, and one failure case.
- Evidence must include APK sha, device target, search screenshots or XML, media session state, first byte time, part growth, download completion time, cache index, lyrics, and artwork.

## Non-Goals

- Do not re-enable BuguYY or FLAC as visible completion paths.
- Do not implement another four-source picker in this task.
- Do not use Quark download, iTunes preview, or browser-only playback as completion.
- Do not finish the Library First UI redesign until this P0 core source path is working.
