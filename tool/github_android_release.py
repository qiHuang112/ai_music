#!/usr/bin/env python3
"""Build planning and verified, atomic GitHub Release delivery for Actions."""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

from publish_android_release import publish

PROJECT = Path(__file__).resolve().parent.parent
CERT = 'f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843'
# Covers archived packages plus developer's allocated debug trial 10198.
LOCAL_VERSION_FLOOR = 10198


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


def plan():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    if not current_main(repo, commit):
        result = {'skip': 'true'}
    else:
        pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp'))
        releases = [release for page in pages for release in page]
        # A rerun of a completed delivery must not mint another APK version.
        published = [release for release in releases if not release['draft'] and not release['prerelease']]
        latest = max(published, key=lambda release: release.get('published_at') or '', default={})
        delivered = f'源码提交：{commit}' in (latest.get('body') or '')
        result = {'skip': 'true'} if delivered else {
            'skip': 'false', **choose_version((PROJECT / 'pubspec.yaml').read_text(), releases)}
    (PROJECT / 'build').mkdir(exist_ok=True)
    (PROJECT / 'build/github-release-plan.json').write_text(json.dumps(result))
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in result.items():
            output.write(f'{key}={value}\n')
    print('Skip completed/superseded commit' if result['skip'] == 'true' else f"Planned {result['tag']}")


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


def publish_release():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    if not current_main(repo, commit):
        print('Main changed during build; leave latest release untouched')
        return
    version = json.loads((PROJECT / 'build/github-release-plan.json').read_text())
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
    (root / 'latest.json').write_text(json.dumps(manifest, ensure_ascii=False))
    checksum = root / (apk.name + '.sha256')
    checksum.write_text(f"{manifest['sha256']}  {apk.name}\n")
    description = root / 'release-notes.md'
    description.write_text(
        f"Android arm64-v8a 正式签名包，版本 {manifest['versionName']} / {manifest['versionCode']}。\n\n"
        f"{notes}\n\n源码提交：{commit}\n\nAPK SHA-256：{manifest['sha256']}\n")
    # Keep the release invisible to latest until every asset has been uploaded and read back.
    gh('release', 'create', version['tag'], str(apk), str(root / 'latest.json'), str(checksum),
       '--repo', repo, '--draft', '--target', commit, '--title',
       f"来听 Android {manifest['versionName']}（{manifest['versionCode']}）", '--notes-file', str(description))
    with tempfile.TemporaryDirectory() as temporary:
        gh('release', 'download', version['tag'], '--repo', repo, '--dir', temporary)
        downloaded = Path(temporary) / apk.name
        if downloaded.stat().st_size != manifest['sizeBytes'] or hashlib.sha256(downloaded.read_bytes()).hexdigest() != manifest['sha256']:
            raise RuntimeError('Uploaded APK size/hash mismatch; release remains a draft')
        if json.loads((Path(temporary) / 'latest.json').read_text()) != manifest:
            raise RuntimeError('Uploaded update manifest mismatch; release remains a draft')
    if not current_main(repo, commit):
        print('Main changed during upload; keep draft and leave latest release untouched')
        return
    gh('release', 'edit', version['tag'], '--repo', repo, '--draft=false', '--latest')
    url = f"https://github.com/{repo}/releases/tag/{version['tag']}"
    print(f'Published {url}')
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with Path(summary).open('a') as output:
            output.write(f"[下载签名 APK]({manifest['url']}) · [Release]({url})\n")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'signing', 'publish'])
    command = parser.parse_args().command
    {'plan': plan, 'signing': signing, 'publish': publish_release}[command]()
