import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import github_macos_release as release


class MacReleaseTest(unittest.TestCase):
    def test_rejects_wrong_app_or_pre_offset_version(self):
        info = {'CFBundleIdentifier': release.BUNDLE, 'CFBundleName': '来听',
                'CFBundleShortVersionString': '1.0.4', 'CFBundleVersion': '10269'}
        version = {'name': '1.0.4', 'code': 10269}
        release.validate_info(info, version)
        for key, value in [('CFBundleIdentifier', 'other.app'),
                           ('CFBundleName', 'Other'), ('CFBundleVersion', '8269')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                release.validate_info({**info, key: value}, version)

    def test_debugger_or_unsandboxed_bundle_is_not_a_release(self):
        sandbox = {'com.apple.security.app-sandbox': True}
        release.validate_entitlements(sandbox)
        for entitlements in [{}, {**sandbox, 'com.apple.security.get-task-allow': True}]:
            with self.subTest(entitlements=entitlements), self.assertRaises(ValueError):
                release.validate_entitlements(entitlements)

    def test_download_checks_bytes_metadata_and_checksum(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data, name = b'complete ZIP', 'app.zip'
            digest = hashlib.sha256(data).hexdigest()
            manifest = {'sha256': digest, 'sizeBytes': len(data), 'sourceCommit': 'abc'}
            files = {name: data, 'macos-latest.json': json.dumps(manifest).encode(),
                     name + '.sha256': f'{digest}  {name}\n'.encode()}
            for filename, content in files.items():
                (root / filename).write_bytes(content)
            release.verify_download(root, manifest, name)
            for filename, content in files.items():
                with self.subTest(file=filename):
                    (root / filename).write_bytes(b'{}')
                    with self.assertRaises(ValueError):
                        release.verify_download(root, manifest, name)
                    (root / filename).write_bytes(content)


if __name__ == '__main__':
    unittest.main()
