import inspect
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

import generate_lamaze_audio as generator  # noqa: E402
from generate_lamaze_audio import (  # noqa: E402
    TRACKS,
    render_lrc,
    render_txt,
    validate_track_specs,
)
from lamaze_production_score import render_production_stems  # noqa: E402


class FakeSpeech:
    def cpu(self):
        return self


class FakeCosyVoice:
    sample_rate = 22_050

    def __init__(self, speakers=("中文女",), empty=False):
        self.speakers = list(speakers)
        self.empty = empty
        self.sft_calls = []

    def list_available_spks(self):
        return self.speakers

    def inference_sft(self, text, speaker, *, stream, speed):
        self.sft_calls.append(
            {
                "text": text,
                "speaker": speaker,
                "stream": stream,
                "speed": speed,
            }
        )
        if not self.empty:
            yield {"tts_speech": FakeSpeech()}


def fake_saver(path, _speech, _sample_rate):
    Path(path).write_bytes(b"RIFF" + b"\0" * 64)


def approved_sources():
    return {
        "voiceEngine": {
            "name": "CosyVoice",
            "commit": generator.COSYVOICE_COMMIT,
            "license": "Apache-2.0",
        },
        "voiceModel": {
            "repo": "FunAudioLLM/CosyVoice-300M-SFT",
            "revision": generator.SFT_REVISION,
            "license": "Apache-2.0",
            "speaker": "中文女",
            "speed": 0.92,
        },
        "sampleLibrary": {
            "name": "VSCO 2 CE",
            "commit": generator.VSCO_COMMIT,
            "license": "CC0-1.0",
            "patchHashes": {
                "UprightPiano.sfz": "a" * 64,
                "ViolinEnsSusVib-Quiet.sfz": "b" * 64,
                "CelloEnsSusVib-Quiet.sfz": "c" * 64,
            },
        },
        "sampler": {
            "name": "sfizz",
            "version": "1.2.3",
            "license": "BSD-2-Clause",
            "archiveSha256": "d" * 64,
        },
    }


def runtime_manifest():
    return {
        "cosyVoice": {
            "path": "E:/AIModels/LamazeAudio/CosyVoice",
            "commit": generator.COSYVOICE_COMMIT,
            "license": "Apache-2.0",
        },
        "models": {
            "sft": {
                "path": "E:/AIModels/LamazeAudio/models/CosyVoice-300M-SFT",
                "repo": "FunAudioLLM/CosyVoice-300M-SFT",
                "revision": generator.SFT_REVISION,
                "license": "Apache-2.0",
            }
        },
        "vsco2Ce": {
            "path": "E:/AIModels/LamazeAudio/VSCO-2-CE",
            "commit": generator.VSCO_COMMIT,
            "license": "CC0-1.0",
            "patchHashes": approved_sources()["sampleLibrary"]["patchHashes"],
        },
        "sfizz": {
            "executable": "E:/AIModels/LamazeAudio/sfizz_render.exe",
            "archiveSha256": "d" * 64,
            "version": "1.2.3",
            "license": "BSD-2-Clause",
        },
    }


class LamazeAudioSpecTests(unittest.TestCase):
    def test_generator_uses_approved_vsco_renderer_and_no_system_tts(self):
        self.assertIs(generator.render_production_stems, render_production_stems)
        self.assertFalse(hasattr(generator, "generate_backing"))
        requirements = inspect.getsource(generator._require_tools)
        self.assertNotIn("say", requirements)
        self.assertNotIn("fluidsynth", requirements)

    def test_track_set_has_approved_names_durations_and_tempos(self):
        self.assertEqual(
            [
                ("01-慢呼放松", 300, 60),
                ("02-宫缩浪潮", 180, 64),
                ("03-暂缓用力", 120, 72),
                ("04-跟随医护", 180, 60),
            ],
            [(track.slug, track.duration_seconds, track.bpm) for track in TRACKS],
        )
        validate_track_specs(TRACKS)

    def test_audio_copy_is_direct_sparse_and_clinician_first(self):
        banned = (
            "这是一段",
            "这首引导",
            "本曲",
            "用于",
            "循环播放",
            "不会替",
            "宫口",
            "厘米",
            "无痛",
            "顺产",
            "保证",
        )
        for track in TRACKS:
            text = "\n".join(cue.text for cue in track.cues)
            self.assertFalse(any(value in text for value in banned), track.slug)
            self.assertIn("医护", text, track.slug)
            self.assertIn("自然呼吸", text, track.slug)
            self.assertTrue(all(cue.style == "spoken" for cue in track.cues))
            self.assertLessEqual(track.cues[0].at_seconds, 6, track.slug)
            gaps = [
                right.at_seconds - left.at_seconds
                for left, right in zip(track.cues, track.cues[1:])
            ]
            self.assertTrue(all(20 <= gap <= 35 for gap in gaps), track.slug)
        self.assertLessEqual(TRACKS[2].cues[0].at_seconds, 3)

    def test_defer_pushing_condition_stays_in_notes_not_audible_lrc(self):
        defer_lrc = render_lrc(TRACKS[2])
        defer_notes = render_txt(TRACKS[2])
        follow_lrc = render_lrc(TRACKS[3])

        self.assertNotIn("明确要求暂缓用力", defer_lrc)
        self.assertIn("明确要求暂缓用力", defer_notes)
        self.assertIn("不要屏气", defer_lrc)
        self.assertIn("先听医护", follow_lrc)
        self.assertNotIn("现在用力", follow_lrc)

    def test_lrc_is_utf8_ready_sorted_and_within_duration(self):
        for track in TRACKS:
            lrc = render_lrc(track)
            self.assertTrue(lrc.startswith("[ar:AI Home]\n"))
            self.assertNotIn("[00:00.00]", lrc)
            self.assertTrue(lrc.endswith("\n"))
            self.assertLess(track.cues[-1].at_seconds, track.duration_seconds)

    def test_cli_accepts_only_production_runtime_paths_and_sft_settings(self):
        args = generator.build_argument_parser().parse_args(
            [
                "--output",
                "out",
                "--cover",
                "cover.png",
                "--cosyvoice-root",
                "CosyVoice",
                "--model-dir",
                "CosyVoice-300M-SFT",
                "--sfizz-render",
                "sfizz_render.exe",
                "--vsco-root",
                "VSCO-2-CE",
                "--runtime-sources",
                "runtime-sources.json",
            ]
        )

        self.assertEqual(Path("CosyVoice"), args.cosyvoice_root)
        self.assertEqual(Path("CosyVoice-300M-SFT"), args.model_dir)
        self.assertEqual("中文女", args.speaker)
        self.assertEqual(0.92, args.speed)
        self.assertFalse(hasattr(args, "soundfont"))
        self.assertFalse(hasattr(args, "preview_track"))

    def test_sft_voice_renderer_preserves_every_track_cue(self):
        model = FakeCosyVoice()
        with tempfile.TemporaryDirectory() as temp_dir:
            paths = generator._render_voice_cues(
                TRACKS[0],
                Path(temp_dir),
                model=model,
                concatenate=lambda chunks: chunks[0],
                audio_saver=fake_saver,
            )

        self.assertEqual(len(TRACKS[0].cues), len(paths))
        self.assertEqual(
            [cue.text for cue in TRACKS[0].cues],
            [call["text"] for call in model.sft_calls],
        )
        self.assertTrue(all(call["speaker"] == "中文女" for call in model.sft_calls))
        self.assertTrue(all(call["speed"] == 0.92 for call in model.sft_calls))
        self.assertTrue(all(call["stream"] is False for call in model.sft_calls))

    def test_sft_voice_renderer_rejects_missing_speaker_and_empty_output(self):
        with tempfile.TemporaryDirectory() as temp_dir, self.assertRaisesRegex(
            ValueError, "中文女"
        ):
            generator._render_voice_cues(
                TRACKS[0],
                Path(temp_dir),
                model=FakeCosyVoice(speakers=("中文男",)),
            )
        with tempfile.TemporaryDirectory() as temp_dir, self.assertRaisesRegex(
            RuntimeError, "yielded no speech"
        ):
            generator._render_voice_cues(
                TRACKS[0],
                Path(temp_dir),
                model=FakeCosyVoice(empty=True),
                concatenate=lambda chunks: chunks[0],
                audio_saver=fake_saver,
            )

    def test_mix_exactly_matches_the_approved_preview_sound(self):
        with mock.patch.object(generator, "_run") as run:
            generator._mix_track(
                TRACKS[0],
                (Path("piano.wav"), Path("violin.wav"), Path("cello.wav")),
                tuple(Path("cue-{:02d}.wav".format(i)) for i in range(len(TRACKS[0].cues))),
                Path("track.wav"),
            )

        command = " ".join(run.call_args.args[0])
        for value in ("volume=0.48", "volume=0.16", "volume=0.12"):
            self.assertIn(value, command)
        self.assertIn("highpass=f=70", command)
        self.assertIn("lowpass=f=12000", command)
        self.assertIn("attack=200", command)
        self.assertIn("release=900", command)
        self.assertIn("loudnorm=I=-18:TP=-1.5:LRA=8", command)
        self.assertIn("alimiter=limit=0.8414:level=false", command)
        self.assertIn("pcm_s24le", command)
        self.assertNotIn("aecho", command)

    def test_runtime_source_manifest_is_pinned_and_path_free_in_metadata(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest = root / "runtime-sources.json"
            cosyvoice = root / "CosyVoice"
            model = root / "CosyVoice-300M-SFT"
            vsco = root / "VSCO"
            cosyvoice.mkdir()
            model.mkdir()
            vsco.mkdir()
            patch_hashes = {}
            for index, patch_name in enumerate(generator.REQUIRED_PATCHES):
                patch = vsco / patch_name
                patch.write_bytes("patch-{}".format(index).encode("ascii"))
                patch_hashes[patch_name] = hashlib.sha256(
                    patch.read_bytes()
                ).hexdigest()
            sfizz = root / "sfizz_render.exe"
            sfizz.write_bytes(b"sfizz")

            payload = runtime_manifest()
            payload["cosyVoice"]["path"] = str(cosyvoice)
            payload["models"]["sft"]["path"] = str(model)
            payload["vsco2Ce"]["path"] = str(vsco)
            payload["vsco2Ce"]["patchHashes"] = patch_hashes
            payload["sfizz"]["executable"] = str(sfizz)
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            loaded = generator.load_audio_sources(
                manifest, cosyvoice, model, vsco, sfizz
            )

            self.assertEqual(patch_hashes, loaded["sampleLibrary"]["patchHashes"])
            self.assertNotIn(str(root), json.dumps(loaded))

            (vsco / generator.REQUIRED_PATCHES[0]).write_bytes(b"changed")
            with self.assertRaises(ValueError):
                generator.load_audio_sources(
                    manifest, cosyvoice, model, vsco, sfizz
                )

            (vsco / generator.REQUIRED_PATCHES[0]).write_bytes(b"patch-0")
            payload["sfizz"]["executable"] = str(root / "different.exe")
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(ValueError):
                generator.load_audio_sources(
                    manifest, cosyvoice, model, vsco, sfizz
                )

    def test_sidecars_record_cosyvoice_vsco_sources_and_stable_ids(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir)
            cover = output / "cover.png"
            cover.write_bytes(b"png")
            generator._write_sidecars(
                TRACKS[0],
                output,
                cover,
                audio_sources=approved_sources(),
            )
            metadata = json.loads(
                (output / "01-慢呼放松.json").read_text(encoding="utf-8")
            )

        self.assertEqual("lamaze-slow-relax", metadata["id"])
        self.assertEqual("CosyVoice SFT 中文女", metadata["voice"])
        self.assertEqual(0.92, metadata["voiceSpeed"])
        self.assertEqual(approved_sources(), metadata["audioSources"])
        self.assertNotIn("soundFontSources", metadata)

    def test_generate_loads_one_model_for_all_four_tracks(self):
        fake_model = object()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output = root / "out"
            cover = root / "cover.png"
            cover.write_bytes(b"png")
            for name in ("CosyVoice", "model", "VSCO"):
                (root / name).mkdir()
            sfizz = root / "sfizz_render.exe"
            sfizz.write_bytes(b"exe")
            sources = root / "runtime-sources.json"
            sources.write_text("{}", encoding="utf-8")

            with mock.patch.object(generator, "_require_tools"), mock.patch.object(
                generator, "load_audio_sources", return_value=approved_sources()
            ), mock.patch.object(
                generator, "_load_cosyvoice_model", return_value=fake_model
            ) as load_model, mock.patch.object(
                generator,
                "render_production_stems",
                return_value=(Path("piano.wav"), Path("violin.wav"), Path("cello.wav")),
            ), mock.patch.object(
                generator,
                "_render_voice_cues",
                return_value=(Path("cue.wav"),),
            ) as render_voice, mock.patch.object(
                generator, "_mix_track"
            ), mock.patch.object(
                generator, "_encode_mp3"
            ):
                generator.generate(
                    output,
                    cover,
                    root / "CosyVoice",
                    root / "model",
                    sfizz,
                    root / "VSCO",
                    sources,
                )

        self.assertEqual(1, load_model.call_count)
        self.assertEqual(4, render_voice.call_count)
        self.assertTrue(
            all(call.kwargs["model"] is fake_model for call in render_voice.call_args_list)
        )


if __name__ == "__main__":
    unittest.main()
