import 'music_thumbnail.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import '../data/music_playlists.dart';
import '../data/online_playlists.dart';
import 'app_localizations.dart';

class DirectPlaylistPage extends StatefulWidget {
  const DirectPlaylistPage({
    super.key,
    required this.playlist,
    required this.repository,
    required this.controller,
    required this.onOpenPlaylist,
  });
  final OnlinePlaylist playlist;
  final OnlinePlaylistRepository repository;
  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  @override
  State<DirectPlaylistPage> createState() => _DirectPlaylistPageState();
}

class _DirectPlaylistPageState extends State<DirectPlaylistPage> {
  OnlinePlaylistDetail? _detail;
  MusicPlaylist? _destination;
  final _selected = <int>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loaded = 0;
  int _total = 0;
  int _request = 0;
  bool get zh => AppStringsScope.of(context).isZh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.load(
        widget.playlist,
        isCanceled: () => !mounted || request != _request,
        onProgress: (loaded, total) {
          if (mounted && request == _request) {
            setState(() {
              _loaded = loaded;
              _total = total;
            });
          }
        },
      );
      if (!mounted || request != _request) return;
      setState(() {
        _detail = result;
        _selected.addAll(Iterable.generate(result.songs.length));
        _loading = false;
      });
      if (result.unavailable > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 76),
            content: Text(
              zh
                  ? '已读取 ${result.songs.length} 首，另 ${result.unavailable} 首暂无法读取。'
                  : '${result.songs.length} loaded; ${result.unavailable} unavailable.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = zh ? '歌单读取失败，请重试' : 'Could not load playlist. Retry.';
        });
      }
    }
  }

  Future<void> _add(MusicPlaylist? target) async {
    if (_saving || _selected.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final indexes = _selected.toList()..sort();
    try {
      final result = await widget.controller.addPlaylistDirectly(
        widget.playlist,
        [for (final i in indexes) _detail!.songs[i]],
        target: target,
      );
      if (result == null) throw StateError('No playlist saved');
      if (mounted) {
        setState(() {
          _destination = result;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = zh ? '加入失败，歌曲列表已保留，请重试' : 'Could not save playlist. Retry.';
        });
      }
    }
  }

  Future<void> _chooseTarget() async {
    final target = await showModalBottomSheet<MusicPlaylist>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (widget.controller.customPlaylists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(zh ? '还没有歌单，请先新建歌单' : 'Create a playlist first.'),
              ),
            for (final p in widget.controller.customPlaylists)
              ListTile(
                title: Text(p.name),
                subtitle: Text('${p.trackIds.length} ${zh ? '首' : 'songs'}'),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (mounted && target != null) await _add(target);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (detail != null) ...[
              Text(
                zh
                    ? '已选 ${_selected.length} 首'
                    : '${_selected.length} selected',
              ),
              Checkbox(
                key: const Key('direct-playlist-select-all'),
                value:
                    detail.songs.isNotEmpty &&
                    _selected.length == detail.songs.length,
                onChanged: _saving || _destination != null
                    ? null
                    : (value) => setState(() {
                        _selected.clear();
                        if (value == true) {
                          _selected.addAll(
                            Iterable.generate(detail.songs.length),
                          );
                        }
                      }),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        zh
                            ? '读取曲目 $_loaded / $_total'
                            : 'Loading $_loaded / $_total',
                      ),
                    ],
                  ),
                )
              : detail == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error ?? ''),
                      TextButton(
                        onPressed: _load,
                        child: Text(zh ? '重试' : 'Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    ListTile(
                      leading: MusicThumbnail(
                        uri: Uri.tryParse(widget.playlist.coverUrl),
                        label: widget.playlist.name,
                        size: 48,
                      ),
                      title: Text(widget.playlist.source.label),
                      subtitle: Text(
                        '${widget.playlist.creator} · ${detail.songs.length} ${zh ? '首' : 'songs'}',
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    if (_saving) const LinearProgressIndicator(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: detail.songs.length,
                        itemBuilder: (context, i) {
                          final song = detail.songs[i];
                          return CheckboxListTile(
                            key: ValueKey('direct-song-$i'),
                            title: Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            value: _selected.contains(i),
                            onChanged: _saving || _destination != null
                                ? null
                                : (value) => setState(() {
                                    if (value == true) {
                                      _selected.add(i);
                                    } else {
                                      _selected.remove(i);
                                    }
                                  }),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        MusicUi.pagePadding,
                        8,
                        MusicUi.pagePadding,
                        12,
                      ),
                      child: _destination != null
                          ? SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const Key('direct-open-playlist'),
                                onPressed: () =>
                                    widget.onOpenPlaylist(_destination!),
                                icon: const Icon(Icons.open_in_new),
                                label: Text(zh ? '打开歌单' : 'Open playlist'),
                              ),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    key: const Key('direct-new-playlist'),
                                    onPressed: _saving || _selected.isEmpty
                                        ? null
                                        : () => _add(null),
                                    icon: const Icon(Icons.playlist_add),
                                    label: Text(zh ? '新建歌单' : 'New playlist'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    key: const Key('direct-add-playlist'),
                                    onPressed: _saving || _selected.isEmpty
                                        ? null
                                        : _chooseTarget,
                                    child: Text(
                                      zh ? '加入歌单' : 'Add to playlist',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
