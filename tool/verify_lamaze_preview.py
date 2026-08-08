#!/usr/bin/env python3
"""Verify Lamaze preview containers, levels, cue audibility, and hashes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Iterable


EXPECTED_SECONDS = 45.0
EXPECTED_SAMPLE_RATE = 48_000
EXPECTED_MP3_BITRATE = 192_000


def probe_audio(path: Path) -> dict:
    decoded = json.loads(
        _capture(
            (
                "ffprobe",
                "-v",
                "error",
                "-show_streams",
                "-show_format",
                "-of",
                "json",
                str(path),
            )
        )
    )
    streams = [stream for stream in decoded.get("streams", []) if stream.get("codec_type") == "audio"]
    if len(streams) != 1:
        raise ValueError("Expected exactly one audio stream: {}".format(path))
    stream = streams[0]
    file_format = decoded.get("format", {})
    bit_depth = stream.get("bits_per_raw_sample") or stream.get("bits_per_sample")
    return {
        "duration": float(stream.get("duration") or file_format["duration"]),
        "codec": stream["codec_name"],
        "sampleRate": int(stream["sample_rate"]),
        "channels": int(stream["channels"]),
        "bitRate": _optional_int(stream.get("bit_rate") or file_format.get("bit_rate")),
        "bitDepth": _optional_int(bit_depth),
    }


def measure_master(path: Path) -> dict:
    output = _capture(
        (
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-filter_complex",
            "ebur128=peak=true",
            "-f",
            "null",
            "-",
        )
    )
    loudness = re.findall(r"I:\s+(-?\d+(?:\.\d+)?)\s+LUFS", output)
    peaks = re.findall(r"Peak:\s+(-?\d+(?:\.\d+)?)\s+dBFS", output)
    if not loudness or not peaks:
        raise ValueError("Unable to parse FFmpeg ebur128 output")
    return {
        "integratedLufs": float(loudness[-1]),
        "truePeakDbtp": float(peaks[-1]),
    }


def measure_mean_volume(path: Path) -> float:
    output = _capture(
        (
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-af",
            "volumedetect",
            "-f",
            "null",
            "-",
        )
    )
    values = re.findall(r"mean_volume:\s+(-?\d+(?:\.\d+)?)\s+dB", output)
    if not values:
        raise ValueError("Unable to parse FFmpeg mean volume")
    return float(values[-1])


def verify_preview(wav: Path, mp3: Path, cue_dir: Path) -> dict:
    for source in (wav, mp3):
        if not source.is_file():
            raise FileNotFoundError(source)
    wav_info = probe_audio(wav)
    mp3_info = probe_audio(mp3)
    _verify_duration(wav_info["duration"], "WAV")
    _verify_duration(mp3_info["duration"], "MP3")
    if (
        wav_info["codec"] != "pcm_s24le"
        or wav_info["sampleRate"] != EXPECTED_SAMPLE_RATE
        or wav_info["channels"] != 2
        or wav_info["bitDepth"] != 24
    ):
        raise ValueError("WAV must be 48 kHz, 24-bit, stereo PCM")
    if (
        mp3_info["codec"] != "mp3"
        or mp3_info["sampleRate"] != EXPECTED_SAMPLE_RATE
        or mp3_info["channels"] != 2
        or mp3_info["bitRate"] is None
        or abs(mp3_info["bitRate"] - EXPECTED_MP3_BITRATE) > EXPECTED_MP3_BITRATE * 0.05
    ):
        raise ValueError("MP3 must be 48 kHz, 192 kbps, stereo")

    master = measure_master(wav)
    if master["truePeakDbtp"] > -1.5:
        raise ValueError("Preview true peak exceeds -1.5 dBTP")

    cue_reports = []
    for index in range(3):
        cue = cue_dir / "cue-{:02d}.wav".format(index)
        if not cue.is_file():
            raise FileNotFoundError(cue)
        info = probe_audio(cue)
        if info["duration"] <= 0.5:
            raise ValueError("Invalid cue duration: {}".format(cue))
        mean_volume = measure_mean_volume(cue)
        if mean_volume < -45:
            raise ValueError("Invalid cue mean volume: {}".format(cue))
        cue_reports.append(
            {
                **info,
                "file": cue.name,
                "meanVolumeDb": mean_volume,
                "sha256": _sha256(cue),
            }
        )

    return {
        "wav": {**wav_info, "file": wav.name, "sha256": _sha256(wav)},
        "mp3": {**mp3_info, "file": mp3.name, "sha256": _sha256(mp3)},
        "master": master,
        "cues": cue_reports,
    }


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wav", required=True, type=Path)
    parser.add_argument("--mp3", required=True, type=Path)
    parser.add_argument("--cues", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    return parser


def _verify_duration(duration: float, label: str) -> None:
    if abs(duration - EXPECTED_SECONDS) > 0.1:
        raise ValueError("{} duration must be 45.0 ± 0.1 seconds".format(label))


def _optional_int(value) -> int | None:
    if value in (None, "", "N/A"):
        return None
    return int(value)


def _capture(command: Iterable[str]) -> str:
    completed = subprocess.run(
        tuple(command),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return completed.stdout


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    args = build_argument_parser().parse_args()
    report = verify_preview(
        args.wav.expanduser().resolve(),
        args.mp3.expanduser().resolve(),
        args.cues.expanduser().resolve(),
    )
    report_path = args.report.expanduser().resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
