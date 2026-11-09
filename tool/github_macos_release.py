#!/usr/bin/env python3
"""Verify the Universal Mac app and stage it for the shared GitHub Release."""
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

from github_android_release import planned_version, repository, stage_dir

PROJECT = Path(__file__).resolve().parent.parent
BUNDLE = 'com.qi.ai.music.mac'


def validate_info(info, version):
    if (info.get('CFBundleIdentifier') != BUNDLE
            or info.get('CFBundleName') != '来听'
            or info.get('CFBundleShortVersionString') != version['name']
            or str(info.get('CFBundleVersion')) != str(version['code'])):
        raise ValueError('Mac bundle identity/version differs from the release')


def validate_entitlements(entitlements):
    if (entitlements.get('com.apple.security.get-task-allow')
            or not entitlements.get('com.apple.security.app-sandbox')):
        raise ValueError('Expected sandboxed release without debugger entitlement')


def verify_download(directory, manifest, filename):
    archive = directory / filename
    if (archive.stat().st_size != manifest['sizeBytes']
            or hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['sha256']):
        raise ValueError('Uploaded Mac ZIP size/hash mismatch')
    if json.loads((directory / 'macos-latest.json').read_text()) != manifest:
        raise ValueError('Uploaded Mac manifest mismatch')
    expected = f"{manifest['sha256']}  {filename}\n"
    if (directory / (filename + '.sha256')).read_text() != expected:
        raise ValueError('Uploaded Mac checksum mismatch')


def stage():
    """Verify the Universal app and stage its ZIP and manifest for publication."""
    repo, commit = repository(), os.environ['GITHUB_SHA']
    version = planned_version()
    app = PROJECT / 'build/macos/Build/Products/Release/来听.app'
    validate_info(plistlib.loads((app / 'Contents/Info.plist').read_bytes()), version)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    entitlements = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)])
    validate_entitlements(plistlib.loads(entitlements))
    # Validate the executable and every bundled framework, including Dart
    # native assets; a universal launcher around a single-arch framework fails.
    binaries = [app / 'Contents/MacOS/来听']
    binaries += [framework / framework.stem
                 for framework in (app / 'Contents/Frameworks').glob('*.framework')]
    for binary in binaries:
        arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        if not {'arm64', 'x86_64'}.issubset(arches):
            raise ValueError(f'Missing Universal architecture: {binary.name}')
    root = PROJECT / 'build/github-macos-release'
    root.mkdir(exist_ok=True)
    archive = root / 'macos.zip'
    if archive.exists():
        archive.unlink()  # ditto appends to an existing ZIP; start a fresh stage.
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                    str(app), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    filename = f"ai-music-macos-{version['name']}-{version['code']}-universal-{digest[:12]}.zip"
    archive = archive.rename(root / filename)
    manifest = {
        'platform': 'macos', 'packageName': BUNDLE, 'channel': 'release',
        'versionName': version['name'], 'versionCode': version['code'],
        'abi': 'universal', 'architectures': ['arm64', 'x86_64'],
        'sizeBytes': archive.stat().st_size, 'sha256': digest, 'sourceCommit': commit,
        'url': f"https://github.com/{repo}/releases/download/{version['tag']}/{filename}",
        'signing': 'ad-hoc', 'notarized': False,
    }
    metadata = root / 'macos-latest.json'
    metadata.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    checksum = root / (filename + '.sha256')
    checksum.write_text(f'{digest}  {filename}\n')
    out = stage_dir('macos')
    for path in (archive, checksum, metadata):
        shutil.copy2(path, out / path.name)
    verify_download(out, manifest, filename)
    print(f"Staged Mac {version['name']} ({version['code']}) {digest}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['stage'])
    {'stage': stage}[parser.parse_args().command]()
