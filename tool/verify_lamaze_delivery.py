#!/usr/bin/env python3
"""Verify CosyVoice/VSCO Lamaze deliverables and write reproducibility records."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from generate_lamaze_audio import (
    BANNED_ANNOUNCEMENTS,
    COSYVOICE_COMMIT,
    FORBIDDEN_CLAIMS,
    REQUIRED_PATCHES,
    SAMPLE_RATE,
    SFT_REVISION,
    TRACKS,
    VSCO_COMMIT,
    render_lrc,
    render_readme,
    render_txt,
)


EXPECTED_INSTRUMENTS = [
    "VSCO Upright Piano",
    "VSCO Quiet Violin Ensemble",
    "VSCO Quiet Cello Ensemble",
]
MIN_INTEGRATED_LUFS = -20.0
MAX_INTEGRATED_LUFS = -16.0


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
            "-show_entries",
            "stream=codec_type,codec_name,sample_rate,channels,bit_rate,"
            "bits_per_sample,bits_per_raw_sample,duration:format=duration,size,bit_rate",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
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
        encoding="utf-8",
        errors="replace",
    )
    summary = process.stderr.rpartition("Summary:")[2]
    loudness = re.search(r"I:\s*(-?\d+(?:\.\d+)?)\s*LUFS", summary)
    true_peak = re.search(r"Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS", summary)
    if loudness is None or true_peak is None:
        raise ValueError("FFmpeg did not report loudness and true peak")
    return {
        "integratedLufs": float(loudness.group(1)),
        "truePeakDbtp": float(true_peak.group(1)),
    }


def normalize_wav_probe(probe: dict) -> dict:
    stream = _single_audio_stream(probe)
    file_format = probe.get("format", {})
    bit_depth = stream.get("bits_per_raw_sample") or stream.get("bits_per_sample")
    return {
        "codec": stream.get("codec_name"),
        "sampleRate": _required_int(stream.get("sample_rate"), "WAV sample rate"),
        "channels": _required_int(stream.get("channels"), "WAV channel count"),
        "bitDepth": _required_int(bit_depth, "WAV bit depth"),
        "duration": float(stream.get("duration") or file_format.get("duration") or 0),
    }


def validate_text_delivery(spec, lrc: str, txt: str, metadata: dict) -> None:
    if lrc != render_lrc(spec):
        raise ValueError("LRC must contain exactly the audible guidance cues")
    if txt != render_txt(spec):
        raise ValueError("TXT must contain the exact safety guidance and spoken cues")
    if any(value in lrc for value in FORBIDDEN_CLAIMS + BANNED_ANNOUNCEMENTS):
        raise ValueError("LRC contains forbidden guidance copy")
    if "soundFontSources" in metadata:
        raise ValueError("Legacy SoundFont metadata is not allowed")
    if (
        metadata.get("id") != spec.track_id
        or metadata.get("title") != spec.title
        or metadata.get("bpm") != spec.bpm
        or metadata.get("durationSeconds") != spec.duration_seconds
        or metadata.get("voice") != "CosyVoice SFT 中文女"
        or metadata.get("voiceSpeed") != 0.92
        or metadata.get("guidanceStyle") != "spoken-direct-actions"
        or metadata.get("instruments") != EXPECTED_INSTRUMENTS
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
    usage = str(metadata.get("usage", ""))
    if "现场医生和助产士指令始终优先" not in usage:
        raise ValueError("Clinical priority metadata is missing")
    if spec.slug == "03-暂缓用力" and "明确要求暂缓用力" not in usage:
        raise ValueError("Defer-pushing conditional usage metadata is missing")
    _validate_audio_sources(metadata.get("audioSources"))


def _validate_audio_sources(sources) -> None:
    if not isinstance(sources, dict):
        raise ValueError("Audio source metadata is missing")
    voice_engine = sources.get("voiceEngine")
    voice_model = sources.get("voiceModel")
    library = sources.get("sampleLibrary")
    sampler = sources.get("sampler")
    expected = (
        (voice_engine, "name", "CosyVoice"),
        (voice_engine, "commit", COSYVOICE_COMMIT),
        (voice_engine, "license", "Apache-2.0"),
        (voice_model, "repo", "FunAudioLLM/CosyVoice-300M-SFT"),
        (voice_model, "revision", SFT_REVISION),
        (voice_model, "license", "Apache-2.0"),
        (voice_model, "speaker", "中文女"),
        (voice_model, "speed", 0.92),
        (library, "name", "VSCO 2 CE"),
        (library, "commit", VSCO_COMMIT),
        (library, "license", "CC0-1.0"),
        (sampler, "name", "sfizz"),
        (sampler, "version", "1.2.3"),
        (sampler, "license", "BSD-2-Clause"),
    )
    for record, key, value in expected:
        if not isinstance(record, dict) or record.get(key) != value:
            raise ValueError("Audio source pin is invalid: {}".format(key))
    patch_hashes = library.get("patchHashes")
    if not isinstance(patch_hashes, dict):
        raise ValueError("VSCO patch hashes are missing")
    for patch_name in REQUIRED_PATCHES:
        if not _is_sha256(patch_hashes.get(patch_name)):
            raise ValueError("VSCO patch hash is invalid: {}".format(patch_name))
    if not _is_sha256(sampler.get("archiveSha256")):
        raise ValueError("sfizz archive hash is invalid")


def validate_audio_delivery(spec, wav_info: dict, mp3_probe: dict, metrics: dict) -> None:
    if (
        wav_info.get("codec") != "pcm_s24le"
        or wav_info.get("sampleRate") != SAMPLE_RATE
        or wav_info.get("channels") != 2
        or wav_info.get("bitDepth") != 24
        or abs(float(wav_info.get("duration", 0)) - spec.duration_seconds) > 0.1
    ):
        raise ValueError("{} WAV must be exact 48 kHz 24-bit stereo".format(spec.slug))
    audio_stream = _single_audio_stream(mp3_probe)
    bit_rate = _required_int(
        audio_stream.get("bit_rate") or mp3_probe.get("format", {}).get("bit_rate"),
        "MP3 bit rate",
    )
    if (
        audio_stream.get("codec_name") != "mp3"
        or _required_int(audio_stream.get("sample_rate"), "MP3 sample rate")
        != SAMPLE_RATE
        or _required_int(audio_stream.get("channels"), "MP3 channel count") != 2
        or abs(bit_rate - 192_000) > 9_600
    ):
        raise ValueError("{} MP3 must be 192 kbps 48 kHz stereo".format(spec.slug))
    duration = float(
        audio_stream.get("duration")
        or mp3_probe.get("format", {}).get("duration")
        or 0
    )
    if abs(duration - spec.duration_seconds) > 0.1:
        raise ValueError("Unexpected MP3 duration for {}".format(spec.slug))
    true_peak = float(metrics.get("truePeakDbtp", 0))
    if true_peak > -1.5:
        raise ValueError("{} true peak exceeds -1.5 dBTP".format(spec.slug))
    integrated_lufs = float(metrics.get("integratedLufs", 0))
    if not MIN_INTEGRATED_LUFS <= integrated_lufs <= MAX_INTEGRATED_LUFS:
        raise ValueError(
            "{} integrated loudness must stay between {} and {} LUFS".format(
                spec.slug,
                MIN_INTEGRATED_LUFS,
                MAX_INTEGRATED_LUFS,
            )
        )


def validate_shared_delivery(root: Path) -> None:
    readme = root / "README.txt"
    shared_cover = root / "cover.png"
    if not readme.is_file() or not shared_cover.is_file():
        raise ValueError("README.txt and cover.png are required")
    if readme.read_text(encoding="utf-8") != render_readme():
        raise ValueError("README.txt does not match the approved safety guidance")
    cover_bytes = shared_cover.read_bytes()
    if not cover_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Shared cover must be a PNG file")
    cover_hash = sha256_file(shared_cover)
    for spec in TRACKS:
        track_cover = root / "{}.png".format(spec.slug)
        if not track_cover.is_file() or sha256_file(track_cover) != cover_hash:
            raise ValueError("Track cover must match shared cover: {}".format(spec.slug))


def verify(root: Path) -> dict:
    validate_shared_delivery(root)
    tracks = []
    for spec in TRACKS:
        paths = {
            extension: root / "{}.{}".format(spec.slug, extension)
            for extension in ("wav", "mp3", "lrc", "txt", "json", "png")
        }
        missing = [str(path) for path in paths.values() if not path.is_file()]
        if missing:
            raise ValueError("Missing deliverables: {}".format(", ".join(missing)))

        wav_probe = ffprobe_audio(paths["wav"])
        wav_info = normalize_wav_probe(wav_probe)
        mp3_probe = ffprobe_audio(paths["mp3"])
        metrics = ffmpeg_audio_metrics(paths["wav"])
        lrc = paths["lrc"].read_text(encoding="utf-8")
        txt = paths["txt"].read_text(encoding="utf-8")
        metadata = json.loads(paths["json"].read_text(encoding="utf-8"))
        validate_text_delivery(spec, lrc, txt, metadata)
        validate_audio_delivery(spec, wav_info, mp3_probe, metrics)
        mp3_stream = _single_audio_stream(mp3_probe)

        tracks.append(
            {
                "id": spec.track_id,
                "slug": spec.slug,
                "durationSeconds": spec.duration_seconds,
                "bpm": spec.bpm,
                "wav": {
                    "sizeBytes": paths["wav"].stat().st_size,
                    "sha256": sha256_file(paths["wav"]),
                    "sampleRate": wav_info["sampleRate"],
                    "bitDepth": wav_info["bitDepth"],
                },
                "mp3": {
                    "sizeBytes": paths["mp3"].stat().st_size,
                    "sha256": sha256_file(paths["mp3"]),
                    "sampleRate": int(mp3_stream["sample_rate"]),
                    "bitRate": int(
                        mp3_stream.get("bit_rate")
                        or mp3_probe.get("format", {}).get("bit_rate")
                    ),
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
    _write_utf8_lf(
        report_path,
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
    )
    excluded = {"SHA256SUMS.txt", report_path.name}
    files = sorted(
        path for path in root.iterdir() if path.is_file() and path.name not in excluded
    )
    checksums = ["{}  {}".format(sha256_file(path), path.name) for path in files]
    _write_utf8_lf(root / "SHA256SUMS.txt", "\n".join(checksums) + "\n")


def _write_utf8_lf(path: Path, value: str) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as target:
        target.write(value)


def _single_audio_stream(probe: dict) -> dict:
    streams = [
        stream
        for stream in probe.get("streams", [])
        if stream.get("codec_type") == "audio"
    ]
    if len(streams) != 1:
        raise ValueError("Expected exactly one audio stream")
    return streams[0]


def _required_int(value, label: str) -> int:
    if value in (None, "", "N/A"):
        raise ValueError("{} is missing".format(label))
    return int(value)


def _is_sha256(value) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    report = verify(root)
    write_records(root, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
