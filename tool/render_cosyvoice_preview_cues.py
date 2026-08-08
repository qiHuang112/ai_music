#!/usr/bin/env python3
"""Render the approved Lamaze preview cues with a pinned CosyVoice model."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from lamaze_preview_spec import PREVIEW_CUES


INSTRUCTION = (
    "A calm, warm adult Mandarin-speaking woman with a natural conversational tone. "
    "Speak gently, slowly and clearly, without whispering, acting, singing or "
    "announcer intonation.<|endofprompt|>"
)


def render_cues(
    model_dir: Path,
    output: Path,
    mode: str,
    speaker: str = "中文女",
    speed: float = 0.92,
    model_factory=None,
    concatenate=None,
    audio_saver=None,
) -> dict:
    """Render one isolated WAV file per approved preview cue."""

    if mode not in {"sft", "instruct"}:
        raise ValueError("mode must be sft or instruct")

    if model_factory is None:
        from cosyvoice.cli.cosyvoice import AutoModel

        model_factory = AutoModel
    model = model_factory(model_dir=str(model_dir))
    if speaker not in model.list_available_spks():
        raise ValueError("CosyVoice model does not provide 中文女")

    if concatenate is None:
        import torch

        concatenate = lambda values: torch.cat(values, dim=1)
    if audio_saver is None:
        import torchaudio

        audio_saver = torchaudio.save

    output.mkdir(parents=True, exist_ok=True)
    records = []
    for index, cue in enumerate(PREVIEW_CUES):
        if mode == "sft":
            iterator = model.inference_sft(
                cue.text,
                speaker,
                stream=False,
                speed=speed,
            )
        else:
            iterator = model.inference_instruct(
                cue.text,
                speaker,
                INSTRUCTION,
                stream=False,
                speed=speed,
            )
        chunks = [item["tts_speech"] for item in iterator]
        if not chunks:
            raise RuntimeError("CosyVoice yielded no speech")

        target = output / "cue-{:02d}.wav".format(index)
        audio_saver(str(target), concatenate(chunks).cpu(), model.sample_rate)
        if not target.is_file() or target.stat().st_size <= 44:
            raise RuntimeError("Invalid cue output: {}".format(target))
        records.append(
            {
                "atSeconds": cue.at_seconds,
                "text": cue.text,
                "file": target.name,
            }
        )

    manifest = {
        "engine": "CosyVoice",
        "mode": mode,
        "speaker": speaker,
        "speed": speed,
        "sampleRate": model.sample_rate,
        "cues": records,
    }
    (output / "voice-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cosyvoice-root", required=True, type=Path)
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("sft", "instruct"))
    parser.add_argument("--speaker", default="中文女")
    parser.add_argument("--speed", default=0.92, type=float)
    return parser


def main() -> None:
    args = build_argument_parser().parse_args()
    cosyvoice_root = args.cosyvoice_root.expanduser().resolve()
    model_dir = args.model_dir.expanduser().resolve()
    if not cosyvoice_root.is_dir():
        raise SystemExit("CosyVoice root does not exist: {}".format(cosyvoice_root))
    if not model_dir.is_dir():
        raise SystemExit("CosyVoice model does not exist: {}".format(model_dir))
    sys.path.insert(0, str(cosyvoice_root))
    sys.path.insert(0, str(cosyvoice_root / "third_party" / "Matcha-TTS"))
    render_cues(
        model_dir,
        args.output.expanduser().resolve(),
        args.mode,
        speaker=args.speaker,
        speed=args.speed,
    )


if __name__ == "__main__":
    main()
