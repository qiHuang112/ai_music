#!/usr/bin/env python3
"""Read-only LAN music library server using only the Python standard library."""

import argparse
import hashlib
import json
import mimetypes
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from typing import Dict, Optional
from urllib.parse import quote, unquote, urlsplit


AUDIO_EXTENSIONS = {".mp3", ".flac"}
ARTWORK_EXTENSIONS = (".png", ".jpg", ".jpeg")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _asset(root: Path, path: Path, **extra: object) -> Dict[str, object]:
    relative = path.relative_to(root).as_posix()
    result: Dict[str, object] = {
        "url": "/api/v1/files/" + quote(relative, safe="/"),
        "sizeBytes": path.stat().st_size,
        "sha256": _sha256(path),
    }
    result.update(extra)
    return result


def _read_metadata(audio: Path) -> Dict[str, str]:
    sidecar = audio.with_suffix(".json")
    if not sidecar.is_file():
        return {}
    try:
        decoded = json.loads(sidecar.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    if not isinstance(decoded, dict):
        return {}
    return {
        key: str(decoded[key]).strip()
        for key in ("id", "title", "artist", "album")
        if decoded.get(key) is not None and str(decoded[key]).strip()
    }


def _default_title_artist(stem: str) -> tuple:
    if " - " in stem:
        artist, title = stem.split(" - ", 1)
        return title.strip() or stem, artist.strip() or "Unknown Artist"
    return stem, "Unknown Artist"


def _stable_id(root: Path, audio: Path) -> str:
    relative = audio.relative_to(root).as_posix().casefold()
    return "lan-" + hashlib.sha256(relative.encode("utf-8")).hexdigest()[:24]


def _folder_path(root: Path, audio: Path) -> str:
    parent = audio.parent.relative_to(root)
    if parent == Path("."):
        return ""
    value = parent.as_posix()
    parts = PurePosixPath(value).parts
    if not parts or any(
        part in {"", ".", ".."} or "\\" in part or "\x00" in part
        for part in parts
    ):
        raise ValueError("Unsafe folder path")
    return value


def _find_artwork(audio: Path) -> Optional[Path]:
    for extension in ARTWORK_EXTENSIONS:
        candidate = audio.with_suffix(extension)
        if candidate.is_file():
            return candidate
    return None


def build_manifest(root: Path, base_url: str = "") -> Dict[str, object]:
    del base_url  # Asset URLs are deliberately relative to the responding server.
    resolved_root = root.expanduser().resolve(strict=True)
    tracks = []
    audio_files = []
    for path in resolved_root.rglob("*"):
        if path.suffix.casefold() not in AUDIO_EXTENSIONS:
            continue
        relative = path.relative_to(resolved_root).as_posix()
        safe_audio = _safe_file(resolved_root, relative)
        if safe_audio is not None:
            audio_files.append(safe_audio)
    for audio in sorted(
        audio_files,
        key=lambda path: path.relative_to(resolved_root).as_posix().casefold(),
    ):
        metadata = _read_metadata(audio)
        default_title, default_artist = _default_title_artist(audio.stem)
        parent = audio.parent.relative_to(resolved_root)
        album = "" if parent == Path(".") else audio.parent.name
        track: Dict[str, object] = {
            "id": metadata.get("id") or _stable_id(resolved_root, audio),
            "title": metadata.get("title") or default_title,
            "artist": metadata.get("artist") or default_artist,
            "album": metadata.get("album") or album,
            "folderPath": _folder_path(resolved_root, audio),
            "audio": _asset(
                resolved_root,
                audio,
                format=audio.suffix.lstrip(".").casefold(),
            ),
        }
        lyrics = audio.with_suffix(".lrc")
        if lyrics.is_file():
            track["lyrics"] = _asset(resolved_root, lyrics, format="lrc")
        artwork = _find_artwork(audio)
        if artwork is not None:
            mime_type = mimetypes.guess_type(str(artwork))[0] or "application/octet-stream"
            track["artwork"] = _asset(resolved_root, artwork, mimeType=mime_type)
        tracks.append(track)

    library_key = str(resolved_root).casefold().encode("utf-8")
    return {
        "schemaVersion": 1,
        "libraryId": "library-" + hashlib.sha256(library_key).hexdigest()[:16],
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "tracks": tracks,
    }


def _safe_file(root: Path, raw_relative: str) -> Optional[Path]:
    relative = PurePosixPath(unquote(raw_relative))
    if relative.is_absolute() or any(part in {"", ".", ".."} for part in relative.parts):
        return None
    lexical_candidate = root / Path(*relative.parts)
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            return None
    try:
        candidate = lexical_candidate.resolve(strict=True)
    except (OSError, RuntimeError):
        return None
    try:
        common = Path(os.path.commonpath((str(root), str(candidate))))
    except ValueError:
        return None
    if common != root or not candidate.is_file() or not _is_manifest_asset(candidate):
        return None
    return candidate


def _is_manifest_asset(candidate: Path) -> bool:
    suffix = candidate.suffix.casefold()
    if suffix in AUDIO_EXTENSIONS:
        return True
    if suffix != ".lrc" and suffix not in ARTWORK_EXTENSIONS:
        return False
    return any(
        candidate.with_suffix(extension).is_file()
        and not candidate.with_suffix(extension).is_symlink()
        for extension in AUDIO_EXTENSIONS
    )


def create_server(root: Path, host: str, port: int) -> ThreadingHTTPServer:
    resolved_root = root.expanduser().resolve(strict=True)

    class LanMusicHandler(BaseHTTPRequestHandler):
        server_version = "AIHomeLanMusic/1.0"

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            path = urlsplit(self.path).path
            if path == "/api/v1/health":
                manifest = build_manifest(resolved_root)
                self._send_json(
                    {
                        "status": "ok",
                        "schemaVersion": 1,
                        "trackCount": len(manifest["tracks"]),
                    }
                )
                return
            if path == "/api/v1/library":
                self._send_json(build_manifest(resolved_root))
                return
            prefix = "/api/v1/files/"
            if path.startswith(prefix):
                target = _safe_file(resolved_root, path[len(prefix) :])
                if target is None:
                    self.send_error(404, "File not found")
                    return
                self._send_file(target)
                return
            self.send_error(404, "Not found")

        def _send_json(self, value: object) -> None:
            payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode(
                "utf-8"
            )
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def _send_file(self, path: Path) -> None:
            size = path.stat().st_size
            self.send_response(200)
            self.send_header(
                "Content-Type", mimetypes.guess_type(str(path))[0] or "application/octet-stream"
            )
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition", "attachment")
            self.end_headers()
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    self.wfile.write(chunk)

        def log_message(self, message: str, *args: object) -> None:
            print("{} - {}".format(self.address_string(), message % args))

    return ThreadingHTTPServer((host, port), LanMusicHandler)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve a read-only LAN music library")
    parser.add_argument("--root", required=True, type=Path, help="Music library directory")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", default=8787, type=int)
    args = parser.parse_args()
    server = create_server(args.root, args.host, args.port)
    print("Serving {} at http://{}:{}".format(args.root.resolve(), args.host, server.server_port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
