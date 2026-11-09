import json
import hashlib
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import github_android_release as release

VERSION = {'RELEASE_NAME': '1.0.3', 'RELEASE_CODE': '10197', 'RELEASE_TAG': 'v1.0.3-10197'}


class GitHubReleaseTest(unittest.TestCase):
    def test_version_exceeds_local_deliveries_and_incomplete_drafts(self):
        releases = [{'tag_name': 'unrelated'}, {'tag_name': 'v1.0.3-10300', 'draft': True}]
        plan = release.choose_version('version: 1.0.4+8171\n', releases)
        self.assertEqual(plan, {'name': '1.0.4', 'number': 8301, 'code': 10301, 'tag': 'v1.0.4-10301'})
        self.assertEqual(release.choose_version('version: 1.0.4+8267\n', [])['code'], 10268)

    def test_wrong_certificate_stages_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / 'build/app/outputs/flutter-apk').mkdir(parents=True)
            apk = project / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libflutter.so', b'flutter')
            with patch.object(release, 'PROJECT', project), \
                 patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'same',
                                         'ANDROID_HOME': temporary, **VERSION}), \
                 patch('subprocess.check_output', side_effect=lambda args, **kwargs:
                       'subject' if args[0] == 'git' else 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64):
                with self.assertRaisesRegex(ValueError, 'trusted release certificate'):
                    release.stage()
                self.assertFalse((project / 'build/release-stage').exists())

    def test_missing_signing_secrets_does_not_write_key(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {'RUNNER_TEMP': temporary}, clear=True):
            with self.assertRaisesRegex(RuntimeError, 'four ANDROID signing secrets'):
                release.signing()
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_stage_points_the_manifest_at_the_planned_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            root = project / 'build/github-release'
            data = b'signed apk bytes'
            manifest = {'versionName': '1.0.3', 'versionCode': 10197, 'url': '/releases/app.apk',
                        'sizeBytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                        'sourceCommit': 'same'}

            def build(*args, **kwargs):
                root.mkdir(parents=True)
                (root / 'app.apk').write_bytes(data)
                return dict(manifest)

            with patch.object(release, 'PROJECT', project), \
                 patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'same',
                                         'ANDROID_HOME': temporary, **VERSION}), \
                 patch.object(release, 'publish', side_effect=build), \
                 patch('subprocess.check_output', return_value='subject'):
                release.stage()
            out = project / 'build/release-stage/stage-android'
            staged = json.loads((out / 'latest.json').read_text())
            self.assertEqual(staged['url'], 'https://github.com/qiHuang112/ai_music/releases/download/v1.0.3-10197/app.apk')
            self.assertEqual((out / 'app.apk').read_bytes(), data)
            self.assertEqual((out / 'app.apk.sha256').read_text(), f"{manifest['sha256']}  app.apk\n")
            with patch.object(release, 'PROJECT', project), \
                 patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'same',
                                         'ANDROID_HOME': temporary, **VERSION, 'RELEASE_CODE': '10198'}), \
                 patch.object(release, 'publish', side_effect=lambda *a, **k: dict(manifest)), \
                 patch('subprocess.check_output', return_value='subject'):
                with self.assertRaisesRegex(RuntimeError, 'differs from planned'):
                    release.stage()


if __name__ == '__main__':
    unittest.main()
