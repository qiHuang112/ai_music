import hashlib
import sys
import tempfile
import unittest
import json
from pathlib import Path
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_lamaze_audio as generator  # noqa: E402
from lamaze_score import render_score_stems  # noqa: E402
from generate_lamaze_audio import TRACKS, render_lrc, validate_track_specs  # noqa: E402


class LamazeAudioSpecTests(unittest.TestCase):
    def test_generator_uses_sampled_score_stems_not_synthetic_backing(self):
        self.assertIs(generator.render_score_stems, render_score_stems)
        self.assertFalse(hasattr(generator, "generate_backing"))

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

    def test_every_track_prioritizes_clinicians_and_has_stop_guidance(self):
        for track in TRACKS:
            lyrics = "\n".join(cue.text for cue in track.cues)
            self.assertIn("医护", lyrics, track.slug)
            self.assertIn("自然呼吸", lyrics, track.slug)
            self.assertNotIn("宫口", lyrics, track.slug)
            self.assertNotIn("厘米", lyrics, track.slug)
            self.assertNotIn("无痛", lyrics, track.slug)
            self.assertNotIn("顺产", lyrics, track.slug)
            self.assertNotIn("保证", lyrics, track.slug)

    def test_audio_copy_is_direct_sparse_and_never_announces_itself(self):
        banned = (
            "这是一段",
            "这首引导",
            "本曲",
            "用于",
            "循环播放",
            "不会替",
        )
        for track in TRACKS:
            text = "\n".join(cue.text for cue in track.cues)
            self.assertFalse(any(value in text for value in banned), track.slug)
            self.assertTrue(all(cue.style == "spoken" for cue in track.cues))
            self.assertLessEqual(track.cues[0].at_seconds, 6, track.slug)
            gaps = [
                right.at_seconds - left.at_seconds
                for left, right in zip(track.cues, track.cues[1:])
            ]
            self.assertTrue(all(20 <= gap <= 35 for gap in gaps), track.slug)
            self.assertTrue(all(len(cue.text) <= 34 for cue in track.cues), track.slug)
        self.assertLessEqual(TRACKS[2].cues[0].at_seconds, 3)

    def test_defer_pushing_track_is_conditional_and_follow_track_never_commands_it(self):
        defer = "\n".join(cue.text for cue in TRACKS[2].cues)
        follow = "\n".join(cue.text for cue in TRACKS[3].cues)

        self.assertIn("明确要求暂缓用力", defer)
        self.assertIn("不要屏气", defer)
        self.assertIn("先听医护", follow)
        self.assertNotIn("现在用力", follow)

    def test_lrc_is_utf8_ready_sorted_and_within_duration(self):
        for track in TRACKS:
            lrc = render_lrc(track)
            self.assertTrue(lrc.startswith("[ar:AI Home]\n"))
            self.assertNotIn("[00:00.00]", lrc)
            self.assertTrue(lrc.endswith("\n"))
            self.assertLess(track.cues[-1].at_seconds, track.duration_seconds)

    def test_preview_cli_accepts_track_duration_voice_and_soundfont(self):
        parser = generator.build_argument_parser()
        args = parser.parse_args(
            [
                "--output",
                "/tmp/preview",
                "--cover",
                "/tmp/cover.png",
                "--soundfont",
                "/tmp/MuseScore_General.sf3",
                "--voice",
                "Grandma (中文（中国大陆）)",
                "--preview-track",
                "01-慢呼放松",
                "--preview-seconds",
                "45",
            ]
        )

        self.assertEqual("01-慢呼放松", args.preview_track)
        self.assertEqual(45, args.preview_seconds)
        self.assertEqual("Grandma (中文（中国大陆）)", args.voice)

    def test_preview_renders_only_clipped_track_without_delivery_sidecars(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output = root / "preview"
            cover = root / "cover.png"
            soundfont = root / "MuseScore_General.sf3"
            cover.write_bytes(b"png")
            soundfont.write_bytes(b"sf3")

            with mock.patch.object(generator, "_require_tools"), mock.patch.object(
                generator,
                "render_score_stems",
                return_value=(
                    Path("piano.wav"),
                    Path("strings.wav"),
                    Path("air.wav"),
                ),
            ) as render_stems, mock.patch.object(
                generator,
                "_render_voice_cues",
                return_value=(Path("voice.aiff"),),
            ) as render_voice, mock.patch.object(
                generator, "_mix_track"
            ) as mix_track, mock.patch.object(
                generator, "_encode_mp3"
            ) as encode_mp3:
                generator.generate(
                    output,
                    cover,
                    soundfont,
                    voice="Grandma (中文（中国大陆）)",
                    preview_track="01-慢呼放松",
                    preview_seconds=45,
                )

            preview_spec = render_stems.call_args.args[0]
            self.assertEqual(45, preview_spec.duration_seconds)
            self.assertEqual([6, 32], [cue.at_seconds for cue in preview_spec.cues])
            self.assertEqual(1, render_stems.call_count)
            self.assertEqual(
                "Grandma (中文（中国大陆）)", render_voice.call_args.kwargs["voice"]
            )
            self.assertEqual("01-慢呼放松-45s.wav", mix_track.call_args.args[3].name)
            self.assertEqual("01-慢呼放松-45s.mp3", encode_mp3.call_args.args[3].name)
            self.assertFalse((output / "README.txt").exists())
            self.assertEqual([], list(output.glob("*.json")))
            self.assertEqual([], list(output.glob("*.lrc")))
            self.assertEqual([], list(output.glob("*.txt")))

    def test_voice_renderer_uses_replaceable_mature_voice_without_chant_effects(self):
        with tempfile.TemporaryDirectory() as temp_dir, mock.patch.object(
            generator, "_run"
        ) as run:
            generator._render_voice_cues(
                generator.preview_track_spec(TRACKS[0], 45),
                Path(temp_dir),
                voice="Grandma (中文（中国大陆）)",
            )

        commands = [" ".join(call.args[0]) for call in run.call_args_list]
        self.assertTrue(commands)
        self.assertTrue(all(" -v Grandma " in " {} ".format(command) for command in commands))
        self.assertTrue(all(" -r 138 " in " {} ".format(command) for command in commands))
        self.assertTrue(all("vibrato" not in command for command in commands))

    def test_mix_uses_clean_voice_filter_and_smooth_background_ducking(self):
        track = generator.preview_track_spec(TRACKS[0], 45)
        with mock.patch.object(generator, "_run") as run:
            generator._mix_track(
                track,
                (Path("piano.wav"), Path("strings.wav"), Path("air.wav")),
                (Path("cue-1.aiff"), Path("cue-2.aiff")),
                Path("preview.wav"),
            )

        command = " ".join(run.call_args.args[0])
        self.assertIn("highpass=f=80", command)
        self.assertIn("lowpass=f=11000", command)
        self.assertIn("sidechaincompress", command)
        self.assertIn("apad=whole_dur=45", command)
        self.assertIn("attack=120", command)
        self.assertIn("release=500", command)
        self.assertNotIn("vibrato", command)

    def test_delivery_metadata_records_spoken_cues_and_soundfont_hashes(self):
        sources = {
            "soundFont": "MuseScore General",
            "version": "0.2.0",
            "license": "MIT",
            "licenseFile": "MuseScore_General_License.md",
            "resources": {
                "MuseScore_General.sf3": {
                    "url": "https://example.test/MuseScore_General.sf3",
                    "sha256": "a" * 64,
                    "sizeBytes": 123,
                },
                "MuseScore_General_License.md": {
                    "url": "https://example.test/license",
                    "sha256": "b" * 64,
                    "sizeBytes": 456,
                },
                "VERSION": {
                    "url": "https://example.test/version",
                    "sha256": "c" * 64,
                    "sizeBytes": 6,
                },
            },
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir)
            cover = output / "cover.png"
            cover.write_bytes(b"png")

            generator._write_sidecars(
                TRACKS[0],
                output,
                cover,
                voice="Grandma (中文（中国大陆）)",
                soundfont_sources=sources,
            )

            metadata = json.loads(
                (output / "01-慢呼放松.json").read_text(encoding="utf-8")
            )
            lrc = (output / "01-慢呼放松.lrc").read_text(encoding="utf-8")

        self.assertEqual("spoken-direct-actions", metadata["guidanceStyle"])
        self.assertEqual(
            [
                {
                    "atSeconds": cue.at_seconds,
                    "text": cue.text,
                    "style": "spoken",
                }
                for cue in TRACKS[0].cues
            ],
            metadata["cues"],
        )
        self.assertEqual(sources, metadata["soundFontSources"])
        self.assertEqual(render_lrc(TRACKS[0]), lrc)

    def test_soundfont_sources_are_verified_against_downloaded_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            resources = {
                "MuseScore_General.sf3": b"soundfont",
                "MuseScore_General_License.md": b"MIT license",
                "VERSION": b"0.2.0\n",
            }
            for name, payload in resources.items():
                (root / name).write_bytes(payload)
            manifest = {
                "soundFont": "MuseScore General",
                "version": "0.2.0",
                "license": "MIT",
                "licenseFile": "MuseScore_General_License.md",
                "resources": {
                    name: {
                        "url": "https://example.test/{}".format(name),
                        "sha256": hashlib.sha256(payload).hexdigest(),
                        "sizeBytes": len(payload),
                    }
                    for name, payload in resources.items()
                },
            }
            manifest_path = root / "lamaze_soundfont_sources.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            loaded = generator.load_soundfont_sources(
                root / "MuseScore_General.sf3"
            )
            self.assertEqual(manifest, loaded)

            manifest["resources"]["VERSION"]["sha256"] = "0" * 64
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(ValueError):
                generator.load_soundfont_sources(root / "MuseScore_General.sf3")


if __name__ == "__main__":
    unittest.main()
