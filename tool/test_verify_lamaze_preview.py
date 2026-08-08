import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from verify_lamaze_preview import build_argument_parser, verify_preview  # noqa: E402


def valid_probe(path):
    if path.suffix == ".mp3":
        return {
            "duration": 45.01,
            "codec": "mp3",
            "sampleRate": 48_000,
            "channels": 2,
            "bitRate": 192_000,
            "bitDepth": None,
        }
    if path.name.startswith("cue-"):
        return {
            "duration": 3.2,
            "codec": "pcm_s16le",
            "sampleRate": 22_050,
            "channels": 1,
            "bitRate": 352_800,
            "bitDepth": 16,
        }
    return {
        "duration": 45.0,
        "codec": "pcm_s24le",
        "sampleRate": 48_000,
        "channels": 2,
        "bitRate": 2_304_000,
        "bitDepth": 24,
    }


class LamazePreviewVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.wav = self.root / "preview.wav"
        self.mp3 = self.root / "preview.mp3"
        self.cues = self.root / "cues"
        self.cues.mkdir()
        self.wav.write_bytes(b"wav")
        self.mp3.write_bytes(b"mp3")
        for index in range(3):
            (self.cues / "cue-{:02d}.wav".format(index)).write_bytes(b"cue")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_valid_preview_returns_hashes_and_audio_measurements(self):
        with mock.patch("verify_lamaze_preview.probe_audio", side_effect=valid_probe), mock.patch(
            "verify_lamaze_preview.measure_master",
            return_value={"integratedLufs": -18.0, "truePeakDbtp": -1.7},
        ), mock.patch(
            "verify_lamaze_preview.measure_mean_volume", return_value=-22.0
        ):
            report = verify_preview(self.wav, self.mp3, self.cues)

        self.assertEqual(64, len(report["wav"]["sha256"]))
        self.assertEqual(64, len(report["mp3"]["sha256"]))
        self.assertEqual(3, len(report["cues"]))
        self.assertEqual(-1.7, report["master"]["truePeakDbtp"])

    def test_rejects_silent_or_too_short_cues(self):
        def short_probe(path):
            result = valid_probe(path)
            if path.name == "cue-01.wav":
                result["duration"] = 0.4
            return result

        with mock.patch("verify_lamaze_preview.probe_audio", side_effect=short_probe), mock.patch(
            "verify_lamaze_preview.measure_master",
            return_value={"integratedLufs": -18.0, "truePeakDbtp": -1.7},
        ), mock.patch(
            "verify_lamaze_preview.measure_mean_volume", return_value=-22.0
        ), self.assertRaisesRegex(ValueError, "cue duration"):
            verify_preview(self.wav, self.mp3, self.cues)

        with mock.patch("verify_lamaze_preview.probe_audio", side_effect=valid_probe), mock.patch(
            "verify_lamaze_preview.measure_master",
            return_value={"integratedLufs": -18.0, "truePeakDbtp": -1.7},
        ), mock.patch(
            "verify_lamaze_preview.measure_mean_volume", return_value=-50.0
        ), self.assertRaisesRegex(ValueError, "cue mean volume"):
            verify_preview(self.wav, self.mp3, self.cues)

    def test_rejects_peak_above_minus_one_point_five_dbtp(self):
        with mock.patch("verify_lamaze_preview.probe_audio", side_effect=valid_probe), mock.patch(
            "verify_lamaze_preview.measure_master",
            return_value={"integratedLufs": -18.0, "truePeakDbtp": -1.2},
        ), mock.patch(
            "verify_lamaze_preview.measure_mean_volume", return_value=-22.0
        ), self.assertRaisesRegex(ValueError, "true peak"):
            verify_preview(self.wav, self.mp3, self.cues)

    def test_cli_accepts_all_artifacts_and_report_path(self):
        args = build_argument_parser().parse_args(
            [
                "--wav",
                "preview.wav",
                "--mp3",
                "preview.mp3",
                "--cues",
                "cues",
                "--report",
                "verification.json",
            ]
        )
        self.assertEqual(Path("verification.json"), args.report)


if __name__ == "__main__":
    unittest.main()
