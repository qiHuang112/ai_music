import hashlib
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from lan_update_server import create_server
from android_release_archive import retain_manifest


class UpdateServerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.server = create_server(self.root, '127.0.0.1', 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def test_empty_then_published_and_complete_download(self):
        with urllib.request.urlopen(self.base + '/api/v1/update/android') as response:
            self.assertEqual(response.status, 204)
        payload = b'APK-test-bytes'
        (self.root / 'app.apk').write_bytes(payload)
        manifest = {'url': '/releases/app.apk', 'sha256': hashlib.sha256(payload).hexdigest()}
        (self.root / 'latest.json').write_text(json.dumps(manifest))
        with urllib.request.urlopen(self.base + '/api/v1/update/android') as response:
            self.assertEqual(json.load(response), manifest)
            self.assertEqual(response.headers['Cache-Control'], 'no-store')
        with urllib.request.urlopen(self.base + manifest['url']) as response:
            self.assertEqual(response.read(), payload)

    def test_path_escape_and_symlinks_are_not_served(self):
        outside = self.root.parent / (self.root.name + '-outside.apk')
        outside.write_bytes(b'not public')
        try:
            (self.root / 'link.apk').symlink_to(outside)
            for path in ['/releases/../latest.json', '/releases/%2e%2e%2foutside.apk', '/releases/link.apk', '/latest.json']:
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(self.base + path)
                self.assertEqual(error.exception.code, 404)
                error.exception.close()
        finally:
            outside.unlink()

    def test_history_is_downloadable_without_changing_latest(self):
        old = {'packageName': 'com.qi.ai.music', 'versionName': '<old>', 'versionCode': 900,
               'channel': 'debug', 'abi': 'arm64-v8a', 'sha256': 'a' * 64,
               'url': '/releases/old.apk', 'sizeBytes': 3}
        latest = {**old, 'versionName': '1.0.2', 'versionCode': 10,
                  'channel': 'release', 'sha256': 'b' * 64, 'url': '/releases/current.apk'}
        retain_manifest(self.root, old)
        retain_manifest(self.root, latest)
        (self.root / 'latest.json').write_text(json.dumps(latest))
        (self.root / 'old.apk').write_bytes(b'old')
        (self.root / 'current.apk').write_bytes(b'new')
        with urllib.request.urlopen(self.base + '/api/v1/releases/android') as response:
            self.assertEqual(len(json.load(response)), 2)
        with urllib.request.urlopen(self.base + '/') as response:
            page = response.read().decode()
            self.assertIn('&lt;old&gt;', page)
            self.assertLess(page.index('current.apk'), page.index('old.apk'))
        with urllib.request.urlopen(self.base + old['url']) as response:
            self.assertEqual(response.read(), b'old')
        with urllib.request.urlopen(self.base + '/api/v1/update/android') as response:
            self.assertEqual(json.load(response), latest)


if __name__ == '__main__':
    unittest.main()
