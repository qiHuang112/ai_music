import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from mirror_github_android_release import GITHUB, asset_url, mirror


class MirrorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.payload = b'CI signed APK bytes'
        self.remote = {
            'packageName': 'com.qi.ai.music', 'versionName': '1.0.3', 'versionCode': 10202,
            'channel': 'release', 'abi': 'arm64-v8a', 'sizeBytes': len(self.payload),
            'sha256': hashlib.sha256(self.payload).hexdigest(),
            'url': GITHUB + '/releases/download/v1.0.3-10202/app.apk',
        }
        self.previous = {**self.remote, 'versionCode': 10199, 'sha256': 'a' * 64,
                         'url': '/releases/previous.apk'}
        self.pointer = self.root / 'latest.json'
        self.pointer.write_text(json.dumps(self.previous))
        (self.root / 'previous.apk').write_bytes(b'previous')

    def run_mirror(self, *, payload=None, verified=None, during_download=None):
        def open_asset(url):
            if url.endswith('latest.json'):
                return io.BytesIO(json.dumps(self.remote).encode())
            if during_download:
                during_download()
            return io.BytesIO(self.payload if payload is None else payload)

        def publish(apk, root, aapt, apksigner, notes, **kwargs):
            self.assertEqual(apk.read_bytes(), self.payload)
            self.assertEqual(kwargs['release_cert'],
                             'f05004de4b5fa23bdd1beee45c4e7c227852129930bcd3bb1cfcff2048464843')
            return verified or {**self.remote, 'url': '/releases/verified.apk'}

        with patch('mirror_github_android_release.open_asset', side_effect=open_asset), \
                patch('mirror_github_android_release.publish', side_effect=publish):
            return mirror(self.root, 'aapt', 'apksigner')

    def test_verified_release_is_available_over_lan_and_history_is_retained(self):
        result = self.run_mirror()
        self.assertEqual(json.loads(self.pointer.read_text()), result)
        self.assertEqual(result['url'], '/releases/verified.apk')
        self.assertEqual((self.root / 'verified.apk').read_bytes(), self.payload)
        self.assertTrue((self.root / 'previous.apk').exists())
        self.assertEqual(len(list((self.root / 'versions').glob('*.json'))), 2)
        self.assertFalse(list(self.root.glob('.github-mirror-*')))

    def test_bad_download_and_apk_metadata_preserve_previous_release(self):
        before = self.pointer.read_bytes()
        for payload in (b'bad bytes', self.payload + b'excess'):
            with self.assertRaises(ValueError):
                self.run_mirror(payload=payload)
            self.assertEqual(self.pointer.read_bytes(), before)
        with self.assertRaises(ValueError):
            self.run_mirror(verified={**self.remote, 'versionCode': 1})
        self.assertEqual(self.pointer.read_bytes(), before)
        self.assertFalse(list(self.root.glob('.github-mirror-*')))

    def test_older_github_release_cannot_downgrade_lan(self):
        self.previous['versionCode'] = 10203
        self.pointer.write_text(json.dumps(self.previous))
        self.assertEqual(self.run_mirror(), self.previous)

    def test_same_version_cannot_replace_published_bytes(self):
        self.previous['versionCode'] = self.remote['versionCode']
        self.pointer.write_text(json.dumps(self.previous))
        before = self.pointer.read_bytes()
        with self.assertRaises(ValueError):
            self.run_mirror()
        self.assertEqual(self.pointer.read_bytes(), before)

    def test_slow_download_cannot_overwrite_a_newer_completed_mirror(self):
        newer = {**self.previous, 'versionCode': 10203, 'url': '/releases/newer.apk'}

        def finish_newer():
            self.pointer.write_text(json.dumps(newer))
            (self.root / 'newer.apk').write_bytes(b'newer verified APK')

        self.assertEqual(self.run_mirror(during_download=finish_newer), newer)
        self.assertEqual(json.loads(self.pointer.read_text()), newer)
        self.assertFalse((self.root / 'verified.apk').exists())

    def test_concurrent_same_version_with_different_bytes_preserves_winner(self):
        winner = {**self.previous, 'versionCode': self.remote['versionCode']}

        def finish_winner():
            self.pointer.write_text(json.dumps(winner))

        with self.assertRaises(ValueError):
            self.run_mirror(during_download=finish_winner)
        self.assertEqual(json.loads(self.pointer.read_text()), winner)
        self.assertFalse((self.root / 'verified.apk').exists())

    def test_external_asset_metadata_and_redirect_destinations_are_rejected(self):
        self.remote['url'] = 'https://other.invalid/app.apk'
        with self.assertRaises(ValueError):
            self.run_mirror()
        for url in ('http://github.com/app.apk', 'https://github.com:8443/app.apk',
                    'https://user:password@github.com/app.apk', 'https://other.invalid/app.apk'):
            self.assertFalse(asset_url(url))


if __name__ == '__main__':
    unittest.main()
