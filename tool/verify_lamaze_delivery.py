#!/usr/bin/env python3
"""Verify generated Lamaze deliverables and write reproducibility records."""

import argparse
import hashlib
import json
import subprocess
import wave
from datetime import datetime, timezone
from pathlib import Path

from generate_lamaze_audio import FORBIDDEN_CLAIMS, SAMPLE_RATE, TRACKS


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ffprobe_audio(path: Path) -> dict:
    process = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "a:0",
            "-show_entries",
            "stream=codec_name,sample_rate,channels,bit_rate:format=duration,size",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(process.stdout)


def verify(root: Path) -> dict:
    tracks = []
    for spec in TRACKS:
        paths = {
            extension: root / "{}.{}".format(spec.slug, extension)
            for extension in ("wav", "mp3", "lrc", "txt", "json", "png")
        }
        missing = [str(path) for path in paths.values() if not path.is_file()]
        if missing:
            raise ValueError("Missing deliverables: {}".format(", ".join(missing)))

        with wave.open(str(paths["wav"]), "rb") as wav_file:
            if wav_file.getframerate() != SAMPLE_RATE or wav_file.getnchannels() != 2:
                raise ValueError("{} must be 48 kHz stereo".format(paths["wav"]))
            duration = wav_file.getnframes() / wav_file.getframerate()
            if abs(duration - spec.duration_seconds) > 0.01:
                raise ValueError("Unexpected WAV duration for {}".format(spec.slug))

        probe = ffprobe_audio(paths["mp3"])
        stream = probe["streams"][0]
        if int(stream["sample_rate"]) != SAMPLE_RATE or int(stream["channels"]) != 2:
            raise ValueError("{} must be 48 kHz stereo".format(paths["mp3"]))
        if int(stream["bit_rate"]) != 192_000:
            raise ValueError("{} must be 192 kbps".format(paths["mp3"]))
        if abs(float(probe["format"]["duration"]) - spec.duration_seconds) > 0.1:
            raise ValueError("Unexpected MP3 duration for {}".format(spec.slug))

        lrc = paths["lrc"].read_text(encoding="utf-8")
        if "医护" not in lrc or "自然呼吸" not in lrc:
            raise ValueError("Safety guidance missing from {}".format(paths["lrc"]))
        if any(claim in lrc for claim in FORBIDDEN_CLAIMS):
            raise ValueError("Forbidden claim in {}".format(paths["lrc"]))
        metadata = json.loads(paths["json"].read_text(encoding="utf-8"))
        if metadata.get("id") != spec.track_id or metadata.get("bpm") != spec.bpm:
            raise ValueError("Metadata mismatch for {}".format(spec.slug))

        tracks.append(
            {
                "id": spec.track_id,
                "slug": spec.slug,
                "durationSeconds": spec.duration_seconds,
                "bpm": spec.bpm,
                "wav": {
                    "sizeBytes": paths["wav"].stat().st_size,
                    "sha256": sha256_file(paths["wav"]),
                },
                "mp3": {
                    "sizeBytes": paths["mp3"].stat().st_size,
                    "sha256": sha256_file(paths["mp3"]),
                    "sampleRate": int(stream["sample_rate"]),
                    "bitRate": int(stream["bit_rate"]),
                },
            }
        )

    return {
        "verifiedAt": datetime.now(timezone.utc).isoformat(),
        "status": "passed",
        "trackCount": len(tracks),
        "tracks": tracks,
    }


def write_records(root: Path, report: dict) -> None:
    report_path = root / "verification-report.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    excluded = {"SHA256SUMS.txt", report_path.name}
    files = sorted(path for path in root.iterdir() if path.is_file() and path.name not in excluded)
    checksums = ["{}  {}".format(sha256_file(path), path.name) for path in files]
    (root / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify Lamaze delivery files")
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    report = verify(root)
    write_records(root, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
