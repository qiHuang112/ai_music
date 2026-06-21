# just_audio_harmonyos

- Package: `just_audio_harmonyos`
- Vendored version: `0.0.1`
- Upstream repository: https://github.com/Wayaer/harmony_flutter_packages/tree/main/just_audio_harmonyos
- Package metadata: https://pub.dev/packages/just_audio_harmonyos
- Pub.dev license metadata: `BSD-3-Clause`

This vendored package is used to provide a HarmonyOS implementation of the
`just_audio` Flutter platform interface for AI Music. The upstream package
license file is retained in `LICENSE`.

Native ETS sources in the package contain Huawei copyright headers with
MIT-style permission terms. The HarmonyOS package metadata therefore uses the
SPDX-style expression `MIT AND BSD-3-Clause` to reflect the source headers and
the package license metadata.

Local changes:

- Vendored the plugin into AI Music under `third_party/` for reproducible
  HarmonyOS builds.
- Kept AI Music compatibility changes for offline cache playback.
- Added file descriptor and AVSession cleanup for long-running playback.
- Removed the upstream example app and bundled demo audio, because AI Music does
  not build or redistribute the example.
