#!/usr/bin/env python3
"""Retain historical AI Music APKs without changing the advertised update."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from android_release_archive import retain_manifest, retained_versions


def archive(apk: Path, root: Path, aapt: str, apksigner: str, trusted_certs: set, release_cert: str):
    metadata = subprocess.check_output([aapt, 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", metadata, re.M)
    if not package or package[1] != 'com.qi.ai.music':
        return None
    signed = subprocess.check_output([apksigner, 'verify', '--print-certs', str(apk)], text=True)
    certificates = set(re.findall(r'certificate SHA-256 digest: ([0-9a-f]+)', signed))
    if not certificates or not certificates.issubset(trusted_certs):
        return None
    digest = hashlib.sha256()
    with apk.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    hash_hex = digest.hexdigest()
    for existing in retained_versions(root):
        if existing['sha256'] == hash_hex:
            retain_manifest(root, existing)
            return existing
    with zipfile.ZipFile(apk) as zipped:
        abis = sorted({item.split('/')[1] for item in zipped.namelist() if item.startswith('lib/') and item.endswith('.so')})
    channel = ('debug' if 'application-debuggable' in metadata else
               'release' if certificates == {release_cert} else 'profile')
    abi = abis[0] if len(abis) == 1 else 'universal'
    code = int(package[2])
    name = f'ai-music-{code}-{channel}-{abi}-{hash_hex[:12]}.apk'
    root.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.archive-', dir=root)
    os.close(fd)
    try:
        shutil.copyfile(apk, temporary)
        if hashlib.sha256(Path(temporary).read_bytes()).hexdigest() != hash_hex:
            raise ValueError('APK changed while archiving')
        os.replace(temporary, root / name)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    record = {
        'packageName': package[1], 'versionName': package[3], 'versionCode': code,
        'channel': channel, 'abi': abi, 'abis': abis,
        'archivedAt': datetime.now(timezone.utc).isoformat(),
        'url': f'/releases/{name}', 'sizeBytes': apk.stat().st_size,
        'sha256': hash_hex, 'notes': '',
    }
    retain_manifest(root, record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--paths-file', required=True, type=Path)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--apksigner', required=True)
    parser.add_argument('--trusted-cert', action='append', required=True)
    parser.add_argument('--release-cert', required=True)
    args = parser.parse_args()
    counts = {'retained': 0, 'skipped': 0, 'invalid': 0}
    for line in args.paths_file.read_text().splitlines():
        try:
            record = archive(Path(line), args.root, args.aapt, args.apksigner, set(args.trusted_cert), args.release_cert)
            counts['retained' if record else 'skipped'] += 1
        except (OSError, ValueError, subprocess.CalledProcessError):
            counts['invalid'] += 1
    print(json.dumps({**counts, 'uniquePackages': len(retained_versions(args.root))}))


if __name__ == '__main__':
    main()
