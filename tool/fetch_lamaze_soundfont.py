#!/usr/bin/env python3
"""Fetch the pinned MIT-licensed SoundFont assets used by Lamaze audio."""

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence
from urllib.parse import urlsplit
from urllib.request import urlopen


BASE_URL = (
    "https://ftp.osuosl.org/pub/musescore/soundfont/"
    "MuseScore_General/"
)


@dataclass(frozen=True)
class SoundFontResource:
    filename: str
    url: str


RESOURCES: Sequence[SoundFontResource] = (
    SoundFontResource(
        filename="MuseScore_General.sf3",
        url=BASE_URL + "MuseScore_General.sf3",
    ),
    SoundFontResource(
        filename="MuseScore_General_License.md",
        url=BASE_URL + "MuseScore_General_License.md",
    ),
    SoundFontResource(filename="VERSION", url=BASE_URL + "VERSION"),
)


def fetch_resources(output: Path, opener: Callable = urlopen) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    records = {}
    for resource in RESOURCES:
        target = output / resource.filename
        temporary = output / (resource.filename + ".download")
        digest = hashlib.sha256()
        try:
            with opener(resource.url) as response, temporary.open("wb") as sink:
                final_url = response.geturl()
                if urlsplit(final_url).scheme.lower() != "https":
                    raise ValueError("SoundFont redirect must remain HTTPS")
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
                    sink.write(chunk)
            temporary.replace(target)
        finally:
            if temporary.exists():
                temporary.unlink()
        records[resource.filename] = {
            "url": resource.url,
            "sha256": digest.hexdigest(),
            "sizeBytes": target.stat().st_size,
        }

    version_text = (output / "VERSION").read_text(
        encoding="utf-8", errors="replace"
    ).strip()
    manifest = {
        "soundFont": "MuseScore General",
        "version": version_text,
        "license": "MIT",
        "licenseFile": "MuseScore_General_License.md",
        "resources": records,
    }
    (output / "lamaze_soundfont_sources.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Lamaze SoundFont assets")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    manifest = fetch_resources(args.output.expanduser().resolve())
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
