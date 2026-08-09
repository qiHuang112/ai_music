# Lamaze CosyVoice Light-Music Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent execution is disabled by the workspace instructions.

**Goal:** Produce two technically verified 45-second previews of `01-慢呼放松`, using CosyVoice Mandarin female speech and CC0-recorded upright-piano/quiet-string samples, without changing the production library or Flutter app.

**Architecture:** Keep the approved production generator untouched while the preview is under review. Add a small preview-only Python pipeline with three boundaries: a pure timing/copy specification, a CosyVoice cue renderer, and an SFZ-backed music/mix renderer. Run model inference and sample rendering on the Windows host, copy only the finished previews back to the Mac, and do not write under `E:\music` until the user approves one preview.

**Tech Stack:** Python 3.10, CosyVoice `AutoModel`, PyTorch/Torchaudio, VSCO 2 CE SFZ samples, `sfizz_render` 1.2.3, FFmpeg/FFprobe, PowerShell, `unittest`.

## Global Constraints

- Voice must use CosyVoice, not macOS `say` or Windows SAPI.
- Render both the SFT `中文女` baseline and an Instruct `中文女` version so naturalness can be compared without changing engines.
- Do not clone an unknown person's individual voice or concatenate public-dataset words.
- Music direction is sparse upright piano with quiet violin and cello ensemble sustains.
- VSCO 2 CE source is pinned to commit `6dd651d55dde97fd4028699be9d4481f26917891` and CC0-1.0.
- CosyVoice source is pinned to commit `074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc`.
- CosyVoice SFT model is pinned to Hugging Face revision `fbb71de2afe387ed854eebd80b9f3d078c6b9869` and Apache-2.0.
- CosyVoice Instruct model is pinned to Hugging Face revision `706bee1915e9fd1f1214929e2a0509c874cff433` and Apache-2.0.
- `sfizz_render` is pinned to release `1.2.3` and BSD-2-Clause.
- Preview duration is `45.0 ± 0.1` seconds, WAV is 48 kHz/24-bit/stereo, MP3 is 192 kbps.
- True peak must not exceed `-1.5 dBTP`; every cue WAV must exceed `0.5` seconds and contain non-silent audio.
- Preview files stay outside `E:\music`; no Flutter, APK, LAN API, playlist, stable ID, or production-song file changes are allowed in this plan.

---

## File Structure

- `tool/lamaze_preview_spec.py`: the exact 45-second cue schedule and immutable source pins.
- `tool/render_cosyvoice_preview_cues.py`: model-independent CLI wrapper that renders one WAV per cue through SFT or Instruct mode.
- `tool/lamaze_light_score.py`: authored piano/violin/cello note events and SFZ rendering commands.
- `tool/render_lamaze_preview.py`: FFmpeg mixing, MP3 encoding, and runtime provenance manifest.
- `tool/verify_lamaze_preview.py`: FFprobe/FFmpeg technical acceptance checks.
- `tool/setup_lamaze_preview_windows.ps1`: idempotent Windows setup for the isolated generation environment.
- `tool/test_lamaze_preview_spec.py`, `tool/test_render_cosyvoice_preview_cues.py`, `tool/test_lamaze_light_score.py`, `tool/test_render_lamaze_preview.py`, `tool/test_verify_lamaze_preview.py`: pure unit tests that do not download models.
- `tool/lamaze_preview_sources.json`: committed source URLs, pinned revisions, licenses, and required SFZ paths.
- Generated outside Git on Windows: `E:\AIHome\lamaze-preview-output\`.
- Copied outside Git on Mac: `/Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice/`.

---

### Task 1: Freeze the preview copy, timing, and source provenance

**Files:**
- Create: `tool/lamaze_preview_spec.py`
- Create: `tool/lamaze_preview_sources.json`
- Create: `tool/test_lamaze_preview_spec.py`

**Interfaces:**
- Produces: `PreviewCue(at_seconds: float, text: str)`
- Produces: `PREVIEW_SECONDS: int`, `PREVIEW_CUES: tuple[PreviewCue, ...]`
- Produces: `load_preview_sources(path: Path) -> dict`

- [ ] **Step 1: Write failing specification tests**

```python
class LamazePreviewSpecTests(unittest.TestCase):
    def test_preview_has_exact_approved_copy_and_timing(self):
        self.assertEqual(45, PREVIEW_SECONDS)
        self.assertEqual(
            [
                (6.0, "肩膀松下来，下巴也松下来。"),
                (20.0, "轻轻吸气，慢慢呼出去。"),
                (35.0, "跟着自己的节奏，放松就好。"),
            ],
            [(cue.at_seconds, cue.text) for cue in PREVIEW_CUES],
        )

    def test_sources_are_pinned_and_permissively_licensed(self):
        sources = load_preview_sources(Path(__file__).with_name("lamaze_preview_sources.json"))
        self.assertEqual("074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc", sources["cosyVoice"]["commit"])
        self.assertEqual("CC0-1.0", sources["vsco2Ce"]["license"])
        self.assertEqual("1.2.3", sources["sfizz"]["version"])
        self.assertEqual(
            ["UprightPiano.sfz", "ViolinEnsSusVib-Quiet.sfz", "CelloEnsSusVib-Quiet.sfz"],
            sources["vsco2Ce"]["requiredPatches"],
        )
```

- [ ] **Step 2: Run the tests and confirm RED**

Run: `python3 -m unittest tool/test_lamaze_preview_spec.py`

Expected: FAIL because `lamaze_preview_spec` does not exist.

- [ ] **Step 3: Add the immutable preview specification**

```python
@dataclass(frozen=True)
class PreviewCue:
    at_seconds: float
    text: str

PREVIEW_SECONDS = 45
PREVIEW_CUES = (
    PreviewCue(6.0, "肩膀松下来，下巴也松下来。"),
    PreviewCue(20.0, "轻轻吸气，慢慢呼出去。"),
    PreviewCue(35.0, "跟着自己的节奏，放松就好。"),
)

def load_preview_sources(path: Path) -> dict:
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if decoded["vsco2Ce"]["license"] != "CC0-1.0":
        raise ValueError("VSCO 2 CE must remain CC0-1.0")
    return decoded
```

The JSON must contain the exact pins from Global Constraints and these source URLs:

```json
{
  "cosyVoice": {"url": "https://github.com/FunAudioLLM/CosyVoice.git", "commit": "074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc", "license": "Apache-2.0"},
  "models": {
    "sft": {"repo": "FunAudioLLM/CosyVoice-300M-SFT", "revision": "fbb71de2afe387ed854eebd80b9f3d078c6b9869", "license": "Apache-2.0"},
    "instruct": {"repo": "FunAudioLLM/CosyVoice-300M-Instruct", "revision": "706bee1915e9fd1f1214929e2a0509c874cff433", "license": "Apache-2.0"}
  },
  "vsco2Ce": {"url": "https://github.com/sgossner/VSCO-2-CE.git", "commit": "6dd651d55dde97fd4028699be9d4481f26917891", "license": "CC0-1.0", "requiredPatches": ["UprightPiano.sfz", "ViolinEnsSusVib-Quiet.sfz", "CelloEnsSusVib-Quiet.sfz"]},
  "sfizz": {"url": "https://github.com/sfztools/sfizz/releases/download/1.2.3/sfizz-1.2.3-win64.zip", "version": "1.2.3", "license": "BSD-2-Clause"}
}
```

- [ ] **Step 4: Run the tests and confirm GREEN**

Run: `python3 -m unittest tool/test_lamaze_preview_spec.py`

Expected: all tests pass.

- [ ] **Step 5: Commit the preview contract**

```bash
git add tool/lamaze_preview_spec.py tool/lamaze_preview_sources.json tool/test_lamaze_preview_spec.py
git commit -m "test: freeze CosyVoice Lamaze preview contract"
```

### Task 2: Add the CosyVoice cue renderer

**Files:**
- Create: `tool/render_cosyvoice_preview_cues.py`
- Create: `tool/test_render_cosyvoice_preview_cues.py`

**Interfaces:**
- Consumes: `PREVIEW_CUES`
- Produces: `render_cues(model_dir: Path, output: Path, mode: str, speaker: str = "中文女", speed: float = 0.92, model_factory=None, concatenate=None, audio_saver=None) -> dict`
- Produces: `cue-00.wav`, `cue-01.wav`, `cue-02.wav`, and `voice-manifest.json`

- [ ] **Step 1: Write failing renderer tests with a fake model**

```python
def test_sft_uses_chinese_female_and_preserves_every_sentence(self):
    fake = FakeModel(sample_rate=22050, speakers=["中文女"])
    manifest = render_cues(
        Path("model"), Path(self.temp_dir), "sft",
        model_factory=lambda **_: fake,
        concatenate=lambda chunks: chunks[0],
        audio_saver=fake.save,
    )
    self.assertEqual([cue.text for cue in PREVIEW_CUES], [call.text for call in fake.sft_calls])
    self.assertTrue(all(call.speaker == "中文女" for call in fake.sft_calls))
    self.assertEqual("sft", manifest["mode"])

def test_instruct_uses_calm_natural_direction(self):
    fake = FakeModel(sample_rate=22050, speakers=["中文女"])
    manifest = render_cues(
        Path("model"), Path(self.temp_dir), "instruct",
        model_factory=lambda **_: fake,
        concatenate=lambda chunks: chunks[0],
        audio_saver=fake.save,
    )
    self.assertIn("calm, warm adult Mandarin-speaking woman", fake.instruct_calls[0].instruction)
    self.assertEqual("instruct", manifest["mode"])
```

Also test rejection of an unknown mode, a missing `中文女` speaker, zero yielded chunks, and cue output shorter than 44 bytes.

- [ ] **Step 2: Run the tests and confirm RED**

Run: `python3 -m unittest tool/test_render_cosyvoice_preview_cues.py`

Expected: FAIL because the renderer does not exist.

- [ ] **Step 3: Implement lazy CosyVoice/PyTorch imports and per-cue rendering**

```python
INSTRUCTION = (
    "A calm, warm adult Mandarin-speaking woman with a natural conversational tone. "
    "Speak gently, slowly and clearly, without whispering, acting, singing or announcer intonation."
    "<|endofprompt|>"
)

def render_cues(model_dir, output, mode, speaker="中文女", speed=0.92,
                model_factory=None, concatenate=None, audio_saver=None):
    if mode not in {"sft", "instruct"}:
        raise ValueError("mode must be sft or instruct")
    if model_factory is None:
        from cosyvoice.cli.cosyvoice import AutoModel
        model_factory = AutoModel
    model = model_factory(model_dir=str(model_dir))
    if speaker not in model.list_available_spks():
        raise ValueError("CosyVoice model does not provide 中文女")
    if concatenate is None:
        import torch
        concatenate = lambda values: torch.cat(values, dim=1)
    if audio_saver is None:
        import torchaudio
        audio_saver = torchaudio.save
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for index, cue in enumerate(PREVIEW_CUES):
        iterator = (
            model.inference_sft(cue.text, speaker, stream=False, speed=speed)
            if mode == "sft"
            else model.inference_instruct(cue.text, speaker, INSTRUCTION, stream=False, speed=speed)
        )
        chunks = [item["tts_speech"] for item in iterator]
        if not chunks:
            raise RuntimeError("CosyVoice yielded no speech")
        target = output / f"cue-{index:02d}.wav"
        audio_saver(str(target), concatenate(chunks).cpu(), model.sample_rate)
        if not target.is_file() or target.stat().st_size <= 44:
            raise RuntimeError(f"Invalid cue output: {target}")
        records.append({"atSeconds": cue.at_seconds, "text": cue.text, "file": target.name})
    manifest = {"engine": "CosyVoice", "mode": mode, "speaker": speaker,
                "speed": speed, "sampleRate": model.sample_rate, "cues": records}
    (output / "voice-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest
```

The CLI must accept `--cosyvoice-root`, prepend both that directory and `third_party/Matcha-TTS` to `sys.path`, then accept `--model-dir`, `--output`, `--mode`, `--speaker`, and `--speed`.

- [ ] **Step 4: Run the renderer tests and confirm GREEN**

Run: `python3 -m unittest tool/test_render_cosyvoice_preview_cues.py`

Expected: all tests pass without CosyVoice installed locally.

- [ ] **Step 5: Commit the voice renderer**

```bash
git add tool/render_cosyvoice_preview_cues.py tool/test_render_cosyvoice_preview_cues.py
git commit -m "feat: render Lamaze preview cues with CosyVoice"
```

### Task 3: Add authored CC0 piano and string rendering

**Files:**
- Create: `tool/lamaze_light_score.py`
- Create: `tool/test_lamaze_light_score.py`

**Interfaces:**
- Consumes: `MidiNote`, `StemScore`, and `write_midi` from `tool/lamaze_score.py`
- Produces: `build_preview_scores() -> dict[str, StemScore]`
- Produces: `render_light_stems(work: Path, sfizz_render: Path, vsco_root: Path) -> tuple[Path, Path, Path]`
- Produces CLI: `lamaze_light_score.py --output PATH --sfizz-render PATH --vsco-root PATH`

- [ ] **Step 1: Write failing score and command tests**

```python
def test_score_is_sparse_authored_and_not_a_per_beat_arpeggio(self):
    scores = build_preview_scores()
    self.assertEqual({"piano", "violin", "cello"}, set(scores))
    starts = [note.start_beat for note in scores["piano"].notes]
    self.assertTrue(any(start != int(start) for start in starts))
    self.assertLess(len(starts), 28)
    self.assertTrue(all(note.velocity <= 52 for score in scores.values() for note in score.notes))

def test_renderer_uses_exact_cc0_sfz_patches(self):
    with mock.patch("lamaze_light_score._run") as run:
        render_light_stems(Path("work"), Path("sfizz_render.exe"), Path("VSCO"))
    commands = [" ".join(call.args[0]) for call in run.call_args_list]
    self.assertTrue(any("UprightPiano.sfz" in command for command in commands))
    self.assertTrue(any("ViolinEnsSusVib-Quiet.sfz" in command for command in commands))
    self.assertTrue(any("CelloEnsSusVib-Quiet.sfz" in command for command in commands))
    self.assertTrue(all("MuseScore_General" not in command for command in commands))
```

Also assert that the score covers at least 43 seconds, contains no percussion channel, and has a deterministic MIDI hash.

- [ ] **Step 2: Run the tests and confirm RED**

Run: `python3 -m unittest tool/test_lamaze_light_score.py`

Expected: FAIL because `lamaze_light_score` does not exist.

- [ ] **Step 3: Implement the exact 45-second authored arrangement**

Use 60 BPM and these six harmonic spans, with chord starts at beats `0.0`, `8.1`, `16.0`, `24.2`, `32.0`, and `40.1`: Cmaj7, Am7, Fmaj7, C/E, Gsus2, Cmaj9. Piano chord velocities range from 34 to 45 and sustain for 6.8 to 7.4 beats. Add only these six piano response starts: `3.4`, `11.7`, `19.3`, `27.6`, `36.2`, `42.3`, each with velocity 38 to 52. Violin and cello use long, overlapping chord tones with velocities 24 to 36 and no note shorter than 6 beats.

Render each MIDI file through the exact command form:

```python
command = (
    str(sfizz_render),
    "--sfz", str(vsco_root / patch_name),
    "--midi", str(midi_path),
    "--wav", str(wav_path),
    "--samplerate", "48000",
    "--quality", "10",
    "--use-eot",
)
```

After rendering, use FFmpeg to pad/trim each stem to exactly 45 seconds, apply a 2.5-second fade-in and 3-second fade-out, and output 48 kHz stereo PCM WAV.

The CLI must write `piano.wav`, `violin.wav`, and `cello.wav` directly under `--output` and fail before rendering when any required SFZ patch or `sfizz_render` is absent.

- [ ] **Step 4: Run the score tests and confirm GREEN**

Run: `python3 -m unittest tool/test_lamaze_light_score.py tool/test_lamaze_score.py`

Expected: both the new preview tests and existing production-score tests pass.

- [ ] **Step 5: Commit the light-music renderer**

```bash
git add tool/lamaze_light_score.py tool/test_lamaze_light_score.py
git commit -m "feat: add CC0 sampled Lamaze light score"
```

### Task 4: Add mixing and technical verification

**Files:**
- Create: `tool/render_lamaze_preview.py`
- Create: `tool/verify_lamaze_preview.py`
- Create: `tool/test_render_lamaze_preview.py`
- Create: `tool/test_verify_lamaze_preview.py`

**Interfaces:**
- Consumes: three music stems and three cue WAV files
- Produces: `mix_preview(stems: Sequence[Path], cues: Sequence[Path], target: Path) -> None`
- Produces: `encode_preview_mp3(wav: Path, target: Path) -> None`
- Produces: `verify_preview(wav: Path, mp3: Path, cue_dir: Path) -> dict`
- Produces CLI: `render_lamaze_preview.py --stems PATH --cues PATH --output-prefix PATH`
- Produces CLI: `verify_lamaze_preview.py --wav PATH --mp3 PATH --cues PATH --report PATH`

- [ ] **Step 1: Write failing mixer and verifier tests**

```python
def test_mix_places_three_cues_and_ducks_music(self):
    with mock.patch("render_lamaze_preview._run") as run:
        mix_preview(STEMS, CUES, Path("preview.wav"))
    command = " ".join(run.call_args.args[0])
    self.assertIn("adelay=6000:all=1", command)
    self.assertIn("adelay=20000:all=1", command)
    self.assertIn("adelay=35000:all=1", command)
    self.assertIn("sidechaincompress", command)
    self.assertIn("pcm_s24le", command)
    self.assertNotIn("aecho", command)

def test_verifier_rejects_silent_or_too_short_cues(self):
    with self.assertRaisesRegex(ValueError, "cue duration"):
        verify_preview(Path("preview.wav"), Path("preview.mp3"), Path("silent-cues"))
```

Also test exact stream requirements, `45.0 ± 0.1` seconds, MP3 bitrate tolerance of 5%, and true-peak rejection above `-1.5 dBTP`.

- [ ] **Step 2: Run the tests and confirm RED**

Run: `python3 -m unittest tool/test_render_lamaze_preview.py tool/test_verify_lamaze_preview.py`

Expected: FAIL because the mixer and verifier do not exist.

- [ ] **Step 3: Implement a clean voice-forward mix**

The FFmpeg graph must:

- Mix piano at `0.48`, violin at `0.16`, and cello at `0.12`.
- Resample voice to 48 kHz, apply only `highpass=f=70`, `lowpass=f=12000`, light compression, and no echo/reverb.
- Delay cues to 6, 20, and 35 seconds.
- Use the combined voice bus as a sidechain key with 200 ms attack and 900 ms release, targeting about 4 dB background reduction.
- Finish with `loudnorm=I=-18:TP=-1.5:LRA=8` and `alimiter=limit=0.8414`.
- Encode WAV as `pcm_s24le`, 48 kHz, stereo, exactly 45 seconds.
- Encode MP3 using `libmp3lame`, `-b:a 192k`, 48 kHz, stereo.

The render CLI must resolve `piano.wav`, `violin.wav`, and `cello.wav` from `--stems`, resolve `cue-00.wav` through `cue-02.wav` from `--cues`, and write `<output-prefix>.wav` plus `<output-prefix>.mp3`. The verify CLI must write its returned dictionary as UTF-8 JSON to `--report` only after all checks pass.

- [ ] **Step 4: Implement FFprobe/FFmpeg verification**

`verify_preview` must parse `ffprobe -show_streams -show_format -of json`, call FFmpeg `ebur128=peak=true`, and return a report containing duration, codec, sample rate, channels, bitrate, integrated loudness, true peak, cue durations, cue mean volumes, and SHA-256 for every output. It must reject a cue mean volume below `-45 dB` or duration at or below `0.5` seconds.

- [ ] **Step 5: Run the tests and confirm GREEN**

Run: `python3 -m unittest tool/test_render_lamaze_preview.py tool/test_verify_lamaze_preview.py`

Expected: all tests pass.

- [ ] **Step 6: Commit the mixer and verifier**

```bash
git add tool/render_lamaze_preview.py tool/verify_lamaze_preview.py tool/test_render_lamaze_preview.py tool/test_verify_lamaze_preview.py
git commit -m "feat: mix and verify Lamaze CosyVoice previews"
```

### Task 5: Provision the isolated Windows generation workspace

**Files:**
- Create: `tool/setup_lamaze_preview_windows.ps1`
- Test manually on: `52637@192.168.31.57`

**Interfaces:**
- Produces: `E:\AIModels\LamazeAudio\venv-py310`
- Produces: pinned CosyVoice, SFT/Instruct models, VSCO 2 CE, `sfizz_render.exe`, FFmpeg, and `runtime-sources.json`

- [ ] **Step 1: Implement an idempotent PowerShell setup script**

The script must stop on errors, create only `E:\AIModels\LamazeAudio`, install the official Python 3.10 winget package when the 3.10 launcher is absent, and perform these exact operations:

```powershell
$Root = 'E:\AIModels\LamazeAudio'
winget install --id Python.Python.3.10 --exact --scope user --silent --accept-package-agreements --accept-source-agreements
py -3.10 -m venv "$Root\venv-py310"
& "$Root\venv-py310\Scripts\python.exe" -m pip install --upgrade 'pip==24.3.1'
git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git "$Root\CosyVoice"
git -C "$Root\CosyVoice" checkout 074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc
git -C "$Root\CosyVoice" submodule update --init --recursive
& "$Root\venv-py310\Scripts\python.exe" -m pip install -r "$Root\CosyVoice\requirements.txt"
& "$Root\venv-py310\Scripts\python.exe" -m pip install 'huggingface_hub==0.30.2'
git clone --branch SFZ --single-branch https://github.com/sgossner/VSCO-2-CE.git "$Root\VSCO-2-CE"
git -C "$Root\VSCO-2-CE" checkout 6dd651d55dde97fd4028699be9d4481f26917891
Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/sfztools/sfizz/releases/download/1.2.3/sfizz-1.2.3-win64.zip' -OutFile "$Root\sfizz.zip"
Expand-Archive -LiteralPath "$Root\sfizz.zip" -DestinationPath "$Root\sfizz-1.2.3" -Force
winget install --id Gyan.FFmpeg.Essentials --exact --scope user --silent --accept-package-agreements --accept-source-agreements
```

Use `huggingface_hub.snapshot_download` with the two exact model revisions in Global Constraints and local directories under `$Root\models`. After every download, compute SHA-256 for the source/license files and all required SFZ patches, then write `$Root\runtime-sources.json`. Existing correct checkouts and downloads must be reused; a mismatched commit must stop instead of being silently overwritten.

- [ ] **Step 2: Run static PowerShell parsing before copying**

Run on Mac:

```bash
pwsh -NoProfile -Command '$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("tool/setup_lamaze_preview_windows.ps1",[ref]$null,[ref]$errors) > $null; if($errors.Count){$errors;exit 1}'
```

Expected: exit code 0. If `pwsh` is unavailable on the Mac, copy the script and run the same parser expression on Windows before execution.

- [ ] **Step 3: Copy and run setup over the pre-authorized SSH connection**

```bash
scp tool/setup_lamaze_preview_windows.ps1 52637@192.168.31.57:'E:/AIHome/setup_lamaze_preview_windows.ps1'
ssh -o BatchMode=yes 52637@192.168.31.57 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File E:\AIHome\setup_lamaze_preview_windows.ps1'
```

Expected: script reports the pinned CosyVoice/VSCO commits, both model directories, `sfizz_render.exe`, FFmpeg, CUDA availability, and exits 0.

- [ ] **Step 4: Verify the environment without rendering media**

Run remote Python to assert `torch.cuda.is_available() is True`, the GPU name contains `RTX 3060 Ti`, both models contain their YAML/weight files, all three SFZ patches exist, and at least 100 GB remains free on E:.

- [ ] **Step 5: Commit the setup script**

```bash
git add tool/setup_lamaze_preview_windows.ps1
git commit -m "build: add isolated Windows Lamaze audio setup"
```

### Task 6: Render, verify, and hand off the two 45-second previews

**Files:**
- Generated outside Git: `E:\AIHome\lamaze-preview-output\sft\*`
- Generated outside Git: `E:\AIHome\lamaze-preview-output\instruct\*`
- Copied outside Git: `/Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice/*`

**Interfaces:**
- Requires: Tasks 1-5 complete
- Produces: two WAV/MP3 previews and two verification reports

- [ ] **Step 1: Run the complete project unit suite before external rendering**

Run:

```bash
python3 -m unittest discover -s tool -p 'test_*.py'
```

Expected: all tests pass.

- [ ] **Step 2: Copy the preview tools to Windows**

Copy the seven runtime files (`lamaze_preview_spec.py`, `lamaze_preview_sources.json`, `render_cosyvoice_preview_cues.py`, `lamaze_score.py`, `lamaze_light_score.py`, `render_lamaze_preview.py`, `verify_lamaze_preview.py`) into `E:\AIHome\lamaze-preview-tool\`, preserving filenames.

- [ ] **Step 3: Render SFT and Instruct cue sets**

Run the pinned environment Python twice:

```text
render_cosyvoice_preview_cues.py --cosyvoice-root E:\AIModels\LamazeAudio\CosyVoice --model-dir E:\AIModels\LamazeAudio\models\CosyVoice-300M-SFT --output E:\AIHome\lamaze-preview-output\sft\cues --mode sft --speaker 中文女 --speed 0.92
render_cosyvoice_preview_cues.py --cosyvoice-root E:\AIModels\LamazeAudio\CosyVoice --model-dir E:\AIModels\LamazeAudio\models\CosyVoice-300M-Instruct --output E:\AIHome\lamaze-preview-output\instruct\cues --mode instruct --speaker 中文女 --speed 0.92
```

Expected: each directory contains three non-silent WAV files and a manifest; no cue is shorter than 0.5 seconds.

- [ ] **Step 4: Render one shared CC0 music bed and two mixes**

Render piano, violin, and cello once from the pinned VSCO checkout:

```text
E:\AIModels\LamazeAudio\venv-py310\Scripts\python.exe E:\AIHome\lamaze-preview-tool\lamaze_light_score.py --output E:\AIHome\lamaze-preview-output\shared-stems --sfizz-render E:\AIModels\LamazeAudio\sfizz-1.2.3\sfizz_render.exe --vsco-root E:\AIModels\LamazeAudio\VSCO-2-CE
```

If `sfizz_render.exe` is nested inside the extracted release, Task 5 must record its resolved absolute path in `runtime-sources.json`, and this command must use that recorded path. Then mix the same stems with each cue set:

```text
E:\AIModels\LamazeAudio\venv-py310\Scripts\python.exe E:\AIHome\lamaze-preview-tool\render_lamaze_preview.py --stems E:\AIHome\lamaze-preview-output\shared-stems --cues E:\AIHome\lamaze-preview-output\sft\cues --output-prefix E:\AIHome\lamaze-preview-output\sft\01-慢呼放松-CosyVoice-SFT-45s
E:\AIModels\LamazeAudio\venv-py310\Scripts\python.exe E:\AIHome\lamaze-preview-tool\render_lamaze_preview.py --stems E:\AIHome\lamaze-preview-output\shared-stems --cues E:\AIHome\lamaze-preview-output\instruct\cues --output-prefix E:\AIHome\lamaze-preview-output\instruct\01-慢呼放松-CosyVoice-Instruct-45s
```

Produce:

```text
01-慢呼放松-CosyVoice-SFT-45s.wav
01-慢呼放松-CosyVoice-SFT-45s.mp3
01-慢呼放松-CosyVoice-Instruct-45s.wav
01-慢呼放松-CosyVoice-Instruct-45s.mp3
```

- [ ] **Step 5: Run technical verification on both variants**

Run:

```text
E:\AIModels\LamazeAudio\venv-py310\Scripts\python.exe E:\AIHome\lamaze-preview-tool\verify_lamaze_preview.py --wav E:\AIHome\lamaze-preview-output\sft\01-慢呼放松-CosyVoice-SFT-45s.wav --mp3 E:\AIHome\lamaze-preview-output\sft\01-慢呼放松-CosyVoice-SFT-45s.mp3 --cues E:\AIHome\lamaze-preview-output\sft\cues --report E:\AIHome\lamaze-preview-output\sft\verification.json
E:\AIModels\LamazeAudio\venv-py310\Scripts\python.exe E:\AIHome\lamaze-preview-tool\verify_lamaze_preview.py --wav E:\AIHome\lamaze-preview-output\instruct\01-慢呼放松-CosyVoice-Instruct-45s.wav --mp3 E:\AIHome\lamaze-preview-output\instruct\01-慢呼放松-CosyVoice-Instruct-45s.mp3 --cues E:\AIHome\lamaze-preview-output\instruct\cues --report E:\AIHome\lamaze-preview-output\instruct\verification.json
```

Expected for both: 45.0 ± 0.1 seconds, WAV 48 kHz/24-bit/stereo, MP3 192 kbps within 5%, true peak at or below -1.5 dBTP, all three cues above -45 dB mean and longer than 0.5 seconds.

- [ ] **Step 6: Copy only verified previews back to the Mac**

```bash
mkdir -p /Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice
scp 52637@192.168.31.57:'E:/AIHome/lamaze-preview-output/sft/01-慢呼放松-CosyVoice-SFT-45s.mp3' /Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice/
scp 52637@192.168.31.57:'E:/AIHome/lamaze-preview-output/sft/verification.json' /Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice/sft-verification.json
scp 52637@192.168.31.57:'E:/AIHome/lamaze-preview-output/instruct/01-慢呼放松-CosyVoice-Instruct-45s.mp3' /Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice/
scp 52637@192.168.31.57:'E:/AIHome/lamaze-preview-output/instruct/verification.json' /Users/huangqi/AIHome/output/lamaze_guide/preview-cosyvoice/instruct-verification.json
```

Expected: two MP3 previews and their reports exist locally; SHA-256 values match the Windows reports.

- [ ] **Step 7: Present both previews and stop before production replacement**

Render both local MP3 files in the Codex response. Ask the user to choose SFT, Instruct, or reject both, and separately note any required change to music, pace, or voice/music ratio. Do not render four full tracks, copy into `E:\music`, or sync a phone until one preview is explicitly approved.

---

## Reference Sources

- CosyVoice official repository and SFT/Instruct examples: <https://github.com/FunAudioLLM/CosyVoice>
- VSCO 2 CE official page, CC0 status, and ambient/calm orchestral guidance: <https://versilian-studios.com/vsco-community/>
- VSCO 2 CE pinned SFZ repository: <https://github.com/sgossner/VSCO-2-CE>
- sfizz offline renderer documentation: <https://sfztools.github.io/sfizz/development/build/>
