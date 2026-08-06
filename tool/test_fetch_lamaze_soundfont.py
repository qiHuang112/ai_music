import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from fetch_lamaze_soundfont import RESOURCES, fetch_resources  # noqa: E402


class _FakeResponse:
    def __init__(self, url, payload):
        self._url = url
        self._payload = payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def geturl(self):
        return self._url

    def read(self, size=-1):
        if not self._payload:
            return b""
        if size < 0:
            size = len(self._payload)
        chunk = self._payload[:size]
        self._payload = self._payload[size:]
        return chunk


class LamazeSoundFontFetchTests(unittest.TestCase):
    def test_fetches_pinned_https_files_and_records_hashes(self):
        payloads = {
            resource.url: (resource.filename + "\n").encode("utf-8")
            for resource in RESOURCES
        }

        def opener(url):
            return _FakeResponse(url, payloads[url])

        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir)
            manifest = fetch_resources(output, opener=opener)
            recorded = json.loads(
                (output / "lamaze_soundfont_sources.json").read_text(
                    encoding="utf-8"
                )
            )

            self.assertEqual(manifest, recorded)
            self.assertEqual("MIT", recorded["license"])
            self.assertEqual(3, len(recorded["resources"]))
            for resource in RESOURCES:
                target = output / resource.filename
                self.assertTrue(target.is_file())
                self.assertEqual(
                    hashlib.sha256(target.read_bytes()).hexdigest(),
                    recorded["resources"][resource.filename]["sha256"],
                )

    def test_rejects_redirect_to_non_https_scheme(self):
        def opener(url):
            return _FakeResponse(url.replace("https://", "http://"), b"unsafe")

        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaises(ValueError):
                fetch_resources(Path(temp_dir), opener=opener)


if __name__ == "__main__":
    unittest.main()
