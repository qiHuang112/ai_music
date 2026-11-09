import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import github_release as release

ENV = {'GITHUB_REPOSITORY': 'qiHuang112/ai_music', 'GITHUB_SHA': 'c' * 40}
TAG = 'v1.0.6-10275'


def page(*items):
    return json.dumps([list(items)])


class PlatformChoiceTest(unittest.TestCase):
    def test_only_the_platform_directories_touched_are_built(self):
        self.assertEqual(release.platforms_for(['ios/Runner/MusicShell.swift', 'docs/a.md']), {'ios'})
        self.assertEqual(release.platforms_for(['macos/Runner/x.swift', 'android/app/build.gradle.kts']),
                         {'macos', 'android'})

    def test_shared_code_or_dependencies_build_everything(self):
        for path in ['lib/main.dart', 'pubspec.yaml', 'pubspec.lock', 'assets/a.png', 'third_party/x/y']:
            with self.subTest(path=path):
                self.assertEqual(release.platforms_for([path]), set(release.PLATFORMS))

    def test_docs_tests_tooling_and_ci_build_nothing(self):
        self.assertEqual(release.platforms_for([
            'docs/worklog/x.md', 'README.md', 'test/a_test.dart', 'tool/github_release.py',
            '.github/workflows/ci.yml', 'ohos/entry/x.ets', 'analysis_options.yaml']), set())

    def test_requested_platforms(self):
        self.assertEqual(release.requested_platforms(''), 'auto')
        self.assertEqual(release.requested_platforms('ALL'), 'all')
        self.assertEqual(release.requested_platforms('ios, macos'), {'ios', 'macos'})
        self.assertEqual(release.requested_platforms('android+ios'), {'android', 'ios'})
        for value in ['windows', 'ios,web', ',']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.requested_platforms(value)

    def test_auto_without_a_comparable_release_builds_everything(self):
        with patch.object(release, 'is_ancestor', return_value=False):
            self.assertEqual(release.choose_platforms('auto', 'a' * 40, 'c' * 40)[0], set(release.PLATFORMS))
        self.assertEqual(release.choose_platforms('auto', None, 'c' * 40)[0], set(release.PLATFORMS))
        self.assertEqual(release.choose_platforms({'ios'}, None, 'c' * 40)[0], {'ios'})

    def test_source_commit_is_read_from_its_own_line(self):
        body = '说明\n\nMac 源码提交：' + 'b' * 40 + '\n源码提交：' + 'a' * 40 + '\n'
        self.assertEqual(release.source_commit({'body': body}), 'a' * 40)
        self.assertIsNone(release.source_commit({'body': 'Mac 源码提交：' + 'b' * 40}))


class CheckGateTest(unittest.TestCase):
    def gate(self, responses, **patches):
        calls = iter(responses)
        with patch.object(release, 'gh', side_effect=lambda *a: json.dumps(next(calls))), \
             patch.object(release, 'is_ancestor', return_value=True), \
             patch.object(release, 'git', return_value=patches.get('changed', 'docs/a.md')):
            return release.await_check('repo', 'c' * 40, sleep=lambda s: None, clock=lambda: 0)

    def test_passing_check_is_reused(self):
        self.assertEqual(self.gate([{'workflow_runs': [{'status': 'completed', 'conclusion': 'success'}]}]),
                         'c' * 40)

    def test_running_check_is_waited_for(self):
        running = {'workflow_runs': [{'status': 'in_progress', 'conclusion': None}]}
        done = {'workflow_runs': [{'status': 'completed', 'conclusion': 'success'}]}
        self.assertEqual(self.gate([running, running, done]), 'c' * 40)

    def test_failed_check_blocks_the_release(self):
        with self.assertRaisesRegex(RuntimeError, 'Check failed'):
            self.gate([{'workflow_runs': [{'status': 'completed', 'conclusion': 'failure'}]}])

    def test_docs_only_commit_uses_its_passing_ancestor(self):
        base = {'workflow_runs': [{'head_sha': 'b' * 40}]}
        self.assertEqual(self.gate([{'workflow_runs': []}, base]), 'b' * 40)
        with self.assertRaisesRegex(RuntimeError, 'No passing Check'):
            self.gate([{'workflow_runs': []}, base], changed='lib/main.dart')


class PlanTest(unittest.TestCase):
    def run_plan(self, previous_body, changed, platforms='auto'):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / 'pubspec.yaml').write_text('version: 1.0.6+8270\n')
            outputs = project / 'outputs'
            responses = iter([page({'tag_name': 'v1.0.6-10274', 'draft': False, 'prerelease': False,
                                              'published_at': '2026-11-09', 'body': previous_body})])
            with patch.object(release, 'PROJECT', project), \
                 patch.dict(os.environ, {**ENV, 'GITHUB_OUTPUT': str(outputs), 'RELEASE_PLATFORMS': platforms}), \
                 patch.object(release, 'gh', side_effect=lambda *a: next(responses)), \
                 patch.object(release, 'current_main', return_value=True), \
                 patch.object(release, 'await_check', return_value='c' * 40), \
                 patch.object(release, 'is_ancestor', return_value=True), \
                 patch.object(release, 'git', return_value='\n'.join(changed)):
                release.plan()
            return dict(line.split('=', 1) for line in outputs.read_text().splitlines())

    def test_ios_only_change_plans_only_ios(self):
        result = self.run_plan('源码提交：' + 'a' * 40, ['ios/Runner/MusicShell.swift'])
        self.assertEqual((result['skip'], result['tag'], result['android'], result['macos'], result['ios']),
                         ('false', TAG, 'false', 'false', 'true'))

    def test_explicit_request_overrides_the_diff(self):
        result = self.run_plan('源码提交：' + 'a' * 40, ['docs/a.md'], platforms='all')
        self.assertEqual({k: result[k] for k in release.PLATFORMS}, dict.fromkeys(release.PLATFORMS, 'true'))

    def test_nothing_to_build_or_already_released_skips(self):
        self.assertEqual(self.run_plan('源码提交：' + 'a' * 40, ['docs/a.md'])['skip'], 'true')
        self.assertEqual(self.run_plan('源码提交：' + 'c' * 40, ['lib/main.dart'])['skip'], 'true')


class PublishTest(unittest.TestCase):
    def stage(self, project, platform, filename, data):
        root = project / f'build/release-stage/stage-{platform}'
        root.mkdir(parents=True)
        digest = hashlib.sha256(data).hexdigest()
        (root / filename).write_bytes(data)
        (root / (filename + '.sha256')).write_text(f'{digest}  {filename}\n')
        manifest = {'versionName': '1.0.6', 'versionCode': 10275, 'sourceCommit': 'c' * 40,
                    'sizeBytes': len(data), 'sha256': digest,
                    'url': f'https://github.com/qiHuang112/ai_music/releases/download/{TAG}/{filename}'}
        (root / release.MANIFESTS[platform]).write_text(json.dumps(manifest))

    def publish(self, corrupt=False, previous_assets=('latest.json', 'macos-latest.json')):
        calls = []
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            self.stage(project, 'ios', 'app.ipa', b'ipa bytes')
            uploaded = {}
            old = {'versionName': '1.0.6', 'versionCode': 10274, 'url': 'https://example/old.apk'}

            def github(*args):
                calls.append(args)
                if args[0] == 'api':
                    return page({'tag_name': 'v1.0.6-10274', 'draft': False, 'prerelease': False,
                                 'published_at': '2026-11-09', 'body': '',
                                 'assets': [{'name': name} for name in previous_assets]})
                if args[:2] == ('release', 'download') and args[2] == 'v1.0.6-10274':
                    target = Path(args[args.index('--dir') + 1])
                    (target / args[args.index('--pattern') + 1]).write_text(json.dumps(old))
                if args[:2] == ('release', 'create'):
                    for path in args[3:]:
                        if path.startswith('--'):
                            break
                        uploaded[Path(path).name] = Path(path).read_bytes()
                if args[:2] == ('release', 'download') and args[2] == TAG:
                    target = Path(args[args.index('--dir') + 1])
                    for name, data in uploaded.items():
                        (target / name).write_bytes(b'bad' if corrupt and name == 'app.ipa' else data)
                return ''

            with patch.object(release, 'PROJECT', project), \
                 patch.object(release, 'STAGE', project / 'build/release-stage'), \
                 patch.dict(os.environ, {**ENV, 'RELEASE_TAG': TAG, 'RELEASE_NAME': '1.0.6',
                                         'RELEASE_CODE': '10275', 'BUILD_IOS': 'true'}), \
                 patch.object(release, 'gh', side_effect=github), \
                 patch.object(release, 'current_main', return_value=True), \
                 patch.object(release, 'git', return_value='subject'):
                release.publish()
            return calls, uploaded

    def test_skipped_platforms_carry_their_previous_manifests(self):
        calls, uploaded = self.publish()
        self.assertEqual(set(uploaded), {'app.ipa', 'app.ipa.sha256', 'ios-unsigned.json',
                                         'latest.json', 'macos-latest.json'})
        self.assertEqual(json.loads(uploaded['latest.json'])['versionCode'], 10274)
        create = next(call for call in calls if call[:2] == ('release', 'create'))
        self.assertIn('--draft', create)
        self.assertIn('来听 1.0.6（10275）· iOS', create)
        self.assertEqual([call for call in calls if call[:2] == ('release', 'edit')][0][-1], '--latest')

    def test_corrupt_upload_stays_a_draft(self):
        with self.assertRaisesRegex(RuntimeError, 'stays a draft'):
            self.publish(corrupt=True)

    def test_release_without_android_manifest_is_refused(self):
        with self.assertRaisesRegex(RuntimeError, 'No Android update manifest'):
            self.publish(previous_assets=())

    def test_tampered_stage_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            self.stage(project, 'ios', 'app.ipa', b'ipa bytes')
            (project / 'build/release-stage/stage-ios/app.ipa').write_bytes(b'other')
            with patch.object(release, 'STAGE', project / 'build/release-stage'):
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    release.staged('ios', TAG, 'c' * 40, 10275)


if __name__ == '__main__':
    unittest.main()
