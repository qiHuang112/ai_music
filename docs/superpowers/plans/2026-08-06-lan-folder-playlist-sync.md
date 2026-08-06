# LAN Folder Playlist Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent execution is not enabled for this task.

**Goal:** Extend schema-v1 LAN imports so every folder that directly contains songs maps to one incrementally merged custom playlist without deleting phone data.

**Architecture:** The Python server emits a validated optional `folderPath` on each track. Flutter parses that field, imports tracks with the existing two-worker pool, then passes successful local cache IDs to a focused `LanFolderPlaylistMerger` that performs one serialized playlist merge after downloads finish. Existing playlist JSON remains backward compatible through an optional `lanFolderKey`.

**Tech Stack:** Python 3.9 standard library, Dart 3.9, Flutter, `unittest`, `flutter_test`, existing `PlaylistStore` and `CachedTrackStore`.

## Global Constraints

- Keep server `schemaVersion: 1`; `folderPath` is optional and old manifests still import.
- Python LAN server remains Python 3.9 standard-library-only.
- A direct song folder maps to its root-relative POSIX path, such as `胎教/钢琴`.
- Root-level songs do not create a playlist.
- Sync is additive: never delete cached tracks, playlist members, playlists, or favorites.
- Reuse an unbound same-name custom playlist and preserve its existing members and order.
- A failed track must not prevent successful tracks from joining their playlists.
- Android version becomes `1.0.0-lan.2+2102`.

---

### Task 1: Emit folder paths from the Python manifest

**Files:**
- Modify: `tool/lan_music_server.py`
- Test: `tool/test_lan_music_server.py`

**Interfaces:**
- Consumes: `build_manifest(root: Path, base_url: str = "") -> Dict[str, object]`
- Produces: track JSON field `folderPath: str`, where root songs use `""`

- [ ] **Step 1: Add failing server tests**

Add assertions that a direct folder returns `Lamaze`, a Chinese nested folder returns `胎教/钢琴`, a root song returns `""`, and sidecar album metadata cannot change the folder path:

```python
def test_manifest_exposes_direct_and_nested_folder_paths(self):
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
```

- [ ] **Step 2: Run the server test and confirm RED**

Run: `python3 -m unittest tool/test_lan_music_server.py`

Expected: FAIL because `folderPath` is absent.

- [ ] **Step 3: Add the minimal manifest implementation**

Compute the parent path from the already resolved safe audio file and emit it independently of sidecar metadata:

```python
def _folder_path(root: Path, audio: Path) -> str:
    parent = audio.parent.relative_to(root)
    if parent == Path("."):
        return ""
    value = parent.as_posix()
    parts = PurePosixPath(value).parts
    if not parts or any(part in {"", ".", ".."} or "\\" in part or "\x00" in part for part in parts):
        raise ValueError("Unsafe folder path")
    return value
```

Set `"folderPath": _folder_path(resolved_root, audio)` in every track.

- [ ] **Step 4: Run Python tests and confirm GREEN**

Run: `python3 -m unittest tool/test_lan_music_server.py`

Expected: all tests pass.

- [ ] **Step 5: Commit the protocol change**

```bash
git add tool/lan_music_server.py tool/test_lan_music_server.py
git commit -m "feat: expose LAN track folder paths"
```

### Task 2: Parse and validate `folderPath` in Flutter

**Files:**
- Modify: `lib/src/data/lan_library_models.dart`
- Modify: `test/lan_library_models_test.dart`

**Interfaces:**
- Consumes: optional track JSON `folderPath`
- Produces: `LanTrackEntry.folderPath: String`
- Produces: `normalizeLanFolderPath(Object? value) -> String`

- [ ] **Step 1: Add failing model tests**

Add test cases for missing/empty paths, `Lamaze`, `胎教/钢琴`, and rejection of `/absolute`, `../secret`, `胎教\\钢琴`, empty segments, NUL, query-like traversal after decoding, and paths longer than 1024 characters.

```dart
test('folderPath accepts safe nested POSIX paths', () {
  final json = _manifestJson();
  ((json['tracks']! as List).single as Map)['folderPath'] = '胎教/钢琴';
  expect(LanLibraryManifest.fromJson(json).tracks.single.folderPath, '胎教/钢琴');
});

test('folderPath rejects traversal and backslashes', () {
  for (final value in ['../secret', '/Lamaze', r'胎教\钢琴', 'a//b']) {
    final json = _manifestJson();
    ((json['tracks']! as List).single as Map)['folderPath'] = value;
    expect(() => LanLibraryManifest.fromJson(json), throwsFormatException);
  }
});
```

- [ ] **Step 2: Run model tests and confirm RED**

Run: `../tools/flutter/bin/flutter test test/lan_library_models_test.dart`

Expected: FAIL because `LanTrackEntry.folderPath` is undefined.

- [ ] **Step 3: Implement strict optional-path parsing**

Add the field and parser:

```dart
String normalizeLanFolderPath(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) return '';
  if (raw.length > 1024 || raw.startsWith('/') || raw.contains(r'\') || raw.contains('\u0000')) {
    throw const FormatException('track.folderPath 必须是安全的相对 POSIX 路径');
  }
  final segments = raw.split('/');
  if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('track.folderPath 不能包含空目录或目录穿越');
  }
  return segments.join('/');
}
```

Default a missing field to `""`.

- [ ] **Step 4: Run model and client tests**

Run: `../tools/flutter/bin/flutter test test/lan_library_models_test.dart test/lan_library_client_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit client protocol parsing**

```bash
git add lib/src/data/lan_library_models.dart test/lan_library_models_test.dart
git commit -m "feat: parse LAN folder paths"
```

### Task 3: Persist LAN folder ownership on custom playlists

**Files:**
- Modify: `lib/src/data/music_playlists.dart`
- Modify: `test/music_playlists_test.dart`

**Interfaces:**
- Produces: `MusicPlaylist.lanFolderKey: String`
- Extends: `MusicPlaylist.copyWith({String? lanFolderKey, bool clearLanFolderKey = false})`
- Persists: optional JSON key `lanFolderKey`

- [ ] **Step 1: Add failing migration and round-trip tests**

```dart
test('playlist store round-trips optional LAN folder ownership', () async {
  final playlist = MusicPlaylist(
    id: 'playlist-lamaze',
    name: 'Lamaze',
    lanFolderKey: 'lan:test-library:folder:lamaze',
    trackIds: const ['track-1'],
    createdAt: DateTime(2026, 8, 6),
    updatedAt: DateTime(2026, 8, 6),
  );
  await store.write(PlaylistLibrary(playlists: [playlist]));
  expect((await store.load()).playlists.single.lanFolderKey,
      'lan:test-library:folder:lamaze');
});
```

Also assert that legacy playlist JSON without the key loads with an empty key.

- [ ] **Step 2: Run the playlist tests and confirm RED**

Run: `../tools/flutter/bin/flutter test test/music_playlists_test.dart`

Expected: compile failure because `lanFolderKey` does not exist.

- [ ] **Step 3: Implement backward-compatible persistence**

Add `this.lanFolderKey = ''` to the constructor, include non-empty `lanFolderKey` in `toJson`, and parse it with `.trim()` in `fromJson`. Ensure every `copyWith` call preserves the value by default.

- [ ] **Step 4: Run playlist tests and confirm GREEN**

Run: `../tools/flutter/bin/flutter test test/music_playlists_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit playlist metadata support**

```bash
git add lib/src/data/music_playlists.dart test/music_playlists_test.dart
git commit -m "feat: persist LAN folder playlist ownership"
```

### Task 4: Add the isolated incremental playlist merger

**Files:**
- Create: `lib/src/application/lan_folder_playlist_merger.dart`
- Create: `test/lan_folder_playlist_merger_test.dart`

**Interfaces:**
- Consumes: `LanFolderTrack(index, folderPath, trackId)`
- Produces: `LanFolderPlaylistMergeResult(created, updated)`
- Produces: `Future<LanFolderPlaylistMergeResult> merge({required String libraryId, required Iterable<LanFolderTrack> tracks, required Set<String> validTrackIds})`

- [ ] **Step 1: Write failing behavior tests**

Cover first creation, reuse of an unbound same-name playlist, stable-key lookup after user rename, nested folders, manifest-order appends, duplicate sync, preservation of old entries/order, and a deterministic name when a same-name playlist is bound to another library.

```dart
final result = await merger.merge(
  libraryId: 'library-one',
  tracks: const [
    LanFolderTrack(index: 0, folderPath: 'Lamaze', trackId: 'a'),
    LanFolderTrack(index: 1, folderPath: 'Lamaze', trackId: 'b'),
  ],
  validTrackIds: const {'manual', 'a', 'b'},
);
expect(result.created, 0);
final merged = (await store.load()).playlists.single;
expect(merged.trackIds, const ['manual', 'a', 'b']);
expect(merged.lanFolderKey, 'lan:library-one:folder:lamaze');
```

- [ ] **Step 2: Run merger tests and confirm RED**

Run: `../tools/flutter/bin/flutter test test/lan_folder_playlist_merger_test.dart`

Expected: compile failure because the merger is absent.

- [ ] **Step 3: Implement one read-modify-write transaction**

The implementation must:

```dart
String lanFolderKey(String libraryId, String folderPath) =>
    'lan:$libraryId:folder:${folderPath.toLowerCase()}';
```

Sort track references by `index`, group non-empty paths, load once, locate by key then unbound exact name, append only new IDs, and write once with `validTrackIds`. A playlist is counted as updated when it is adopted or receives at least one new member.

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run: `../tools/flutter/bin/flutter test test/lan_folder_playlist_merger_test.dart test/music_playlists_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit the merger**

```bash
git add lib/src/application/lan_folder_playlist_merger.dart test/lan_folder_playlist_merger_test.dart
git commit -m "feat: merge LAN folders into playlists"
```

### Task 5: Integrate playlist merging into LAN sync

**Files:**
- Modify: `lib/src/application/lan_sync_use_case.dart`
- Modify: `lib/src/application/music_controller.dart`
- Modify: `test/lan_sync_use_case_test.dart`
- Modify: `test/music_controller_test.dart`

**Interfaces:**
- `LanSyncUseCase` receives `PlaylistStore` or `LanFolderPlaylistMerger`
- `LanSyncResult` adds `playlistsCreated`, `playlistsUpdated`, and `playlistError`

- [ ] **Step 1: Add failing integration tests**

Extend `_trackJson` with an optional `folderPath`. Test that four successful Lamaze imports yield one ordered playlist, a bad hash is omitted while good tracks are merged, repeat sync is idempotent, an empty/missing path does nothing, a removed manifest track remains in the phone playlist, and a playlist write failure leaves imported cache files present while returning `playlistError`.

- [ ] **Step 2: Run sync/controller tests and confirm RED**

Run: `../tools/flutter/bin/flutter test test/lan_sync_use_case_test.dart test/music_controller_test.dart`

Expected: failures because sync does not merge playlists.

- [ ] **Step 3: Collect successful local IDs without changing worker concurrency**

For every `LanCacheImportResult`, add:

```dart
importedTracks.add(LanFolderTrack(
  index: index,
  folderPath: track.folderPath,
  trackId: imported.cached.cacheId,
));
```

After `Future.wait`, list cached records to build `validTrackIds`, call the merger once, and catch only playlist merge errors into `playlistError`; do not turn successful audio imports into track failures.

- [ ] **Step 4: Wire the controller to the same `PlaylistStore`**

Construct the default use case with `_playlistStore`, then retain the existing `await loadCache(repairLegacy: false)` after sync so the custom-playlist UI refreshes immediately.

- [ ] **Step 5: Run integration tests and confirm GREEN**

Run: `../tools/flutter/bin/flutter test test/lan_sync_use_case_test.dart test/music_controller_test.dart test/music_playlists_test.dart`

Expected: all tests pass, including the existing two-worker concurrency assertion.

- [ ] **Step 6: Commit sync integration**

```bash
git add lib/src/application/lan_sync_use_case.dart lib/src/application/music_controller.dart test/lan_sync_use_case_test.dart test/music_controller_test.dart
git commit -m "feat: sync LAN folders into custom playlists"
```

### Task 6: Show playlist results and bump the release version

**Files:**
- Modify: `lib/src/presentation/app_localizations.dart`
- Modify: `lib/src/presentation/download_manager_page.dart`
- Modify: `test/widget_test.dart`
- Modify: `pubspec.yaml`
- Modify: `test/lan_android_config_test.dart`

**Interfaces:**
- Extends: `lanSyncSummary` with playlist counts
- Displays: non-fatal playlist error below the summary

- [ ] **Step 1: Add failing UI and version assertions**

Assert Chinese summary text contains `新建 1 个歌单` and that `pubspec.yaml` contains `version: 1.0.0-lan.2+2102`.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `../tools/flutter/bin/flutter test test/widget_test.dart test/lan_android_config_test.dart`

Expected: summary/version assertions fail.

- [ ] **Step 3: Update localized copy, UI and version**

Change `lanSyncSummary` to receive playlist counts and render both song and playlist outcomes. If `playlistError != null`, show a non-fatal red message stating that songs were saved but playlist merging can be retried.

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run: `../tools/flutter/bin/flutter test test/widget_test.dart test/lan_android_config_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit UI/version changes**

```bash
git add lib/src/presentation/app_localizations.dart lib/src/presentation/download_manager_page.dart test/widget_test.dart pubspec.yaml test/lan_android_config_test.dart
git commit -m "feat: report LAN playlist sync results"
```

### Task 7: Verify the full folder-playlist feature

**Files:**
- Modify after evidence exists: `docs/codex_collab/requests/AM-20260806-001-lamaze-audio-folder-playlists.md`

- [ ] **Step 1: Run all Python LAN tests**

Run: `python3 -m unittest tool/test_lan_music_server.py`

Expected: all tests pass.

- [ ] **Step 2: Run the complete Flutter test suite**

Run: `../tools/flutter/bin/flutter test`

Expected: zero failures.

- [ ] **Step 3: Run static analysis**

Run: `../tools/flutter/bin/flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Build the Android release APK**

Run: `../tools/flutter/bin/flutter build apk --release`

Expected: exit code 0 and `build/app/outputs/flutter-apk/app-release.apk` exists.

- [ ] **Step 5: Verify the real Windows manifest**

Run through SSH: `python E:\AIHome\ai_music\tool\lan_music_server.py --root E:\music --host 127.0.0.1 --port 0` is not used as a persistent process; instead copy the updated server, restart the existing port 8787 service, and verify `/api/v1/library` reports the four Lamaze tracks with `folderPath: "Lamaze"`.

- [ ] **Step 6: Install and test only on Xiaomi 10 Pro**

Use the current user-provided endpoint for Mi 10 Pro. Preserve app data when signing allows it; if signing conflicts, stop for explicit uninstall authorization. Verify first sync, one `Lamaze` playlist with four tracks, repeat sync without duplicates, lyrics, playback, and offline playback after the server stops.

- [ ] **Step 7: Record evidence and commit**

Update the request with exact test counts, HEAD, APK path/SHA-256, server result, device endpoint/model, and observed playlist membership, then commit only those evidence changes.
