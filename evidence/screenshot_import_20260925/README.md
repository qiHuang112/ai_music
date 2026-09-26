# Screenshot Import Device Check

- Device: wireless ADB `192.168.31.77:37769`; installed `com.qi.ai.music` with `adb install -r` and no data removal.
- OCR screenshot candidate APK and pulled device `base.apk`: `088c7cab7c073a55f65d5620f081d98b113d35b9a67ffc1cd3c1fe8f6feb149e` (SHA-256), installed at `2026-09-25 19:51:54` local time.
- Final APK and pulled device `base.apk`: `0c99604f51717624e50076bb7e81e8e67cb01a1c252299f4297f033ff465a609` (SHA-256), installed at `2026-09-25 20:00:04` local time. The final change only affected next-song prefetch behavior; it passed launch check, not a repeated OCR screenshot capture. Sogou IME remained default.
- `home-awake.png`: original LAN playlist remained after the first preserve-data update.
- `import-empty.png`: screenshot entry and empty import page.
- `synthetic-playlist.png`: developer-generated image, not a user photo.
- `synthetic-ocr-result.png`: first device pass, exposing a false heading and compact separator bug.
- `synthetic-ocr-result-final.png`: final installed build reads two rows, `稻香 / 周杰伦` and `哎呀 / 王蓉`; only the first passed automatic selection. This demonstrates OCR and correction, not accuracy on the user's actual screenshots or complete media playback.
- The generated image and temporary picker XML were removed from device storage after verification. No user photo was selected.
