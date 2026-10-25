import 'app_theme.dart';
import 'package:flutter/material.dart';

import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'desktop_scope.dart';

class ListSearchField extends StatelessWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.emptySuffix,
    this.hintText,
    this.padding,
  });

  /// Defaults to the page gutter; on the Mac it lines up with the page
  /// title and is slimmer.
  final EdgeInsetsGeometry? padding;

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final Widget? emptySuffix;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final desktop = DesktopMusicScope.maybeOf(context) != null;
    return Padding(
      padding:
          padding ??
          (desktop
              ? const EdgeInsets.fromLTRB(32, 4, 32, 10)
              : const EdgeInsets.fromLTRB(
                  MusicUi.pagePadding,
                  8,
                  MusicUi.pagePadding,
                  8,
                )),
      child: TextField(
        style: desktop ? const TextStyle(fontSize: 13.5) : null,
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText ?? strings.listSearchHint,
          prefixIcon: Icon(Icons.search, size: desktop ? 18 : null),
          contentPadding: desktop
              ? const EdgeInsets.symmetric(vertical: 9)
              : null,
          suffixIcon: controller.text.isEmpty
              ? emptySuffix
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
