import copy
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_lamaze_audio import TRACKS, render_lrc  # noqa: E402
from verify_lamaze_delivery import (  # noqa: E402
    ffmpeg_audio_metrics,
    validate_audio_delivery,
    validate_text_delivery,
)


def _metadata(spec):
    return {
        "id": spec.track_id,
        "title": spec.title,
        "bpm": spec.bpm,
        "durationSeconds": spec.duration_seconds,
        "guidanceStyle": "spoken-direct-actions",
        "cues": [
            {
                "atSeconds": cue.at_seconds,
                "text": cue.text,
                "style": cue.style,
            }
            for cue in spec.cues
        ],
        "soundFontSources": {
            "soundFont": "MuseScore General",
            "version": "0.2.0",
            "license": "MIT",
            "licenseFile": "MuseScore_General_License.md",
            "resources": {
                "MuseScore_General.sf3": {"sha256": "a" * 64},
                "MuseScore_General_License.md": {"sha256": "b" * 64},
                "VERSION": {"sha256": "c" * 64},
            },
        },
    }


class LamazeDeliveryVerifierTests(unittest.TestCase):
    def test_ffmpeg_metrics_parser_uses_summary_loudness_and_true_peak(self):
        class Result:
            stderr = """
            t: 1.0 I: -17.2 LUFS TPK: -3.0 dBFS
            Summary:
              Integrated loudness:
                I: -15.6 LUFS
              True peak:
                Peak: -4.2 dBFS
            """

        def runner(*args, **kwargs):
            return Result()

        self.assertEqual(
            {"integratedLufs": -15.6, "truePeakDbfs": -4.2},
            ffmpeg_audio_metrics(Path("track.wav"), runner=runner),
        )

    def test_text_delivery_requires_exact_audible_cues_and_source_hashes(self):
        spec = TRACKS[0]
        validate_text_delivery(spec, render_lrc(spec), _metadata(spec))

        invalid_rows = []
        wrong_id = _metadata(spec)
        wrong_id["id"] = "different"
        invalid_rows.append((render_lrc(spec), wrong_id))
        chant = _metadata(spec)
        chant["cues"][0]["style"] = "chant"
        invalid_rows.append((render_lrc(spec), chant))
        missing_hash = _metadata(spec)
        del missing_hash["soundFontSources"]["resources"]["VERSION"]["sha256"]
        invalid_rows.append((render_lrc(spec), missing_hash))
        invalid_rows.append((render_lrc(spec) + "[04:59.00]这是一段说明\n", _metadata(spec)))

        for lrc, metadata in invalid_rows:
            with self.subTest(metadata=metadata.get("id"), lrc=lrc[-20:]):
                with self.assertRaises(ValueError):
                    validate_text_delivery(spec, lrc, metadata)

    def test_audio_delivery_requires_exact_formats_and_safe_true_peak(self):
        spec = TRACKS[0]
        wav = {"sampleRate": 48000, "channels": 2, "duration": 300.0}
        mp3 = {
            "streams": [
                {
                    "codec_type": "audio",
                    "sample_rate": "48000",
                    "channels": 2,
                    "bit_rate": "192000",
                }
            ],
            "format": {"duration": "300.0"},
        }
        metrics = {"integratedLufs": -15.8, "truePeakDbfs": -4.2}
        validate_audio_delivery(spec, wav, mp3, metrics)

        bad_peak = copy.deepcopy(metrics)
        bad_peak["truePeakDbfs"] = -0.5
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, wav, mp3, bad_peak)

        bad_wav = copy.deepcopy(wav)
        bad_wav["sampleRate"] = 44100
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, bad_wav, mp3, metrics)

        bad_mp3 = copy.deepcopy(mp3)
        bad_mp3["streams"][0]["bit_rate"] = "128000"
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, wav, bad_mp3, metrics)


if __name__ == "__main__":
    unittest.main()
