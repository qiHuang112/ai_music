import hashlib
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from lan_update_server import create_server


class DiagnosticsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.server = create_server(self.root / 'android', '127.0.0.1', 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_port}'
        self.payload = {'schemaVersion': 1, 'reportId': 'a' * 32,
                        'app': {'packageName': 'com.qi.ai.music'},
                        'operations': [{'operation': 'search'}],
                        'listeningStats': {'2026-10.json': [{'day': '2026-10-11', 'ms': 30000}]}}

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def post(self, payload):
        raw = json.dumps(payload).encode()
        request = urllib.request.Request(self.base + '/api/v1/diagnostics', data=raw,
                                         headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request) as response:
            return json.load(response), raw

    def test_discovery_save_stats_receipt_and_idempotency(self):
        with urllib.request.urlopen(self.base + '/api/v1/diagnostics') as response:
            self.assertEqual(json.load(response)['service'], 'ai-music-diagnostics')
        receipt, raw = self.post(self.payload)
        saved = json.loads((self.root / 'diagnostics' / ('a' * 32 + '.json')).read_text())
        self.assertEqual(saved['payload'], self.payload)
        self.assertEqual(receipt['sha256'], hashlib.sha256(raw).hexdigest())
        self.assertEqual(self.post(self.payload)[0], receipt)
        self.assertEqual((self.root / 'diagnostics' / ('a' * 32 + '.json')).stat().st_mode & 0o777, 0o600)
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.post({**self.payload, 'operations': []})
        self.assertEqual(error.exception.code, 409)
        error.exception.close()

    def test_invalid_report_cannot_escape_or_be_downloaded(self):
        for patch in [{'reportId': '../escape'}, {'operations': 'bad'}, {'listeningStats': []}, {'schemaVersion': 2}]:
            with self.assertRaises(urllib.error.HTTPError) as error:
                self.post({**self.payload, **patch})
            self.assertEqual(error.exception.code, 400)
            error.exception.close()
        for path in ['/diagnostics/aaaa.json', '/api/v1/diagnostics/aaaa.json', '/releases/../diagnostics/aaaa.json']:
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(self.base + path)
            self.assertEqual(error.exception.code, 404)
            error.exception.close()
        self.assertFalse((self.root / 'diagnostics').exists())

    def test_preview_performance_report_retains_its_actual_identity(self):
        self.payload['app'] = {'packageName': 'com.qi.ai.music.preview', 'channel': 'preview'}
        self.payload['operations'] = [{'operation': 'performance.sample', 'details': {'skin': 'neon', 'fps': 30, 'cpuPercent': 21, 'memoryMiB': 110}}]
        receipt, _ = self.post(self.payload)
        saved = json.loads((self.root / 'diagnostics' / (receipt['reportId'] + '.json')).read_text())
        self.assertEqual(saved['payload']['app'], self.payload['app'])
        self.assertEqual(saved['payload']['operations'], self.payload['operations'])
        self.payload['reportId'] = 'b' * 32
        self.payload['app']['packageName'] = 'other.application'
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.post(self.payload)
        self.assertEqual(error.exception.code, 400)
        error.exception.close()


if __name__ == '__main__':
    unittest.main()
