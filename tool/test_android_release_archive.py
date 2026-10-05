import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from android_release_archive import retained_versions
from archive_android_apks import archive
from publish_android_release import publish


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.output = self.root / 'published'

    def tearDown(self):
        self.temporary.cleanup()

    def apk(self, name, data):
        file = self.root / name
        with zipfile.ZipFile(file, 'w') as output:
            output.writestr('lib/arm64-v8a/libflutter.so', data)
        return file

    def publish(self, apk, code, certificate=None):
        metadata = f"package: name='com.qi.ai.music' versionCode='{code}' versionName='1.0.{code}'"
        def output(args, **kwargs):
            return metadata if args[0] == 'aapt' else (
                f'Signer #1 certificate SHA-256 digest: {certificate or 'a' * 64}'
            )
        with patch(
            'publish_android_release.subprocess.check_output', side_effect=output
        ):
            return publish(apk, self.output, 'aapt', 'apksigner', release_cert='a' * 64)

    def test_new_publish_retains_old_metadata_and_bytes(self):
        old = self.publish(self.apk('old.apk', b'old'), 1)
        new = self.publish(self.apk('new.apk', b'new'), 2)
        self.assertEqual(len(retained_versions(self.output)), 2)
        self.assertTrue((self.output / Path(old['url']).name).is_file())
        self.assertEqual(json.loads((self.output / 'latest.json').read_text()), new)
        self.publish(self.root / 'new.apk', 2)
        self.assertEqual(len(retained_versions(self.output)), 2)
        with self.assertRaises(ValueError):
            self.publish(self.apk('conflict.apk', b'other'), 2)
        self.assertEqual(json.loads((self.output / 'latest.json').read_text()), new)

    def test_wrong_release_signer_cannot_change_latest_or_archive(self):
        self.publish(self.apk('latest.apk', b'good'), 1)
        before = {str(p.relative_to(self.output)): p.read_bytes()
                  for p in self.output.rglob('*') if p.is_file()}
        with self.assertRaises(ValueError):
            self.publish(self.apk('wrong-signer.apk', b'wrong'), 2, 'b' * 64)
        after = {str(p.relative_to(self.output)): p.read_bytes()
                 for p in self.output.rglob('*') if p.is_file()}
        self.assertEqual(after, before)

    def test_archive_older_debug_is_deduplicated_and_keeps_release_pointer(self):
        latest = self.publish(self.apk('latest.apk', b'new'), 2)
        old = self.apk('old.apk', b'old')
        def output(args, **kwargs):
            return ("package: name='com.qi.ai.music' versionCode='1' versionName='1.0.1'\napplication-debuggable"
                    if args[0] == 'aapt' else 'Signer #1 certificate SHA-256 digest: deadbeef')
        with patch('archive_android_apks.subprocess.check_output', side_effect=output):
            record = archive(old, self.output, 'aapt', 'apksigner', {'deadbeef'}, 'release')
            repeated = archive(old, self.output, 'aapt', 'apksigner', {'deadbeef'}, 'release')
        self.assertEqual(record, repeated)
        self.assertEqual(record['channel'], 'debug')
        self.assertEqual(len(retained_versions(self.output)), 2)
        self.assertEqual(json.loads((self.output / 'latest.json').read_text()), latest)
        self.assertEqual((self.output / Path(record['url']).name).read_bytes(), old.read_bytes())


if __name__ == '__main__':
    unittest.main()
