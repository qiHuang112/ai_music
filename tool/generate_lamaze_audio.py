#!/usr/bin/env python3
"""Generate four original Mandarin Lamaze companion tracks on macOS.

The spoken guidance is rendered with the local Tingting voice. The original
loopable ambient bed is synthesized with NumPy, then mixed and encoded by
FFmpeg. This generator is intentionally separate from the LAN server.
"""

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np


SAMPLE_RATE = 48_000
ARTIST = "AI Home"
ALBUM = "拉玛泽呼吸引导"
VOICE = "Tingting"
FORBIDDEN_CLAIMS = ("宫口", "厘米", "无痛", "顺产", "保证")


@dataclass(frozen=True)
class Cue:
    at_seconds: float
    text: str
    style: str = "spoken"


@dataclass(frozen=True)
class TrackSpec:
    track_id: str
    slug: str
    title: str
    duration_seconds: int
    bpm: int
    cues: Sequence[Cue]


SAFETY_OPENING = (
    Cue(0, "这是一段呼吸陪伴。现场医生和助产士的指令始终优先。"),
    Cue(
        11,
        "若感到头晕、手脚发麻或任何不适，请停止练习，恢复自然呼吸，并告诉医护人员。",
    ),
)


TRACKS = (
    TrackSpec(
        track_id="lamaze-slow-relax",
        slug="01-慢呼放松",
        title="慢呼放松",
        duration_seconds=300,
        bpm=60,
        cues=SAFETY_OPENING
        + (
            Cue(32, "把注意力带回此刻。让肩膀松下来，让下巴和双手也松下来。"),
            Cue(54, "用鼻子轻轻吸气，再从嘴边缓缓呼气。保持顺畅，不需要屏气。"),
            Cue(78, "慢慢吸气，柔柔呼气。", "chant"),
            Cue(102, "每一次呼气，都允许身体多放松一点。只选择你觉得舒服的深度。"),
            Cue(127, "吸气时感受胸腹自然展开。呼气时让额头、嘴角和骨盆周围保持柔软。"),
            Cue(152, "呼吸流动，身体放松。", "chant"),
            Cue(176, "不必追求固定秒数。跟随自己的节奏，让每一次呼吸都轻松可持续。"),
            Cue(201, "如果宫缩来到，继续让呼吸流动；如果需要调整，请听从现场医护。"),
            Cue(226, "慢慢吸气，长长呼气。", "chant"),
            Cue(250, "把注意力放在这一口呼气上。松开肩膀，松开手指，松开不必要的紧张。"),
            Cue(276, "继续自然呼吸。你可以循环播放，也可以随时停下休息。"),
        ),
    ),
    TrackSpec(
        track_id="lamaze-contraction-wave",
        slug="02-宫缩浪潮",
        title="宫缩浪潮",
        duration_seconds=180,
        bpm=64,
        cues=SAFETY_OPENING
        + (
            Cue(31, "当你感觉宫缩像浪潮来到，把注意力放在持续流动的呼吸上。"),
            Cue(49, "轻轻吸气。缓缓呼气。不要和身体较劲，也不需要屏住呼吸。"),
            Cue(67, "浪潮升起，呼吸相伴。", "chant"),
            Cue(84, "在感觉更强的时候，可以让呼吸变得轻一点、快一点，但始终保持舒适。"),
            Cue(104, "如果感觉缓和，让呼气重新变长。肩膀、手掌和嘴边继续放松。"),
            Cue(124, "一口一口，跟着浪潮。", "chant"),
            Cue(142, "每次宫缩的应对方式可以不同。现场医护的观察和指令优先。"),
            Cue(163, "让呼吸回到自然，等待下一次需要时再继续。"),
        ),
    ),
    TrackSpec(
        track_id="lamaze-defer-pushing",
        slug="03-暂缓用力",
        title="暂缓用力",
        duration_seconds=120,
        bpm=72,
        cues=SAFETY_OPENING
        + (
            Cue(31, "这一段仅在医护人员明确要求暂缓用力时使用。指令一旦改变，请立刻跟随医护。"),
            Cue(49, "嘴唇轻轻张开，做短而轻的哈气。不要屏气，不要主动向下用力。"),
            Cue(65, "轻轻哈气，呼吸不停。", "chant"),
            Cue(80, "可以想象在轻轻吹动一片羽毛。每次哈气都短、轻、连续。"),
            Cue(97, "如果感觉头晕或发麻，马上停止，恢复自然呼吸，并告诉医护人员。"),
            Cue(111, "继续听从医护，让呼吸保持流动。"),
        ),
    ),
    TrackSpec(
        track_id="lamaze-follow-care-team",
        slug="04-跟随医护",
        title="跟随医护",
        duration_seconds=180,
        bpm=60,
        cues=SAFETY_OPENING
        + (
            Cue(31, "这首引导不会替现场医护下达用力口令。请把医护人员的实时指令放在第一位。"),
            Cue(51, "听清指令之前，让呼吸自然流动。放松肩膀、下巴和双手。"),
            Cue(70, "听见声音，跟随当下。", "chant"),
            Cue(88, "医护可能根据你和宝宝的情况调整节奏。只需要一次听清一个指令。"),
            Cue(108, "指令之间，回到自然呼吸。不要自行延长屏气，也不要勉强自己。"),
            Cue(128, "呼吸流动，安心跟随。", "chant"),
            Cue(146, "如果不确定，可以直接询问医生或助产士。现场沟通比音频更重要。"),
            Cue(165, "继续自然呼吸，等待并跟随下一条医护指令。"),
        ),
    ),
)


def validate_track_specs(tracks: Iterable[TrackSpec]) -> None:
    rows = tuple(tracks)
    if len(rows) != 4:
        raise ValueError("Exactly four tracks are required")
    ids = set()
    slugs = set()
    for track in rows:
        if track.track_id in ids or track.slug in slugs:
            raise ValueError("Track IDs and slugs must be unique")
        ids.add(track.track_id)
        slugs.add(track.slug)
        if track.duration_seconds <= 0 or track.bpm <= 0:
            raise ValueError("Duration and BPM must be positive")
        if not track.cues or track.cues[0].at_seconds != 0:
            raise ValueError("Every track must begin at zero")
        positions = [cue.at_seconds for cue in track.cues]
        if positions != sorted(positions) or positions[-1] >= track.duration_seconds:
            raise ValueError("Cue positions must be sorted and inside the track")
        lyrics = "\n".join(cue.text for cue in track.cues)
        if "医护" not in lyrics or "自然呼吸" not in lyrics:
            raise ValueError("Every track needs clinical priority and stop guidance")
        for claim in FORBIDDEN_CLAIMS:
            if claim in lyrics:
                raise ValueError("Forbidden claim in {}: {}".format(track.slug, claim))
        if any(cue.style not in {"spoken", "chant"} for cue in track.cues):
            raise ValueError("Unsupported cue style")


def render_lrc(track: TrackSpec) -> str:
    lines = [
        "[ar:{}]".format(ARTIST),
        "[al:{}]".format(ALBUM),
        "[ti:{}]".format(track.title),
        "[by:AI Home original production]",
    ]
    lines.extend("{}{}".format(_lrc_timestamp(cue.at_seconds), cue.text) for cue in track.cues)
    return "\n".join(lines) + "\n"


def render_txt(track: TrackSpec) -> str:
    heading = [
        track.title,
        "",
        "用途说明：呼吸陪伴工具，不替代医生或助产士的现场判断。现场医护指令始终优先。",
        "若头晕、手脚发麻或不适，请停止练习、恢复自然呼吸并告诉医护人员。",
        "",
        "引导词：",
    ]
    heading.extend(cue.text for cue in track.cues)
    return "\n".join(heading) + "\n"


def _lrc_timestamp(seconds: float) -> str:
    total_centiseconds = int(round(seconds * 100))
    minutes, remainder = divmod(total_centiseconds, 6000)
    whole_seconds, centiseconds = divmod(remainder, 100)
    return "[{:02d}:{:02d}.{:02d}]".format(minutes, whole_seconds, centiseconds)


def _run(command: Sequence[str]) -> None:
    subprocess.run(list(command), check=True)


def _require_tools() -> None:
    missing = [name for name in ("say", "ffmpeg", "ffprobe") if shutil.which(name) is None]
    if missing:
        raise RuntimeError("Missing required tools: {}".format(", ".join(missing)))


def _quantized_frequency(frequency: float, duration: int) -> float:
    return round(frequency * duration) / duration


def generate_backing(track: TrackSpec, target: Path) -> None:
    total_frames = track.duration_seconds * SAMPLE_RATE
    frames_per_chunk = SAMPLE_RATE
    beat_rate = track.bpm / 60.0
    total_beats = int(round(track.duration_seconds * beat_rate))
    if not math.isclose(total_beats, track.duration_seconds * beat_rate):
        raise ValueError("Track duration must contain a whole number of beats")

    roots = {
        60: (130.81, 164.81, 196.00, 261.63),
        64: (146.83, 174.61, 220.00, 293.66),
        72: (130.81, 174.61, 220.00, 261.63),
    }
    frequencies = tuple(
        _quantized_frequency(value, track.duration_seconds) for value in roots[track.bpm]
    )
    breath_cycles = max(1, round(track.duration_seconds / 8.0))
    breath_rate = breath_cycles / track.duration_seconds
    seed = int.from_bytes(
        hashlib.sha256(track.track_id.encode("utf-8")).digest()[:8], "big"
    )
    rng = np.random.default_rng(seed)
    shimmer_frequencies = tuple(
        _quantized_frequency(float(value), track.duration_seconds)
        for value in rng.uniform(0.07, 0.19, size=4)
    )

    with wave.open(str(target), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        for start in range(0, total_frames, frames_per_chunk):
            count = min(frames_per_chunk, total_frames - start)
            t = (np.arange(start, start + count, dtype=np.float64) / SAMPLE_RATE)
            breathing = 0.72 + 0.18 * np.sin(2 * np.pi * breath_rate * t - np.pi / 2)
            beat_phase = np.mod(t * beat_rate, 1.0)
            pulse = np.exp(-7.5 * beat_phase)
            beat_index = np.floor(t * beat_rate).astype(np.int64)
            note_index = (beat_index // 8) % len(frequencies)
            since_chime = np.mod(t, 8.0 / beat_rate)

            left = np.zeros(count, dtype=np.float64)
            right = np.zeros(count, dtype=np.float64)
            pad_weights = (0.33, 0.24, 0.19, 0.13)
            for index, (frequency, weight) in enumerate(zip(frequencies, pad_weights)):
                phase = 2 * np.pi * frequency * t
                shimmer = 1 + 0.05 * np.sin(2 * np.pi * shimmer_frequencies[index] * t)
                left += weight * shimmer * np.sin(phase + index * 0.17)
                right += weight * shimmer * np.sin(phase - index * 0.13)
                left += weight * 0.08 * np.sin(2 * phase + 0.4)
                right += weight * 0.08 * np.sin(2 * phase - 0.4)

            chime_frequency = np.take(np.asarray(frequencies) * 2.0, note_index)
            chime_envelope = np.exp(-2.8 * since_chime)
            chime = chime_envelope * np.sin(2 * np.pi * chime_frequency * t)
            low_pulse = pulse * np.sin(2 * np.pi * frequencies[0] * 0.5 * t)
            left = (left * breathing + 0.08 * chime + 0.035 * low_pulse) * 0.28
            right = (right * breathing + 0.08 * chime - 0.035 * low_pulse) * 0.28
            stereo = np.column_stack((left, right))
            pcm = np.clip(stereo, -0.98, 0.98)
            output.writeframes((pcm * 32767).astype("<i2").tobytes())


def _render_voice_cues(track: TrackSpec, work: Path) -> Sequence[Path]:
    paths = []
    for index, cue in enumerate(track.cues):
        target = work / "cue-{:02d}.aiff".format(index)
        _run(("say", "-v", VOICE, "-r", "152", "-o", str(target), cue.text))
        paths.append(target)
    return paths


def _mix_track(track: TrackSpec, backing: Path, cues: Sequence[Path], wav_target: Path) -> None:
    command = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(backing)]
    for cue_path in cues:
        command.extend(("-i", str(cue_path)))

    filters = ["[0:a]aresample=48000,volume=0.46[bed]"]
    voice_labels = []
    for index, cue in enumerate(track.cues, start=1):
        label = "voice{}".format(index)
        voice_filter = (
            "aresample=48000,highpass=f=95,lowpass=f=9500,"
            "acompressor=threshold=-22dB:ratio=2.5:attack=15:release=180,volume=1.35"
        )
        if cue.style == "chant":
            voice_filter += ",vibrato=f=4.2:d=0.10,aecho=0.8:0.35:55:0.12"
        delay = int(round(cue.at_seconds * 1000))
        filters.append("[{}:a]{},adelay={}:all=1[{}]".format(index, voice_filter, delay, label))
        voice_labels.append("[{}]".format(label))
    inputs = "[bed]" + "".join(voice_labels)
    filters.append(
        "{}amix=inputs={}:duration=first:normalize=0,"
        "loudnorm=I=-16:TP=-1.5:LRA=9,alimiter=limit=0.94[out]".format(
            inputs, 1 + len(voice_labels)
        )
    )
    command.extend(
        (
            "-filter_complex",
            ";".join(filters),
            "-map",
            "[out]",
            "-t",
            str(track.duration_seconds),
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "2",
            "-c:a",
            "pcm_s16le",
            str(wav_target),
        )
    )
    _run(command)


def _encode_mp3(track: TrackSpec, wav_source: Path, cover: Path, target: Path) -> None:
    _run(
        (
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(wav_source),
            "-i",
            str(cover),
            "-map",
            "0:a:0",
            "-map",
            "1:v:0",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "-ar",
            str(SAMPLE_RATE),
            "-c:v",
            "png",
            "-disposition:v:0",
            "attached_pic",
            "-metadata",
            "title={}".format(track.title),
            "-metadata",
            "artist={}".format(ARTIST),
            "-metadata",
            "album={}".format(ALBUM),
            str(target),
        )
    )


def _write_sidecars(track: TrackSpec, output: Path, cover: Path) -> None:
    stem = output / track.slug
    stem.with_suffix(".lrc").write_text(render_lrc(track), encoding="utf-8")
    stem.with_suffix(".txt").write_text(render_txt(track), encoding="utf-8")
    metadata = {
        "id": track.track_id,
        "title": track.title,
        "artist": ARTIST,
        "album": ALBUM,
        "durationSeconds": track.duration_seconds,
        "bpm": track.bpm,
        "language": "zh-CN",
        "voice": VOICE,
        "usage": "呼吸陪伴工具；现场医生和助产士指令始终优先。",
        "license": "Original production for this project",
    }
    stem.with_suffix(".json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    shutil.copy2(cover, stem.with_suffix(".png"))


def generate(output: Path, cover_source: Path) -> None:
    validate_track_specs(TRACKS)
    _require_tools()
    output.mkdir(parents=True, exist_ok=True)
    common_cover = output / "cover.png"
    if cover_source != common_cover.resolve():
        shutil.copy2(cover_source, common_cover)
    readme = output / "README.txt"
    readme.write_text(
        "拉玛泽呼吸引导（原创）\n\n"
        "本套音频用于呼吸陪伴，不替代医生或助产士的现场判断。\n"
        "现场医护指令始终优先。若头晕、手脚发麻或不适，请停止练习、恢复自然呼吸并告诉医护人员。\n"
        "03-暂缓用力仅在医护人员明确要求暂缓用力时使用。\n",
        encoding="utf-8",
    )

    for track in TRACKS:
        print("Generating {} ({}s, {} BPM)".format(track.slug, track.duration_seconds, track.bpm))
        with tempfile.TemporaryDirectory(prefix="lamaze-audio-") as temp_dir:
            work = Path(temp_dir)
            backing = work / "backing.wav"
            generate_backing(track, backing)
            voice_cues = _render_voice_cues(track, work)
            wav_target = output / "{}.wav".format(track.slug)
            mp3_target = output / "{}.mp3".format(track.slug)
            _mix_track(track, backing, voice_cues, wav_target)
            _encode_mp3(track, wav_target, common_cover, mp3_target)
            _write_sidecars(track, output, common_cover)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate original Lamaze guide audio")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cover", required=True, type=Path)
    args = parser.parse_args()
    if not args.cover.is_file():
        raise SystemExit("Cover file does not exist: {}".format(args.cover))
    generate(args.output.expanduser().resolve(), args.cover.expanduser().resolve())


if __name__ == "__main__":
    main()
