import 'package:flutter/material.dart';

import '../domain/music_models.dart';
import 'app_localizations.dart';

class ListSearchField extends StatelessWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: strings.listSearchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).deleteButtonTooltip,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(Icons.close),
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

List<Track> filterTracksByQuery(List<Track> tracks, String query) {
  final tokens = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) {
    return tracks;
  }
  return [
    for (final track in tracks)
      if (_matchesTrack(track, tokens)) track,
  ];
}

bool _matchesTrack(Track track, List<String> tokens) {
  final haystack = [
    track.title,
    track.artist,
    track.album,
    track.subtitle,
  ].join(' ').toLowerCase();
  return tokens.every(haystack.contains);
}
