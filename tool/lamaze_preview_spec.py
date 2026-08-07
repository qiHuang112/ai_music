"""Immutable copy, timing, and provenance contract for the Lamaze preview."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


PREVIEW_SECONDS = 45


@dataclass(frozen=True)
class PreviewCue:
    at_seconds: float
    text: str


PREVIEW_CUES = (
    PreviewCue(6.0, "肩膀松下来，下巴也松下来。"),
    PreviewCue(20.0, "轻轻吸气，慢慢呼出去。"),
    PreviewCue(35.0, "跟着自己的节奏，放松就好。"),
)


def load_preview_sources(path: Path) -> dict:
    """Load and minimally validate the pinned preview source manifest."""

    decoded = json.loads(path.read_text(encoding="utf-8"))
    if decoded["vsco2Ce"]["license"] != "CC0-1.0":
        raise ValueError("VSCO 2 CE must remain CC0-1.0")
    for model in decoded["models"].values():
        if model["license"] != "Apache-2.0":
            raise ValueError("CosyVoice models must remain Apache-2.0")
    return decoded
