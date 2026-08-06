#!/usr/bin/env python3
"""Build deterministic original MIDI scores and sampled Lamaze stems."""

import shutil
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Sequence


TICKS_PER_BEAT = 480
SAMPLE_RATE = 48_000


@dataclass(frozen=True)
class MidiNote:
    start_beat: float
    duration_beats: float
    pitch: int
    velocity: int


@dataclass(frozen=True)
class StemScore:
    name: str
    program: int
    notes: Sequence[MidiNote]


_PROGRESSIONS = {
    "lamaze-slow-relax": (
        (48, 52, 55),
        (43, 47, 50),
        (45, 48, 52),
        (41, 45, 48),
    ),
    "lamaze-contraction-wave": (
        (50, 53, 57),
        (46, 50, 53),
        (41, 45, 48),
        (48, 52, 55),
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


def build_stem_scores(track) -> Dict[str, StemScore]:
    total_beats = _total_beats(track)
    progression = _PROGRESSIONS[track.track_id]

    piano_notes = []
    piano_pattern = (0, 2, 1, 2)
    for start in range(0, total_beats, 4):
        chord = progression[(start // 4) % len(progression)]
        for offset, note_index in enumerate(piano_pattern):
            note_start = start + offset
            if note_start >= total_beats:
                break
            piano_notes.append(
                MidiNote(
                    start_beat=note_start,
                    duration_beats=min(0.82, total_beats - note_start),
                    pitch=chord[note_index] + 12,
                    velocity=(52, 46, 49, 44)[offset],
                )
            )

    string_notes = []
    for start in range(0, total_beats, 8):
        chord = progression[(start // 8) % len(progression)]
        duration = min(7.75, total_beats - start)
        for pitch in chord:
            string_notes.append(
                MidiNote(
                    start_beat=start,
                    duration_beats=duration,
                    pitch=pitch + 12,
                    velocity=40,
                )
            )

    air_notes = []
    for start in range(0, total_beats, 16):
        chord = progression[(start // 16) % len(progression)]
        duration = min(15.5, total_beats - start)
        for pitch in (chord[0], chord[2]):
            air_notes.append(
                MidiNote(
                    start_beat=start,
                    duration_beats=duration,
                    pitch=pitch + 24,
                    velocity=28,
                )
            )

    return {
        "piano": StemScore(name="piano", program=0, notes=tuple(piano_notes)),
        "strings": StemScore(
            name="strings", program=48, notes=tuple(string_notes)
        ),
        "air": StemScore(name="air", program=89, notes=tuple(air_notes)),
    }


def midi_bytes(track, score: StemScore) -> bytes:
    total_ticks = _total_beats(track) * TICKS_PER_BEAT
    tempo = round(60_000_000 / track.bpm)
    payload = bytearray()
    payload.extend(_variable_length(0))
    payload.extend((0xFF, 0x51, 0x03))
    payload.extend(tempo.to_bytes(3, "big"))
    payload.extend(_variable_length(0))
    payload.extend((0xC0, score.program))

    events = []
    for note in score.notes:
        start = round(note.start_beat * TICKS_PER_BEAT)
        end = round((note.start_beat + note.duration_beats) * TICKS_PER_BEAT)
        if not 0 <= start < end <= total_ticks:
            raise ValueError("MIDI note lies outside the track")
        if not 0 <= note.pitch <= 127 or not 1 <= note.velocity <= 127:
            raise ValueError("MIDI note pitch or velocity is invalid")
        events.append((start, 1, 0x90, note.pitch, note.velocity))
        events.append((end, 0, 0x80, note.pitch, 0))

    current_tick = 0
    for tick, _, status, pitch, velocity in sorted(events):
        payload.extend(_variable_length(tick - current_tick))
        payload.extend((status, pitch, velocity))
        current_tick = tick
    payload.extend(_variable_length(total_ticks - current_tick))
    payload.extend((0xFF, 0x2F, 0x00))

    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, TICKS_PER_BEAT)
    return header + b"MTrk" + struct.pack(">I", len(payload)) + bytes(payload)


def write_midi(track, score: StemScore, target: Path) -> Path:
    target.write_bytes(midi_bytes(track, score))
    return target


def render_score_stems(track, work: Path, soundfont: Path) -> Sequence[Path]:
    if not soundfont.is_file():
        raise FileNotFoundError("SoundFont does not exist: {}".format(soundfont))
    missing = [name for name in ("fluidsynth", "ffmpeg") if shutil.which(name) is None]
    if missing:
        raise RuntimeError("Missing required tools: {}".format(", ".join(missing)))
    work.mkdir(parents=True, exist_ok=True)
    targets = []
    for score in build_stem_scores(track).values():
        midi_path = write_midi(track, score, work / "{}.mid".format(score.name))
        rendered = work / "{}-rendered.wav".format(score.name)
        target = work / "{}.wav".format(score.name)
        _run(
            (
                "fluidsynth",
                "-ni",
                "-F",
                str(rendered),
                "-r",
                str(SAMPLE_RATE),
                "-o",
                "synth.gain=0.55",
                str(soundfont),
                str(midi_path),
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
                "apad=whole_dur={}".format(track.duration_seconds),
                "-t",
                str(track.duration_seconds),
                "-ar",
                str(SAMPLE_RATE),
                "-ac",
                "2",
                "-c:a",
                "pcm_s16le",
                str(target),
            )
        )
        targets.append(target)
    return tuple(targets)


def _total_beats(track) -> int:
    beats = track.duration_seconds * track.bpm / 60
    rounded = round(beats)
    if abs(beats - rounded) > 1e-9:
        raise ValueError("Track duration must contain a whole number of beats")
    return rounded


def _variable_length(value: int) -> bytes:
    if value < 0:
        raise ValueError("MIDI delta cannot be negative")
    buffer = value & 0x7F
    encoded = bytearray((buffer,))
    while value >> 7:
        value >>= 7
        buffer = (value & 0x7F) | 0x80
        encoded.insert(0, buffer)
    return bytes(encoded)


def _run(command: Iterable[str]) -> None:
    subprocess.run(tuple(command), check=True)
