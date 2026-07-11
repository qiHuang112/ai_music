# AM-017 Gequhai Cookie Jar P2 Plan

## Goal

Close the source-researcher P2 by preserving Gequhai page cookies across the defender retry path and proving the behavior with RED/GREEN tests.

## Steps

1. Add a failing resolver test that simulates first GET `403` with Cookie A, retry GET `200` with Cookie B, then asserts `/api/music` receives both cookies while CDN HEAD/Range receives no referer.
2. Implement a small name-based cookie jar in `GequhaiPlayerAudioResolver._fetchPage`.
3. Keep the existing page/api/media validation SourceAttempt flow unchanged.
4. Add encoded `window.mp3_extra_url` Quark detection as evidence only, with no completion-path change.
5. Run targeted resolver/controller/widget tests, the full targeted suite, analyze, diff-check, and a fresh debug APK build.
6. Report RED-GREEN, root cause, protocol evidence, scope diff, and whether Xiaomi 10 Pro needs reinstall.

## Verification Commands

- RED: run the new resolver test on reviewed HEAD `d84080f` with only the test added; expected failure is API cookie missing Cookie A.
- GREEN: run the same resolver test on HEAD `b306932`; expected pass.
- Full targeted suite: `flutter test --no-pub test/music_resolver_test.dart test/music_cache_test.dart test/progressive_audio_cache_test.dart test/music_controller_test.dart test/widget_test.dart`.
- Static checks: `flutter analyze --no-pub` and `git diff --check origin/release/1.0.2..HEAD`.
