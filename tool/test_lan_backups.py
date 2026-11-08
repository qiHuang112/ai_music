import hashlib
import json
import os
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import lan_backups
from lan_update_server import create_server


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def manifest(device_id, name, tracks, favorites=(), playlists=()):
    return {
        'schemaVersion': 1,
        'device': {'id': device_id, 'name': name, 'platform': 'android', 'appVersion': '1.0.5'},
        'createdAt': '2026-11-08T10:00:00Z',
        'tracks': tracks,
        'favorites': [{'trackId': t} for t in favorites],
        'playlists': list(playlists),
    }


class BackupServerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.server = create_server(self.root / 'android', '127.0.0.1', 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_address[1]}/api/v1/backup'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.temporary.cleanup()

    def request(self, method, path, body=None, content_type='application/json'):
        data = json.dumps(body).encode() if isinstance(body, (dict, list)) else body
        request = urllib.request.Request(self.base + path, data=data, method=method)
        if data is not None:
            request.add_header('Content-Type', content_type)
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                payload = response.read()
                kind = response.headers.get_content_type()
                return response.status, json.loads(payload) if kind == 'application/json' else payload
        except urllib.error.HTTPError as error:
            return error.code, None

    def test_upload_list_and_restore_a_device(self):
        song, lyric = b'audio-bytes' * 100, b'[00:01]la'
        status, receipt = self.request('PUT', f'/blobs/{sha(song)}', song, 'application/octet-stream')
        self.assertEqual((status, receipt['stored']), (201, True))
        status, receipt = self.request('PUT', f'/blobs/{sha(song)}', song, 'application/octet-stream')
        self.assertEqual((status, receipt['stored']), (200, False))
        status, _ = self.request('PUT', f'/blobs/{sha(b"other")}', song, 'application/octet-stream')
        self.assertEqual(status, 400)

        status, result = self.request('POST', '/blobs/missing', {'sha256': [sha(song), sha(lyric)]})
        self.assertEqual(result['missing'], [sha(lyric)])

        tracks = {'t1': {'title': '晴天', 'artist': '周杰伦', 'files': [
            {'role': 'audio', 'sha256': sha(song), 'size': len(song)},
            {'role': 'lyrics', 'sha256': sha(lyric), 'size': len(lyric)},
        ]}}
        document = manifest('device-aaaa1111', 'Mi 10 Pro', tracks, favorites=['t1'],
                            playlists=[{'id': 'p1', 'name': '通勤', 'entries': [{'trackId': 't1'}]}])
        status, _ = self.request('PUT', '/devices/device-aaaa1111', document)
        self.assertEqual(status, 409)  # lyrics not uploaded yet
        self.request('PUT', f'/blobs/{sha(lyric)}', lyric, 'application/octet-stream')
        status, summary = self.request('PUT', '/devices/device-aaaa1111', document)
        self.assertEqual(status, 200)
        self.assertEqual((summary['playlistCount'], summary['favoriteCount'], summary['trackCount']), (1, 1, 1))
        self.assertEqual(summary['totalBytes'], len(song) + len(lyric))

        status, listing = self.request('GET', '/devices')
        self.assertEqual([d['deviceName'] for d in listing['devices']], ['Mi 10 Pro'])
        status, restored = self.request('GET', '/devices/device-aaaa1111')
        self.assertEqual(restored['playlists'][0]['name'], '通勤')
        status, body = self.request('GET', f'/blobs/{sha(song)}')
        self.assertEqual(body, song)

    def test_devices_share_files_and_only_unused_old_files_are_swept(self):
        shared, old = b'shared-song' * 50, b'old-song' * 50
        for data in (shared, old):
            self.request('PUT', f'/blobs/{sha(data)}', data, 'application/octet-stream')

        def track(data):
            return {'files': [{'role': 'audio', 'sha256': sha(data), 'size': len(data)}]}

        self.request('PUT', '/devices/device-aaaa1111',
                     manifest('device-aaaa1111', 'A', {'s': track(shared), 'o': track(old)}))
        self.request('PUT', '/devices/device-bbbb2222', manifest('device-bbbb2222', 'B', {'s': track(shared)}))
        # Age every file past the grace period, then A drops the old song.
        past = time.time() - lan_backups.ORPHAN_GRACE_SECONDS - 60
        for blob in (self.root / 'backups/blobs').glob('*/*'):
            os.utime(blob, (past, past))
        self.request('PUT', '/devices/device-aaaa1111', manifest('device-aaaa1111', 'A', {'s': track(shared)}))
        status, result = self.request('POST', '/blobs/missing', {'sha256': [sha(shared), sha(old)]})
        self.assertEqual(result['missing'], [sha(old)])
        status, listing = self.request('GET', '/devices')
        self.assertEqual(sorted(d['deviceName'] for d in listing['devices']), ['A', 'B'])

    def test_rejects_bad_ids_and_hashes(self):
        self.assertEqual(self.request('GET', '/devices/..%2F..%2Fetc')[0], 400)
        self.assertEqual(self.request('GET', '/blobs/not-a-hash')[0], 400)
        self.assertEqual(self.request('GET', f'/blobs/{sha(b"none")}')[0], 404)
        document = manifest('device-aaaa1111', 'A', {})
        self.assertEqual(self.request('PUT', '/devices/device-bbbb2222', document)[0], 400)

    def test_lan_only(self):
        with self.assertRaises(PermissionError):
            lan_backups.lan_only('8.8.8.8')


if __name__ == '__main__':
    unittest.main()
