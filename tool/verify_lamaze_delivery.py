#!/usr/bin/env python3
"""Verify generated Lamaze deliverables and write reproducibility records."""

import argparse
import hashlib
import json
import re
import subprocess
import wave
from datetime import datetime, timezone
from pathlib import Path

from generate_lamaze_audio import (
    BANNED_ANNOUNCEMENTS,
    FORBIDDEN_CLAIMS,
    SAMPLE_RATE,
    TRACKS,
    render_lrc,
)


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
            "stream=codec_type,codec_name,sample_rate,channels,bit_rate:format=duration,size",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(process.stdout)


def ffmpeg_audio_metrics(path: Path, runner=subprocess.run) -> dict:
    process = runner(
        [
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
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    summary = process.stderr.rpartition("Summary:")[2]
    loudness = re.search(r"I:\s*(-?\d+(?:\.\d+)?)\s*LUFS", summary)
    true_peak = re.search(r"Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS", summary)
    if loudness is None or true_peak is None:
        raise ValueError("FFmpeg did not report loudness and true peak")
    return {
        "integratedLufs": float(loudness.group(1)),
        "truePeakDbfs": float(true_peak.group(1)),
    }


def validate_text_delivery(spec, lrc: str, metadata: dict) -> None:
    if lrc != render_lrc(spec):
        raise ValueError("LRC must contain exactly the audible guidance cues")
    if any(value in lrc for value in FORBIDDEN_CLAIMS + BANNED_ANNOUNCEMENTS):
        raise ValueError("LRC contains forbidden guidance copy")
    if (
        metadata.get("id") != spec.track_id
        or metadata.get("title") != spec.title
        or metadata.get("bpm") != spec.bpm
        or metadata.get("durationSeconds") != spec.duration_seconds
        or metadata.get("guidanceStyle") != "spoken-direct-actions"
    ):
        raise ValueError("Track metadata does not match the approved specification")
    expected_cues = [
        {
            "atSeconds": cue.at_seconds,
            "text": cue.text,
            "style": "spoken",
        }
        for cue in spec.cues
    ]
    if metadata.get("cues") != expected_cues:
        raise ValueError("Metadata cues must match the spoken LRC cues")
    sources = metadata.get("soundFontSources")
    if (
        not isinstance(sources, dict)
        or sources.get("license") != "MIT"
        or not str(sources.get("version", "")).strip()
    ):
        raise ValueError("SoundFont license or version metadata is missing")
    resources = sources.get("resources")
    if not isinstance(resources, dict):
        raise ValueError("SoundFont source hashes are missing")
    for filename in (
        "MuseScore_General.sf3",
        "MuseScore_General_License.md",
        "VERSION",
    ):
        record = resources.get(filename)
        digest = record.get("sha256") if isinstance(record, dict) else None
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError("SoundFont source hash is missing: {}".format(filename))


def validate_audio_delivery(spec, wav_info: dict, mp3_probe: dict, metrics: dict) -> None:
    if (
        wav_info.get("sampleRate") != SAMPLE_RATE
        or wav_info.get("channels") != 2
        or abs(float(wav_info.get("duration", 0)) - spec.duration_seconds) > 0.01
    ):
        raise ValueError("{} WAV must be exact 48 kHz stereo".format(spec.slug))
    streams = mp3_probe.get("streams")
    audio_stream = next(
        (
            stream
            for stream in streams if stream.get("codec_type", "audio") == "audio"
        ),
        None,
    ) if isinstance(streams, list) else None
    if (
        not isinstance(audio_stream, dict)
        or audio_stream.get("codec_name") not in (None, "mp3")
        or int(audio_stream.get("sample_rate", 0)) != SAMPLE_RATE
        or int(audio_stream.get("channels", 0)) != 2
        or int(audio_stream.get("bit_rate", 0)) != 192_000
    ):
        raise ValueError("{} MP3 must be 192 kbps 48 kHz stereo".format(spec.slug))
    duration = float(mp3_probe.get("format", {}).get("duration", 0))
    if abs(duration - spec.duration_seconds) > 0.1:
        raise ValueError("Unexpected MP3 duration for {}".format(spec.slug))
    true_peak = float(metrics.get("truePeakDbfs", 0))
    if true_peak > -1.5:
        raise ValueError("{} true peak exceeds -1.5 dBFS".format(spec.slug))


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
            wav_info = {
                "sampleRate": wav_file.getframerate(),
                "channels": wav_file.getnchannels(),
                "duration": wav_file.getnframes() / wav_file.getframerate(),
            }

        probe = ffprobe_audio(paths["mp3"])
        metrics = ffmpeg_audio_metrics(paths["wav"])

        lrc = paths["lrc"].read_text(encoding="utf-8")
        metadata = json.loads(paths["json"].read_text(encoding="utf-8"))
        validate_text_delivery(spec, lrc, metadata)
        validate_audio_delivery(spec, wav_info, probe, metrics)
        stream = probe["streams"][0]

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
                "audioMetrics": metrics,
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
