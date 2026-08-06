import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_lamaze_audio import TRACKS, render_lrc, validate_track_specs  # noqa: E402


class LamazeAudioSpecTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
