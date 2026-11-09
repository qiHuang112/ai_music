#!/usr/bin/env python3
"""Verify the device app and stage an unsigned IPA for user-side signing."""
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from github_android_release import planned_version, repository, stage_dir

PROJECT = Path(__file__).resolve().parent.parent


def stage():
    """Verify the device app and stage the unsigned IPA for publication."""
    repo, commit = repository(), os.environ['GITHUB_SHA']
    version = planned_version()
    app = PROJECT / 'build/ios/iphoneos/Runner.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'com.tjs.aimusic'
            or info.get('CFBundleShortVersionString') != version['name']
            or str(info.get('CFBundleVersion')) != str(version['code'])):
        raise ValueError('iOS bundle identity/version mismatch')
    arches = subprocess.check_output(
        ['lipo', '-archs', str(app / info['CFBundleExecutable'])], text=True).split()
    if arches != ['arm64']:
        raise ValueError('Expected device arm64 executable')
    root = PROJECT / 'build/ios/ipa'
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        payload = Path(temporary) / 'Payload'
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        # Remove any residual local signatures/profiles before redistribution.
        for path in sorted(payload.rglob('_CodeSignature'), reverse=True):
            shutil.rmtree(path)
        for path in payload.rglob('embedded.mobileprovision'):
            path.unlink()
        archive = root / 'unsigned.ipa'
        archive.unlink(missing_ok=True)
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(payload),
                        str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    filename = f"ai-music-ios-{version['name']}-{version['code']}-unsigned-{digest[:12]}.ipa"
    archive = archive.rename(root / filename)
    checksum = root / (filename + '.sha256')
    checksum.write_text(f'{digest}  {filename}\n')
    metadata = root / 'ios-unsigned.json'
    metadata.write_text(json.dumps({
        'platform': 'ios', 'signing': 'unsigned', 'requiresResigning': True,
        'packageName': 'com.tjs.aimusic', 'versionName': version['name'],
        'versionCode': version['code'], 'sourceCommit': commit,
        'sha256': digest, 'sizeBytes': archive.stat().st_size,
        'url': f"https://github.com/{repo}/releases/download/{version['tag']}/{filename}",
    }, indent=2) + '\n')
    out = stage_dir('ios')
    for path in (archive, checksum, metadata):
        shutil.copy2(path, out / path.name)
    if hashlib.sha256((out / filename).read_bytes()).hexdigest() != digest:
        raise ValueError('Staged IPA differs from the package')
    print(f"Staged iOS {version['name']} ({version['code']}) {digest}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['stage'])
    {'stage': stage}[parser.parse_args().command]()
