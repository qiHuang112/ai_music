#!/usr/bin/env python3
"""Install the LAN update server as the current user's persistent launch agent."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def deploy(root: Path, port: int):
    root = root.resolve()
    service = root.parent / 'update-service'
    logs = service / 'logs'
    logs.mkdir(parents=True, exist_ok=True)
    label = 'com.qi.ai.music.android-updates'
    domain = f'gui/{os.getuid()}'
    target = f'{domain}/{label}'
    existing = subprocess.run(['launchctl', 'print', target], capture_output=True)
    occupied = subprocess.run(['lsof', '-nP', f'-iTCP:{port}', '-sTCP:LISTEN'], capture_output=True)
    if occupied.returncode == 0 and existing.returncode != 0:
        raise RuntimeError(f'Port {port} belongs to another server; it was not stopped')
    tools = Path(__file__).resolve().parent
    for name in ['lan_update_server.py', 'android_release_archive.py']:
        shutil.copyfile(tools / name, service / name)
    agent = Path.home() / 'Library' / 'LaunchAgents' / f'{label}.plist'
    agent.parent.mkdir(parents=True, exist_ok=True)
    configuration = {
        'Label': label,
        'ProgramArguments': [shutil.which('python3') or sys.executable, str(service / 'lan_update_server.py'), '--root', str(root), '--port', str(port)],
        'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 10,
        'WorkingDirectory': str(service),
        'EnvironmentVariables': {'PYTHONUNBUFFERED': '1'},
        'StandardOutPath': str(logs / 'server.log'),
        'StandardErrorPath': str(logs / 'error.log'),
    }
    if existing.returncode == 0:
        subprocess.run(['launchctl', 'bootout', target], check=True)
    temporary = agent.with_suffix('.plist.part')
    temporary.write_bytes(plistlib.dumps(configuration))
    temporary.replace(agent)
    subprocess.run(['launchctl', 'bootstrap', domain, str(agent)], check=True)
    last_error = None
    for _ in range(30):
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/v1/update/android', timeout=1) as response:
                release = json.load(response)
            print(f"Running {label}: release {release['versionName']} ({release['versionCode']})")
            print(f'Packages: {root}')
            print(f'Login autostart: {agent}')
            return
        except (OSError, ValueError) as error:
            last_error = error
            time.sleep(0.3)
    raise RuntimeError(f'Server did not become healthy: {last_error}; see {logs}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--port', default=8788, type=int)
    args = parser.parse_args()
    deploy(args.root, args.port)
