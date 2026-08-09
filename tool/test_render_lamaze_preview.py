import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from render_lamaze_preview import (  # noqa: E402
    build_argument_parser,
    encode_preview_mp3,
    mix_preview,
)


class LamazePreviewMixTests(unittest.TestCase):
    def test_mix_places_three_cues_ducks_music_and_avoids_echo(self):
        stems = tuple(Path(name) for name in ("piano.wav", "violin.wav", "cello.wav"))
        cues = tuple(Path("cue-{:02d}.wav".format(index)) for index in range(3))
        with mock.patch("render_lamaze_preview._run") as run:
            mix_preview(stems, cues, Path("preview.wav"))

        command = " ".join(run.call_args.args[0])
        self.assertIn("volume=0.48", command)
        self.assertIn("volume=0.16", command)
        self.assertIn("volume=0.12", command)
        self.assertIn("adelay=6000:all=1", command)
        self.assertIn("adelay=20000:all=1", command)
        self.assertIn("adelay=35000:all=1", command)
        self.assertIn("sidechaincompress", command)
        self.assertIn("attack=200", command)
        self.assertIn("release=900", command)
        self.assertIn("loudnorm=I=-18:TP=-1.5:LRA=8", command)
        self.assertIn("alimiter=limit=0.8414:level=false", command)
        self.assertIn("pcm_s24le", command)
        self.assertNotIn("aecho", command)

    def test_mix_requires_three_stems_and_three_cues(self):
        with self.assertRaisesRegex(ValueError, "three music stems"):
            mix_preview((Path("piano.wav"),), (), Path("preview.wav"))
        with self.assertRaisesRegex(ValueError, "three voice cues"):
            mix_preview(
                (Path("piano.wav"), Path("violin.wav"), Path("cello.wav")),
                (Path("cue.wav"),),
                Path("preview.wav"),
            )

    def test_mp3_encoder_uses_192k_stereo_at_48khz(self):
        with mock.patch("render_lamaze_preview._run") as run:
            encode_preview_mp3(Path("preview.wav"), Path("preview.mp3"))

        command = " ".join(run.call_args.args[0])
        self.assertIn("libmp3lame", command)
        self.assertIn("-b:a 192k", command)
        self.assertIn("-ar 48000", command)
        self.assertIn("-ac 2", command)

    def test_cli_accepts_stems_cues_and_output_prefix(self):
        args = build_argument_parser().parse_args(
            [
                "--stems",
                "stems",
                "--cues",
                "cues",
                "--output-prefix",
                "preview",
            ]
        )
        self.assertEqual(Path("stems"), args.stems)
        self.assertEqual(Path("cues"), args.cues)
        self.assertEqual(Path("preview"), args.output_prefix)


if __name__ == "__main__":
    unittest.main()
