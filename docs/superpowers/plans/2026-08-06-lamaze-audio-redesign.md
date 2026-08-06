# Lamaze Immersive Audio Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent execution is not enabled for this task.

**Goal:** Replace the four synthetic, narration-heavy Lamaze tracks with original sampled-instrument light music and sparse, direct Mandarin action guidance, gated by a 45-second user-approved preview.

**Architecture:** Track timing and cue copy remain deterministic Python data. A new score renderer writes original MIDI for separate piano, strings, and air-pad stems, rendered through FluidSynth with the MIT-licensed MuseScore General SoundFont; the voice renderer remains replaceable and produces isolated cue files. FFmpeg mixes stems and voice, verifies loudness/signatures, and only promotes a complete validated set into the delivery directory.

**Tech Stack:** Python 3.9+, NumPy only for analysis/fades rather than instrument synthesis, Standard MIDI, FluidSynth, MuseScore General SoundFont, macOS `say`, FFmpeg/FFprobe, `unittest`.

## Global Constraints

- Pure instrumental background: soft piano, warm strings, very quiet air pad.
- No singing, humming, drums, nature ambience, white noise, strong bass, or abrupt bells.
- Mature, stable, friendly Mandarin female voice; one direct action per cue.
- Average cue spacing is 20 to 35 seconds; `03-暂缓用力` begins its first action within 3 seconds.
- Remove all announcement/self-description phrases from audio and LRC.
- Keep safety details in TXT/README/JSON; audio uses only short action-oriented safety prompts.
- No dilation-stage inference, painless/vaginal-birth promises, long breath holds, or autonomous pushing commands.
- Preserve the four stable track IDs and deliver 48 kHz WAV, 192 kbps MP3, UTF-8 LRC/TXT, JSON, and PNG.
- Do not overwrite the complete production set until the 45-second preview is approved by the user.

---

### Task 1: Replace narration copy with sparse action cues

**Files:**
- Modify: `tool/generate_lamaze_audio.py`
- Modify: `tool/test_generate_lamaze_audio.py`

**Interfaces:**
- Preserves: `TRACKS`, `TrackSpec`, `Cue`, `render_lrc`, `validate_track_specs`
- Changes: cues may begin after zero; every first cue is at most 6 seconds and track 03 is at most 3 seconds

- [ ] **Step 1: Write failing cue-contract tests**

Add exact rejection checks for `这是一段`, `这首引导`, `本曲`, `用于`, `循环播放`, `不会替`, and any cue style other than `spoken`. Assert no cue gap exceeds 35 seconds, no non-initial gap is under 20 seconds, each sentence is short, and track 03 begins within 3 seconds.

```python
def test_audio_copy_is_direct_sparse_and_never_announces_itself(self):
    banned = ("这是一段", "这首引导", "本曲", "用于", "循环播放", "不会替")
    for track in TRACKS:
        text = "\n".join(cue.text for cue in track.cues)
        self.assertFalse(any(value in text for value in banned), track.slug)
        self.assertTrue(all(cue.style == "spoken" for cue in track.cues))
        gaps = [right.at_seconds - left.at_seconds for left, right in zip(track.cues, track.cues[1:])]
        self.assertTrue(all(20 <= gap <= 35 for gap in gaps), track.slug)
    self.assertLessEqual(TRACKS[2].cues[0].at_seconds, 3)
```

- [ ] **Step 2: Run tests and confirm RED**

Run: `python3 -m unittest tool/test_generate_lamaze_audio.py`

Expected: failures for announcement phrases, chant styles, and old cue timing.

- [ ] **Step 3: Replace all four cue schedules**

Use direct action phrases only. The schedules are:

```python
SLOW_CUES = (6, 32, 60, 88, 116, 144, 172, 200, 228, 256, 284)
WAVE_CUES = (6, 31, 56, 81, 106, 131, 156)
DEFER_CUES = (2, 22, 42, 62, 82, 102)
FOLLOW_CUES = (6, 34, 62, 90, 118, 146, 174)
```

Use short phrases such as `肩膀松下来，下巴也松下来。`, `轻轻吸气……慢慢呼出去。`, `嘴唇轻轻张开，像吹动羽毛一样，短短地呼气。`, and `先听医护的声音，让呼吸自然流动。`. Keep a short later cue for dizziness: `如果头晕，先回到自然呼吸，告诉身边的医护。`

- [ ] **Step 4: Update validation and confirm GREEN**

Remove the requirement that the first cue equals zero. Require first cue `<= 6`, track 03 first cue `<= 3`, spoken-only style, banned-announcement rejection, and the existing medical forbidden-claim checks.

Run: `python3 -m unittest tool/test_generate_lamaze_audio.py`

Expected: all tests pass.

- [ ] **Step 5: Commit direct cue copy**

```bash
git add tool/generate_lamaze_audio.py tool/test_generate_lamaze_audio.py
git commit -m "feat: rewrite Lamaze guidance as direct cues"
```

### Task 2: Add reproducible sampled-instrument rendering

**Files:**
- Create: `tool/lamaze_score.py`
- Create: `tool/test_lamaze_score.py`
- Create: `tool/fetch_lamaze_soundfont.py`
- Create: `tool/lamaze_soundfont_sources.json`
- Modify: `tool/generate_lamaze_audio.py`

**Interfaces:**
- Produces: `render_score_stems(track: TrackSpec, work: Path, soundfont: Path) -> Sequence[Path]`
- Produces: three stereo 48 kHz stems named `piano.wav`, `strings.wav`, and `air.wav`
- Consumes: FluidSynth CLI and `MuseScore_General.sf3`

- [ ] **Step 1: Write failing score tests**

Test Standard MIDI headers, exact tick duration, allowed programs (Acoustic Grand Piano 0, String Ensemble 48, Warm Pad 89), note velocities below 90, no percussion channel, deterministic bytes, and distinct score hashes across the four tracks.

- [ ] **Step 2: Run score tests and confirm RED**

Run: `python3 -m unittest tool/test_lamaze_score.py`

Expected: import failure because `lamaze_score.py` is absent.

- [ ] **Step 3: Implement a small Standard MIDI writer and score templates**

Define immutable `MidiNote(start_beat, duration_beats, pitch, velocity)` and `StemScore(program, notes)`. Write format-0 MIDI with 480 ticks per quarter note, tempo meta event from `track.bpm`, program change, sorted note-on/off events, and end-of-track. Compose original diatonic progressions with piano notes, long string chords, and a sparse warm pad; never use channel 10.

- [ ] **Step 4: Add a pinned source fetcher**

`fetch_lamaze_soundfont.py` downloads these exact HTTPS resources into a caller-provided cache directory:

```text
https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3
https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General_License.md
https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/VERSION
```

It computes SHA-256 for each file and writes `lamaze_soundfont_sources.json` with URL, version text, license filename and hashes. It refuses HTTP redirects to a non-HTTPS scheme.

- [ ] **Step 5: Render stems through FluidSynth**

For each stem, call:

```text
fluidsynth -ni -F /tmp/lamaze-score/piano.wav -r 48000 /Users/huangqi/AIHome/output/lamaze_guide/build-assets/MuseScore_General.sf3 /tmp/lamaze-score/piano.mid
```

Then trim/pad exactly to `track.duration_seconds`, convert to stereo PCM, and fail if FluidSynth or the SoundFont is unavailable. Delete the old `generate_backing` sine/chime synthesis path.

- [ ] **Step 6: Run score and generator tests**

Run: `python3 -m unittest tool/test_lamaze_score.py tool/test_generate_lamaze_audio.py`

Expected: all tests pass.

- [ ] **Step 7: Commit sampled scoring**

```bash
git add tool/lamaze_score.py tool/test_lamaze_score.py tool/fetch_lamaze_soundfont.py tool/lamaze_soundfont_sources.json tool/generate_lamaze_audio.py
git commit -m "feat: render Lamaze music with sampled instruments"
```

### Task 3: Produce and review the 45-second preview

**Files:**
- Modify: `tool/generate_lamaze_audio.py`
- Modify: `tool/test_generate_lamaze_audio.py`
- Create outside Git: `/Users/huangqi/AIHome/output/lamaze_guide/preview/01-慢呼放松-45s.wav`
- Create outside Git: `/Users/huangqi/AIHome/output/lamaze_guide/preview/01-慢呼放松-45s.mp3`

**Interfaces:**
- Adds CLI options `--preview-track`, `--preview-seconds`, `--voice`, and `--soundfont`; the concrete preview invocation appears in Step 4.
- Uses a replaceable voice renderer; initial mature Mandarin candidate is `Grandma (中文（中国大陆）)` and alternatives `Shelley (中文（中国大陆）)` and `Flo (中文（中国大陆）)` remain available if the first sample is rejected

- [ ] **Step 1: Add failing preview CLI tests**

Patch subprocess calls and assert preview mode renders only track 01, clips the score and cue set at 45 seconds, does not write full-delivery JSON/SHA records, and never invokes chant effects.

- [ ] **Step 2: Run generator tests and confirm RED**

Run: `python3 -m unittest tool/test_generate_lamaze_audio.py`

Expected: preview-option assertions fail.

- [ ] **Step 3: Implement replaceable voice and preview rendering**

Render each cue separately with the selected CLI `--voice` value and speech rate 138, high-pass at 80 Hz, low-pass at 11 kHz, light compression, no vibrato, and short room reverb below 8% wet. During cues, apply a 2.5 dB sidechain-style background dip with smooth attack/release.

- [ ] **Step 4: Install/render prerequisites and create preview**

Run:

```bash
brew install fluid-synth
python3 tool/fetch_lamaze_soundfont.py --output /Users/huangqi/AIHome/output/lamaze_guide/build-assets
python3 tool/generate_lamaze_audio.py \
  --output /Users/huangqi/AIHome/output/lamaze_guide/preview \
  --cover /Users/huangqi/AIHome/output/lamaze_guide/Lamaze/cover.png \
  --soundfont /Users/huangqi/AIHome/output/lamaze_guide/build-assets/MuseScore_General.sf3 \
  --voice 'Grandma (中文（中国大陆）)' \
  --preview-track 01-慢呼放松 \
  --preview-seconds 45
```

- [ ] **Step 5: Verify preview audio technically**

Use FFprobe to confirm 45 seconds, 48 kHz stereo WAV and 192 kbps MP3. Use FFmpeg `ebur128`/`astats` to confirm no clipping and true peak below -1.5 dBTP.

- [ ] **Step 6: Send the preview to the user and pause only full-set rendering**

Render the local MP3 in the Codex response and request a direct verdict on music cleanliness, voice naturalness, pace, and voice/music ratio. LAN feature implementation may continue, but Task 4 cannot start until the preview is explicitly approved.

- [ ] **Step 7: Commit preview tooling, not generated media**

```bash
git add tool/generate_lamaze_audio.py tool/test_generate_lamaze_audio.py
git commit -m "feat: add Lamaze audio preview workflow"
```

### Task 4: Render and validate all four production tracks

**Files:**
- Modify: `tool/verify_lamaze_delivery.py`
- Modify: `tool/test_generate_lamaze_audio.py`
- Modify: `tool/generate_lamaze_audio.py`
- Generated outside Git: `/Users/huangqi/AIHome/output/lamaze_guide/Lamaze/*`

**Interfaces:**
- Requires: explicit user approval of Task 3 preview
- Produces: complete validated delivery set with unchanged stable IDs

- [ ] **Step 1: Add failing delivery-verifier tests**

Test cue timestamps, no banned announcement copy, spoken-only cue metadata, 48 kHz stereo, 192 kbps MP3, exact stable IDs, no clipping, true peak target, and required license/source hashes in metadata.

- [ ] **Step 2: Run audio tests and confirm RED**

Run: `python3 -m unittest tool/test_generate_lamaze_audio.py tool/test_lamaze_score.py`

Expected: new delivery checks fail until verifier/generator metadata is updated.

- [ ] **Step 3: Render to a staging directory**

Generate all four tracks under a directory created by `lamaze_stage_dir="/Users/huangqi/AIHome/output/lamaze_guide/Lamaze.staging-$(date +%Y%m%d-%H%M%S)"` with the user-approved voice and mix settings. TXT/README retain the full safety usage notes; LRC contains only audible cues.

- [ ] **Step 4: Run complete verification**

Run `tool/verify_lamaze_delivery.py` against the staging directory and inspect every track on headphones and phone speakers. Verification must emit a passed report and fresh SHA-256 file.

- [ ] **Step 5: Atomically promote the complete set**

Move the current `Lamaze` directory to a timestamped recoverable backup, move staging to `Lamaze`, and retain the backup until phone acceptance. Do not overwrite individual production files in place.

- [ ] **Step 6: Commit generator and verifier code**

```bash
git add tool/generate_lamaze_audio.py tool/verify_lamaze_delivery.py tool/test_generate_lamaze_audio.py tool/lamaze_score.py tool/test_lamaze_score.py tool/lamaze_soundfont_sources.json
git commit -m "feat: finalize immersive Lamaze audio generation"
```

### Task 5: Deploy audio to Windows and verify phone sync

**Files:**
- Update outside Git: `E:\music\Lamaze\*`
- Modify after evidence exists: `/Users/huangqi/AIHome/output/lamaze_guide/DELIVERY_RECORD.md`
- Modify: `docs/codex_collab/requests/AM-20260806-001-lamaze-audio-folder-playlists.md`

- [ ] **Step 1: Copy the verified complete set to Windows**

Use non-interactive SSH/SCP to copy into a staging directory beside `E:\music\Lamaze`, verify SHA-256 on Windows, then rename directories so the LAN server never observes a partial set.

- [ ] **Step 2: Restart and verify the Python server**

Confirm `/api/v1/health` is healthy and `/api/v1/library` contains four stable Lamaze IDs, new hashes, and `folderPath: "Lamaze"`.

- [ ] **Step 3: Sync and audition on Xiaomi 10 Pro**

Use the currently authorized Mi 10 Pro only. Verify the four existing stable IDs update rather than duplicate, all enter one `Lamaze` custom playlist, lyrics align, repeat sync adds nothing, and playback remains available after the server stops.

- [ ] **Step 4: Update delivery evidence**

Record final WAV/MP3 hashes, source/voice settings, instrument-license hashes, Windows paths, server response, APK version/SHA, device model/endpoint, and offline result.

- [ ] **Step 5: Commit final evidence**

```bash
git add docs/codex_collab/requests/AM-20260806-001-lamaze-audio-folder-playlists.md
git commit -m "docs: record Lamaze audio and LAN playlist verification"
```
