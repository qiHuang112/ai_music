import 'app_theme.dart';
import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import '../data/music_resolver.dart';
import '../domain/music_models.dart';
import '../data/saved_online_track.dart';
import 'app_localizations.dart';

Future<void> showSongSourcePicker(
  BuildContext context,
  MusicController controller,
  Track track,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => SongSourcePage(controller: controller, track: track),
  ),
);

class SongSourcePage extends StatefulWidget {
  const SongSourcePage({
    super.key,
    required this.controller,
    required this.track,
  });
  final MusicController controller;
  final Track track;
  @override
  State<SongSourcePage> createState() => _SongSourcePageState();
}

class _SongSourcePageState extends State<SongSourcePage> {
  late final TextEditingController _query;
  List<MusicSearchCandidate> _results = [];
  String? _error;
  bool _loading = false;
  bool _saving = false;
  int _request = 0;
  late MusicDataSource _source;
  bool get zh => AppStringsScope.of(context).isZh;
  @override
  void initState() {
    super.initState();
    _source = widget.controller.source;
    _query = TextEditingController(
      text: '${widget.track.title} ${widget.track.artist}'.trim(),
    );
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool refresh = false}) async {
    final request = ++_request;
    if (_query.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await widget.controller.searchSongSources(
        widget.track,
        query: _query.text,
        searchSource: _source,
        refresh: refresh,
      );
      if (mounted && request == _request) {
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = zh ? '搜索失败，请重试' : 'Search failed. Retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _choose(MusicSearchCandidate candidate) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.chooseSongSource(widget.track, candidate);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = zh
              ? '切换未完成，请重试或选择其它来源'
              : 'Unable to save or play this source. Retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(zh ? '切换来源' : 'Choose source'),
        actions: [
          IconButton(
            tooltip: zh ? '刷新来源' : 'Refresh sources',
            onPressed: _saving || _loading
                ? null
                : () => _search(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(MusicUi.pagePadding),
              child: TextField(
                controller: _query,
                enabled: !_saving,
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: zh ? '歌名 / 歌手' : 'Song / artist',

                  suffixIcon: IconButton(
                    onPressed: _saving ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            Padding(
              padding: MusicUi.horizontalInsets,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in [
                      MusicDataSource.auto,
                      MusicDataSource.buguyy,
                      MusicDataSource.flac,
                    ])
                      ChoiceChip(
                        label: Text(
                          source == MusicDataSource.auto
                              ? (zh ? '全部' : 'All')
                              : source == MusicDataSource.buguyy
                              ? '布谷YY'
                              : 'FLAC',
                        ),
                        selected: _source == source,
                        onSelected: _saving
                            ? null
                            : (_) {
                                setState(() => _source = source);
                                _search();
                              },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            if (_loading || _saving) const LinearProgressIndicator(),
            Expanded(
              child: !_loading && _results.isEmpty
                  ? Center(
                      child: Text(
                        zh
                            ? '没有找到歌曲，可修改关键词重新搜索'
                            : 'No songs found. Try another search.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final candidate = _results[i];
                        return ListTile(
                          key: ValueKey('song-source-$i'),
                          title: Text(
                            candidate.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${candidate.subtitle}${candidate.platform.isEmpty ? '' : ' · ${candidate.platform}'}',
                          ),
                          trailing: Icon(
                            SavedOnlineTrack(candidate: candidate).trackId ==
                                    (widget.controller.selectedSongSource(
                                              widget.track,
                                            ) ==
                                            null
                                        ? null
                                        : SavedOnlineTrack(
                                            candidate: widget.controller
                                                .selectedSongSource(
                                                  widget.track,
                                                )!,
                                          ).trackId)
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: _saving ? null : () => _choose(candidate),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
