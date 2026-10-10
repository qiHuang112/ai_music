import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import push_and_publish_android as delivery


class DeliveryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def test_version_exceeds_debug_and_release_history(self):
        (self.root / 'versions').mkdir()
        (self.root / 'versions/debug.json').write_text(json.dumps({
            'packageName': 'com.qi.ai.music', 'sha256': 'debug', 'versionCode': 10156}))
        (self.root / 'latest.json').write_text(json.dumps({
            'sha256': 'release', 'versionCode': 10153, 'versionName': '1.0.2'}))
        project = self.root / 'project'
        project.mkdir()
        (project / 'pubspec.yaml').write_text('version: 1.0.3+8171\n')
        with patch.object(delivery, 'PROJECT', project):
            self.assertEqual(delivery.next_version(self.root), ('1.0.3', 8157))

    def test_dirty_tree_refused_before_push(self):
        with patch.object(delivery, 'git', return_value=' M file'), \
             patch.object(delivery.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError):
                delivery.push_and_publish(self.root)
            run.assert_not_called()

    def test_push_failure_never_builds_or_publishes(self):
        with patch.object(delivery, 'require_clean', return_value='abc'), \
             patch.object(delivery.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'push')) as run, \
             patch.object(delivery, 'publish') as publish:
            with self.assertRaises(subprocess.CalledProcessError):
                delivery.push_and_publish(self.root)
            self.assertEqual(run.call_count, 1)
            publish.assert_not_called()

    def test_ci_push_failure_never_dispatches_or_builds(self):
        with patch.object(delivery, 'git', side_effect=['main', 'abc']), \
             patch.object(delivery.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'push')) as run, \
             patch.object(delivery, 'publish') as publish:
            with self.assertRaises(subprocess.CalledProcessError):
                delivery.push_for_ci()
            self.assertEqual(run.call_count, 1)
            publish.assert_not_called()

    def test_remote_mismatch_never_builds(self):
        with patch.object(delivery, 'require_clean', return_value='abc'), \
             patch.object(delivery, 'git', return_value='other refs/heads/main'), \
             patch.object(delivery.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError):
                delivery.push_and_publish(self.root)
            self.assertEqual(run.call_count, 1)

    def test_retry_same_commit_verifies_existing_release_without_build(self):
        manifest = {'sourceCommit': 'abc', 'versionName': '1.0.2', 'versionCode': 10157}
        (self.root / 'latest.json').write_text(json.dumps(manifest))
        with patch.object(delivery, 'require_clean', return_value='abc'), \
             patch.object(delivery, 'git', return_value='abc refs/heads/main'), \
             patch.object(delivery.subprocess, 'run') as run, \
             patch.object(delivery, 'verify_http') as verify:
            self.assertEqual(delivery.push_and_publish(self.root, publish_only=True), manifest)
            run.assert_not_called()
            verify.assert_called_once()

    def test_build_failure_preserves_latest(self):
        project = self.root / 'project'
        (project / 'android').mkdir(parents=True)
        (project / 'android/key.properties').touch()
        (project / 'pubspec.yaml').write_text('version: 1.0.3+8171\n')
        sdk = self.root / 'sdk'
        tools = sdk / 'build-tools/35.0.0'
        tools.mkdir(parents=True)
        (tools / 'aapt').touch()
        (tools / 'apksigner').touch()
        manifest = {'sha256': 'old', 'versionCode': 10153, 'versionName': '1.0.2'}
        latest = self.root / 'latest.json'
        latest.write_text(json.dumps(manifest))
        before = latest.read_bytes()
        with patch.object(delivery, 'PROJECT', project), \
             patch.object(delivery, 'require_clean', return_value='abc'), \
             patch.object(delivery, 'git', return_value='abc refs/heads/main'), \
             patch.dict(delivery.os.environ, {'ANDROID_HOME': str(sdk)}), \
             patch.object(delivery.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'build')), \
             patch.object(delivery, 'publish') as publish:
            with self.assertRaises(subprocess.CalledProcessError):
                delivery.push_and_publish(self.root, publish_only=True)
            self.assertEqual(latest.read_bytes(), before)
            publish.assert_not_called()


if __name__ == '__main__':
    unittest.main()
