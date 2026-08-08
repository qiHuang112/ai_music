#!/usr/bin/env python3
"""Render an authored 45-second Lamaze score with CC0 VSCO 2 CE samples."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Sequence

from lamaze_score import MidiNote, StemScore, write_midi


SAMPLE_RATE = 48_000


@dataclass(frozen=True)
class PreviewTrackSpec:
    duration_seconds: int = 45
    bpm: int = 60


PREVIEW_TRACK = PreviewTrackSpec()


def _notes(
    values: Sequence[tuple[float, float, int, int]],
) -> tuple[MidiNote, ...]:
    return tuple(
        MidiNote(
            start_beat=start,
            duration_beats=duration,
            pitch=pitch,
            velocity=velocity,
        )
        for start, duration, pitch, velocity in values
    )


def build_preview_scores() -> Dict[str, StemScore]:
    """Return the fixed, sparse score approved for the first preview."""

    piano_values = (
        (0.0, 7.3, 48, 39),
        (0.0, 7.3, 55, 37),
        (0.0, 7.3, 64, 35),
        (3.4, 2.4, 67, 46),
        (8.1, 7.2, 45, 40),
        (8.1, 7.2, 52, 37),
        (8.1, 7.2, 60, 36),
        (11.7, 2.2, 64, 48),
        (16.0, 7.4, 41, 41),
        (16.0, 7.4, 48, 38),
        (16.0, 7.4, 57, 36),
        (19.3, 2.5, 60, 45),
        (24.2, 7.0, 40, 39),
        (24.2, 7.0, 48, 37),
        (24.2, 7.0, 55, 35),
        (27.6, 2.3, 59, 47),
        (32.0, 7.2, 43, 41),
        (32.0, 7.2, 50, 38),
        (32.0, 7.2, 57, 36),
        (36.2, 2.2, 62, 52),
        (40.1, 4.8, 48, 39),
        (40.1, 4.8, 55, 36),
        (40.1, 4.8, 62, 34),
        (42.3, 2.0, 64, 44),
    )
    violin_values = (
        (0.0, 15.8, 64, 28),
        (0.0, 15.8, 67, 26),
        (0.0, 15.8, 71, 24),
        (15.6, 16.1, 60, 30),
        (15.6, 16.1, 64, 27),
        (15.6, 16.1, 69, 25),
        (31.5, 13.3, 62, 31),
        (31.5, 13.3, 67, 28),
        (31.5, 13.3, 69, 25),
    )
    cello_values = (
        (0.0, 15.8, 48, 32),
        (15.6, 16.1, 41, 34),
        (31.5, 13.3, 43, 33),
    )
    return {
        "piano": StemScore("piano", 0, _notes(piano_values)),
        "violin": StemScore("violin", 48, _notes(violin_values)),
        "cello": StemScore("cello", 48, _notes(cello_values)),
    }


def render_light_stems(
    work: Path,
    sfizz_render: Path,
    vsco_root: Path,
) -> tuple[Path, Path, Path]:
    """Render piano, violin, and cello stems through the pinned SFZ patches."""

    if not sfizz_render.is_file():
        raise FileNotFoundError("sfizz_render does not exist: {}".format(sfizz_render))
    if shutil.which("ffmpeg") is None:
        raise RuntimeError("Missing required tool: ffmpeg")
    patches = {
        "piano": "UprightPiano.sfz",
        "violin": "ViolinEnsSusVib-Quiet.sfz",
        "cello": "CelloEnsSusVib-Quiet.sfz",
    }
    for patch_name in patches.values():
        if not (vsco_root / patch_name).is_file():
            raise FileNotFoundError("VSCO patch does not exist: {}".format(patch_name))

    work.mkdir(parents=True, exist_ok=True)
    targets = []
    scores = build_preview_scores()
    for name in ("piano", "violin", "cello"):
        midi_path = write_midi(PREVIEW_TRACK, scores[name], work / "{}.mid".format(name))
        rendered = work / "{}-rendered.wav".format(name)
        target = work / "{}.wav".format(name)
        _run(
            (
                str(sfizz_render),
                "--sfz",
                str(vsco_root / patches[name]),
                "--midi",
                str(midi_path),
                "--wav",
                str(rendered),
                "--samplerate",
                str(SAMPLE_RATE),
                "--quality",
                "10",
                "--use-eot",
            )
        )
        _run(
            (
                "ffmpeg",
                "-y",
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(rendered),
                "-af",
                "apad=whole_dur=45,atrim=duration=45,"
                "afade=t=in:st=0:d=2.5,afade=t=out:st=42:d=3",
                "-ar",
                str(SAMPLE_RATE),
                "-ac",
                "2",
                "-c:a",
                "pcm_s24le",
                str(target),
            )
        )
        if not target.is_file():
            raise RuntimeError("Stem renderer did not create {}".format(target))
        targets.append(target)
    return tuple(targets)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sfizz-render", required=True, type=Path)
    parser.add_argument("--vsco-root", required=True, type=Path)
    return parser


def _run(command: Iterable[str]) -> None:
    subprocess.run(tuple(command), check=True)


def main() -> None:
    args = build_argument_parser().parse_args()
    render_light_stems(
        args.output.expanduser().resolve(),
        args.sfizz_render.expanduser().resolve(),
        args.vsco_root.expanduser().resolve(),
    )


if __name__ == "__main__":
    main()
