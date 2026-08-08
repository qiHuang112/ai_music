#!/usr/bin/env python3
"""Mix CosyVoice cues with the approved sampled Lamaze light-music bed."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path
from typing import Iterable, Sequence

from lamaze_preview_spec import PREVIEW_CUES, PREVIEW_SECONDS


SAMPLE_RATE = 48_000


def mix_preview(
    stems: Sequence[Path],
    cues: Sequence[Path],
    target: Path,
) -> None:
    if len(stems) != 3:
        raise ValueError("Preview requires exactly three music stems")
    if len(cues) != 3:
        raise ValueError("Preview requires exactly three voice cues")

    target.parent.mkdir(parents=True, exist_ok=True)
    command = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    for source in (*stems, *cues):
        command.extend(("-i", str(source)))

    filters = [
        "[0:a]aresample=48000,volume=0.48[piano]",
        "[1:a]aresample=48000,volume=0.16[violin]",
        "[2:a]aresample=48000,volume=0.12[cello]",
        "[piano][violin][cello]amix=inputs=3:duration=longest:normalize=0[bed]",
    ]
    voice_labels = []
    for input_index, cue in enumerate(PREVIEW_CUES, start=3):
        label = "voice{}".format(input_index - 3)
        delay = round(cue.at_seconds * 1000)
        filters.append(
            "[{}:a]aresample=48000,highpass=f=70,lowpass=f=12000,"
            "acompressor=threshold=-22dB:ratio=2:attack=25:release=180:makeup=2dB,"
            "adelay={}:all=1[{}]".format(input_index, delay, label)
        )
        voice_labels.append("[{}]".format(label))
    filters.extend(
        (
            "{}amix=inputs=3:duration=longest:normalize=0[voicebus]".format(
                "".join(voice_labels)
            ),
            "[voicebus]apad=whole_dur=45,atrim=duration=45,"
            "asplit=2[voicekey][voicemix]",
            "[bed][voicekey]sidechaincompress=threshold=0.02:ratio=4:"
            "attack=200:release=900[ducked]",
            "[ducked][voicemix]amix=inputs=2:duration=first:normalize=0,"
            "loudnorm=I=-18:TP=-1.5:LRA=8,alimiter=limit=0.8414[out]",
        )
    )
    command.extend(
        (
            "-filter_complex",
            ";".join(filters),
            "-map",
            "[out]",
            "-t",
            str(PREVIEW_SECONDS),
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "2",
            "-c:a",
            "pcm_s24le",
            str(target),
        )
    )
    _run(command)


def encode_preview_mp3(wav: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    _run(
        (
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(wav),
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "2",
            str(target),
        )
    )


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stems", required=True, type=Path)
    parser.add_argument("--cues", required=True, type=Path)
    parser.add_argument("--output-prefix", required=True, type=Path)
    return parser


def _run(command: Iterable[str]) -> None:
    subprocess.run(tuple(command), check=True)


def main() -> None:
    args = build_argument_parser().parse_args()
    stems_dir = args.stems.expanduser().resolve()
    cues_dir = args.cues.expanduser().resolve()
    prefix = args.output_prefix.expanduser().resolve()
    stems = tuple(stems_dir / "{}.wav".format(name) for name in ("piano", "violin", "cello"))
    cues = tuple(cues_dir / "cue-{:02d}.wav".format(index) for index in range(3))
    for source in (*stems, *cues):
        if not source.is_file():
            raise SystemExit("Preview source does not exist: {}".format(source))
    wav = prefix.with_suffix(".wav")
    mp3 = prefix.with_suffix(".mp3")
    mix_preview(stems, cues, wav)
    encode_preview_mp3(wav, mp3)


if __name__ == "__main__":
    main()
