#!/usr/bin/env python3
"""Mirror a verified CI release into the LAN archive without rebuilding it."""
import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

from android_release_archive import retain_manifest
from publish_android_release import publish

GITHUB = 'https://github.com/qiHuang112/ai_music'
CERT = 'f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843'
ASSET_HOSTS = {'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}
REPOSITORY_API = 'repos/qiHuang112/ai_music'


def github_cli():
    # launchd's default PATH does not include Homebrew. Credentials stay in gh's
    # existing user/keychain configuration, never in the APP or service plist.
    for executable in (shutil.which('gh'), '/opt/homebrew/bin/gh', '/usr/local/bin/gh'):
        if executable and Path(executable).is_file():
            return executable
    raise RuntimeError('GitHub CLI is required to mirror private releases')


def github_api(endpoint, output, *, binary=False):
    args = [github_cli(), 'api', '--hostname', 'github.com', endpoint]
    if binary:
        args.extend(['-H', 'Accept: application/octet-stream'])
    result = subprocess.run(args, stdout=output, stderr=subprocess.PIPE,
                            timeout=600 if binary else 60)
    if result.returncode:
        raise RuntimeError(f'Authenticated GitHub download failed (gh exit {result.returncode})')
    output.seek(0)


def open_private_asset(url):
    value = urlsplit(url)
    prefix = '/qiHuang112/ai_music/releases/'
    if (not asset_url(url) or value.hostname != 'github.com' or value.query or
            not value.path.startswith(prefix)):
        raise ValueError('Private downloads must belong to qiHuang112/ai_music')
    path = value.path[len(prefix):]
    if path == 'latest/download/latest.json':
        endpoint, name = f'{REPOSITORY_API}/releases/latest', 'latest.json'
    else:
        parts = path.split('/')
        if len(parts) != 3 or parts[0] != 'download':
            raise ValueError('Unexpected private release asset URL')
        tag, name = unquote(parts[1]), unquote(parts[2])
        if not tag or not name or any(c in name for c in '/\\\x00'):
            raise ValueError('Invalid private release asset name')
        endpoint = f'{REPOSITORY_API}/releases/tags/{quote(tag, safe="")}'
    with tempfile.TemporaryFile() as metadata:
        github_api(endpoint, metadata)
        release = json.load(metadata)
    assets = [asset for asset in release.get('assets', []) if asset.get('name') == name]
    if len(assets) != 1 or release.get('draft') or release.get('prerelease'):
        raise ValueError('Expected one published GitHub release asset')
    asset = assets[0]
    limit = 64 * 1024 if name == 'latest.json' else 500 * 1024 * 1024
    if (type(asset.get('id')) is not int or asset['id'] < 1 or
            type(asset.get('size')) is not int or not 0 < asset['size'] <= limit):
        raise ValueError('Invalid private release asset metadata')
    output = tempfile.TemporaryFile()
    try:
        github_api(f"{REPOSITORY_API}/releases/assets/{asset['id']}", output, binary=True)
        if os.fstat(output.fileno()).st_size != asset['size']:
            raise ValueError('Private release asset size mismatch')
        return output
    except BaseException:
        output.close()
        raise


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
    output = tempfile.TemporaryFile()
    try:
        with urllib.request.build_opener(AssetRedirects()).open(
                urllib.request.Request(url, headers={'User-Agent': 'ai-music-lan-mirror'}),
                timeout=30) as response:
            shutil.copyfileobj(response, output, 1024 * 1024)
        output.seek(0)
        return output
    except urllib.error.HTTPError as error:
        output.close()
        error.close()
        if error.code not in (401, 404) and error.code < 500:
            raise
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        # github.com/.../releases/download can time out from this Mac while
        # the GitHub API that gh uses still works; fall back to gh.
        output.close()
    except BaseException:
        output.close()
        raise
    return open_private_asset(url)


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
