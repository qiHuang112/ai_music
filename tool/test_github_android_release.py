import json
import hashlib
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import github_android_release as release


class GitHubReleaseTest(unittest.TestCase):
    def test_version_exceeds_local_deliveries_and_incomplete_drafts(self):
        releases = [{'tag_name': 'unrelated'}, {'tag_name': 'v1.0.3-10200', 'draft': True}]
        plan = release.choose_version('version: 1.0.4+8171\n', releases)
        self.assertEqual(plan, {'name': '1.0.4', 'number': 8201, 'code': 10201, 'tag': 'v1.0.4-10201'})
        self.assertEqual(release.choose_version('version: 1.0.3+8171\n', [])['code'], 10197)

    def test_superseded_commit_does_not_build(self):
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(release, 'PROJECT', Path(temporary)), \
             patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'old',
                                     'GITHUB_OUTPUT': f'{temporary}/outputs'}), \
             patch.object(release, 'gh', return_value='new'):
            release.plan()
            self.assertEqual(json.loads((Path(temporary) / 'build/github-release-plan.json').read_text()),
                             {'skip': 'true'})

    def test_completed_commit_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(release, 'PROJECT', Path(temporary)), \
             patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'same',
                                     'GITHUB_OUTPUT': f'{temporary}/outputs'}), \
             patch.object(release, 'gh', side_effect=['same', json.dumps([[{
                 'draft': False, 'prerelease': False, 'body': '源码提交：same'}]])]):
            release.plan()
            self.assertEqual((Path(temporary) / 'outputs').read_text(), 'skip=true\n')

    def test_wrong_certificate_prevents_any_release_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / 'build/app/outputs/flutter-apk').mkdir(parents=True)
            apk = project / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libflutter.so', b'flutter')
            (project / 'build/github-release-plan.json').write_text(json.dumps({'name': '1.0.3', 'code': 10196}))
            with patch.object(release, 'PROJECT', project), \
                 patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'same', 'ANDROID_HOME': temporary}), \
                 patch.object(release, 'gh', return_value='same') as gh, \
                 patch('subprocess.check_output', side_effect=lambda args, **kwargs:
                       'subject' if args[0] == 'git' else 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64):
                with self.assertRaisesRegex(ValueError, 'trusted release certificate'):
                    release.publish_release()
                self.assertEqual(gh.call_count, 1)  # Only the read of main.

    def test_missing_signing_secrets_does_not_write_key(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {'RUNNER_TEMP': temporary}, clear=True):
            with self.assertRaisesRegex(RuntimeError, 'four ANDROID signing secrets'):
                release.signing()
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_only_verified_upload_becomes_latest(self):
        for corrupt in [False, True]:
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory() as temporary:
                project = Path(temporary)
                (project / 'build').mkdir()
                (project / 'build/github-release-plan.json').write_text(json.dumps({
                    'name': '1.0.3', 'code': 10197, 'tag': 'v1.0.3-10197'}))
                root = project / 'build/github-release'
                data = b'signed apk bytes'
                manifest = {
                    'versionName': '1.0.3', 'versionCode': 10197, 'url': '/releases/app.apk',
                    'sizeBytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                }
                calls = []

                def stage(*args, **kwargs):
                    root.mkdir()
                    (root / 'app.apk').write_bytes(data)
                    return manifest.copy()

                def github(*args):
                    calls.append(args)
                    if args[0] == 'api':
                        return 'same'
                    if args[:2] == ('release', 'download'):
                        downloaded = Path(args[args.index('--dir') + 1])
                        (downloaded / 'app.apk').write_bytes(b'corrupt' if corrupt else data)
                        (downloaded / 'latest.json').write_bytes((root / 'latest.json').read_bytes())
                    return ''

                with patch.object(release, 'PROJECT', project), \
                     patch.dict(os.environ, {'GITHUB_REPOSITORY': 'qiHuang112/ai_music',
                                             'GITHUB_SHA': 'same', 'ANDROID_HOME': temporary}), \
                     patch.object(release, 'publish', side_effect=stage), \
                     patch.object(release, 'gh', side_effect=github), \
                     patch('subprocess.check_output', return_value='subject'):
                    if corrupt:
                        with self.assertRaisesRegex(RuntimeError, 'size/hash mismatch'):
                            release.publish_release()
                    else:
                        release.publish_release()
                create = next(call for call in calls if call[:2] == ('release', 'create'))
                self.assertIn('--draft', create)
                edits = [call for call in calls if call[:2] == ('release', 'edit')]
                self.assertEqual(len(edits), 0 if corrupt else 1)


if __name__ == '__main__':
    unittest.main()
