#!/usr/bin/env python3
"""Plan and publish one GitHub Release whose platforms are built in parallel.

plan:    gate on this commit's passing Check, pick the version, choose the
         platforms to build (only those the change can affect, unless asked).
publish: gather the verified packages the platform jobs staged, carry the
         previous release's update manifests forward for platforms not built,
         upload everything to a draft, read it all back, then make it latest.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

from github_android_release import PROJECT, choose_version, current_main, gh, repository

PLATFORMS = ('android', 'macos', 'ios')
LABELS = {'android': 'Android', 'macos': 'Mac', 'ios': 'iOS'}
# The update manifest each platform publishes. Android's is what the app and
# the LAN mirror read from the latest release, so a release always carries one.
MANIFESTS = {'android': 'latest.json', 'macos': 'macos-latest.json', 'ios': 'ios-unsigned.json'}
STAGE = PROJECT / 'build/release-stage'
# Paths no package is built from: documentation, tests, tooling and CI, and
# targets this workflow does not build.
INERT = ('docs/', '.github/', '.agents/', 'tool/', 'test/', 'test_render/', 'tmp/',
         'branding/', 'ohos/', 'linux/', 'windows/', 'web/')
INERT_FILES = {'analysis_options.yaml', 'ai_music.iml', '.gitignore', '.metadata'}
CHECK_WAIT = 25 * 60


def git(*args):
    return subprocess.check_output(['git', *args], text=True, cwd=PROJECT).strip()


def platforms_for(paths):
    """The platforms a set of changed paths can affect."""
    affected = set()
    for path in paths:
        if path.endswith('.md') or path.startswith(INERT) or path in INERT_FILES:
            continue
        top = path.split('/', 1)[0]
        if top in PLATFORMS:
            affected.add(top)
        else:
            return set(PLATFORMS)  # Shared code, assets or dependencies.
    return affected


def requested_platforms(value):
    value = (value or 'auto').strip().lower()
    if value in ('auto', 'all'):
        return value
    chosen = {item.strip() for item in re.split(r'[,+\s]+', value) if item.strip()}
    unknown = chosen - set(PLATFORMS)
    if not chosen or unknown:
        raise ValueError(f'Unknown platforms: {value!r}; use auto, all or android,macos,ios')
    return chosen


def is_docs_only(paths):
    # Mirrors ci.yml's paths-ignore: such pushes get no Check run of their own.
    return all(path.startswith('docs/') or path.endswith('.md') for path in paths)


def is_ancestor(older, newer):
    return subprocess.run(['git', 'merge-base', '--is-ancestor', older, newer],
                          cwd=PROJECT).returncode == 0


def check_runs(repo, commit):
    data = json.loads(gh('api', f'repos/{repo}/actions/workflows/ci.yml/runs'
                                f'?head_sha={commit}&per_page=20'))
    return data.get('workflow_runs', [])


def await_check(repo, commit, sleep=time.sleep, clock=time.monotonic):
    """Release only what Check passed, without running the tests a second time.

    A Check still running for this commit is waited for. A docs-only commit has
    none of its own; the nearest passing ancestor stands in for it.
    """
    deadline = clock() + CHECK_WAIT
    while True:
        runs = check_runs(repo, commit)
        if any(run.get('conclusion') == 'success' for run in runs):
            return commit
        if any(run.get('status') != 'completed' for run in runs):
            if clock() > deadline:
                raise RuntimeError('Check for this commit is still running; release later')
            print('Waiting for this commit\'s Check to finish...')
            sleep(20)
            continue
        if runs:
            raise RuntimeError('Check failed for this commit; fix it before releasing')
        data = json.loads(gh('api', f'repos/{repo}/actions/workflows/ci.yml/runs'
                                    '?branch=main&status=success&per_page=50'))
        for run in data.get('workflow_runs', []):
            base = run['head_sha']
            if is_ancestor(base, commit):
                changed = git('diff', '--name-only', base, commit).splitlines()
                if is_docs_only(changed):
                    return base
                break
        raise RuntimeError('No passing Check covers this commit; push and let Check pass first')


def published(releases):
    return [item for item in releases if not item.get('draft') and not item.get('prerelease')]


def latest_release(releases):
    return max(published(releases), key=lambda item: item.get('published_at') or '', default=None)


def source_commit(release):
    match = re.search(r'^源码提交：([0-9a-f]{7,40})\s*$', (release or {}).get('body') or '', re.M)
    return match[1] if match else None


def choose_platforms(requested, previous_source, commit):
    if requested == 'all':
        return set(PLATFORMS), 'all requested'
    if requested != 'auto':
        return set(requested), 'requested'
    if not previous_source or not is_ancestor(previous_source, commit):
        return set(PLATFORMS), 'no earlier release to compare with'
    changed = git('diff', '--name-only', previous_source, commit).splitlines()
    return platforms_for(changed), f'changed since {previous_source[:7]}'


def write_outputs(result):
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in result.items():
            output.write(f'{key}={value}\n')


def plan():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    result = {'skip': 'true', **{name: 'false' for name in PLATFORMS}}
    if not current_main(repo, commit):
        print('Main has moved on; nothing to release for this commit')
        return write_outputs(result)
    requested = requested_platforms(os.environ.get('RELEASE_PLATFORMS'))
    checked = await_check(repo, commit)
    pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp'))
    releases = [item for page in pages for item in page]
    previous = latest_release(releases)
    previous_source = source_commit(previous)
    if previous_source == commit:
        print('This commit is already the latest release')
        return write_outputs(result)
    platforms, reason = choose_platforms(requested, previous_source, commit)
    if not platforms:
        print(f'Nothing to build ({reason}): only docs, tests or tooling changed')
        return write_outputs(result)
    version = choose_version((PROJECT / 'pubspec.yaml').read_text(), releases)
    result.update({'skip': 'false', 'name': version['name'], 'number': version['number'],
                   'code': version['code'], 'tag': version['tag'],
                   **{name: str(name in platforms).lower() for name in PLATFORMS}})
    write_outputs(result)
    print(f"Planned {version['tag']} for {', '.join(sorted(platforms))} ({reason}); "
          f'Check passed on {checked[:7]}')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def staged(platform, tag, commit, code):
    """A platform job's verified package, re-checked after the artifact hop."""
    root = STAGE / f'stage-{platform}'
    manifest = json.loads((root / MANIFESTS[platform]).read_text())
    package = root / Path(manifest['url']).name
    if (manifest.get('sourceCommit') != commit or manifest.get('versionCode') != code
            or not manifest['url'].endswith(f'/releases/download/{tag}/{package.name}')
            or package.stat().st_size != manifest['sizeBytes'] or sha256(package) != manifest['sha256']):
        raise ValueError(f'Staged {platform} package does not match its manifest')
    checksum = root / (package.name + '.sha256')
    if checksum.read_text() != f"{manifest['sha256']}  {package.name}\n":
        raise ValueError(f'Staged {platform} checksum mismatch')
    return manifest, [package, checksum, root / MANIFESTS[platform]]


def carried(repo, previous, platform, directory):
    """The previous release's manifest for a platform this release skips."""
    name = MANIFESTS[platform]
    if not previous or name not in {asset['name'] for asset in previous.get('assets', [])}:
        return None
    target = directory / platform
    target.mkdir(parents=True, exist_ok=True)
    gh('release', 'download', previous['tag_name'], '--repo', repo, '--pattern', name,
       '--dir', str(target))
    return json.loads((target / name).read_text()), target / name


def notes_for(name, code, commit, built, kept):
    lines = [f'来听 {name}（{code}）。', '']
    for platform in PLATFORMS:
        label = LABELS[platform]
        if platform in built:
            manifest = built[platform]
            text = {
                'android': 'arm64-v8a 正式签名 APK',
                'macos': 'Universal ZIP（Apple Silicon 与 Intel；ad-hoc 签名，未经 Apple 公证）',
                'ios': 'arm64 未签名 IPA（需自行重签安装）',
            }[platform]
            lines += [f"- {label}：{text}，{manifest['versionName']} / {manifest['versionCode']}，"
                      f"SHA-256 `{manifest['sha256']}`"]
        elif platform in kept:
            manifest = kept[platform]
            lines += [f"- {label}：本次无改动，沿用 {manifest['versionName']} / "
                      f"{manifest['versionCode']}（[下载]({manifest['url']})）"]
    subject = git('log', '-1', '--format=%s', commit)
    lines += ['', subject, '', f'源码提交：{commit}', '']
    return '\n'.join(lines)


def publish():
    repo, commit = repository(), os.environ['GITHUB_SHA']
    if not current_main(repo, commit):
        print('Main changed during the build; leave the latest release untouched')
        return
    tag, name, code = os.environ['RELEASE_TAG'], os.environ['RELEASE_NAME'], int(os.environ['RELEASE_CODE'])
    chosen = [platform for platform in PLATFORMS if os.environ.get(f'BUILD_{platform.upper()}') == 'true']
    built, files = {}, []
    for platform in chosen:
        manifest, paths = staged(platform, tag, commit, code)
        built[platform] = manifest
        files += paths
    pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp'))
    releases = [item for page in pages for item in page]
    previous = latest_release(releases)
    kept = {}
    with tempfile.TemporaryDirectory() as temporary:
        for platform in PLATFORMS:
            if platform in built:
                continue
            found = carried(repo, previous, platform, Path(temporary))
            if found:
                kept[platform], path = found
                files.append(path)
        if 'android' not in built and 'android' not in kept:
            raise RuntimeError('No Android update manifest to publish or carry forward')
        notes = Path(temporary) / 'notes.md'
        notes.write_text(notes_for(name, code, commit, built, kept))
        # A failed earlier attempt at this tag leaves a draft; start it over.
        for item in releases:
            if item['tag_name'] == tag:
                if not item.get('draft'):
                    raise RuntimeError(f'{tag} is already published')
                gh('release', 'delete', tag, '--repo', repo, '--yes')
        title = f"来听 {name}（{code}）· {' / '.join(LABELS[p] for p in chosen)}"
        # Invisible to "latest" until every file has been read back intact.
        gh('release', 'create', tag, *map(str, files), '--repo', repo, '--draft',
           '--target', commit, '--title', title, '--notes-file', str(notes))
        back = Path(temporary) / 'back'
        back.mkdir()
        gh('release', 'download', tag, '--repo', repo, '--dir', str(back))
        for path in files:
            if sha256(back / path.name) != sha256(path):
                raise RuntimeError(f'Uploaded {path.name} differs; release stays a draft')
    if not current_main(repo, commit):
        print('Main changed during upload; keep the draft and leave latest untouched')
        return
    gh('release', 'edit', tag, '--repo', repo, '--draft=false', '--latest')
    url = f'https://github.com/{repo}/releases/tag/{tag}'
    print(f'Published {url}')
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with Path(summary).open('a') as output:
            output.write(f"[Release {tag}]({url})：构建 {', '.join(LABELS[p] for p in chosen)}"
                         + (f"；沿用 {', '.join(LABELS[p] for p in kept)}" if kept else '') + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'publish'])
    {'plan': plan, 'publish': publish}[parser.parse_args().command]()
