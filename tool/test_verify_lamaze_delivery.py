import copy
import sys
import unittest
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from generate_lamaze_audio import (  # noqa: E402
    COSYVOICE_COMMIT,
    SFT_REVISION,
    TRACKS,
    VSCO_COMMIT,
    render_lrc,
)
from verify_lamaze_delivery import (  # noqa: E402
    ffmpeg_audio_metrics,
    validate_audio_delivery,
    validate_text_delivery,
)


def _audio_sources():
    return {
        "voiceEngine": {
            "name": "CosyVoice",
            "commit": COSYVOICE_COMMIT,
            "license": "Apache-2.0",
        },
        "voiceModel": {
            "repo": "FunAudioLLM/CosyVoice-300M-SFT",
            "revision": SFT_REVISION,
            "license": "Apache-2.0",
            "speaker": "中文女",
            "speed": 0.92,
        },
        "sampleLibrary": {
            "name": "VSCO 2 CE",
            "commit": VSCO_COMMIT,
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


def _metadata(spec):
    return {
        "id": spec.track_id,
        "title": spec.title,
        "bpm": spec.bpm,
        "durationSeconds": spec.duration_seconds,
        "voice": "CosyVoice SFT 中文女",
        "voiceSpeed": 0.92,
        "guidanceStyle": "spoken-direct-actions",
        "cues": [
            {
                "atSeconds": cue.at_seconds,
                "text": cue.text,
                "style": cue.style,
            }
            for cue in spec.cues
        ],
        "instruments": [
            "VSCO Upright Piano",
            "VSCO Quiet Violin Ensemble",
            "VSCO Quiet Cello Ensemble",
        ],
        "audioSources": _audio_sources(),
        "usage": (
            "呼吸陪伴工具；现场医生和助产士指令始终优先。"
            + (
                "仅在医护人员明确要求暂缓用力时使用。"
                if spec.slug == "03-暂缓用力"
                else ""
            )
        ),
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
            self.assertEqual("utf-8", kwargs.get("encoding"))
            self.assertEqual("replace", kwargs.get("errors"))
            return Result()

        self.assertEqual(
            {"integratedLufs": -15.6, "truePeakDbtp": -4.2},
            ffmpeg_audio_metrics(Path("track.wav"), runner=runner),
        )

    def test_text_delivery_requires_exact_cues_voice_and_source_pins(self):
        spec = TRACKS[0]
        validate_text_delivery(spec, render_lrc(spec), _metadata(spec))

        invalid_rows = []
        wrong_id = _metadata(spec)
        wrong_id["id"] = "different"
        invalid_rows.append(wrong_id)
        chant = _metadata(spec)
        chant["cues"][0]["style"] = "chant"
        invalid_rows.append(chant)
        wrong_voice = _metadata(spec)
        wrong_voice["voice"] = "System TTS"
        invalid_rows.append(wrong_voice)
        wrong_revision = _metadata(spec)
        wrong_revision["audioSources"]["voiceModel"]["revision"] = "main"
        invalid_rows.append(wrong_revision)
        missing_patch_hash = _metadata(spec)
        del missing_patch_hash["audioSources"]["sampleLibrary"]["patchHashes"][
            "UprightPiano.sfz"
        ]
        invalid_rows.append(missing_patch_hash)
        legacy = _metadata(spec)
        legacy["soundFontSources"] = {"license": "MIT"}
        invalid_rows.append(legacy)

        for metadata in invalid_rows:
            with self.subTest(metadata=metadata.get("id")):
                with self.assertRaises(ValueError):
                    validate_text_delivery(spec, render_lrc(spec), metadata)

        with self.assertRaises(ValueError):
            validate_text_delivery(
                spec,
                render_lrc(spec) + "[04:59.00]这是一段说明\n",
                _metadata(spec),
            )

    def test_defer_track_metadata_retains_conditional_usage(self):
        spec = TRACKS[2]
        validate_text_delivery(spec, render_lrc(spec), _metadata(spec))

        metadata = _metadata(spec)
        metadata["usage"] = "现场医护优先。"
        with self.assertRaises(ValueError):
            validate_text_delivery(spec, render_lrc(spec), metadata)

    def test_audio_delivery_requires_24_bit_pcm_and_safe_true_peak(self):
        spec = TRACKS[0]
        wav = {
            "codec": "pcm_s24le",
            "sampleRate": 48000,
            "channels": 2,
            "bitDepth": 24,
            "duration": 300.0,
        }
        mp3 = {
            "streams": [
                {
                    "codec_type": "audio",
                    "codec_name": "mp3",
                    "sample_rate": "48000",
                    "channels": 2,
                    "bit_rate": "192000",
                }
            ],
            "format": {"duration": "300.0"},
        }
        metrics = {"integratedLufs": -18.0, "truePeakDbtp": -2.0}
        validate_audio_delivery(spec, wav, mp3, metrics)

        bad_peak = copy.deepcopy(metrics)
        bad_peak["truePeakDbtp"] = -0.5
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, wav, mp3, bad_peak)

        bad_depth = copy.deepcopy(wav)
        bad_depth["bitDepth"] = 16
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, bad_depth, mp3, metrics)

        bad_codec = copy.deepcopy(wav)
        bad_codec["codec"] = "pcm_f32le"
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, bad_codec, mp3, metrics)

        bad_mp3 = copy.deepcopy(mp3)
        bad_mp3["streams"][0]["bit_rate"] = "128000"
        with self.assertRaises(ValueError):
            validate_audio_delivery(spec, wav, bad_mp3, metrics)


if __name__ == "__main__":
    unittest.main()
