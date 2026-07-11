# AM-017 Gequhai Cookie Jar P2 Design

## Problem

Source-researcher found a protocol fidelity bug in the Android Gequhai player-audio provider. The research protocol keeps a browser-like cookie jar across the initial page GET, one allowed defender retry, and the `/api/music` POST. The Android implementation at `d84080f` only forwarded the final page response cookies to `/api/music`.

## Root Cause

`GequhaiPlayerAudioResolver._fetchPage` treated each page response as an independent cookie source. During a first `403` defender response followed by a successful retry, cookies from the first response were lost before `_fetchApi` built the API request headers.

## Expected Behavior

- Merge cookies from the first page GET and the retry GET by cookie name.
- Use the merged cookie header for the retry page GET and for `POST /api/music`.
- Keep CDN media validation and playback requests no-referer.
- Treat encoded `window.mp3_extra_url` Quark links only as external-pan evidence; they must not enter the completion path.

## Non-Goals

- No new Gequhai songs beyond the existing scoped `play/38173` PoC.
- No UI, streaming, cache, Android native, iOS, or OHOS changes.
- No change to the direct-audio gate: HEAD audio, positive length, Range 206, and positive total remain required.

## Review Focus

Review should check protocol fidelity and minimal scope: cookie jar preservation, no-referer CDN validation, and unchanged fail-closed/cache behavior.
