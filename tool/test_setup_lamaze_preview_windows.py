import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("setup_lamaze_preview_windows.ps1")


class WindowsLamazePreviewSetupTests(unittest.TestCase):
    def test_script_is_scoped_pinned_and_independent_from_flutter(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("E:\\AIModels\\LamazeAudio", text)
        self.assertIn("074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc", text)
        self.assertIn("fbb71de2afe387ed854eebd80b9f3d078c6b9869", text)
        self.assertIn("706bee1915e9fd1f1214929e2a0509c874cff433", text)
        self.assertIn("6dd651d55dde97fd4028699be9d4481f26917891", text)
        self.assertIn("sfizz-1.2.3-win64.zip", text)
        self.assertIn("Gyan.FFmpeg.Essentials", text)
        self.assertIn("Python.Python.3.10", text)
        self.assertIn("venv-py310", text)
        self.assertIn("py -0p", text)
        self.assertLess(text.index("py -0p"), text.index("py -3.10 -c"))
        self.assertIn("py -3.10 -m venv", text)
        self.assertNotIn("py -3.9 -m venv", text)
        self.assertNotIn("dart", text.lower())
        self.assertNotIn("flutter", text.lower())
        self.assertNotIn("E:\\music", text)

    def test_existing_repository_mismatch_stops_instead_of_overwriting(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("git -C $Path rev-parse HEAD", text)
        self.assertIn("does not match pinned commit", text)
        self.assertNotIn("git reset --hard", text)
        self.assertNotIn("Remove-Item -Recurse", text)

    def test_script_verifies_cuda_models_patches_and_free_space(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("torch.cuda.is_available", text)
        self.assertIn("NVIDIA GeForce RTX 3060 Ti", text)
        self.assertIn("cosyvoice.yaml", text)
        self.assertIn("UprightPiano.sfz", text)
        self.assertIn("ViolinEnsSusVib-Quiet.sfz", text)
        self.assertIn("CelloEnsSusVib-Quiet.sfz", text)
        self.assertIn("100GB", text)
        self.assertIn("runtime-sources.json", text)

    def test_script_bootstraps_legacy_whisper_before_full_requirements(self):
        text = SCRIPT.read_text(encoding="utf-8")

        wheel = "'wheel==0.45.1'"
        whisper = "'openai-whisper==20231117'"
        no_build_isolation = "--no-build-isolation"
        requirements = "-r $requirementsPath"

        self.assertIn("'setuptools==65.5.0'", text)
        self.assertIn(wheel, text)
        self.assertIn(whisper, text)
        self.assertIn(no_build_isolation, text)
        self.assertLess(text.index(wheel), text.index(whisper))
        self.assertLess(text.index(whisper), text.index(requirements))

    def test_model_download_uses_resumable_conservative_network_settings(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn('os.environ["HF_HUB_DOWNLOAD_TIMEOUT"] = "120"', text)
        self.assertIn('os.environ["HF_HUB_ETAG_TIMEOUT"] = "120"', text)
        self.assertEqual(text.count("max_workers=1"), 2)

    def test_cuda_probe_avoids_nested_native_argument_quotes(self):
        text = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("json.dumps(dict(available=", text)
        self.assertIn("else None", text)
        self.assertNotIn('json.dumps({"available"', text)


if __name__ == "__main__":
    unittest.main()
