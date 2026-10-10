#!/usr/bin/env python3
"""Push main to trigger GitHub CI; retain explicit local LAN delivery support."""
import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import urllib.request
from pathlib import Path

from android_release_archive import retained_versions
from publish_android_release import publish

PROJECT = Path(__file__).resolve().parent.parent
ARCHIVE = Path('/Users/huangqi/AIHome/releases/ai_music/android')
FLUTTER = '/Users/huangqi/AIHome/tools/flutter/bin/flutter'
CERT = 'f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843'
SERVER = 'http://192.168.31.167:8788'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=PROJECT, text=True).strip()


def require_clean(commit=None):
    if git('status', '--porcelain'):
        raise RuntimeError('Commit all workspace changes before publishing')
    if git('branch', '--show-current') != 'main':
        raise RuntimeError('Publish only from main')
    head = git('rev-parse', 'HEAD')
    if commit is not None and head != commit:
        raise RuntimeError('HEAD changed during release build; nothing published')
    return head


def next_version(root):
    records = retained_versions(root)
    actual_code = max([2000] + [r['versionCode'] for r in records]) + 1
    # The source declares the release name; latest may still be the previous
    # minor version while a reviewed version bump is being published.
    name = re.search(r'^version:\s*([^+\s]+)', (PROJECT / 'pubspec.yaml').read_text(), re.M)[1]
    # Flutter's split-per-ABI arm64 APK adds 2000 to the build number.
    return name, actual_code - 2000


def verify_http(manifest, server):
    with urllib.request.urlopen(server + '/api/v1/update/android', timeout=15) as response:
        current = json.load(response)
    if current['sha256'] != manifest['sha256'] or current['versionCode'] != manifest['versionCode']:
        raise RuntimeError('LAN service is not serving the published release')
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(server + manifest['url'], timeout=30) as response:
        for chunk in iter(lambda: response.read(1024 * 1024), b''):
            size += len(chunk)
            digest.update(chunk)
    if size != manifest['sizeBytes'] or digest.hexdigest() != manifest['sha256']:
        raise RuntimeError('LAN APK download failed size/hash verification')


def push_and_publish(root=ARCHIVE, server=SERVER, publish_only=False):
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.push-publish.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        commit = require_clean()
        if not publish_only:
            subprocess.run(['git', 'push', 'origin', 'main'], cwd=PROJECT, check=True)
        remote = git('ls-remote', 'origin', 'refs/heads/main').split()[0]
        if remote != commit:
            raise RuntimeError('Remote main differs from HEAD; nothing published')
        latest = root / 'latest.json'
        if latest.exists():
            previous = json.loads(latest.read_text())
            if previous.get('sourceCommit') == commit:
                verify_http(previous, server)
                print(f"Already published {previous['versionName']} ({previous['versionCode']})")
                return previous
        signing = PROJECT / 'android/key.properties'
        if not signing.exists() and not all(os.environ.get('AI_MUSIC_' + key) for key in
                                           ['STOREFILE', 'KEYALIAS', 'KEYPASSWORD', 'STOREPASSWORD']):
            raise RuntimeError('Local release signing configuration is missing')
        sdk = Path(os.environ.get('ANDROID_HOME', '/Users/huangqi/Library/Android/sdk'))
        versions = sorted((sdk / 'build-tools').iterdir(), key=lambda p: tuple(int(v) for v in p.name.split('.') if v.isdigit()))
        tools = next(p for p in reversed(versions) if (p / 'aapt').exists() and (p / 'apksigner').exists())
        name, number = next_version(root)
        build_env = os.environ.copy()
        build_env.setdefault('JAVA_HOME', '/Users/huangqi/Library/Java/JavaVirtualMachines/openjdk-22.0.1/Contents/Home')
        build_env.setdefault('ANDROID_HOME', str(sdk))
        subprocess.run([FLUTTER, 'build', 'apk', '--release', '--no-pub',
                        '--target-platform', 'android-arm64', '--split-per-abi',
                        '--build-name', name, '--build-number', str(number)], cwd=PROJECT, env=build_env, check=True)
        require_clean(commit)
        if git('ls-remote', 'origin', 'refs/heads/main').split()[0] != commit:
            raise RuntimeError('Remote main changed during build; nothing published')
        apk = PROJECT / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
        result = publish(apk, root, str(tools / 'aapt'), str(tools / 'apksigner'),
                         git('log', '-1', '--format=%s'), release_cert=CERT, source_commit=commit)
        verify_http(result, server)
        print(f"Published {result['versionName']} ({result['versionCode']}) at {server} · {commit[:7]}")
        return result


def push_for_ci(publish_only=False):
    # CI reads committed remote bytes, so unrelated developer edits need not
    # block pushing this commit. Local LAN builds still require a clean tree.
    if git('branch', '--show-current') != 'main':
        raise RuntimeError('Publish only from main')
    commit = git('rev-parse', 'HEAD')
    if not publish_only:
        subprocess.run(['git', 'push', 'origin', 'main'], cwd=PROJECT, check=True)
    if git('ls-remote', 'origin', 'refs/heads/main').split()[0] != commit:
        raise RuntimeError('Remote main differs from HEAD')
    if publish_only:
        subprocess.run(['gh', 'workflow', 'run', 'android-release.yml', '--ref', 'main',
                        '--repo', 'qiHuang112/ai_music'], cwd=PROJECT, check=True)
    print(f'Pushed {commit[:7]}; GitHub Actions handles signed release publication')
    print('https://github.com/qiHuang112/ai_music/actions/workflows/android-release.yml')
    return commit


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish-only', action='store_true', help='Retry publication of an already pushed, clean HEAD')
    parser.add_argument('--lan', action='store_true', help='Explicitly build on this Mac and publish to the legacy LAN service')
    parser.add_argument('--root', type=Path, default=ARCHIVE)
    parser.add_argument('--server', default=SERVER)
    args = parser.parse_args()
    if args.lan:
        push_and_publish(args.root, args.server.rstrip('/'), args.publish_only)
    else:
        push_for_ci(args.publish_only)
