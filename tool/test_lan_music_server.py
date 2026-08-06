import hashlib
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen


sys.path.insert(0, str(Path(__file__).resolve().parent))

from lan_music_server import build_manifest, create_server  # noqa: E402


class LanMusicManifestTests(unittest.TestCase):
    def test_build_manifest_discovers_audio_and_sidecars(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            album = root / "Lamaze"
            album.mkdir()
            audio = album / "AI Home - 慢呼放松.mp3"
            audio.write_bytes(b"ID3" + b"audio" * 100)
            (album / "AI Home - 慢呼放松.lrc").write_text(
                "[00:00.00]现场医护指令优先\n", encoding="utf-8"
            )
            (album / "AI Home - 慢呼放松.png").write_bytes(b"png-cover")

            manifest = build_manifest(root, "http://127.0.0.1:8787")

            self.assertEqual(1, manifest["schemaVersion"])
            self.assertEqual(1, len(manifest["tracks"]))
            track = manifest["tracks"][0]
            self.assertEqual("慢呼放松", track["title"])
            self.assertEqual("AI Home", track["artist"])
            self.assertEqual("Lamaze", track["album"])
            self.assertEqual("Lamaze", track["folderPath"])
            self.assertEqual("mp3", track["audio"]["format"])
            self.assertEqual(audio.stat().st_size, track["audio"]["sizeBytes"])
            self.assertEqual(
                hashlib.sha256(audio.read_bytes()).hexdigest(),
                track["audio"]["sha256"],
            )
            self.assertTrue(track["audio"]["url"].startswith("/api/v1/files/"))
            self.assertEqual("lrc", track["lyrics"]["format"])
            self.assertEqual("image/png", track["artwork"]["mimeType"])

    def test_json_sidecar_overrides_metadata_and_stable_id(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            folder = root / "真实目录"
            folder.mkdir()
            audio = folder / "unknown.flac"
            audio.write_bytes(b"fLaC" + b"audio" * 100)
            audio.with_suffix(".json").write_text(
                json.dumps(
                    {
                        "id": "lamaze-wave",
                        "title": "宫缩浪潮",
                        "artist": "AI Home",
                        "album": "拉玛泽呼吸引导",
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            track = build_manifest(root, "http://127.0.0.1:8787")["tracks"][0]

            self.assertEqual("lamaze-wave", track["id"])
            self.assertEqual("宫缩浪潮", track["title"])
            self.assertEqual("AI Home", track["artist"])
            self.assertEqual("拉玛泽呼吸引导", track["album"])
            self.assertEqual("真实目录", track["folderPath"])
            self.assertNotIn("lyrics", track)
            self.assertNotIn("artwork", track)

    def test_manifest_exposes_nested_and_root_folder_paths(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            nested = root / "胎教" / "钢琴"
            nested.mkdir(parents=True)
            (nested / "AI Home - 晚安.mp3").write_bytes(b"ID3" + b"a" * 200)
            (root / "AI Home - 根目录.mp3").write_bytes(b"ID3" + b"b" * 200)

            tracks = build_manifest(root)["tracks"]
            by_title = {track["title"]: track for track in tracks}

            self.assertEqual("胎教/钢琴", by_title["晚安"]["folderPath"])
            self.assertEqual("", by_title["根目录"]["folderPath"])

    def test_flac_jpeg_and_filename_metadata_fallback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            album = root / "舒缓练习"
            album.mkdir()
            audio = album / "AI Home - 跟随医护.flac"
            audio.write_bytes(b"fLaC" + b"audio" * 100)
            audio.with_suffix(".jpg").write_bytes(b"jpeg-cover")

            track = build_manifest(root)["tracks"][0]

            self.assertTrue(track["id"].startswith("lan-"))
            self.assertEqual("跟随医护", track["title"])
            self.assertEqual("AI Home", track["artist"])
            self.assertEqual("舒缓练习", track["album"])
            self.assertEqual("flac", track["audio"]["format"])
            self.assertEqual("image/jpeg", track["artwork"]["mimeType"])

    def test_malformed_json_sidecar_falls_back_to_filename_metadata(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            audio = root / "AI Home - 慢呼放松.mp3"
            audio.write_bytes(b"ID3" + b"audio" * 100)
            audio.with_suffix(".json").write_text("{broken", encoding="utf-8")

            track = build_manifest(root)["tracks"][0]

            self.assertEqual("慢呼放松", track["title"])
            self.assertEqual("AI Home", track["artist"])

    def test_manifest_ignores_audio_symlink_outside_root(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            parent = Path(temp_dir)
            root = parent / "music"
            root.mkdir()
            secret = parent / "secret.mp3"
            secret.write_bytes(b"ID3-secret")
            try:
                (root / "linked.mp3").symlink_to(secret)
            except OSError as error:
                self.skipTest("symlinks unavailable: {}".format(error))

            manifest = build_manifest(root)

            self.assertEqual([], manifest["tracks"])


class LanMusicHttpTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name) / "music"
        self.root.mkdir()
        self.audio = self.root / "AI Home - 测试.mp3"
        self.audio.write_bytes(b"ID3" + b"audio" * 100)
        self.server = create_server(self.root, "127.0.0.1", 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temp_dir.cleanup()

    def test_health_library_and_unicode_file_download(self):
        with urlopen(f"{self.base_url}/api/v1/health") as response:
            health = json.load(response)
        with urlopen(f"{self.base_url}/api/v1/library") as response:
            manifest = json.load(response)
        with urlopen(self.base_url + manifest["tracks"][0]["audio"]["url"]) as response:
            content = response.read()

        self.assertEqual("ok", health["status"])
        self.assertEqual(1, health["trackCount"])
        self.assertEqual(self.audio.read_bytes(), content)

    def test_file_endpoint_rejects_path_traversal(self):
        secret = self.root.parent / "secret.mp3"
        secret.write_bytes(b"ID3-secret")

        with self.assertRaises(HTTPError) as caught:
            urlopen(f"{self.base_url}/api/v1/files/%2e%2e/secret.mp3")

        self.assertIn(caught.exception.code, {403, 404})
        caught.exception.close()

    def test_file_endpoint_only_serves_manifest_assets(self):
        secret = self.root / "secret.txt"
        secret.write_text("not part of the library", encoding="utf-8")
        orphan_lyrics = self.root / "orphan.lrc"
        orphan_lyrics.write_text("[00:00.00]orphan", encoding="utf-8")

        for name in ("secret.txt", "orphan.lrc"):
            with self.subTest(name=name):
                with self.assertRaises(HTTPError) as caught:
                    urlopen(f"{self.base_url}/api/v1/files/{name}")
                self.assertEqual(404, caught.exception.code)
                caught.exception.close()

    def test_unknown_endpoint_returns_404(self):
        with self.assertRaises(HTTPError) as caught:
            urlopen(f"{self.base_url}/api/v1/missing")

        self.assertEqual(404, caught.exception.code)
        caught.exception.close()


if __name__ == "__main__":
    unittest.main()
