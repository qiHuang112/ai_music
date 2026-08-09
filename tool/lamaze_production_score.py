#!/usr/bin/env python3
"""Render sparse production-length Lamaze music with CC0 VSCO samples."""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable

from lamaze_score import MidiNote, StemScore, write_midi


SAMPLE_RATE = 48_000
PATCHES = {
    "piano": "UprightPiano.sfz",
    "violin": "ViolinEnsSusVib-Quiet.sfz",
    "cello": "CelloEnsSusVib-Quiet.sfz",
}


@dataclass(frozen=True)
class Arrangement:
    span_beats: float
    response_beat: float
    velocity_contour: tuple[int, ...]


ARRANGEMENTS = {
    "lamaze-slow-relax": Arrangement(8.0, 3.4, (38, 36, 40, 37)),
    "lamaze-contraction-wave": Arrangement(8.0, 3.6, (34, 38, 42, 38, 34, 36)),
    "lamaze-defer-pushing": Arrangement(6.0, 2.6, (36, 39, 37, 35)),
    "lamaze-follow-care-team": Arrangement(12.0, 5.2, (33, 35, 34, 32)),
}


PROGRESSIONS = {
    "lamaze-slow-relax": (
        (48, 52, 55),
        (45, 48, 52),
        (41, 45, 48),
        (43, 47, 50),
    ),
    "lamaze-contraction-wave": (
        (48, 52, 55),
        (50, 53, 57),
        (46, 50, 53),
        (41, 45, 48),
    ),
    "lamaze-defer-pushing": (
        (45, 48, 52),
        (41, 45, 48),
        (48, 52, 55),
        (43, 47, 50),
    ),
    "lamaze-follow-care-team": (
        (48, 52, 55),
        (45, 48, 52),
        (41, 45, 48),
        (43, 47, 50),
    ),
}


def build_production_scores(track) -> Dict[str, StemScore]:
    """Build a quiet, sparse piano/violin/cello arrangement for one track."""

    try:
        arrangement = ARRANGEMENTS[track.track_id]
        progression = PROGRESSIONS[track.track_id]
    except KeyError as error:
        raise ValueError("Unknown Lamaze track: {}".format(track.track_id)) from error

    total_beats = track.duration_seconds * track.bpm / 60
    if total_beats != round(total_beats):
        raise ValueError("Track duration must contain a whole number of beats")
    total_beats = float(round(total_beats))

    piano = []
    violin = []
    cello = []
    span_index = 0
    start = 0.0
    while start < total_beats:
        chord = progression[span_index % len(progression)]
        base_velocity = arrangement.velocity_contour[
            span_index % len(arrangement.velocity_contour)
        ]
        chord_duration = min(
            arrangement.span_beats - 0.7,
            total_beats - start,
        )
        voicing = (chord[0], chord[2], chord[1] + 12)
        for offset, pitch in enumerate(voicing):
            piano.append(
                MidiNote(
                    start_beat=start,
                    duration_beats=chord_duration,
                    pitch=pitch,
                    velocity=base_velocity - offset * 2,
                )
            )

        response_start = start + arrangement.response_beat
        if response_start < total_beats:
            piano.append(
                MidiNote(
                    start_beat=response_start,
                    duration_beats=min(2.1, total_beats - response_start),
                    pitch=chord[2] + 12,
                    velocity=min(52, base_velocity + 7),
                )
            )

        sustain = min(arrangement.span_beats + 0.35, total_beats - start)
        violin_velocity = max(24, base_velocity - 10)
        for pitch in (chord[1] + 12, chord[2] + 12):
            violin.append(
                MidiNote(start, sustain, pitch, violin_velocity)
            )
        cello.append(
            MidiNote(start, sustain, chord[0], max(26, base_velocity - 7))
        )

        start += arrangement.span_beats
        span_index += 1

    return {
        "piano": StemScore("piano", 0, tuple(piano)),
        "violin": StemScore("violin", 48, tuple(violin)),
        "cello": StemScore("cello", 48, tuple(cello)),
    }


def render_production_stems(
    track,
    work: Path,
    sfizz_render: Path,
    vsco_root: Path,
) -> tuple[Path, Path, Path]:
    """Render one track's three stems through the pinned VSCO SFZ patches."""

    if not sfizz_render.is_file():
        raise FileNotFoundError("sfizz_render does not exist: {}".format(sfizz_render))
    if shutil.which("ffmpeg") is None:
        raise RuntimeError("Missing required tool: ffmpeg")
    for patch_name in PATCHES.values():
        if not (vsco_root / patch_name).is_file():
            raise FileNotFoundError(
                "VSCO patch does not exist: {}".format(patch_name)
            )

    work.mkdir(parents=True, exist_ok=True)
    scores = build_production_scores(track)
    targets = []
    fade_out_start = max(0.0, track.duration_seconds - 3.0)
    for name in ("piano", "violin", "cello"):
        midi_path = write_midi(track, scores[name], work / "{}.mid".format(name))
        rendered = work / "{}-rendered.wav".format(name)
        target = work / "{}.wav".format(name)
        _run(
            (
                str(sfizz_render),
                "--sfz",
                str(vsco_root / PATCHES[name]),
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
                "apad=whole_dur={duration},atrim=duration={duration},"
                "afade=t=in:st=0:d=2.5,afade=t=out:st={fade}:d=3".format(
                    duration=track.duration_seconds,
                    fade=fade_out_start,
                ),
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


def _run(command: Iterable[str]) -> None:
    subprocess.run(tuple(command), check=True)
