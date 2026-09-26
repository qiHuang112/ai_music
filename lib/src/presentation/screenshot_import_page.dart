import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../application/music_controller.dart';
import '../application/download_queue_controller.dart';
import '../application/screenshot_matcher.dart';
import '../application/screenshot_song_parser.dart';
import '../data/music_resolver.dart';
import '../data/music_playlists.dart';
import '../platform/screenshot_ocr.dart';
import 'app_localizations.dart';
import 'playlist_actions.dart';

List<XFile> orderPickedScreenshots(List<XFile> picked) {
  final screenshotName = RegExp(
    r'^screenshot[_-]\d{4}-\d{2}-\d{2}[-_]\d{2}-\d{2}-\d{2}',
    caseSensitive: false,
  );
  if (!picked.every((image) => screenshotName.hasMatch(image.name))) {
    return picked;
  }
  return [...picked]..sort((a, b) => a.name.compareTo(b.name));
}

class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({
    super.key,
    required this.controller,
    this.ocr = const OnDeviceScreenshotOcr(),
    this.picker,
    this.pickImages,
    this.matcher,
    this.openPickerOnStart = false,
  });

  final MusicController controller;
  final ScreenshotOcr ocr;
  final ImagePicker? picker;
  final Future<List<XFile>> Function()? pickImages;
  final ScreenshotMatcher? matcher;
  final bool openPickerOnStart;

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ImportRow {
  _ImportRow(this.draft);

  ScreenshotSongDraft draft;
  List<MusicSearchCandidate> candidates = const [];
  MusicSearchCandidate? selected;
  MusicSearchCandidate? recommended;
  bool searching = false;
  bool expanded = false;
  bool searched = false;
  int request = 0;
  String? error;

  String get key => '${draft.imageId}\u001f${draft.row}';
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _images = <XFile>[];
  final _ocrLines = <String, List<ScreenshotTextLine>>{};
  final _rows = <_ImportRow>[];
  final _downloadErrors = <String, String>{};
  final _parser = const ScreenshotSongParser();
  late final ScreenshotMatcher _matcher;
  bool _recognizing = false;
  bool _adding = false;
  bool _searchingAll = false;
  int _searchGeneration = 0;
  Future<void>? _searchTask;
  String? _error;

  @override
  void initState() {
    super.initState();
    _matcher = widget.matcher ?? widget.controller.createScreenshotMatcher();
    if (widget.openPickerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickImages(initial: true);
      });
    }
  }

  @override
  void dispose() {
    _searchGeneration += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final selected = _rows.where((row) => row.selected != null).length;
    final verified = _rows.where((row) => row.searched).length;
    final processing = _recognizing || _searchingAll;
    final visibleRows = processing
        ? _rows.where((row) => row.searched).toList(growable: false)
        : _rows;
    return Scaffold(
      appBar: AppBar(title: Text(strings.importScreenshots)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _recognizing ? null : () => _pickImages(),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(zh ? '选择截图' : 'Choose images'),
                  ),
                  const SizedBox(width: 12),
                  if (_images.isNotEmpty)
                    Text(
                      zh ? '${_images.length} 张图片' : '${_images.length} images',
                    ),
                  if (_recognizing) ...[
                    const SizedBox(width: 12),
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
            if (_images.isNotEmpty)
              SizedBox(
                height: 102,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _images.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final image = _images.removeAt(oldIndex);
                      _images.insert(newIndex, image);
                      _rebuildRows();
                    });
                  },
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    return Padding(
                      key: ValueKey(image.path),
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        children: [
                          InkWell(
                            onTap: () => _preview(image),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(image.path),
                                width: 78,
                                height: 96,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton.filledTonal(
                              tooltip: zh ? '删除图片' : 'Remove image',
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _images.removeAt(index);
                                  _ocrLines.remove(image.path);
                                  _rebuildRows();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      processing
                          ? (zh
                                ? '正在搜索 · $verified/${_rows.length} 首'
                                : 'Searching $verified/${_rows.length} songs')
                          : (zh
                                ? '已处理 $verified/${_rows.length} 首 · 已勾选 $selected 首'
                                : '$verified/${_rows.length} checked · $selected selected'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: visibleRows.isEmpty && processing
                  ? const Center(child: CircularProgressIndicator())
                  : visibleRows.isEmpty
                  ? Center(
                      child: Text(
                        _images.isEmpty
                            ? (zh ? '选择歌单截图' : 'Choose playlist screenshots')
                            : (zh ? '未识别出歌曲，可换图重试' : 'No songs found'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visibleRows.length + (processing ? 1 : 0),
                      itemBuilder: (context, index) =>
                          index == visibleRows.length
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _buildRow(visibleRows[index], index, zh),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _rows.isEmpty || processing
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(zh ? '已选 $selected 首' : '$selected selected'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: selected == 0 || _adding ? null : _addToPlaylist,
                    child: Text(zh ? '加入歌单' : 'Add to playlist'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: selected == 0 || _adding
                        ? null
                        : _downloadSelectedTracks,
                    child: Text(zh ? '下载已选' : 'Download selected'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRow(_ImportRow row, int rowIndex, bool zh) {
    final draft = row.draft;
    final imageIndex = _images.indexWhere(
      (image) => image.path == draft.imageId,
    );
    final status = row.selected != null
        ? (zh
              ? '已选 · 候选 ${row.candidates.length} 首'
              : 'Selected · ${row.candidates.length} choices')
        : row.recommended != null
        ? (zh
              ? '未勾选 · 候选 ${row.candidates.length} 首'
              : 'Not selected · ${row.candidates.length} choices')
        : row.searching
        ? (zh ? '正在搜索' : 'Searching')
        : row.searched
        ? (zh ? '未搜到' : 'No results')
        : (zh ? '未搜索' : 'Not searched');
    return Column(
      children: [
        ListTile(
          leading: Semantics(
            label: zh ? '选择 ${draft.title}' : 'Select ${draft.title}',
            child: Checkbox(
              value: row.selected != null,
              onChanged: row.recommended == null
                  ? null
                  : (checked) => setState(() {
                      row.selected = checked == true ? row.recommended : null;
                    }),
            ),
          ),
          title: Text(draft.title),
          subtitle: Text(
            '${draft.artist.isEmpty ? (zh ? '未识别歌手' : 'Artist unknown') : draft.artist}'
            '${draft.version.isEmpty ? '' : ' · ${draft.version}'}'
            ' · ${zh ? '图' : 'Image '}${imageIndex + 1}'
            '${status.isEmpty ? '' : '\n$status'}',
          ),
          onTap: row.candidates.isNotEmpty
              ? () => setState(() => row.expanded = !row.expanded)
              : row.searched && !row.searching
              ? () => _matchRow(row)
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (row.candidates.isNotEmpty)
                Icon(row.expanded ? Icons.expand_less : Icons.expand_more)
              else if (row.searched && !row.searching)
                IconButton(
                  tooltip: zh ? '重试查找' : 'Retry matches',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _matchRow(row),
                ),
              IconButton(
                tooltip: zh ? '修改识别结果' : 'Edit recognition',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editRow(row),
              ),
            ],
          ),
        ),
        if (row.searching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
        if (row.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              row.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (row.selected != null &&
            _downloadErrors.containsKey(_candidateKey(row.selected!)))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(_downloadErrors[_candidateKey(row.selected!)]!),
                ),
                TextButton(
                  onPressed: _adding
                      ? null
                      : () => _retryDownload(row.selected!),
                  child: Text(zh ? '重试下载' : 'Retry download'),
                ),
              ],
            ),
          ),
        if (row.expanded)
          for (final candidate in row.candidates)
            ListTile(
              dense: true,
              onTap: () => _chooseCandidate(row, candidate),
              title: Text(candidate.name),
              subtitle: Text('${candidate.artist} · ${candidate.sourceLabel}'),
              trailing: Icon(
                row.selected != null &&
                        _candidateKey(row.selected!) == _candidateKey(candidate)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
            ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _pickImages({bool initial = false}) async {
    try {
      final platform = ImagePickerPlatform.instance;
      if (platform is ImagePickerAndroid) {
        platform.useAndroidPhotoPicker = true;
      }
      final picked =
          await (widget.pickImages?.call() ??
              (widget.picker ?? ImagePicker()).pickMultiImage());
      if (!mounted) return;
      if (picked.isEmpty) {
        if (initial && _images.isEmpty) Navigator.of(context).pop();
        return;
      }
      final orderedPicked = orderPickedScreenshots(picked);
      setState(() {
        for (final image in orderedPicked) {
          if (_images.every((existing) => existing.path != image.path)) {
            _images.add(image);
          }
        }
        _recognizing = true;
        _error = null;
      });
      for (final image in orderedPicked) {
        if (_ocrLines.containsKey(image.path)) continue;
        try {
          _ocrLines[image.path] = await widget.ocr.recognize(image.path);
        } catch (error) {
          _error = '图片识别失败：$error';
        }
      }
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _rebuildRows();
        _searchingAll = _rows.isNotEmpty;
      });
      if (_rows.isNotEmpty) _startBackgroundSearch();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = '无法选择图片：$error';
      });
    }
  }

  void _rebuildRows() {
    final previous = {for (final row in _rows) row.key: row};
    final parsed = _parser.parse([
      for (final image in _images)
        (image.path, _ocrLines[image.path] ?? const <ScreenshotTextLine>[]),
    ]);
    _rows
      ..clear()
      ..addAll([
        for (final draft in parsed)
          previous['${draft.imageId}\u001f${draft.row}'] ?? _ImportRow(draft),
      ]);
  }

  Future<bool> _matchRow(_ImportRow row) async {
    if (!mounted || !_rows.contains(row)) return false;
    final request = ++row.request;
    setState(() {
      row.searched = false;
      row.searching = true;
      row.error = null;
      row.candidates = const [];
      row.selected = null;
      row.recommended = null;
    });
    try {
      final match = await _matcher.match(row.draft);
      if (!mounted || !_rows.contains(row) || row.request != request) {
        return false;
      }
      setState(() {
        row.candidates = match.candidates;
        row.recommended = match.recommended;
        row.selected = match.recommended;
      });
      return true;
    } catch (error) {
      if (mounted && _rows.contains(row) && row.request == request) {
        setState(() => row.error = '搜索失败：$error');
      }
      return false;
    } finally {
      if (mounted && _rows.contains(row) && row.request == request) {
        setState(() {
          row.searching = false;
          row.searched = true;
        });
      }
    }
  }

  void _chooseCandidate(_ImportRow row, MusicSearchCandidate candidate) {
    if (row.selected != null &&
        _candidateKey(row.selected!) == _candidateKey(candidate)) {
      setState(() => row.selected = null);
      return;
    }
    setState(() {
      row.error = null;
      row.recommended = candidate;
      row.selected = candidate;
    });
  }

  void _startBackgroundSearch() {
    final generation = ++_searchGeneration;
    final previousTask = _searchTask;
    _searchTask = () async {
      if (previousTask != null) await previousTask;
      if (mounted && generation == _searchGeneration) {
        await _searchAll(generation);
      }
    }();
  }

  Future<void> _searchAll(int generation) async {
    setState(() => _searchingAll = true);
    var consecutiveFailures = 0;
    try {
      final pending = List<_ImportRow>.of(_rows);
      for (var offset = 0; offset < pending.length; offset += 3) {
        if (!mounted || generation != _searchGeneration) return;
        final batch = pending.skip(offset).take(3).toList(growable: false);
        final outcomes = await Future.wait([
          for (final row in batch)
            if (_rows.contains(row) && !row.searched && !row.searching)
              _matchRow(row)
            else
              Future<bool>.value(true),
        ]);
        for (var index = 0; index < batch.length; index += 1) {
          if (!_rows.contains(batch[index])) continue;
          consecutiveFailures = outcomes[index] ? 0 : consecutiveFailures + 1;
          if (consecutiveFailures >= 3) {
            if (mounted && generation == _searchGeneration) {
              setState(() => _error = '歌源暂不可用，已暂停后续查找');
            }
            return;
          }
        }
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searchingAll = false);
      }
    }
  }

  Future<void> _editRow(_ImportRow row) async {
    final edited = await showDialog<ScreenshotSongDraft>(
      context: context,
      builder: (context) => _EditScreenshotSongDialog(draft: row.draft),
    );
    if (!mounted || !_rows.contains(row)) return;
    if (edited != null) {
      setState(() {
        row.draft = edited;
      });
      await _matchRow(row);
    }
  }

  void _preview(XFile image) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          Dialog(child: InteractiveViewer(child: Image.file(File(image.path)))),
    );
  }

  Future<void> _addToPlaylist() async {
    final selected = [
      for (final row in _rows)
        if (row.selected != null) row.selected!,
    ];
    final playlist = await showModalBottomSheet<MusicPlaylist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('新建歌单'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final created = await showCreatePlaylistDialog(
                  context,
                  widget.controller,
                );
                if (mounted && created != null) {
                  await _saveSelection(created, selected);
                }
              },
            ),
            for (final playlist in widget.controller.customPlaylists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                onTap: () => Navigator.pop(sheetContext, playlist),
              ),
          ],
        ),
      ),
    );
    if (playlist != null && mounted) {
      await _saveSelection(playlist, selected);
    }
  }

  Future<void> _saveSelection(
    MusicPlaylist playlist,
    List<MusicSearchCandidate> selected,
  ) async {
    setState(() => _adding = true);
    try {
      await widget.controller.addCandidatesToPlaylist(playlist, selected);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已加入 ${playlist.name}')));
    } catch (error) {
      if (mounted) setState(() => _error = '添加失败：$error');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _downloadSelectedTracks() async {
    final selected = [
      for (final row in _rows)
        if (row.selected != null) row.selected!,
    ];
    setState(() => _adding = true);
    var downloaded = 0;
    var failed = 0;
    try {
      for (final candidate in selected) {
        if (!mounted) return;
        final error = await _downloadSelected(candidate);
        if (error == null) {
          downloaded += 1;
        } else {
          failed += 1;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载 $downloaded 首，失败 $failed 首')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<String?> _downloadSelected(MusicSearchCandidate candidate) async {
    final key = _candidateKey(candidate);
    if (widget.controller.isCandidateCached(candidate)) {
      if (mounted) setState(() => _downloadErrors.remove(key));
      return null;
    }
    try {
      final task = await widget.controller.downloadCandidateAndWait(
        candidate,
        requireExactIdentity: false,
      );
      final error = task?.status == DownloadTaskStatus.completed
          ? null
          : task?.error.isNotEmpty == true
          ? task!.error
          : '下载未完成';
      if (mounted) {
        setState(() {
          if (error == null) {
            _downloadErrors.remove(key);
          } else {
            _downloadErrors[key] = error;
          }
        });
      }
      return error;
    } catch (error) {
      if (mounted) setState(() => _downloadErrors[key] = '$error');
      return '$error';
    }
  }

  Future<void> _retryDownload(MusicSearchCandidate candidate) async {
    setState(() => _adding = true);
    await _downloadSelected(candidate);
    if (mounted) setState(() => _adding = false);
  }

  static String _candidateKey(MusicSearchCandidate candidate) =>
      '${candidate.source.storageValue}|${candidate.platform}|${candidate.id}';
}

class _EditScreenshotSongDialog extends StatefulWidget {
  const _EditScreenshotSongDialog({required this.draft});

  final ScreenshotSongDraft draft;

  @override
  State<_EditScreenshotSongDialog> createState() =>
      _EditScreenshotSongDialogState();
}

class _EditScreenshotSongDialogState extends State<_EditScreenshotSongDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.draft.title,
  );
  late final TextEditingController _artist = TextEditingController(
    text: widget.draft.artist,
  );
  late final TextEditingController _version = TextEditingController(
    text: widget.draft.version,
  );

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _version.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改识别结果'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: '歌名'),
        ),
        TextField(
          controller: _artist,
          decoration: const InputDecoration(labelText: '歌手'),
        ),
        TextField(
          controller: _version,
          decoration: const InputDecoration(labelText: '版本'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_title.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            widget.draft.copyWith(
              title: _title.text.trim(),
              artist: _artist.text.trim(),
              version: _version.text.trim(),
            ),
          );
        },
        child: const Text('保存并重新搜索'),
      ),
    ],
  );
}
