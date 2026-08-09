# Lamaze CosyVoice SFT Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent execution is disabled by the workspace instructions.

**Goal:** Render, validate, deploy, and phone-test all four Lamaze tracks with the user-approved CosyVoice SFT Mandarin female voice and the approved CC0 VSCO sampled light-music sound.

**Architecture:** Keep the stable track specification, lyrics, and LAN IDs in `generate_lamaze_audio.py`. Add a production-length sparse score renderer that uses the same VSCO piano/violin/cello patches as the accepted 45-second preview, then render every timed cue with one loaded CosyVoice SFT model and mix with the exact accepted voice filters, stem ratios, ducking, and mastering target. Render into an isolated Windows staging directory, validate the complete set, then atomically replace `E:\music\Lamaze` while retaining a recoverable backup.

**Tech Stack:** Python 3.10, CosyVoice `AutoModel`, PyTorch/Torchaudio, VSCO 2 CE SFZ samples, `sfizz_render` 1.2.3, FFmpeg/FFprobe, Python standard-library `unittest`, PowerShell, Android Debug Bridge.

## Global Constraints

- The approved voice is CosyVoice SFT speaker `中文女` at speed `0.92`; do not use macOS `say`, Windows SAPI, voice cloning, or Instruct mode.
- Use `UprightPiano.sfz`, `ViolinEnsSusVib-Quiet.sfz`, and `CelloEnsSusVib-Quiet.sfz` from VSCO 2 CE commit `6dd651d55dde97fd4028699be9d4481f26917891`, license `CC0-1.0`.
- Use CosyVoice commit `074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc` and SFT model revision `fbb71de2afe387ed854eebd80b9f3d078c6b9869`, license `Apache-2.0`.
- Use the accepted mix: music stem gains `0.48`, `0.16`, `0.12`; voice high-pass `70 Hz`, low-pass `12 kHz`, no echo; sidechain attack `200 ms`, release `900 ms`; master `-18 LUFS`, true peak target `-1.5 dBTP`.
- Preserve durations/BPM: `01` 300 s/60 BPM, `02` 180 s/64 BPM, `03` 120 s/72 BPM, `04` 180 s/60 BPM.
- Preserve stable IDs: `lamaze-slow-relax`, `lamaze-contraction-wave`, `lamaze-defer-pushing`, `lamaze-follow-care-team`.
- `03-暂缓用力` is only for use when the care team asks the mother to defer pushing; the audible copy remains direct action guidance and never autonomously commands pushing.
- `04-跟随医护` never issues a pushing command; in-person clinical instructions always take priority.
- Deliver 48 kHz/24-bit/stereo WAV, 192 kbps MP3, UTF-8 LRC/TXT/JSON, shared PNG cover, verification report, and SHA-256 sums.
- Do not mutate `/Users/huangqi/AIHome/ai_music`, Xiaomi 17 Pro, or `E:\music\Lamaze` before the staging set passes all automated checks.

---

### Task 1: Add the production-length VSCO score renderer

**Files:**
- Create: `tool/lamaze_production_score.py`
- Create: `tool/test_lamaze_production_score.py`
- Reuse: `tool/lamaze_score.py`

**Interfaces:**
- Consumes: `TrackSpec`-like values containing `track_id`, `duration_seconds`, and `bpm`.
- Produces: `build_production_scores(track) -> dict[str, StemScore]`.
- Produces: `render_production_stems(track, work: Path, sfizz_render: Path, vsco_root: Path) -> tuple[Path, Path, Path]`.

- [ ] **Step 1: Write failing score tests**

Add tests that require exactly `piano`, `violin`, and `cello`; non-grid response notes; velocities at or below `52`; no percussion channel; deterministic MIDI; distinct hashes for four tracks; exact end duration; and fewer than one piano note per two beats. Patch `_run` and require the exact three SFZ patch names, `--quality 10`, 48 kHz rendering, and 24-bit stereo stem output.

```python
scores = build_production_scores(TRACKS[0])
self.assertEqual(["piano", "violin", "cello"], list(scores))
self.assertTrue(any(note.start_beat != int(note.start_beat) for note in scores["piano"].notes))
self.assertLess(len(scores["piano"].notes), TRACKS[0].duration_seconds * TRACKS[0].bpm / 120)
self.assertTrue(all(note.velocity <= 52 for score in scores.values() for note in score.notes))
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `python3 -m unittest tool/test_lamaze_production_score.py -v`

Expected: import failure because `lamaze_production_score.py` does not exist.

- [ ] **Step 3: Implement sparse track-specific arrangements**

Use immutable arrangements with harmonic spans of `8` beats for tracks 01/02, `6` beats for track 03, and `12` beats for track 04. Every span contains one quiet piano chord and at most one fractional-beat response note; violin and cello use long sustains. Track 02 applies only a gentle repeating velocity contour; no track uses drums or one-note-per-beat arpeggios.

```python
PATCHES = {
    "piano": "UprightPiano.sfz",
    "violin": "ViolinEnsSusVib-Quiet.sfz",
    "cello": "CelloEnsSusVib-Quiet.sfz",
}

ARRANGEMENTS = {
    "lamaze-slow-relax": Arrangement(span_beats=8.0, response_beat=3.4),
    "lamaze-contraction-wave": Arrangement(span_beats=8.0, response_beat=3.6),
    "lamaze-defer-pushing": Arrangement(span_beats=6.0, response_beat=2.6),
    "lamaze-follow-care-team": Arrangement(span_beats=12.0, response_beat=5.2),
}
```

Each stem command must use the pinned `sfizz_render`, followed by FFmpeg `apad`, exact `atrim`, a 2.5-second fade-in, a 3-second fade-out, 48 kHz stereo, and `pcm_s24le`.

- [ ] **Step 4: Run score tests and confirm GREEN**

Run: `python3 -m unittest tool/test_lamaze_production_score.py tool/test_lamaze_score.py tool/test_lamaze_light_score.py -v`

Expected: all score tests pass.

### Task 2: Replace the old production voice and mix with the accepted SFT pipeline

**Files:**
- Modify: `tool/generate_lamaze_audio.py`
- Modify: `tool/test_generate_lamaze_audio.py`
- Reuse: `tool/setup_lamaze_preview_windows.ps1`

**Interfaces:**
- Consumes: Windows paths for `--cosyvoice-root`, `--model-dir`, `--sfizz-render`, `--vsco-root`, and `--runtime-sources`.
- Produces: one complete delivery directory with four WAV/MP3/LRC/TXT/JSON/PNG sets and a shared cover/README.
- Produces: `load_audio_sources(runtime_sources: Path) -> dict`.
- Produces: `_render_voice_cues(track, work, model, speaker="中文女", speed=0.92, concatenate=None, audio_saver=None) -> tuple[Path, ...]`.

- [ ] **Step 1: Write failing generator tests**

Replace the old SoundFont/system-voice assertions with tests requiring:

```python
self.assertIs(generator.render_production_stems, render_production_stems)
self.assertNotIn("say", inspect.getsource(generator._require_tools))
self.assertNotIn("fluidsynth", inspect.getsource(generator._require_tools))
```

Use a fake CosyVoice model to prove every cue is passed to `inference_sft` with `中文女`, `stream=False`, and speed `0.92`, and that one model instance is reused across four tracks. Require the CLI paths above and remove `--soundfont`, `--voice`, and preview-only arguments.

Update the track 03 audible cue at 22 seconds to a direct action such as `按医护的提示，继续短短地呼气。`; keep the conditional-use statement in TXT/README/JSON.

- [ ] **Step 2: Run generator tests and confirm RED**

Run: `python3 -m unittest tool/test_generate_lamaze_audio.py -v`

Expected: failures for the old `say`, FluidSynth, SoundFont CLI, source metadata, and mix behavior.

- [ ] **Step 3: Implement source validation and SFT cue rendering**

`load_audio_sources` must validate the exact commits/revision/licenses from Global Constraints, validate the three patch hashes as lowercase SHA-256, and return path-free reproducibility metadata:

```python
{
  "voiceEngine": {"name": "CosyVoice", "commit": COSYVOICE_COMMIT, "license": "Apache-2.0"},
  "voiceModel": {"repo": "FunAudioLLM/CosyVoice-300M-SFT", "revision": SFT_REVISION,
                 "license": "Apache-2.0", "speaker": "中文女", "speed": 0.92},
  "sampleLibrary": {"name": "VSCO 2 CE", "commit": VSCO_COMMIT,
                    "license": "CC0-1.0", "patchHashes": {...}},
  "sampler": {"name": "sfizz", "version": "1.2.3", "license": "BSD-2-Clause",
              "archiveSha256": "..."}
}
```

Load `AutoModel` only after prepending CosyVoice and Matcha-TTS to `sys.path`. Render cues with `inference_sft`; save one float WAV per cue; fail on missing `中文女`, no yielded chunks, or invalid output.

- [ ] **Step 4: Implement the accepted full-length mix and delivery metadata**

Use the same three gains and filters as the accepted preview. Generalize the cue count and track duration, output `pcm_s24le`, and retain cover-tagged 192 kbps MP3 encoding. Remove the old echo and the old `pcm_s16le` output.

Metadata must use `voice: "CosyVoice SFT 中文女"`, `voiceSpeed: 0.92`, `instruments: ["VSCO Upright Piano", "VSCO Quiet Violin Ensemble", "VSCO Quiet Cello Ensemble"]`, and `audioSources` from `load_audio_sources`.

- [ ] **Step 5: Run generator and preview regression tests**

Run: `python3 -m unittest tool/test_generate_lamaze_audio.py tool/test_render_cosyvoice_preview_cues.py tool/test_render_lamaze_preview.py -v`

Expected: all tests pass and accepted preview constants remain unchanged.

### Task 3: Update complete-delivery verification for CosyVoice and VSCO

**Files:**
- Modify: `tool/verify_lamaze_delivery.py`
- Modify: `tool/test_verify_lamaze_delivery.py`

**Interfaces:**
- Preserves: `verify(root: Path) -> dict`, `write_records(root: Path, report: dict) -> None`.
- Requires: 24-bit WAV and exact `audioSources` provenance.

- [ ] **Step 1: Write failing verifier tests**

Require WAV bit depth `24`, exact stable IDs/cues, `voice == "CosyVoice SFT 中文女"`, `voiceSpeed == 0.92`, Apache/CC0/BSD licenses, exact source pins, and all three patch/archive hashes. Reject legacy `soundFontSources`, any `aecho`-style metadata, invalid hashes, and peaks above `-1.5 dBTP`.

- [ ] **Step 2: Run verifier tests and confirm RED**

Run: `python3 -m unittest tool/test_verify_lamaze_delivery.py -v`

Expected: metadata source and WAV-depth assertions fail against the legacy verifier.

- [ ] **Step 3: Implement the new verification contract**

Read WAV properties with FFprobe so `bits_per_sample`/`bits_per_raw_sample` can be checked. Preserve duration, MP3, loudness, cue, forbidden-copy, and checksum validation. Write `verification-report.json` only after all four tracks pass; then write `SHA256SUMS.txt` for all delivery files except the checksum file itself.

- [ ] **Step 4: Run the complete Python suite**

Run: `python3 -m unittest discover -s tool -p 'test_*.py'`

Expected: all tests pass.

### Task 4: Render and validate the four-track staging set on Windows

**Files:**
- Generated outside Git: `E:\AIHome\lamaze-production-tool\*`
- Generated outside Git: `E:\AIHome\lamaze-production-output\Lamaze.staging-*\*`
- Copied outside Git: `/Users/huangqi/AIHome/output/lamaze_guide/Lamaze.staging-*\*`

**Interfaces:**
- Requires: Tasks 1-3 and `E:\AIModels\LamazeAudio\runtime-sources.json`.
- Produces: a passed four-track report and matching Windows/Mac SHA-256 records.

- [ ] **Step 1: Preserve the existing cover and copy runtime tools**

Copy the current `E:\music\Lamaze\cover.png` to an input directory outside production. Copy only the required Python runtime files into `E:\AIHome\lamaze-production-tool`.

- [ ] **Step 2: Render all four tracks to a timestamped staging directory**

Run the pinned Python 3.10 environment with:

```text
generate_lamaze_audio.py --output E:\AIHome\lamaze-production-output\Lamaze.staging-<timestamp> --cover E:\AIHome\lamaze-production-input\cover.png --cosyvoice-root E:\AIModels\LamazeAudio\CosyVoice --model-dir E:\AIModels\LamazeAudio\models\CosyVoice-300M-SFT --sfizz-render E:\AIModels\LamazeAudio\sfizz-1.2.3\bin\Release\sfizz_render.exe --vsco-root E:\AIModels\LamazeAudio\VSCO-2-CE --runtime-sources E:\AIModels\LamazeAudio\runtime-sources.json
```

- [ ] **Step 3: Run complete technical verification**

Run `verify_lamaze_delivery.py <staging>` and require `status: passed`, `trackCount: 4`, exact durations/formats, and safe true peaks. Copy the complete staging set to the Mac and compare all SHA-256 values with `SHA256SUMS.txt`.

- [ ] **Step 4: Perform a listening spot check before deployment**

Extract 20-second windows around the first two cues of each track and listen for word clarity, unexpected silence, sample artifacts, abrupt note releases, and voice masking. If any issue is found, stop before production replacement.

### Task 5: Atomically deploy and verify LAN/mobile behavior

**Files:**
- Update outside Git: `E:\music\Lamaze\*`
- Update after evidence: `docs/codex_collab/requests/AM-20260806-001-lamaze-audio-folder-playlists.md`
- Update after evidence: `/Users/huangqi/AIHome/output/lamaze_guide/DELIVERY_RECORD.md`

**Interfaces:**
- Requires: verified staging set from Task 4.
- Produces: one recoverable Windows backup, healthy LAN manifest, and Xiaomi 10 Pro acceptance evidence.

- [ ] **Step 1: Atomically replace the Windows directory**

Stop the Python LAN service. Rename the current `E:\music\Lamaze` to `Lamaze.backup-<timestamp>`, then rename the verified staging directory into `E:\music\Lamaze`. Do not delete the backup until device acceptance passes.

- [ ] **Step 2: Restart and verify the Python-only LAN server**

Start `py -3 tool\lan_music_server.py --root E:\music --host 0.0.0.0 --port 8787`. Require healthy `/api/v1/health`, exactly four Lamaze records with `folderPath: "Lamaze"`, unchanged stable IDs, and MP3 hashes matching the staging report.

- [ ] **Step 3: Verify Xiaomi 10 Pro at the authorized endpoint**

Connect only to `192.168.31.76:39153`. Run first manual sync, confirm four content updates without duplicate stable IDs, confirm one `Lamaze` playlist containing four songs, play each track and inspect lyrics, run repeat sync expecting no updates, then stop the server and prove offline playback still works. Do not connect Xiaomi 17 Pro.

- [ ] **Step 4: Record evidence and request architecture review**

Record final source commit, audio SHA-256, Windows backup/current paths, server response, device endpoint/model, playlist result, repeat-sync result, and offline result. Run `team_ops.py` validation before updating the request. Request architect review before any merge or push.

- [ ] **Step 5: Final verification**

Run Python tests, Flutter tests, Flutter analyze, and `git diff --check`; confirm the source worktree is clean except intentional evidence updates and that `/Users/huangqi/AIHome/ai_music` remains untouched.

---

## Stop Gate

The user approved only the SFT preview sound. This plan authorizes production rendering and replacement after technical verification, but not any Xiaomi 17 Pro connection, destructive removal of the Windows backup, branch merge, tag, or push.
