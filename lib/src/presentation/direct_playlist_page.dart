import 'playlist_sliver_header.dart';
import 'mini_player.dart';
import 'app_theme.dart';
import 'music_thumbnail.dart';
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

enum _PlaylistAction { add, join, open }

class _DirectPlaylistPageState extends State<DirectPlaylistPage> {
  OnlinePlaylistDetail? _detail;
  MusicPlaylist? _destination;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loaded = 0;
  int _total = 0;
  int _request = 0;
  int? _playingIndex;
  int _playRequest = 0;
  bool get zh => AppStringsScope.of(context).isZh;
  @override
  void initState() {
    super.initState();
    _destination = widget.controller.playlistForOnlineOrigin(widget.playlist);
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
    if (_saving || _detail == null || _detail!.songs.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.controller.addPlaylistDirectly(
        widget.playlist,
        _detail!.songs,
        target: target,
      );
      if (result == null) throw StateError('No playlist saved');
      if (mounted) {
        setState(() {
          _destination = widget.controller.playlistForOnlineOrigin(
            widget.playlist,
          );
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(zh ? '已加入我的歌单' : 'Added to your playlists')),
        );
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

  Future<void> _play(int index) async {
    final request = ++_playRequest;
    setState(() {
      _playingIndex = index;
      _error = null;
    });
    try {
      await widget.controller.playOnlinePlaylistSong(
        widget.playlist,
        _detail!.songs[index],
        queueSongs: _detail!.songs,
      );
    } catch (_) {
      if (mounted && request == _playRequest) {
        setState(
          () => _error = zh ? '播放失败，请重试或切换来源' : 'Playback failed. Retry.',
        );
      }
    } finally {
      if (mounted && request == _playRequest) {
        setState(() => _playingIndex = null);
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
    final actions = <Widget>[
      if (detail != null)
        PopupMenuButton<_PlaylistAction>(
          key: const Key('direct-playlist-actions'),
          tooltip: zh ? '歌单操作' : 'Playlist actions',
          enabled: !_saving,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case _PlaylistAction.add:
                _add(null);
              case _PlaylistAction.join:
                _chooseTarget();
              case _PlaylistAction.open:
                widget.onOpenPlaylist(
                  widget.controller.playlistForOnlineOrigin(widget.playlist) ??
                      _destination!,
                );
            }
          },
          itemBuilder: (_) => [
            if (_destination != null)
              PopupMenuItem(
                key: const Key('direct-open-playlist'),
                value: _PlaylistAction.open,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: Text(zh ? '打开歌单' : 'Open playlist'),
                ),
              )
            else
              PopupMenuItem(
                key: const Key('direct-new-playlist'),
                value: _PlaylistAction.add,
                enabled: detail.songs.isNotEmpty,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: Text(zh ? '添加到我的歌单' : 'Save playlist'),
                ),
              ),
            PopupMenuItem(
              key: const Key('direct-add-playlist'),
              value: _PlaylistAction.join,
              enabled: detail.songs.isNotEmpty,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(zh ? '加入已有歌单' : 'Add to existing playlist'),
              ),
            ),
          ],
        ),
    ];
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        extendBody: true,
        appBar: _loading || detail == null
            ? AppBar(title: Text(zh ? '歌单详情' : 'Playlist'), actions: actions)
            : null,
        bottomNavigationBar: MiniPlayer(controller: widget.controller),
        body: SafeArea(
          top: _loading || detail == null,
          bottom: false,
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
              : PlaylistScrollView(
                  slivers: [
                    PlaylistSliverHeader(
                      title: widget.playlist.name,
                      actions: actions,
                    ),
                    SliverToBoxAdapter(
                      child: Column(
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
                        ],
                      ),
                    ),
                    SliverList.builder(
                      itemCount: detail.songs.length,
                      itemBuilder: (context, i) {
                        final song = detail.songs[i];
                        return ListTile(
                          key: ValueKey('direct-song-$i'),
                          onTap: _playingIndex == i ? null : () => _play(i),
                          leading: IconButton(
                            key: ValueKey('direct-play-song-$i'),
                            tooltip: zh ? '播放' : 'Play',
                            onPressed: _playingIndex == i
                                ? null
                                : () => _play(i),
                            icon: _playingIndex == i
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded),
                          ),
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
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: Builder(
                        builder: (context) => SizedBox(
                          height: MusicUi.scrollInsets(context).bottom,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
