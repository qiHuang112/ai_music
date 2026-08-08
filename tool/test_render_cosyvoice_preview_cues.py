import sys
import tempfile
import unittest
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from lamaze_preview_spec import PREVIEW_CUES  # noqa: E402
from render_cosyvoice_preview_cues import INSTRUCTION, render_cues  # noqa: E402


class FakeSpeech:
    def cpu(self):
        return self


class FakeModel:
    def __init__(self, *, speakers=("中文女",), empty=False):
        self.sample_rate = 22_050
        self._speakers = list(speakers)
        self.empty = empty
        self.sft_calls = []
        self.instruct_calls = []

    def list_available_spks(self):
        return self._speakers

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

    def inference_instruct(self, text, speaker, instruction, *, stream, speed):
        self.instruct_calls.append(
            {
                "text": text,
                "speaker": speaker,
                "instruction": instruction,
                "stream": stream,
                "speed": speed,
            }
        )
        if not self.empty:
            yield {"tts_speech": FakeSpeech()}


def fake_saver(path, _speech, _sample_rate):
    Path(path).write_bytes(b"RIFF" + (b"\0" * 64))


class CosyVoicePreviewCueTests(unittest.TestCase):
    def test_sft_uses_chinese_female_and_preserves_every_sentence(self):
        fake = FakeModel()
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest = render_cues(
                Path("model"),
                Path(temp_dir),
                "sft",
                model_factory=lambda **_: fake,
                concatenate=lambda chunks: chunks[0],
                audio_saver=fake_saver,
            )

        self.assertEqual(
            [cue.text for cue in PREVIEW_CUES],
            [call["text"] for call in fake.sft_calls],
        )
        self.assertTrue(
            all(call["speaker"] == "中文女" for call in fake.sft_calls)
        )
        self.assertTrue(all(call["speed"] == 0.92 for call in fake.sft_calls))
        self.assertEqual("sft", manifest["mode"])
        self.assertEqual(22_050, manifest["sampleRate"])

    def test_instruct_uses_calm_natural_direction(self):
        fake = FakeModel()
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest = render_cues(
                Path("model"),
                Path(temp_dir),
                "instruct",
                model_factory=lambda **_: fake,
                concatenate=lambda chunks: chunks[0],
                audio_saver=fake_saver,
            )

        self.assertIn("calm, warm adult Mandarin-speaking woman", INSTRUCTION)
        self.assertTrue(
            all(
                call["instruction"] == INSTRUCTION
                for call in fake.instruct_calls
            )
        )
        self.assertEqual("instruct", manifest["mode"])

    def test_rejects_unknown_mode_before_loading_model(self):
        with tempfile.TemporaryDirectory() as temp_dir, self.assertRaisesRegex(
            ValueError, "sft or instruct"
        ):
            render_cues(
                Path("model"),
                Path(temp_dir),
                "clone",
                model_factory=lambda **_: self.fail("model should not load"),
            )

    def test_rejects_model_without_chinese_female_speaker(self):
        fake = FakeModel(speakers=("中文男",))
        with tempfile.TemporaryDirectory() as temp_dir, self.assertRaisesRegex(
            ValueError, "中文女"
        ):
            render_cues(
                Path("model"),
                Path(temp_dir),
                "sft",
                model_factory=lambda **_: fake,
            )

    def test_rejects_empty_model_output(self):
        fake = FakeModel(empty=True)
        with tempfile.TemporaryDirectory() as temp_dir, self.assertRaisesRegex(
            RuntimeError, "yielded no speech"
        ):
            render_cues(
                Path("model"),
                Path(temp_dir),
                "sft",
                model_factory=lambda **_: fake,
                concatenate=lambda chunks: chunks[0],
                audio_saver=fake_saver,
            )


if __name__ == "__main__":
    unittest.main()
