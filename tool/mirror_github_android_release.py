#!/usr/bin/env python3
"""Mirror a verified CI release into the LAN archive without rebuilding it."""
import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import tempfile
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

from android_release_archive import retain_manifest
from publish_android_release import publish

GITHUB = 'https://github.com/qiHuang112/ai_music'
CERT = 'f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843'
ASSET_HOSTS = {'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}


def asset_url(url):
    value = urlsplit(url)
    return (value.scheme == 'https' and value.hostname in ASSET_HOSTS and
            value.port in (None, 443) and not value.username and not value.password and not value.fragment)


class AssetRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        if not asset_url(new_url):
            raise ValueError('Unexpected GitHub asset redirect')
        return super().redirect_request(request, response, code, message, headers, new_url)


def open_asset(url):
    if not asset_url(url):
        raise ValueError('Expected an official GitHub HTTPS asset')
    return urllib.request.build_opener(AssetRedirects()).open(
        urllib.request.Request(url, headers={'User-Agent': 'ai-music-lan-mirror'}), timeout=30)


def read_manifest():
    with open_asset(GITHUB + '/releases/latest/download/latest.json') as response:
        data = response.read(64 * 1024 + 1)
    if len(data) > 64 * 1024:
        raise ValueError('Release metadata is too large')
    manifest = json.loads(data)
    url = manifest.get('url', '')
    if (manifest.get('packageName') != 'com.qi.ai.music' or manifest.get('channel') != 'release' or
            manifest.get('abi') != 'arm64-v8a' or type(manifest.get('versionCode')) is not int or
            manifest['versionCode'] < 1 or type(manifest.get('sizeBytes')) is not int or
            not 0 < manifest['sizeBytes'] <= 500 * 1024 * 1024 or
            not re.fullmatch(r'[a-f0-9]{64}', manifest.get('sha256', '')) or
            not url.startswith(GITHUB + '/releases/download/') or not url.endswith('.apk') or
            not asset_url(url)):
        raise ValueError('Invalid CI release metadata')
    return manifest


def mirror(root: Path, aapt: str, apksigner: str):
    remote = read_manifest()
    root.mkdir(parents=True, exist_ok=True)
    pointer = root / 'latest.json'
    previous = json.loads(pointer.read_text()) if pointer.exists() else None
    if previous and previous['versionCode'] > remote['versionCode']:
        return previous
    if previous and previous['versionCode'] == remote['versionCode']:
        if previous['sha256'] != remote['sha256']:
            raise ValueError('Published version changed its APK bytes')
        local = root / Path(previous['url']).name
        if local.is_file() and hashlib.sha256(local.read_bytes()).hexdigest() == remote['sha256']:
            return previous
    with tempfile.TemporaryDirectory(prefix='.github-mirror-', dir=root) as temporary:
        stage = Path(temporary)
        apk = stage / 'download.apk'
        digest = hashlib.sha256()
        size = 0
        with open_asset(remote['url']) as response, apk.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > remote['sizeBytes']:
                    raise ValueError('APK exceeds declared size')
                digest.update(chunk)
                output.write(chunk)
        if size != remote['sizeBytes'] or digest.hexdigest() != remote['sha256']:
            raise ValueError('APK size or SHA-256 mismatch')
        verified = publish(apk, stage / 'verified', aapt, apksigner,
                           remote.get('notes', ''), release_cert=CERT,
                           source_commit=remote.get('sourceCommit', ''))
        for key in ('packageName', 'versionName', 'versionCode', 'channel', 'abi', 'sizeBytes', 'sha256'):
            if verified[key] != remote[key]:
                raise ValueError(f'CI metadata differs from verified APK: {key}')
        # Downloads may overlap. Serialize only the final commit and recheck
        # the live pointer, so a slower old download cannot undo a newer one.
        with (root / '.github-mirror.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            current = json.loads(pointer.read_text()) if pointer.exists() else None
            if current and current['versionCode'] > remote['versionCode']:
                return current
            if current and current['versionCode'] == remote['versionCode']:
                if current['sha256'] != remote['sha256']:
                    raise ValueError('Published version changed its APK bytes')
                local = root / Path(current['url']).name
                if local.is_file() and hashlib.sha256(local.read_bytes()).hexdigest() == remote['sha256']:
                    return current
            # Install immutable bytes before exposing the LAN download URL.
            name = Path(verified['url']).name
            shutil.copyfile(apk, stage / name)
            os.replace(stage / name, root / name)
            if current:
                retain_manifest(root, current)
            retain_manifest(root, verified)
            manifest_file = stage / 'latest.json'
            with manifest_file.open('w') as output:
                json.dump(verified, output, ensure_ascii=False)
                output.flush()
                os.fsync(output.fileno())
            os.replace(manifest_file, pointer)
    return verified


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--apksigner', required=True)
    args = parser.parse_args()
    result = mirror(args.root, args.aapt, args.apksigner)
    print(f"LAN release {result['versionName']} ({result['versionCode']}) · {result['sha256']}")
