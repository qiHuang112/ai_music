import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import github_macos_release as release


class MacReleaseTest(unittest.TestCase):
    def item(self, **changes):
        return {'draft': False, 'prerelease': False, 'tag_name': 'v1.0.4-10269',
                'body': '源码提交：abc', 'assets': [], **changes}

    def test_mac_reuses_final_android_code_without_abi_offset(self):
        self.assertEqual(release.select_release([self.item()], 'abc'), {
            'skip': 'false', 'name': '1.0.4', 'code': 10269, 'tag': 'v1.0.4-10269'})

    def test_wrong_commit_draft_and_prerelease_cannot_receive_mac(self):
        for item in [self.item(body='源码提交：other'), self.item(draft=True),
                     self.item(prerelease=True)]:
            with self.subTest(item=item), self.assertRaises(ValueError):
                release.select_release([item], 'abc')

    def test_completed_upload_skips_but_partial_upload_can_resume(self):
        archive = 'ai-music-macos-1.0.4-10269-universal-123.zip'
        item = self.item(body='源码提交：abc\nMac 源码提交：abc', assets=[
            {'name': name} for name in ['macos-latest.json', archive, archive + '.sha256']])
        self.assertEqual(release.select_release([item], 'abc')['skip'], 'true')
        item['assets'].pop()
        self.assertEqual(release.select_release([item], 'abc')['skip'], 'false')

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
