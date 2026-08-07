import sys
import unittest
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from lamaze_preview_spec import (  # noqa: E402
    PREVIEW_CUES,
    PREVIEW_SECONDS,
    load_preview_sources,
)


class LamazePreviewSpecTests(unittest.TestCase):
    def test_preview_has_exact_approved_copy_and_timing(self):
        self.assertEqual(45, PREVIEW_SECONDS)
        self.assertEqual(
            [
                (6.0, "肩膀松下来，下巴也松下来。"),
                (20.0, "轻轻吸气，慢慢呼出去。"),
                (35.0, "跟着自己的节奏，放松就好。"),
            ],
            [(cue.at_seconds, cue.text) for cue in PREVIEW_CUES],
        )

    def test_sources_are_pinned_and_permissively_licensed(self):
        sources = load_preview_sources(TOOL_DIR / "lamaze_preview_sources.json")

        self.assertEqual(
            "074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc",
            sources["cosyVoice"]["commit"],
        )
        self.assertEqual(
            "fbb71de2afe387ed854eebd80b9f3d078c6b9869",
            sources["models"]["sft"]["revision"],
        )
        self.assertEqual(
            "706bee1915e9fd1f1214929e2a0509c874cff433",
            sources["models"]["instruct"]["revision"],
        )
        self.assertEqual("CC0-1.0", sources["vsco2Ce"]["license"])
        self.assertEqual("1.2.3", sources["sfizz"]["version"])
        self.assertEqual(
            [
                "UprightPiano.sfz",
                "ViolinEnsSusVib-Quiet.sfz",
                "CelloEnsSusVib-Quiet.sfz",
            ],
            sources["vsco2Ce"]["requiredPatches"],
        )


if __name__ == "__main__":
    unittest.main()
