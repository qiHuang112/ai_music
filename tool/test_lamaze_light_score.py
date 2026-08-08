import hashlib
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from lamaze_light_score import (  # noqa: E402
    PREVIEW_TRACK,
    build_argument_parser,
    build_preview_scores,
    render_light_stems,
)
from lamaze_score import midi_bytes  # noqa: E402


def midi_channels(data):
    header_length = struct.unpack(">I", data[4:8])[0]
    track_start = 8 + header_length
    track_length = struct.unpack(">I", data[track_start + 4 : track_start + 8])[0]
    payload = data[track_start + 8 : track_start + 8 + track_length]
    channels = []
    offset = 0
    while offset < len(payload):
        while payload[offset] & 0x80:
            offset += 1
        offset += 1
        status = payload[offset]
        offset += 1
        if status == 0xFF:
            meta_type = payload[offset]
            offset += 1
            length = 0
            while True:
                byte = payload[offset]
                offset += 1
                length = (length << 7) | (byte & 0x7F)
                if not byte & 0x80:
                    break
            offset += length
            if meta_type == 0x2F:
                break
            continue
        channels.append(status & 0x0F)
        offset += 1 if status & 0xF0 == 0xC0 else 2
    return channels


class LamazeLightScoreTests(unittest.TestCase):
    def test_score_is_sparse_authored_and_not_a_per_beat_arpeggio(self):
        scores = build_preview_scores()

        self.assertEqual({"piano", "violin", "cello"}, set(scores))
        starts = [note.start_beat for note in scores["piano"].notes]
        self.assertTrue(any(start != int(start) for start in starts))
        self.assertLess(len(starts), 28)
        self.assertTrue(
            all(
                note.velocity <= 52
                for score in scores.values()
                for note in score.notes
            )
        )
        self.assertGreaterEqual(
            max(
                note.start_beat + note.duration_beats
                for score in scores.values()
                for note in score.notes
            ),
            44,
        )

    def test_preview_midi_is_deterministic_and_uses_no_percussion_channel(self):
        for score in build_preview_scores().values():
            first = midi_bytes(PREVIEW_TRACK, score)
            second = midi_bytes(PREVIEW_TRACK, score)
            self.assertEqual(hashlib.sha256(first).digest(), hashlib.sha256(second).digest())
            self.assertNotIn(9, midi_channels(first))

    def test_renderer_uses_exact_cc0_sfz_patches(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = root / "work"
            vsco = root / "VSCO"
            vsco.mkdir()
            for patch_name in (
                "UprightPiano.sfz",
                "ViolinEnsSusVib-Quiet.sfz",
                "CelloEnsSusVib-Quiet.sfz",
            ):
                (vsco / patch_name).write_text("<region>", encoding="utf-8")
            sfizz = root / "sfizz_render.exe"
            sfizz.write_bytes(b"exe")
            commands = []

            def fake_run(command):
                command = tuple(str(value) for value in command)
                commands.append(command)
                if "--wav" in command:
                    Path(command[command.index("--wav") + 1]).write_bytes(b"rendered")
                else:
                    Path(command[-1]).write_bytes(b"stem")

            with mock.patch(
                "lamaze_light_score.shutil.which", return_value="ffmpeg"
            ), mock.patch("lamaze_light_score._run", side_effect=fake_run):
                stems = render_light_stems(work, sfizz, vsco)

        flattened = [" ".join(command) for command in commands]
        self.assertEqual(["piano.wav", "violin.wav", "cello.wav"], [p.name for p in stems])
        self.assertTrue(any("UprightPiano.sfz" in command for command in flattened))
        self.assertTrue(any("ViolinEnsSusVib-Quiet.sfz" in command for command in flattened))
        self.assertTrue(any("CelloEnsSusVib-Quiet.sfz" in command for command in flattened))
        self.assertTrue(all("MuseScore_General" not in command for command in flattened))
        self.assertTrue(all("--quality 10" in command for command in flattened[::2]))

    def test_cli_accepts_output_renderer_and_vsco_paths(self):
        args = build_argument_parser().parse_args(
            [
                "--output",
                "out",
                "--sfizz-render",
                "sfizz_render.exe",
                "--vsco-root",
                "VSCO",
            ]
        )
        self.assertEqual(Path("out"), args.output)
        self.assertEqual(Path("sfizz_render.exe"), args.sfizz_render)
        self.assertEqual(Path("VSCO"), args.vsco_root)


if __name__ == "__main__":
    unittest.main()
