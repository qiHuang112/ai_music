#!/usr/bin/env python3
"""Build a release APK for the development phone and install it, keeping data.

Self-test builds live in their own version-code range (60000 and up) so they
can never share a number with a formal release, which CI mints from the
GitHub Releases (10271, 10272, ...). They are re-signed with the local debug
certificate the development phone already uses; a formal release cannot be
installed over them, and they never enter a release channel.

    python3 tool/build_android_selftest.py --device 192.168.31.78:38015

The device's serial is checked before installing, so a changed wireless
address can never send the build to another phone.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'build/device-check/selftest'
RECORD = OUT / 'builds.json'
SELFTEST_FLOOR = 60000
# Flutter's split-per-ABI arm64 APK adds 2000 to the build number.
ABI_OFFSET = 2000
DEBUG_CERT = 'e0eda7c40b0f8d5b67a03d8c21803e21c10d32f2b399216cfd56f14a12bb375d'
PHONE_77_SERIAL = '6595e6a1'
PACKAGE = 'com.qi.ai.music'


def next_code(recorded, installed=None):
    """The next self-test version code: above the floor, every earlier
    self-test build and whatever the phone has installed now."""
    return max([SELFTEST_FLOOR - 1, installed or 0, *recorded]) + 1


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def adb(device, *args):
    return run('adb', '-s', device, *args)


def installed_code(device):
    dump = adb(device, 'shell', 'dumpsys', 'package', PACKAGE)
    match = re.search(r'versionCode=(\d+)', dump)
    return int(match[1]) if match else None


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--device', help='adb address of the development phone; omit to only build')
    parser.add_argument('--expect-serial', default=PHONE_77_SERIAL)
    args = parser.parse_args()

    sdk = Path(os.environ.get('ANDROID_HOME', '/Users/huangqi/Library/Android/sdk'))
    tools = sdk / 'build-tools/35.0.0'
    env = os.environ.copy()
    env.setdefault('ANDROID_HOME', str(sdk))
    env.setdefault('JAVA_HOME', '/Users/huangqi/Library/Java/JavaVirtualMachines/openjdk-22.0.1/Contents/Home')

    if args.device:
        serial = adb(args.device, 'shell', 'getprop', 'ro.serialno')
        if serial != args.expect_serial:
            raise SystemExit(f'{args.device} is {serial}, not {args.expect_serial}; nothing built or installed')

    OUT.mkdir(parents=True, exist_ok=True)
    records = json.loads(RECORD.read_text()) if RECORD.exists() else []
    code = next_code([r['versionCode'] for r in records],
                     installed_code(args.device) if args.device else None)

    subprocess.run(['bash', str(PROJECT / 'tool/build_android_release.sh'),
                    '--build-number', str(code - ABI_OFFSET)], cwd=PROJECT, env=env, check=True)
    built = next((PROJECT / 'build/release').glob('ai-music-v*-android-arm64.apk'))
    formal = OUT / f'ai-music-{code}-formal.apk'
    devcert = OUT / f'ai-music-{code}-devcert.apk'
    formal.write_bytes(built.read_bytes())
    run(str(tools / 'apksigner'), 'sign', '--ks', str(Path.home() / '.android/debug.keystore'),
        '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--ks-key-alias', 'androiddebugkey',
        '--out', str(devcert), str(formal))

    certs = run(str(tools / 'apksigner'), 'verify', '--print-certs', str(devcert))
    badging = run(str(tools / 'aapt'), 'dump', 'badging', str(devcert))
    if DEBUG_CERT not in certs:
        raise SystemExit('Re-signed APK does not carry the development certificate')
    if f"versionCode='{code}'" not in badging or "application-debuggable" in badging:
        raise SystemExit(f'Unexpected APK metadata for {code}')

    record = {
        'versionCode': code,
        'sourceCommit': run('git', 'rev-parse', 'HEAD', cwd=PROJECT),
        'dirty': bool(run('git', 'status', '--porcelain', cwd=PROJECT)),
        'formal': str(formal.relative_to(PROJECT)),
        'formalSha256': sha256(formal),
        'devcert': str(devcert.relative_to(PROJECT)),
        'devcertSha256': sha256(devcert),
    }
    if args.device:
        adb(args.device, 'install', '-r', str(devcert))
        path = adb(args.device, 'shell', 'pm', 'path', PACKAGE).splitlines()[0].split(':', 1)[1]
        on_device = adb(args.device, 'shell', 'sha256sum', path).split()[0]
        if on_device != record['devcertSha256'] or installed_code(args.device) != code:
            raise SystemExit('Installed APK does not match the build')
        record['installedOn'] = args.expect_serial
    records.append(record)
    RECORD.write_text(json.dumps(records, indent=2, ensure_ascii=False))
    print(json.dumps(record, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
