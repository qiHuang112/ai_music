"""Immutable release metadata retained independently of the latest pointer."""
import json
import os
import tempfile
from pathlib import Path


def retain_manifest(root: Path, manifest: dict):
    directory = root / 'versions'
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"{manifest['sha256']}.json"
    if destination.exists():
        return
    fd, temporary = tempfile.mkstemp(prefix='.version-', dir=directory)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            json.dump(manifest, output, ensure_ascii=False)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def retained_versions(root: Path):
    records = {}
    for file in (root / 'versions').glob('*.json'):
        try:
            record = json.loads(file.read_text(encoding='utf-8'))
            if record.get('packageName') == 'com.qi.ai.music':
                records[record['sha256']] = record
        except (OSError, ValueError, KeyError, AttributeError):
            continue
    latest = root / 'latest.json'
    if latest.is_file():
        try:
            record = json.loads(latest.read_text(encoding='utf-8'))
            records[record['sha256']] = record
        except (OSError, ValueError, KeyError, TypeError):
            pass
    return sorted(records.values(), key=lambda row: row.get('versionCode', 0), reverse=True)
