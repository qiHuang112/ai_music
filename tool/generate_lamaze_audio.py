#!/usr/bin/env python3
"""Generate four Mandarin Lamaze tracks with CosyVoice SFT and VSCO samples."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from lamaze_production_score import render_production_stems


SAMPLE_RATE = 48_000
ARTIST = "AI Home"
ALBUM = "拉玛泽呼吸引导"
DEFAULT_SPEAKER = "中文女"
DEFAULT_SPEED = 0.92
COSYVOICE_COMMIT = "074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc"
SFT_REVISION = "fbb71de2afe387ed854eebd80b9f3d078c6b9869"
VSCO_COMMIT = "6dd651d55dde97fd4028699be9d4481f26917891"
REQUIRED_PATCHES = (
    "UprightPiano.sfz",
    "ViolinEnsSusVib-Quiet.sfz",
    "CelloEnsSusVib-Quiet.sfz",
)
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
            Cue(22, "按医护的提示，继续短短地呼气。"),
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
    lines.extend(
        "{}{}".format(_lrc_timestamp(cue.at_seconds), cue.text)
        for cue in track.cues
    )
    return "\n".join(lines) + "\n"


def render_txt(track: TrackSpec) -> str:
    heading = [
        track.title,
        "",
        "用途说明：呼吸陪伴工具，不替代医生或助产士的现场判断。现场医护指令始终优先。",
    ]
    if track.slug == "03-暂缓用力":
        heading.append("仅在医护人员明确要求暂缓用力时使用。")
    heading.extend(
        (
            "若头晕、手脚发麻或不适，请停止练习、恢复自然呼吸并告诉医护人员。",
            "",
            "引导词：",
        )
    )
    heading.extend(cue.text for cue in track.cues)
    return "\n".join(heading) + "\n"


def _lrc_timestamp(seconds: float) -> str:
    total_centiseconds = int(round(seconds * 100))
    minutes, remainder = divmod(total_centiseconds, 6000)
    whole_seconds, centiseconds = divmod(remainder, 100)
    return "[{:02d}:{:02d}.{:02d}]".format(
        minutes, whole_seconds, centiseconds
    )


def _run(command: Sequence[str]) -> None:
    subprocess.run(list(command), check=True)


def _require_tools(sfizz_render: Path) -> None:
    missing = [name for name in ("ffmpeg", "ffprobe") if shutil.which(name) is None]
    if missing:
        raise RuntimeError("Missing required tools: {}".format(", ".join(missing)))
    if not sfizz_render.is_file():
        raise FileNotFoundError("sfizz_render does not exist: {}".format(sfizz_render))


def _load_cosyvoice_model(
    cosyvoice_root: Path,
    model_dir: Path,
    *,
    model_factory=None,
):
    if not cosyvoice_root.is_dir():
        raise FileNotFoundError("CosyVoice root does not exist: {}".format(cosyvoice_root))
    if not model_dir.is_dir():
        raise FileNotFoundError("CosyVoice model does not exist: {}".format(model_dir))
    for path in (cosyvoice_root, cosyvoice_root / "third_party" / "Matcha-TTS"):
        value = str(path)
        if value not in sys.path:
            sys.path.insert(0, value)
    if model_factory is None:
        from cosyvoice.cli.cosyvoice import AutoModel

        model_factory = AutoModel
    return model_factory(model_dir=str(model_dir))


def _render_voice_cues(
    track: TrackSpec,
    work: Path,
    *,
    model,
    speaker: str = DEFAULT_SPEAKER,
    speed: float = DEFAULT_SPEED,
    concatenate=None,
    audio_saver=None,
) -> tuple[Path, ...]:
    if speaker not in model.list_available_spks():
        raise ValueError("CosyVoice model does not provide 中文女")
    if concatenate is None:
        import torch

        concatenate = lambda values: torch.cat(values, dim=1)
    if audio_saver is None:
        import torchaudio

        audio_saver = torchaudio.save

    paths = []
    for index, cue in enumerate(track.cues):
        chunks = [
            item["tts_speech"]
            for item in model.inference_sft(
                cue.text,
                speaker,
                stream=False,
                speed=speed,
            )
        ]
        if not chunks:
            raise RuntimeError("CosyVoice yielded no speech")
        target = work / "cue-{:02d}.wav".format(index)
        audio_saver(str(target), concatenate(chunks).cpu(), model.sample_rate)
        if not target.is_file() or target.stat().st_size <= 44:
            raise RuntimeError("Invalid cue output: {}".format(target))
        paths.append(target)
    return tuple(paths)


def _mix_track(
    track: TrackSpec,
    stems: Sequence[Path],
    cues: Sequence[Path],
    wav_target: Path,
) -> None:
    if len(stems) != 3:
        raise ValueError("Exactly three sampled score stems are required")
    if len(cues) != len(track.cues):
        raise ValueError("Every guidance cue needs one rendered voice file")
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
    for input_index, cue in enumerate(track.cues, start=3):
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
            "{}amix=inputs={}:duration=longest:normalize=0[voicebus]".format(
                "".join(voice_labels), len(voice_labels)
            ),
            "[voicebus]apad=whole_dur={duration},atrim=duration={duration},"
            "asplit=2[voicekey][voicemix]".format(duration=track.duration_seconds),
            "[bed][voicekey]sidechaincompress=threshold=0.02:ratio=4:"
            "attack=200:release=900[ducked]",
            "[ducked][voicemix]amix=inputs=2:duration=first:normalize=0,"
            "loudnorm=I=-18:TP=-1.5:LRA=8,"
            "alimiter=limit=0.8414:level=false[out]",
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
            "pcm_s24le",
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
            "-ac",
            "2",
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


def _usage_for(track: TrackSpec) -> str:
    value = "呼吸陪伴工具；现场医生和助产士指令始终优先。"
    if track.slug == "03-暂缓用力":
        value += "仅在医护人员明确要求暂缓用力时使用。"
    return value


def _write_sidecars(
    track: TrackSpec,
    output: Path,
    cover: Path,
    *,
    audio_sources: dict,
) -> None:
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
        "voice": "CosyVoice SFT 中文女",
        "voiceSpeed": DEFAULT_SPEED,
        "guidanceStyle": "spoken-direct-actions",
        "cues": [
            {
                "atSeconds": cue.at_seconds,
                "text": cue.text,
                "style": cue.style,
            }
            for cue in track.cues
        ],
        "instruments": [
            "VSCO Upright Piano",
            "VSCO Quiet Violin Ensemble",
            "VSCO Quiet Cello Ensemble",
        ],
        "audioSources": audio_sources,
        "usage": _usage_for(track),
        "license": "Original production for this project",
    }
    stem.with_suffix(".json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    shutil.copy2(cover, stem.with_suffix(".png"))


def load_audio_sources(runtime_sources: Path) -> dict:
    decoded = json.loads(runtime_sources.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("Runtime source manifest must be a JSON object")
    cosyvoice = decoded.get("cosyVoice")
    sft = decoded.get("models", {}).get("sft")
    vsco = decoded.get("vsco2Ce")
    sfizz = decoded.get("sfizz")
    if not all(isinstance(value, dict) for value in (cosyvoice, sft, vsco, sfizz)):
        raise ValueError("Runtime source manifest is incomplete")
    expected = (
        (cosyvoice, "commit", COSYVOICE_COMMIT),
        (cosyvoice, "license", "Apache-2.0"),
        (sft, "repo", "FunAudioLLM/CosyVoice-300M-SFT"),
        (sft, "revision", SFT_REVISION),
        (sft, "license", "Apache-2.0"),
        (vsco, "commit", VSCO_COMMIT),
        (vsco, "license", "CC0-1.0"),
        (sfizz, "version", "1.2.3"),
        (sfizz, "license", "BSD-2-Clause"),
    )
    for record, key, value in expected:
        if record.get(key) != value:
            raise ValueError("Unexpected runtime source {}".format(key))
    patch_hashes = vsco.get("patchHashes")
    if not isinstance(patch_hashes, dict):
        raise ValueError("VSCO patch hashes are missing")
    approved_patch_hashes = {}
    for patch_name in REQUIRED_PATCHES:
        digest = str(patch_hashes.get(patch_name, "")).lower()
        if not _is_sha256(digest):
            raise ValueError("Invalid VSCO patch hash: {}".format(patch_name))
        approved_patch_hashes[patch_name] = digest
    archive_hash = str(sfizz.get("archiveSha256", "")).lower()
    if not _is_sha256(archive_hash):
        raise ValueError("Invalid sfizz archive hash")
    return {
        "voiceEngine": {
            "name": "CosyVoice",
            "commit": COSYVOICE_COMMIT,
            "license": "Apache-2.0",
        },
        "voiceModel": {
            "repo": "FunAudioLLM/CosyVoice-300M-SFT",
            "revision": SFT_REVISION,
            "license": "Apache-2.0",
            "speaker": DEFAULT_SPEAKER,
            "speed": DEFAULT_SPEED,
        },
        "sampleLibrary": {
            "name": "VSCO 2 CE",
            "commit": VSCO_COMMIT,
            "license": "CC0-1.0",
            "patchHashes": approved_patch_hashes,
        },
        "sampler": {
            "name": "sfizz",
            "version": "1.2.3",
            "license": "BSD-2-Clause",
            "archiveSha256": archive_hash,
        },
    }


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def generate(
    output: Path,
    cover_source: Path,
    cosyvoice_root: Path,
    model_dir: Path,
    sfizz_render: Path,
    vsco_root: Path,
    runtime_sources: Path,
    *,
    speaker: str = DEFAULT_SPEAKER,
    speed: float = DEFAULT_SPEED,
    model_factory=None,
) -> None:
    validate_track_specs(TRACKS)
    if speaker != DEFAULT_SPEAKER or speed != DEFAULT_SPEED:
        raise ValueError("Production voice must remain 中文女 at speed 0.92")
    _require_tools(sfizz_render)
    if not cover_source.is_file():
        raise FileNotFoundError("Cover file does not exist: {}".format(cover_source))
    if not vsco_root.is_dir():
        raise FileNotFoundError("VSCO root does not exist: {}".format(vsco_root))
    audio_sources = load_audio_sources(runtime_sources)
    model = _load_cosyvoice_model(
        cosyvoice_root,
        model_dir,
        model_factory=model_factory,
    )

    output.mkdir(parents=True, exist_ok=True)
    common_cover = output / "cover.png"
    if cover_source.resolve() != common_cover.resolve():
        shutil.copy2(cover_source, common_cover)
    (output / "README.txt").write_text(
        "拉玛泽呼吸引导（原创）\n\n"
        "本套音频用于呼吸陪伴，不替代医生或助产士的现场判断。\n"
        "现场医护指令始终优先。若头晕、手脚发麻或不适，请停止练习、恢复自然呼吸并告诉医护人员。\n"
        "03-暂缓用力仅在医护人员明确要求暂缓用力时使用。\n",
        encoding="utf-8",
    )

    for track in TRACKS:
        print(
            "Generating {} ({}s, {} BPM)".format(
                track.slug, track.duration_seconds, track.bpm
            )
        )
        with tempfile.TemporaryDirectory(prefix="lamaze-cosyvoice-") as temp_dir:
            work = Path(temp_dir)
            stems = render_production_stems(track, work, sfizz_render, vsco_root)
            voice_cues = _render_voice_cues(
                track,
                work,
                model=model,
                speaker=speaker,
                speed=speed,
            )
            wav_target = output / "{}.wav".format(track.slug)
            mp3_target = output / "{}.mp3".format(track.slug)
            _mix_track(track, stems, voice_cues, wav_target)
            _encode_mp3(track, wav_target, common_cover, mp3_target)
            _write_sidecars(
                track,
                output,
                common_cover,
                audio_sources=audio_sources,
            )


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cover", required=True, type=Path)
    parser.add_argument("--cosyvoice-root", required=True, type=Path)
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--sfizz-render", required=True, type=Path)
    parser.add_argument("--vsco-root", required=True, type=Path)
    parser.add_argument("--runtime-sources", required=True, type=Path)
    parser.add_argument("--speaker", default=DEFAULT_SPEAKER)
    parser.add_argument("--speed", default=DEFAULT_SPEED, type=float)
    return parser


def main() -> None:
    args = build_argument_parser().parse_args()
    generate(
        args.output.expanduser().resolve(),
        args.cover.expanduser().resolve(),
        args.cosyvoice_root.expanduser().resolve(),
        args.model_dir.expanduser().resolve(),
        args.sfizz_render.expanduser().resolve(),
        args.vsco_root.expanduser().resolve(),
        args.runtime_sources.expanduser().resolve(),
        speaker=args.speaker,
        speed=args.speed,
    )


if __name__ == "__main__":
    main()
