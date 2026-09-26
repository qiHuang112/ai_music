import 'package:flutter/material.dart';

import '../application/chart_playlist_importer.dart';
import '../application/music_controller.dart';
import '../data/music_charts.dart';
import '../data/music_playlists.dart';
import 'app_localizations.dart';
import 'playlist_actions.dart';

enum _PlaylistChoice { create }

class DiscoverChartsSection extends StatelessWidget {
  const DiscoverChartsSection({super.key, required this.onOpenChart});

  final ValueChanged<MusicChart> onOpenChart;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.discover, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _platformCard(
          context,
          title: strings.qqMusic,
          subtitle: strings.qqPeakCharts,
          icon: Icons.music_note,
          charts: qqMusicCharts,
        ),
        const SizedBox(height: 8),
        _platformCard(
          context,
          title: strings.neteaseMusic,
          subtitle: strings.neteaseFeaturedCharts,
          icon: Icons.library_music,
          charts: neteaseMusicCharts,
        ),
      ],
    );
  }

  Widget _platformCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<MusicChart> charts,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                for (final chart in charts)
                  ActionChip(
                    key: ValueKey('chart-${chart.platform.name}-${chart.id}'),
                    label: Text(chart.title),
                    onPressed: () => onOpenChart(chart),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MusicChartPage extends StatefulWidget {
  const MusicChartPage({
    super.key,
    required this.chart,
    required this.controller,
    required this.onSearchSong,
    this.repository,
  });

  final MusicChart chart;
  final MusicController controller;
  final ValueChanged<MusicChartEntry> onSearchSong;
  final MusicChartRepository? repository;

  @override
  State<MusicChartPage> createState() => _MusicChartPageState();
}

class _MusicChartPageState extends State<MusicChartPage> {
  MusicChartResult? _result;
  String? _error;
  bool _loading = true;
  bool _adding = false;
  int _matched = 0;
  int _toMatch = 0;
  final Set<int> _selectedRanks = {};
  int _request = 0;

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
      _result = null;
      _selectedRanks.clear();
    });
    try {
      final result = await (widget.repository ?? MusicChartRepository()).load(
        widget.chart,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _result = result;
        _selectedRanks.clear();
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final entries = _result?.entries ?? const <MusicChartEntry>[];
    final title = widget.chart.platform == MusicChartPlatform.qq
        ? strings.qqMusic
        : strings.neteaseMusic;
    return Scaffold(
      appBar: AppBar(
        title: Text('$title · ${widget.chart.title}'),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            onPressed: _loading || _adding ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _result == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_loading || _adding)
                  LinearProgressIndicator(
                    value: _adding && _toMatch > 0 ? _matched / _toMatch : null,
                  ),
                if (_error != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(_error!),
                    trailing: IconButton(
                      tooltip: strings.retrySearch,
                      onPressed: _loading || _adding ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                if (_result?.updatedAt case final updatedAt?)
                  ListTile(
                    dense: true,
                    title: Text(strings.chartUpdated(updatedAt)),
                  ),
                if (widget.chart.isVideo)
                  ListTile(dense: true, title: Text(strings.mvChartHint))
                else if (entries.isNotEmpty)
                  ListTile(
                    dense: true,
                    title: Text(strings.chartSelectionHint),
                    trailing: TextButton(
                      onPressed: _loading || _adding
                          ? null
                          : () => setState(() {
                              if (_selectedRanks.length == entries.length) {
                                _selectedRanks.clear();
                              } else {
                                _selectedRanks.addAll(
                                  entries.map((e) => e.rank),
                                );
                              }
                            }),
                      child: Text(
                        _selectedRanks.length == entries.length
                            ? strings.clearSelection
                            : strings.selectAll,
                      ),
                    ),
                  ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(child: Text(_error ?? strings.chartEmpty))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final selected = _selectedRanks.contains(
                              entry.rank,
                            );
                            return ListTile(
                              key: ValueKey('chart-entry-${entry.rank}'),
                              leading: widget.chart.isVideo
                                  ? SizedBox(
                                      width: 44,
                                      child: Center(
                                        child: Text('${entry.rank}'),
                                      ),
                                    )
                                  : Checkbox(
                                      value: selected,
                                      onChanged: _loading || _adding
                                          ? null
                                          : (_) => _toggle(entry.rank),
                                    ),
                              title: Text(entry.title, maxLines: 1),
                              subtitle: Text(
                                '${entry.rank}. ${entry.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: widget.chart.isVideo
                                  ? null
                                  : IconButton(
                                      tooltip: strings.searchOnline,
                                      onPressed: _loading || _adding
                                          ? null
                                          : () => widget.onSearchSong(entry),
                                      icon: const Icon(Icons.search),
                                    ),
                              onTap: widget.chart.isVideo || _loading || _adding
                                  ? null
                                  : () => _toggle(entry.rank),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: widget.chart.isVideo || entries.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    _adding
                        ? strings.chartMatching(_matched, _toMatch)
                        : strings.chartSelected(_selectedRanks.length),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _loading || _adding || _selectedRanks.isEmpty
                        ? null
                        : _addToPlaylist,
                    child: Text(strings.addToPlaylist),
                  ),
                ],
              ),
            ),
    );
  }

  void _toggle(int rank) {
    setState(() {
      if (!_selectedRanks.add(rank)) _selectedRanks.remove(rank);
    });
  }

  Future<void> _addToPlaylist() async {
    final selected = [
      for (final entry in _result?.entries ?? const <MusicChartEntry>[])
        if (_selectedRanks.contains(entry.rank)) entry,
    ];
    if (selected.isEmpty) return;
    setState(() {
      _adding = true;
      _matched = 0;
      _toMatch = selected.length;
    });
    try {
      final importer = ChartPlaylistImporter(
        widget.controller.createScreenshotMatcher(),
      );
      final result = await importer.match(
        selected,
        concurrency: widget.controller.screenshotSearchConcurrency,
        isCanceled: () => !mounted,
        onProgress: (completed, _) {
          if (mounted) setState(() => _matched = completed);
        },
      );
      if (!mounted || result.canceled) return;
      if (result.serviceError != null) {
        _showStatus(
          AppStringsScope.of(context).chartMatchInterrupted(
            selected.length - result.unprocessed,
            selected.length,
          ),
        );
        return;
      }
      if (result.candidates.isEmpty) {
        _showStatus(AppStringsScope.of(context).chartNoMatches);
        return;
      }
      final playlist = await _choosePlaylist();
      if (playlist == null || !mounted) return;
      final added = await widget.controller.addCandidatesToPlaylist(
        playlist,
        result.candidates,
      );
      if (!mounted) return;
      _showStatus(
        AppStringsScope.of(
          context,
        ).chartAdded(playlist.name, added, result.failed),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showStatus(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<MusicPlaylist?> _choosePlaylist() async {
    final strings = AppStringsScope.of(context);
    final selected = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(strings.newPlaylist),
              onTap: () => Navigator.pop(sheetContext, _PlaylistChoice.create),
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
    if (!mounted) return null;
    if (selected is MusicPlaylist) return selected;
    if (selected == _PlaylistChoice.create) {
      return showCreatePlaylistDialog(context, widget.controller);
    }
    return null;
  }
}
