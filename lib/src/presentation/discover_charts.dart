import 'app_theme.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_charts.dart';
import '../data/music_playlists.dart';
import 'app_localizations.dart';

class DiscoverChartsSection extends StatelessWidget {
  const DiscoverChartsSection({super.key, required this.onOpenChart});

  final ValueChanged<MusicChart> onOpenChart;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.discover,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _platformCard(context, title: strings.qqMusic, charts: qqMusicCharts),
        const SizedBox(height: 18),
        _platformCard(
          context,
          title: strings.neteaseMusic,
          charts: neteaseMusicCharts,
        ),
      ],
    );
  }

  Widget _platformCard(
    BuildContext context, {
    required String title,
    required List<MusicChart> charts,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
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
              TextButton(
                key: ValueKey('chart-${chart.platform.name}-${chart.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  backgroundColor: colors.surfaceContainerHighest,
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MusicUi.coverRadius),
                  ),
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
                child: Text(chart.title),
                onPressed: () => onOpenChart(chart),
              ),
          ],
        ),
      ],
    );
  }
}

typedef ChartPlaylistBuilder =
    Widget Function(
      MusicPlaylist playlist,
      VoidCallback refresh,
      bool refreshing,
      String? error,
      String? updatedAt,
    );

class MusicChartPage extends StatefulWidget {
  const MusicChartPage({
    super.key,
    required this.chart,
    required this.controller,
    required this.playlistBuilder,
    this.repository,
  });

  final MusicChart chart;
  final MusicController controller;
  final ChartPlaylistBuilder playlistBuilder;
  final MusicChartRepository? repository;

  @override
  State<MusicChartPage> createState() => _MusicChartPageState();
}

class _MusicChartPageState extends State<MusicChartPage> {
  MusicChartResult? _result;
  MusicPlaylist? _playlist;
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _playlist = widget.controller.allPlaylists
        .where((p) => p.id == widget.chart.playlistId)
        .firstOrNull;
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await (widget.repository ?? MusicChartRepository()).load(
        widget.chart,
      );
      if (!mounted || request != _request) return;
      final playlist = widget.chart.isVideo
          ? null
          : await widget.controller.updateChartPlaylist(widget.chart, result);
      if (!mounted || request != _request) return;
      setState(() {
        _result = result;
        _playlist = playlist;
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
    final playlist = _playlist;
    if (!widget.chart.isVideo && playlist != null) {
      return widget.playlistBuilder(
        playlist,
        () {
          _load();
        },
        _loading,
        _error,
        _result?.updatedAt,
      );
    }
    final strings = AppStringsScope.of(context);
    final entries = _result?.entries ?? const <MusicChartEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chart.playlistName),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _result == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(_error!),
                    trailing: IconButton(
                      tooltip: strings.retrySearch,
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                if (_result?.updatedAt case final updatedAt?)
                  ListTile(
                    dense: true,
                    title: Text(strings.chartUpdated(updatedAt)),
                  ),
                if (widget.chart.isVideo)
                  ListTile(dense: true, title: Text(strings.mvChartHint)),
                Expanded(
                  child: entries.isEmpty
                      ? Center(child: Text(_error ?? strings.chartEmpty))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ListTile(
                              key: ValueKey('chart-entry-${entry.rank}'),
                              leading: SizedBox(
                                width: 44,
                                child: Center(child: Text('${entry.rank}')),
                              ),
                              title: Text(entry.title, maxLines: 1),
                              subtitle: Text(
                                entry.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
