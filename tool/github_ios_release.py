#!/usr/bin/env python3
"""Build metadata and publish an unsigned IPA for user-side signing."""
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from github_android_release import current_main, gh, repository
from github_macos_release import select_release

PROJECT = Path(__file__).resolve().parent.parent
PLAN = PROJECT / 'build/github-ios-plan.json'


def plan():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    version = {'skip': 'true'}
    if current_main(repo, commit):
        pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100',
                              '--paginate', '--slurp'))
        releases = [item for page in pages for item in page]
        version = select_release(releases, commit)
        with tempfile.TemporaryDirectory() as temporary:
            gh('release', 'download', version['tag'], '--repo', repo,
               '--pattern', 'latest.json', '--dir', temporary)
            android = json.loads((Path(temporary) / 'latest.json').read_text())
        if (android.get('sourceCommit') != commit
                or android.get('versionName') != version['name']
                or android.get('versionCode') != version['code']):
            raise ValueError('Android release does not match source/version')
        release = next(item for item in releases if item['tag_name'] == version['tag'])
        # Never use the Mac completion flag to skip the iOS build.
        version['skip'] = 'true' if any(
            asset['name'] == 'ios-unsigned.json'
            for asset in release.get('assets', [])) else 'false'
    PLAN.parent.mkdir(exist_ok=True)
    PLAN.write_text(json.dumps(version))
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in version.items():
            output.write(f'{key}={value}\n')


def publish():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    if not current_main(repo, commit):
        return
    version = json.loads(PLAN.read_text())
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
    existing = json.loads(gh('release', 'view', version['tag'], '--repo', repo,
                            '--json', 'assets'))
    names = {asset['name'] for asset in existing['assets']}
    pending = [str(path) for path in (archive, checksum) if path.name not in names]
    if pending:
        gh('release', 'upload', version['tag'], *pending, '--repo', repo)
    with tempfile.TemporaryDirectory() as temporary:
        gh('release', 'download', version['tag'], '--repo', repo, '--dir', temporary,
           '--pattern', filename, '--pattern', checksum.name)
        if (hashlib.sha256((Path(temporary) / filename).read_bytes()).hexdigest() != digest
                or (Path(temporary) / checksum.name).read_text() != checksum.read_text()):
            raise ValueError('Uploaded IPA/checksum mismatch')
    # Completion marker is published only after full package download verification.
    gh('release', 'upload', version['tag'], str(metadata), '--repo', repo, '--clobber')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as output:
            output.write(f'IPA (unsigned; requires AltStore/SideStore/Sideloadly signing): {filename}\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'publish'])
    {'plan': plan, 'publish': publish}[parser.parse_args().command]()
