#!/usr/bin/env python3
"""Release version choice, signing setup and the verified, staged APK."""
import argparse
import base64
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from publish_android_release import publish

PROJECT = Path(__file__).resolve().parent.parent
CERT = 'f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843'
# Covers archived packages plus the latest delivered developer trial.
LOCAL_VERSION_FLOOR = 10267


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True).strip()


def repository():
    value = os.environ['GITHUB_REPOSITORY']
    if value != 'qiHuang112/ai_music':
        raise RuntimeError('Release publication is restricted to qiHuang112/ai_music')
    return value


def current_main(repo, commit):
    return gh('api', f'repos/{repo}/git/ref/heads/main', '--jq', '.object.sha') == commit


def choose_version(source, releases):
    name, number = re.search(r'^version:\s*([\w.\-]+)\+(\d+)\s*$', source, re.M).groups()
    codes = [LOCAL_VERSION_FLOOR, int(number) + 2000]
    for release in releases:
        match = re.fullmatch(r'v[\w.\-]+-(\d+)', release['tag_name'])
        if match:
            codes.append(int(match[1]))
    code = max(codes) + 1
    if code > 2100000000:
        raise ValueError('Android versionCode limit reached')
    return {'name': name, 'number': code - 2000, 'code': code, 'tag': f'v{name}-{code}'}


def planned_version():
    """The version the plan job chose, handed to each platform job."""
    return {'name': os.environ['RELEASE_NAME'], 'code': int(os.environ['RELEASE_CODE']),
            'tag': os.environ['RELEASE_TAG']}


def stage_dir(platform):
    root = PROJECT / f'build/release-stage/stage-{platform}'
    if root.exists():
        for path in root.iterdir():
            path.unlink()
    root.mkdir(parents=True, exist_ok=True)
    return root


def signing():
    required = ['KEYSTORE_BASE64', 'AI_MUSIC_KEYALIAS', 'AI_MUSIC_KEYPASSWORD', 'AI_MUSIC_STOREPASSWORD']
    if any(not os.environ.get(key) for key in required):
        raise RuntimeError('Configure the four ANDROID signing secrets before running this workflow')
    data = base64.b64decode(os.environ['KEYSTORE_BASE64'], validate=True)
    destination = Path(os.environ['RUNNER_TEMP']) / 'ai-music-release.jks'
    # Restrict permissions before writing any private-key bytes.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'wb') as output:
        output.write(data)


def stage():
    """Verify the signed APK and stage it with its manifest for publication."""
    repo, commit = repository(), os.environ['GITHUB_SHA']
    version = planned_version()
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools/35.0.0'
    root = PROJECT / 'build/github-release'
    notes = subprocess.check_output(['git', 'log', '-1', '--format=%s'], text=True).strip()
    manifest = publish(PROJECT / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
                       root, str(tools / 'aapt'), str(tools / 'apksigner'), notes,
                       release_cert=CERT, source_commit=commit)
    if manifest['versionCode'] != version['code'] or manifest['versionName'] != version['name']:
        raise RuntimeError('Built APK version differs from planned release')
    apk = root / Path(manifest['url']).name
    manifest['url'] = f"https://github.com/{repo}/releases/download/{version['tag']}/{apk.name}"
    out = stage_dir('android')
    shutil.copy2(apk, out / apk.name)
    (out / 'latest.json').write_text(json.dumps(manifest, ensure_ascii=False))
    (out / (apk.name + '.sha256')).write_text(f"{manifest['sha256']}  {apk.name}\n")
    print(f"Staged Android {manifest['versionName']} ({manifest['versionCode']}) {manifest['sha256']}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['signing', 'stage'])
    command = parser.parse_args().command
    {'signing': signing, 'stage': stage}[command]()
