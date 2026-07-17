# AM-005 Streaming Seek, Progressive Search, and Pagination Design

Status: user-approved design
Request: AM-20260711-005
Date: 2026-07-16

## Problem

The current Gequhai path couples search, full-audio validation, playback
resolution, and progressive caching too tightly:

- Search validates every parsed candidate serially through detail page, player
  API, `HEAD`, and `Range` before returning any result.
- Playback resolves the same candidate again instead of reusing the result that
  search already validated.
- Search always requests `/s/<query>`, truncates the parsed rows to eight, and
  stores page `0`, even though Gequhai exposes later pages with `?page=N`.
- Progressive caching downloads one contiguous prefix from byte zero. A seek
  beyond that prefix waits for the background download and returns HTTP 504
  after the first-byte timeout.
- A player that entered an error state has no explicit reload path when the user
  presses play again.

## Goals

1. Show each validated result as soon as it is ready instead of waiting for the
   whole page.
2. Load later Gequhai pages automatically when the user reaches the bottom of
   the visible result list.
3. Reuse search-time full-audio resolution for the first play or download
   action, with one fresh resolution available if playback loading fails.
4. Keep forward and backward seek usable while the contiguous background cache
   is incomplete.
5. Preserve the existing fail-closed rule: only validated complete audio is
   visible, and failures never create a formal cache entry.

## Non-goals

- No visual redesign of the search page.
- No parallel fan-out across all Gequhai candidates or pages.
- No eager loading of every available page.
- No sparse-file or block-cache implementation in this change.
- No restoration of preview, HTML, pan-link, or legacy sources as successful
  completion paths.

## Chosen Approach

Use progressive validated search, session-scoped prepared resolutions, and
on-demand upstream Range pass-through for cache misses.

Direct CDN playback was rejected because it would reintroduce the existing
failure mode for sources whose direct player request and download behavior
differ. A sparse block cache was rejected because its index, merge, eviction,
and promotion rules are larger than the P1 problem requires.

## Search Architecture

### Page fetch and parsing

The Gequhai resolver will accept an explicit one-based page number. Page 1 uses
`/s/<encoded-query>` and page N uses `/s/<encoded-query>?page=N`. Parsing will
return the candidate rows plus whether a next-page link exists. Every candidate
will carry its real page number.

The parser will no longer use an application-level `take(8)` truncation. It will
process the rows returned by the current provider page, while existing title,
artist, and confidence filters remain unchanged.

### Progressive validation

Candidates on one page remain serial to respect the provider's low-frequency
request policy. Each candidate still passes the complete chain:

1. detail page metadata and candidate match;
2. player API direct URL;
3. audio `HEAD` validation;
4. byte-zero `Range` validation.

After one candidate passes, the resolver emits an updated immutable result list
immediately. Validation of the remaining rows continues in the background of
the same search request. A newer query invalidates all later emissions from the
older request.

This changes perceived latency without weakening the full-audio gate. The first
visible result no longer waits for the rest of the page. Timing logs will record
page fetch, each candidate validation, first visible result, and page completion
separately; third-party network time will be reported rather than hidden behind
a fixed SLA.

### Pagination state

`MusicController` will keep explicit search state for current query, current
page, next-page availability, initial loading, and load-more loading. Loading a
page is idempotent: only one request for a given page can be active, and merged
candidates are deduplicated by concrete source, platform, and candidate ID.

The result list will request the next page when its scroll position approaches
the bottom. If a page yields no visible candidate but advertises a next page,
the controller may continue to the next page so an empty first page cannot
strand pagination. Only one page is processed at a time.

An initial-page failure uses the existing search error state. A later-page
failure preserves existing results and exposes the existing refresh action as a
retry for that page. It must not restart page 1 or clear the list.

### Prepared resolution reuse

Successful search validation stores the corresponding `ResolvedMusic` in an
in-memory prepared-resolution map owned by the resolver. The key is the same
concrete candidate identity used for pagination deduplication.

The first `resolve` call for that candidate consumes the prepared value without
network requests. Prepared values are cleared on a new search session and are
bounded to candidates in that session. If player loading fails after consuming
the prepared value, one subsequent resolve performs a fresh detail/API/media
chain. There is no unbounded automatic retry.

## Streaming and Seek Architecture

The background cache remains a single contiguous file from byte zero. This
keeps cache promotion atomic and avoids sparse-file correctness problems.

For each local proxy request:

1. Reject malformed or truly unsatisfiable ranges with HTTP 416.
2. If the requested start is already inside the downloaded prefix, serve it
   from the part file and continue following background growth.
3. If the requested start is ahead of the downloaded prefix, open an upstream
   request for that exact Range and stream the validated response directly to
   the player.
4. Do not write pass-through seek bytes into the part file. The independent
   byte-zero background fetch remains the only writer and may still promote the
   file after complete download.

An upstream seek response is usable only when it is HTTP 206, starts at the
requested byte, has an audio content type, and reports a positive consistent
total length. A malformed or mismatched response fails closed and leaves the
formal cache untouched.

The valid initial `Content-Range` matcher will be corrected so a normal
`bytes 0-<end>/<total>` response is accepted instead of unnecessarily falling
back to a full GET.

## Player Recovery

`MusicAudioHandler` will record player source errors. If the current source is
in an error/idle state and the user presses play, the handler reloads the current
queue item at the last known position once, then plays it. A seek issued after
an error uses the requested position as the reload position.

Recovery is user-triggered and single-attempt. Repeated upstream failures remain
visible as structured playback errors rather than entering a retry loop.

## Failure and Cache Rules

- Search candidates that fail detail, API, `HEAD`, or `Range` validation remain
  hidden.
- A failed later page does not discard previously validated candidates.
- A failed on-demand seek Range does not modify the contiguous part file.
- A failed background fetch remains transient and cannot be adopted into the
  formal cache.
- Cache promotion occurs only after the byte-zero background download reaches
  its validated total length.
- Starting a new streaming candidate retires the old local proxy token as it
  does today.

## UI Behavior

- The existing top progress indicator remains visible while page 1 continues
  validating, even after the first rows appear.
- Scrolling near the bottom automatically starts the next page.
- Loading another page does not disable actions on existing rows.
- A later-page error keeps the rows visible and shows the existing refresh icon
  for retry.
- No page-number controls or explanatory copy are added.

## Verification

### Automated tests

- Gequhai page 1 and page N use the correct URLs and candidate page numbers.
- Next-page metadata is parsed from the provider HTML.
- The first validated candidate is emitted before page validation completes.
- Invalid candidates remain hidden and later valid candidates still appear.
- Prepared resolution avoids a second detail/API/HEAD/Range chain.
- Pagination merges pages without duplicate candidate identities.
- A newer query discards old page emissions and prepared resolutions.
- A valid initial upstream 206 does not fall back to full GET.
- A far-forward seek on a slow background download receives a prompt, correctly
  aligned upstream 206.
- A backward seek inside the cached prefix is served from the part file.
- Misaligned, non-audio, failed, and unsatisfiable Range responses fail closed
  without formal cache entries.
- User-triggered play or seek reloads once after a player source error.

### Xiaomi 10 Pro evidence

- Search a multi-result artist query and record first-result and page-complete
  timings separately.
- Scroll through page 1 into page 2 and verify no duplicate rows.
- Start an uncached full-audio result, seek beyond the buffered position, then
  seek backward; confirm `media_session` remains playing and position advances.
- Reproduce a failed Range and confirm the retry behavior, structured log, and
  absence of a formal cache entry.
- Capture logcat/proxy evidence showing valid 206 alignment and no local HTTP
  504 on supported Range media.

## Delivery Constraints

- Changes remain limited to common Dart, Android-observable playback behavior,
  and matching tests.
- The developer role does not stage, commit, or push.
- Existing unrelated dirty worktree changes are preserved.
