import json
import tempfile
import unittest
from pathlib import Path

from perf_transitions import latest_session, load_operations, render, summarize


def _entry(name, details):
    return {'at': '2026-11-10T21:00:00', 'operation': name, 'details': details}


class PerfTransitionsTest(unittest.TestCase):
    def setUp(self):
        self.operations = [
            _entry('perf.transition', {
                'kind': 'push', 'from': 'home', 'to': 'playlist-detail', 'firstOpen': False,
                'dropped': 3, 'overBudgetUi': 2, 'overBudgetRaster': 0, 'firstUiMs': '30.0',
                'worstUiMs': '20.0', 'worstRasterMs': '8.0', 'budgetMs': '11.1',
                'hints': ['notify_mid_slide'],
                'notifies': [{'source': 'MusicController', 'frame': 1,
                              'caller': 'MusicController.recordPlaylistUsage'}]}),
            _entry('perf.transitions', {'pages': {
                'push:playlist-detail': {'n': 5, 'janky': 1, 'dropped': 3,
                                         'worstUiMs': 30.0, 'worstRasterMs': 8.0},
                'tab:tab:library': {'n': 4, 'janky': 0, 'dropped': 0,
                                    'worstUiMs': 9.0, 'worstRasterMs': 7.0}}}),
            _entry('search', {'query': 'x'}),
        ]

    def test_summary_and_rendering_name_the_cause(self):
        pages, janky = summarize(self.operations)
        self.assertEqual(pages['push:playlist-detail']['n'], 5)
        self.assertEqual(pages['push:playlist-detail']['hints']['notify_mid_slide'], 1)
        text = render(pages, janky)
        self.assertIn('recordPlaylistUsage', text)
        self.assertIn('afterRouteEntrance', text)
        self.assertIn('tab:tab:library', text)

    def test_newest_session_only_by_default(self):
        old = dict(self.operations[0], session='1')
        new = dict(self.operations[0], session='2', details=dict(
            self.operations[0]['details'], to='settings'))
        operations = [old, new]
        self.assertEqual(latest_session(operations), '2')
        pages, janky = summarize(operations, '2')
        self.assertEqual([e['to'] for e in janky], ['settings'])
        self.assertNotIn('push:playlist-detail', pages)

    def test_reads_uploaded_reports_and_operation_logs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ('a' * 32 + '.json')).write_text(json.dumps(
                {'payload': {'operations': self.operations}}))
            log = root / 'operations.jsonl'
            log.write_text('\n'.join(json.dumps(e) for e in self.operations))
            self.assertEqual(len(load_operations(None, root)[1]), 3)
            self.assertEqual(len(load_operations('a' * 32, root)[1]), 3)
            self.assertEqual(len(load_operations(str(log), root)[1]), 3)


if __name__ == '__main__':
    unittest.main()
