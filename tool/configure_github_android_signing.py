#!/usr/bin/env python3
"""Upload existing local Android signing material to encrypted Actions secrets.

Requires an authenticated GitHub CLI. Never prints signing values or writes them
to tracked files. Run once when setting up CI or rotating the existing key.
"""
import base64
import subprocess
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
REPO = 'qiHuang112/ai_music'


def configure():
    subprocess.run(['gh', 'auth', 'status', '--active'], check=True, stdout=subprocess.DEVNULL)
    values = {}
    for line in (PROJECT / 'android/key.properties').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith(('#', '!')):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    store = Path(values['storeFile'])
    if not store.is_absolute():
        store = PROJECT / 'android' / store
    secrets = {
        'ANDROID_KEYSTORE_BASE64': base64.b64encode(store.read_bytes()).decode(),
        'ANDROID_KEY_ALIAS': values['keyAlias'],
        'ANDROID_KEY_PASSWORD': values['keyPassword'],
        'ANDROID_STORE_PASSWORD': values['storePassword'],
    }
    for name, value in secrets.items():
        if not value:
            raise ValueError(f'Missing local signing value for {name}')
    for name, value in secrets.items():
        subprocess.run(['gh', 'secret', 'set', name, '--repo', REPO],
                       input=value, text=True, check=True)
        print(f'Configured encrypted secret: {name}')


if __name__ == '__main__':
    configure()
