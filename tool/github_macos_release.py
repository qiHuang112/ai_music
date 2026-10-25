#!/usr/bin/env python3
"""Attach a verified Universal Mac app to the same commit's Android release."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

from github_android_release import current_main, gh, repository

PROJECT = Path(__file__).resolve().parent.parent
BUNDLE = 'com.qi.ai.music.mac'


def select_release(releases, commit):
    matches = [item for item in releases
               if not item['draft'] and not item['prerelease']
               and f'源码提交：{commit}' in (item.get('body') or '')]
    if not matches:
        raise ValueError('No published Android release for this source commit')
    item = max(matches, key=lambda item: item.get('published_at') or '')
    match = re.fullmatch(r'v([\w.\-]+)-(\d+)', item['tag_name'])
    if not match:
        raise ValueError('Unexpected shared release tag')
    names = {asset['name'] for asset in item.get('assets', [])}
    complete = (f'Mac 源码提交：{commit}' in (item.get('body') or '')
                and 'macos-latest.json' in names
                and any(name.startswith('ai-music-macos-') and name.endswith('.zip')
                        and name + '.sha256' in names for name in names))
    return {'skip': 'true' if complete else 'false', 'name': match[1],
            'code': int(match[2]), 'tag': item['tag_name']}


def plan():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    if not current_main(repo, commit):
        version = {'skip': 'true'}
    else:
        pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100',
                              '--paginate', '--slurp'))
        version = select_release([item for page in pages for item in page], commit)
        # Android adds an ABI offset to Flutter's build number. The Mac uses
        # the final displayed Android versionCode, not that pre-offset number.
        with tempfile.TemporaryDirectory() as temporary:
            gh('release', 'download', version['tag'], '--repo', repo,
               '--pattern', 'latest.json', '--dir', temporary)
            android = json.loads((Path(temporary) / 'latest.json').read_text())
        if (android.get('sourceCommit') != commit
                or android.get('versionName') != version['name']
                or android.get('versionCode') != version['code']):
            raise ValueError('Android manifest does not match this commit/version')
    (PROJECT / 'build').mkdir(exist_ok=True)
    (PROJECT / 'build/github-macos-plan.json').write_text(json.dumps(version))
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in version.items():
            output.write(f'{key}={value}\n')
    print(f'Mac plan: {version}')


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


def publish_release():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    if not current_main(repo, commit):
        print('Main changed; leave published assets untouched')
        return
    version = json.loads((PROJECT / 'build/github-macos-plan.json').read_text())
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
    # Hash-named archives are retained on retries. Only the Mac metadata
    # pointer is replaced; Android latest.json and older packages stay intact.
    existing = json.loads(gh('release', 'view', version['tag'], '--repo', repo,
                            '--json', 'assets,body'))
    names = {item['name'] for item in existing['assets']}
    new_files = [str(path) for path in (archive, checksum) if path.name not in names]
    if new_files:
        gh('release', 'upload', version['tag'], *new_files, '--repo', repo)
    gh('release', 'upload', version['tag'], str(metadata), '--repo', repo, '--clobber')
    with tempfile.TemporaryDirectory() as temporary:
        gh('release', 'download', version['tag'], '--repo', repo, '--dir', temporary,
           '--pattern', filename, '--pattern', checksum.name, '--pattern', metadata.name)
        verify_download(Path(temporary), manifest, filename)
    body = existing['body'].split('\n<!-- macos-release -->')[0]
    body += (f"\n<!-- macos-release -->\n\n### Mac {version['name']}（{version['code']}）\n\n"
             f"Universal：支持 Apple Silicon 和 Intel。\n\n[下载 Mac ZIP]({manifest['url']})\n\n"
             '解压后将来听.app拖入应用程序；沿用原有歌单和设置。\n\n'
             '采用 ad-hoc 本地签名，尚未进行 Developer ID 签名／Apple 公证。\n\n'
             f'Mac 源码提交：{commit}\n\nMac ZIP SHA-256：{digest}\n')
    notes = root / 'release-notes.md'
    notes.write_text(body)
    gh('release', 'edit', version['tag'], '--repo', repo, '--title',
       f"来听 {version['name']}（{version['code']}）· Android / Mac", '--notes-file', str(notes))
    print(f"Published Mac: {manifest['url']}")
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as output:
            output.write(f"[下载 Mac Universal ZIP]({manifest['url']})\n")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'publish'])
    {'plan': plan, 'publish': publish_release}[parser.parse_args().command]()
