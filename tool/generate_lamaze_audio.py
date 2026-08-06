#!/usr/bin/env python3
"""Generate four original Mandarin Lamaze companion tracks on macOS.

The spoken guidance is rendered with the local Tingting voice. The original
loopable ambient bed is synthesized with NumPy, then mixed and encoded by
FFmpeg. This generator is intentionally separate from the LAN server.
"""

import argparse
import json
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from lamaze_score import render_score_stems


SAMPLE_RATE = 48_000
ARTIST = "AI Home"
ALBUM = "拉玛泽呼吸引导"
VOICE = "Tingting"
FORBIDDEN_CLAIMS = ("宫口", "厘米", "无痛", "顺产", "保证")
BANNED_ANNOUNCEMENTS = (
    "这是一段",
    "这首引导",
    "本曲",
    "用于",
    "循环播放",
    "不会替",
)


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


TRACKS = (
    TrackSpec(
        track_id="lamaze-slow-relax",
        slug="01-慢呼放松",
        title="慢呼放松",
        duration_seconds=300,
        bpm=60,
        cues=(
            Cue(6, "肩膀松下来，下巴也松下来。"),
            Cue(32, "轻轻吸气……慢慢呼出去。"),
            Cue(60, "双手放松，让呼吸自然流动。"),
            Cue(88, "额头放松，嘴唇也保持柔软。"),
            Cue(116, "吸气时让胸腹自然展开，呼气时慢慢松开。"),
            Cue(144, "只跟随舒服的节奏，不需要屏气。"),
            Cue(172, "宫缩来到时，把注意力放在这一口呼气上。"),
            Cue(200, "慢慢呼气，让身体多放松一点。"),
            Cue(228, "需要调整时，直接告诉身边的医护。"),
            Cue(256, "如果头晕，先回到自然呼吸，告诉身边的医护。"),
            Cue(284, "轻轻吸气，再把这一口气慢慢呼出去。"),
        ),
    ),
    TrackSpec(
        track_id="lamaze-contraction-wave",
        slug="02-宫缩浪潮",
        title="宫缩浪潮",
        duration_seconds=180,
        bpm=64,
        cues=(
            Cue(6, "浪潮来到时，先把肩膀松下来。"),
            Cue(31, "轻轻吸气，慢慢呼出去。"),
            Cue(56, "感觉增强时，让呼吸轻一点、短一点。"),
            Cue(81, "嘴唇保持柔软，让呼吸继续流动。"),
            Cue(106, "感觉缓和时，把呼气慢慢放长。"),
            Cue(131, "如果头晕，先回到自然呼吸，告诉身边的医护。"),
            Cue(156, "一口一口呼吸，继续跟随医护的声音。"),
        ),
    ),
    TrackSpec(
        track_id="lamaze-defer-pushing",
        slug="03-暂缓用力",
        title="暂缓用力",
        duration_seconds=120,
        bpm=72,
        cues=(
            Cue(2, "嘴唇轻轻张开，做短而轻的哈气。"),
            Cue(22, "只有医护明确要求暂缓用力时，继续这样呼吸。"),
            Cue(42, "像吹动羽毛一样，短短地呼气。"),
            Cue(62, "不要屏气，也不要主动向下用力。"),
            Cue(82, "让肩膀和双手放松，保持自然呼吸。"),
            Cue(102, "如果头晕，先停下来，告诉身边的医护。"),
        ),
    ),
    TrackSpec(
        track_id="lamaze-follow-care-team",
        slug="04-跟随医护",
        title="跟随医护",
        duration_seconds=180,
        bpm=60,
        cues=(
            Cue(6, "先听医护的声音，让呼吸自然流动。"),
            Cue(34, "肩膀松下来，下巴和双手也松下来。"),
            Cue(62, "每次只听清一个指令，再跟随当下。"),
            Cue(90, "指令之间，回到自然呼吸。"),
            Cue(118, "不确定时，直接询问医生或助产士。"),
            Cue(146, "如果头晕，先回到自然呼吸，告诉身边的医护。"),
            Cue(174, "继续听医护的声音，等待下一条指令。"),
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
        if not track.cues or not 0 <= track.cues[0].at_seconds <= 6:
            raise ValueError("Every track must begin within six seconds")
        if track.slug == "03-暂缓用力" and track.cues[0].at_seconds > 3:
            raise ValueError("The defer-pushing track must begin within three seconds")
        positions = [cue.at_seconds for cue in track.cues]
        if positions != sorted(positions) or positions[-1] >= track.duration_seconds:
            raise ValueError("Cue positions must be sorted and inside the track")
        gaps = [right - left for left, right in zip(positions, positions[1:])]
        if any(gap < 20 or gap > 35 for gap in gaps):
            raise ValueError("Cue spacing must stay between 20 and 35 seconds")
        lyrics = "\n".join(cue.text for cue in track.cues)
        if "医护" not in lyrics or "自然呼吸" not in lyrics:
            raise ValueError("Every track needs clinical priority and stop guidance")
        for claim in FORBIDDEN_CLAIMS:
            if claim in lyrics:
                raise ValueError("Forbidden claim in {}: {}".format(track.slug, claim))
        for announcement in BANNED_ANNOUNCEMENTS:
            if announcement in lyrics:
                raise ValueError(
                    "Announcement copy in {}: {}".format(track.slug, announcement)
                )
        if any(cue.style != "spoken" for cue in track.cues):
            raise ValueError("Every cue must use direct spoken guidance")
        if any(len(cue.text) > 34 for cue in track.cues):
            raise ValueError("Guidance sentences must stay short")


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
    missing = [
        name
        for name in ("say", "ffmpeg", "ffprobe", "fluidsynth")
        if shutil.which(name) is None
    ]
    if missing:
        raise RuntimeError("Missing required tools: {}".format(", ".join(missing)))


def _render_voice_cues(track: TrackSpec, work: Path) -> Sequence[Path]:
    paths = []
    for index, cue in enumerate(track.cues):
        target = work / "cue-{:02d}.aiff".format(index)
        _run(("say", "-v", VOICE, "-r", "152", "-o", str(target), cue.text))
        paths.append(target)
    return paths


def _mix_track(
    track: TrackSpec,
    stems: Sequence[Path],
    cues: Sequence[Path],
    wav_target: Path,
) -> None:
    if len(stems) != 3:
        raise ValueError("Exactly three sampled score stems are required")
    command = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    for stem in stems:
        command.extend(("-i", str(stem)))
    for cue_path in cues:
        command.extend(("-i", str(cue_path)))

    filters = [
        "[0:a]aresample=48000,volume=0.72[piano]",
        "[1:a]aresample=48000,volume=0.40[strings]",
        "[2:a]aresample=48000,volume=0.12[air]",
        "[piano][strings][air]amix=inputs=3:duration=first:normalize=0[bed]",
    ]
    voice_labels = []
    for index, cue in enumerate(track.cues, start=len(stems)):
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


def generate(output: Path, cover_source: Path, soundfont: Path) -> None:
    validate_track_specs(TRACKS)
    _require_tools()
    if not soundfont.is_file():
        raise FileNotFoundError("SoundFont does not exist: {}".format(soundfont))
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
            stems = render_score_stems(track, work, soundfont)
            voice_cues = _render_voice_cues(track, work)
            wav_target = output / "{}.wav".format(track.slug)
            mp3_target = output / "{}.mp3".format(track.slug)
            _mix_track(track, stems, voice_cues, wav_target)
            _encode_mp3(track, wav_target, common_cover, mp3_target)
            _write_sidecars(track, output, common_cover)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate original Lamaze guide audio")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cover", required=True, type=Path)
    parser.add_argument("--soundfont", required=True, type=Path)
    args = parser.parse_args()
    if not args.cover.is_file():
        raise SystemExit("Cover file does not exist: {}".format(args.cover))
    if not args.soundfont.is_file():
        raise SystemExit("SoundFont does not exist: {}".format(args.soundfont))
    generate(
        args.output.expanduser().resolve(),
        args.cover.expanduser().resolve(),
        args.soundfont.expanduser().resolve(),
    )


if __name__ == "__main__":
    main()
