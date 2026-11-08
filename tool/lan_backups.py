"""Per-device library backups on the home LAN.

Each device uploads its playlists, favorites and the songs in them. Files
(audio, lyrics, artwork) are stored once by SHA-256, however many devices
have them; each device keeps only its latest manifest. Any device can list
the backups and download what it picks.

Layout under the backup root:
    blobs/ab/<sha256>          file contents, named by their hash
    devices/<device id>.json   the latest manifest of one device
"""
import hashlib
import ipaddress
import json
import os
import re
import shutil
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 1
MAX_MANIFEST_BYTES = 32 * 1024 * 1024
MAX_BLOB_BYTES = 1024 * 1024 * 1024
MAX_MISSING_QUERY = 20000
# Keep this much disk free; uploads beyond it are refused instead of filling
# the Mac's drive.
MIN_FREE_BYTES = 2 * 1024 * 1024 * 1024
# A blob no manifest uses is removed only after this long, so files another
# device is still uploading (its manifest comes last) are never swept away.
ORPHAN_GRACE_SECONDS = 24 * 3600

_SHA256 = re.compile(r'[a-f0-9]{64}')
_DEVICE_ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{7,63}')
_ROLES = {'audio', 'lyrics', 'artwork'}


class MissingFiles(Exception):
    """A manifest refers to files that have not been uploaded yet."""


def lan_only(client_address: str):
    if not ipaddress.ip_address(client_address).is_private:
        raise PermissionError('LAN clients only')


def valid_sha256(value) -> bool:
    return isinstance(value, str) and _SHA256.fullmatch(value) is not None


def valid_device_id(value) -> bool:
    return isinstance(value, str) and _DEVICE_ID.fullmatch(value) is not None


class BackupStore:
    def __init__(self, root: Path):
        self.root = root
        self.blobs = root / 'blobs'
        self.devices = root / 'devices'
        self.lock = threading.Lock()

    # ---- Blobs -------------------------------------------------------------

    def blob_path(self, sha256: str) -> Path:
        if not valid_sha256(sha256):
            raise ValueError('Invalid hash')
        return self.blobs / sha256[:2] / sha256

    def missing(self, hashes) -> list:
        if not isinstance(hashes, list) or len(hashes) > MAX_MISSING_QUERY:
            raise ValueError('Invalid hash list')
        result = []
        for value in hashes:
            if not valid_sha256(value):
                raise ValueError('Invalid hash')
            if not self.blob_path(value).is_file():
                result.append(value)
        return sorted(set(result))

    def put_blob(self, sha256: str, stream, length: int, client_address: str) -> dict:
        lan_only(client_address)
        target = self.blob_path(sha256)
        if not 0 <= length <= MAX_BLOB_BYTES:
            raise ValueError('Invalid size')
        if target.is_file():
            # Still read the body so the connection stays usable.
            _drain(stream, length)
            return {'sha256': sha256, 'size': target.stat().st_size, 'stored': False}
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if shutil.disk_usage(self.root).free - length < MIN_FREE_BYTES:
            _drain(stream, length)
            raise OSError('Not enough free disk space')
        target.parent.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256()
        fd, temporary = tempfile.mkstemp(prefix='.upload-', dir=target.parent)
        try:
            remaining = length
            with os.fdopen(fd, 'wb') as output:
                while remaining:
                    chunk = stream.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError('Truncated upload')
                    digest.update(chunk)
                    output.write(chunk)
                    remaining -= len(chunk)
                output.flush()
                os.fsync(output.fileno())
            if digest.hexdigest() != sha256:
                raise ValueError('Content does not match its hash')
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        return {'sha256': sha256, 'size': length, 'stored': True}

    # ---- Manifests ---------------------------------------------------------

    def put_manifest(self, device_id: str, payload: bytes, client_address: str) -> dict:
        lan_only(client_address)
        if not valid_device_id(device_id):
            raise ValueError('Invalid device ID')
        if len(payload) > MAX_MANIFEST_BYTES:
            raise ValueError('Manifest too large')
        document = json.loads(payload)
        _validate_manifest(document, device_id)
        hashes = referenced_hashes(document)
        absent = [h for h in hashes if not self.blob_path(h).is_file()]
        if absent:
            # The client uploads files first; a manifest pointing at missing
            # files would restore songs that cannot be downloaded.
            raise MissingFiles(f'{len(absent)} files not uploaded')
        stored = {
            'receivedAt': datetime.now(timezone.utc).isoformat(),
            'clientAddress': client_address,
            'manifest': document,
        }
        with self.lock:
            self.devices.mkdir(parents=True, exist_ok=True, mode=0o700)
            _write_json(self.devices / f'{device_id}.json', stored)
            self._sweep_orphans()
        return self.summary(device_id)

    def manifest(self, device_id: str) -> dict:
        if not valid_device_id(device_id):
            raise ValueError('Invalid device ID')
        path = self.devices / f'{device_id}.json'
        if not path.is_file():
            raise FileNotFoundError(device_id)
        stored = json.loads(path.read_text(encoding='utf-8'))
        return {'receivedAt': stored['receivedAt'], **stored['manifest']}

    def summary(self, device_id: str) -> dict:
        document = self.manifest(device_id)
        tracks = document.get('tracks', {})
        sizes = {}
        for track in tracks.values():
            for item in track.get('files', []):
                sizes[item['sha256']] = item.get('size', 0)
        device = document['device']
        return {
            'deviceId': device['id'],
            'deviceName': device.get('name', ''),
            'platform': device.get('platform', ''),
            'appVersion': device.get('appVersion', ''),
            'createdAt': document.get('createdAt', ''),
            'receivedAt': document['receivedAt'],
            'playlistCount': len(document.get('playlists', [])),
            'favoriteCount': len(document.get('favorites', [])),
            'trackCount': len(tracks),
            'totalBytes': sum(sizes.values()),
        }

    def list_devices(self) -> list:
        if not self.devices.is_dir():
            return []
        result = []
        for path in sorted(self.devices.glob('*.json')):
            try:
                result.append(self.summary(path.stem))
            except (OSError, ValueError, KeyError, TypeError):
                continue
        return sorted(result, key=lambda row: row['receivedAt'], reverse=True)

    def _sweep_orphans(self):
        used = set()
        for path in self.devices.glob('*.json'):
            try:
                stored = json.loads(path.read_text(encoding='utf-8'))
                used |= referenced_hashes(stored['manifest'])
            except (OSError, ValueError, KeyError, TypeError):
                # An unreadable manifest must not cost any files.
                return
        cutoff = time.time() - ORPHAN_GRACE_SECONDS
        for blob in self.blobs.glob('*/*'):
            if blob.name not in used and valid_sha256(blob.name) and blob.stat().st_mtime < cutoff:
                blob.unlink(missing_ok=True)


def referenced_hashes(document) -> set:
    hashes = set()
    for track in (document.get('tracks') or {}).values():
        for item in track.get('files', []):
            hashes.add(item['sha256'])
    return hashes


def _validate_manifest(document, device_id: str):
    if not isinstance(document, dict) or document.get('schemaVersion') != SCHEMA_VERSION:
        raise ValueError('Invalid schema')
    device = document.get('device')
    if not isinstance(device, dict) or device.get('id') != device_id:
        raise ValueError('Device mismatch')
    tracks = document.get('tracks')
    if not isinstance(tracks, dict):
        raise ValueError('Invalid tracks')
    for key, track in tracks.items():
        if not isinstance(key, str) or not isinstance(track, dict):
            raise ValueError('Invalid track')
        files = track.get('files', [])
        if not isinstance(files, list):
            raise ValueError('Invalid files')
        for item in files:
            if (not isinstance(item, dict) or item.get('role') not in _ROLES or
                    not valid_sha256(item.get('sha256')) or
                    not isinstance(item.get('size'), int) or item['size'] < 0):
                raise ValueError('Invalid file entry')
    for name in ('favorites', 'playlists'):
        if not isinstance(document.get(name, []), list):
            raise ValueError(f'Invalid {name}')
    for entry in document.get('favorites', []):
        if not isinstance(entry, dict) or entry.get('trackId') not in tracks:
            raise ValueError('Favorite refers to an unknown track')
    for playlist in document.get('playlists', []):
        if not isinstance(playlist, dict) or not isinstance(playlist.get('entries', []), list):
            raise ValueError('Invalid playlist')
        for entry in playlist.get('entries', []):
            if not isinstance(entry, dict) or entry.get('trackId') not in tracks:
                raise ValueError('Playlist entry refers to an unknown track')


def _write_json(target: Path, document):
    fd, temporary = tempfile.mkstemp(prefix='.manifest-', dir=target.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            json.dump(document, output, ensure_ascii=False)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _drain(stream, length: int):
    remaining = length
    while remaining:
        chunk = stream.read(min(1024 * 1024, remaining))
        if not chunk:
            return
        remaining -= len(chunk)
