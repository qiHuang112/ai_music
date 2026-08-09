import hashlib
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from generate_lamaze_audio import TRACKS  # noqa: E402
from lamaze_production_score import (  # noqa: E402
    build_production_scores,
    render_production_stems,
)
from lamaze_score import TICKS_PER_BEAT, midi_bytes  # noqa: E402


def _read_variable_length(data, offset):
    value = 0
    while True:
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, offset


def _midi_channels_and_end(data):
    header_length = struct.unpack(">I", data[4:8])[0]
    track_start = 8 + header_length
    track_length = struct.unpack(">I", data[track_start + 4 : track_start + 8])[0]
    payload = data[track_start + 8 : track_start + 8 + track_length]
    offset = 0
    tick = 0
    channels = []
    while offset < len(payload):
        delta, offset = _read_variable_length(payload, offset)
        tick += delta
        status = payload[offset]
        offset += 1
        if status == 0xFF:
            meta_type = payload[offset]
            offset += 1
            length, offset = _read_variable_length(payload, offset)
            offset += length
            if meta_type == 0x2F:
                return channels, tick
            continue
        channels.append(status & 0x0F)
        offset += 1 if status & 0xF0 == 0xC0 else 2
    raise AssertionError("MIDI end-of-track event is missing")


class LamazeProductionScoreTests(unittest.TestCase):
    def test_scores_are_sparse_soft_and_cover_each_exact_track_duration(self):
        for track in TRACKS:
            scores = build_production_scores(track)
            total_beats = track.duration_seconds * track.bpm / 60

            self.assertEqual(["piano", "violin", "cello"], list(scores))
            piano_starts = {note.start_beat for note in scores["piano"].notes}
            self.assertTrue(any(start != int(start) for start in piano_starts))
            self.assertLess(len(piano_starts), total_beats / 2)
            self.assertTrue(
                all(
                    0 < note.velocity <= 52
                    for score in scores.values()
                    for note in score.notes
                )
            )
            self.assertEqual(
                total_beats,
                max(
                    note.start_beat + note.duration_beats
                    for score in scores.values()
                    for note in score.notes
                ),
            )

    def test_midi_is_deterministic_distinct_and_has_no_percussion_channel(self):
        track_hashes = []
        for track in TRACKS:
            payloads = []
            expected_end = round(
                track.duration_seconds * track.bpm / 60 * TICKS_PER_BEAT
            )
            for score in build_production_scores(track).values():
                first = midi_bytes(track, score)
                second = midi_bytes(track, score)
                channels, end_tick = _midi_channels_and_end(first)

                self.assertEqual(first, second)
                self.assertNotIn(9, channels)
                self.assertEqual(expected_end, end_tick)
                payloads.append(first)
            track_hashes.append(hashlib.sha256(b"".join(payloads)).hexdigest())

        self.assertEqual(len(TRACKS), len(set(track_hashes)))

    def test_renderer_uses_exact_vsco_patches_and_24_bit_stems(self):
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
                "lamaze_production_score.shutil.which", return_value="ffmpeg"
            ), mock.patch(
                "lamaze_production_score._run", side_effect=fake_run
            ):
                stems = render_production_stems(TRACKS[0], work, sfizz, vsco)

        flattened = [" ".join(command) for command in commands]
        self.assertEqual(
            ["piano.wav", "violin.wav", "cello.wav"],
            [path.name for path in stems],
        )
        for patch_name in (
            "UprightPiano.sfz",
            "ViolinEnsSusVib-Quiet.sfz",
            "CelloEnsSusVib-Quiet.sfz",
        ):
            self.assertTrue(any(patch_name in command for command in flattened))
        self.assertEqual(3, sum("--quality 10" in command for command in flattened))
        self.assertEqual(3, sum("pcm_s24le" in command for command in flattened))
        self.assertTrue(all("MuseScore_General" not in command for command in flattened))


if __name__ == "__main__":
    unittest.main()
