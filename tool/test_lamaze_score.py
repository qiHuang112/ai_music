import hashlib
import struct
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_lamaze_audio import TRACKS  # noqa: E402
from lamaze_score import (  # noqa: E402
    TICKS_PER_BEAT,
    build_stem_scores,
    midi_bytes,
)


def _read_variable_length(data, offset):
    value = 0
    while True:
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, offset


def _parse_midi(data):
    if data[:4] != b"MThd":
        raise AssertionError("missing MIDI header")
    header_length = struct.unpack(">I", data[4:8])[0]
    midi_format, track_count, division = struct.unpack(">HHH", data[8:14])
    track_start = 8 + header_length
    if data[track_start : track_start + 4] != b"MTrk":
        raise AssertionError("missing track chunk")
    track_length = struct.unpack(">I", data[track_start + 4 : track_start + 8])[0]
    payload = data[track_start + 8 : track_start + 8 + track_length]
    offset = 0
    tick = 0
    programs = []
    channels = []
    velocities = []
    end_tick = None
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
                end_tick = tick
                break
            continue
        event = status & 0xF0
        channel = status & 0x0F
        channels.append(channel)
        if event == 0xC0:
            programs.append(payload[offset])
            offset += 1
        elif event in (0x80, 0x90):
            offset += 1
            velocity = payload[offset]
            offset += 1
            if event == 0x90 and velocity:
                velocities.append(velocity)
        else:
            raise AssertionError("unexpected MIDI event: 0x{:02x}".format(status))
    return {
        "format": midi_format,
        "trackCount": track_count,
        "division": division,
        "programs": programs,
        "channels": channels,
        "velocities": velocities,
        "endTick": end_tick,
    }


class LamazeScoreTests(unittest.TestCase):
    def test_scores_use_only_three_soft_non_percussion_instruments(self):
        for track in TRACKS:
            scores = build_stem_scores(track)
            self.assertEqual(["piano", "strings", "air"], list(scores))
            self.assertEqual([0, 48, 89], [score.program for score in scores.values()])
            for score in scores.values():
                self.assertTrue(score.notes, (track.slug, score.name))
                self.assertTrue(
                    all(0 < note.velocity < 90 for note in score.notes),
                    (track.slug, score.name),
                )
                self.assertTrue(
                    all(
                        note.start_beat >= 0
                        and note.duration_beats > 0
                        and note.start_beat + note.duration_beats
                        <= track.duration_seconds * track.bpm / 60
                        for note in score.notes
                    ),
                    (track.slug, score.name),
                )

    def test_midi_is_format_zero_deterministic_and_ends_at_exact_duration(self):
        for track in TRACKS:
            total_ticks = int(track.duration_seconds * track.bpm / 60 * TICKS_PER_BEAT)
            for score in build_stem_scores(track).values():
                first = midi_bytes(track, score)
                second = midi_bytes(track, score)
                parsed = _parse_midi(first)

                self.assertEqual(first, second)
                self.assertEqual(0, parsed["format"])
                self.assertEqual(1, parsed["trackCount"])
                self.assertEqual(TICKS_PER_BEAT, parsed["division"])
                self.assertEqual([score.program], parsed["programs"])
                self.assertEqual(total_ticks, parsed["endTick"])
                self.assertNotIn(9, parsed["channels"])
                self.assertTrue(all(value < 90 for value in parsed["velocities"]))

    def test_each_track_has_a_distinct_reproducible_score_hash(self):
        hashes = []
        for track in TRACKS:
            payload = b"".join(
                midi_bytes(track, score)
                for score in build_stem_scores(track).values()
            )
            hashes.append(hashlib.sha256(payload).hexdigest())

        self.assertEqual(len(TRACKS), len(set(hashes)))


if __name__ == "__main__":
    unittest.main()
