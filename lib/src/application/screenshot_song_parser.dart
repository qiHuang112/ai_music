import 'dart:ui';

class ScreenshotTextLine {
  const ScreenshotTextLine({required this.text, required this.bounds});

  final String text;
  final Rect bounds;
}

class ScreenshotSongDraft {
  const ScreenshotSongDraft({
    required this.imageId,
    required this.row,
    required this.title,
    required this.artist,
    required this.version,
    required this.rawText,
    this.durationSeconds = 0,
  });

  final String imageId;
  final int row;
  final String title;
  final String artist;
  final String version;
  final String rawText;
  final int durationSeconds;

  ScreenshotSongDraft copyWith({
    String? title,
    String? artist,
    String? version,
  }) {
    return ScreenshotSongDraft(
      imageId: imageId,
      row: row,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      version: version ?? this.version,
      rawText: rawText,
      durationSeconds: durationSeconds,
    );
  }
}

class ScreenshotSongParser {
  const ScreenshotSongParser();

  List<ScreenshotSongDraft> parse(
    List<(String, List<ScreenshotTextLine>)> images,
  ) {
    final songs = <ScreenshotSongDraft>[];
    final seen = <String>{};
    for (final (imageId, lines) in images) {
      final ordered = [...lines]
        ..sort((a, b) {
          final vertical = a.bounds.top.compareTo(b.bounds.top);
          return vertical == 0
              ? a.bounds.left.compareTo(b.bounds.left)
              : vertical;
        });
      final indexed = _numberedRows(imageId, ordered);
      if (indexed != null) {
        for (final draft in indexed) {
          final key =
              '${_normal(draft.title)}|${_normal(draft.artist)}|${_normal(draft.version)}';
          if (draft.artist.isEmpty || seen.add(key)) songs.add(draft);
        }
        continue;
      }
      final unnumberedPlaylist = _unnumberedPlaylistRows(imageId, ordered);
      if (unnumberedPlaylist != null) {
        for (final draft in unnumberedPlaylist) {
          final key =
              '${_normal(draft.title)}|${_normal(draft.artist)}|${_normal(draft.version)}';
          if (draft.artist.isEmpty || seen.add(key)) songs.add(draft);
        }
        continue;
      }
      final heights = [
        for (final line in ordered)
          if (line.bounds.height > 0) line.bounds.height,
      ]..sort();
      final typicalHeight = heights.isEmpty
          ? 0.0
          : heights[heights.length ~/ 2];
      var row = 0;
      for (var i = 0; i < ordered.length; i += 1) {
        final titleText = _clean(ordered[i].text);
        if (_isChrome(titleText) ||
            (i == 0 &&
                ordered.length >= 3 &&
                titleText.endsWith('歌单') &&
                ordered[i].bounds.height > typicalHeight * 1.25)) {
          continue;
        }
        final inline = _splitTitleArtist(titleText);
        var title = inline.$1;
        var artist = inline.$2;
        if (artist.isEmpty && i + 1 < ordered.length) {
          final next = _clean(ordered[i + 1].text);
          if (_couldBeArtist(ordered[i], ordered[i + 1], next)) {
            artist = _artistFromSubtitle(next);
            i += 1;
          }
        }
        if (title.isEmpty || _isChrome(title)) continue;
        final version = _version(title);
        final draft = ScreenshotSongDraft(
          imageId: imageId,
          row: row++,
          title: title,
          artist: artist,
          version: version,
          rawText: artist.isEmpty ? titleText : '$titleText\n$artist',
        );
        final key = '${_normal(title)}|${_normal(artist)}|${_normal(version)}';
        // An unknown artist is not enough evidence to merge two screenshots.
        if (artist.isEmpty || seen.add(key)) songs.add(draft);
      }
    }
    return songs;
  }

  List<ScreenshotSongDraft>? _unnumberedPlaylistRows(
    String imageId,
    List<ScreenshotTextLine> lines,
  ) {
    final headers = [
      for (final line in lines)
        if (RegExp(r'^[|｜丨\s]*\d{1,4}\s*首').hasMatch(line.text.trim())) line,
    ];
    if (headers.isEmpty) return null;
    final header = headers.first;
    final imageWidth = lines
        .map((line) => line.bounds.right)
        .reduce((a, b) => a > b ? a : b);
    final footer = [
      for (final line in lines)
        if (line.bounds.top > header.bounds.bottom &&
            RegExp(r'登录获取|去登录').hasMatch(line.text))
          line.bounds.top,
    ];
    final end = footer.isEmpty
        ? double.infinity
        : footer.reduce((a, b) => a < b ? a : b);
    final rows = <ScreenshotSongDraft>[];
    final usedTitles = <ScreenshotTextLine>{};
    for (final subtitle in lines) {
      if (subtitle.bounds.top <= header.bounds.bottom ||
          subtitle.bounds.top >= end ||
          subtitle.bounds.left < imageWidth * 0.12 ||
          subtitle.bounds.left > imageWidth * 0.4 ||
          subtitle.text.trim().endsWith('添加') ||
          !RegExp(r'[-—]').hasMatch(subtitle.text)) {
        continue;
      }
      final possibleTitles = [
        for (final title in lines)
          if (!usedTitles.contains(title) &&
              title.bounds.top > header.bounds.bottom &&
              title.bounds.bottom <= subtitle.bounds.top + 5 &&
              subtitle.bounds.top - title.bounds.bottom <= 90 &&
              title.bounds.height >= subtitle.bounds.height * 0.8 &&
              ((title.bounds.left - subtitle.bounds.left).abs() <= 65 ||
                  (title.bounds.left < subtitle.bounds.left &&
                      title.bounds.right >= subtitle.bounds.left)) &&
              !_isChrome(_clean(title.text)) &&
              !title.text.trim().endsWith('添加') &&
              !RegExp(r'^\d+$').hasMatch(title.text.trim()))
            title,
      ]..sort((a, b) => b.bounds.bottom.compareTo(a.bounds.bottom));
      if (possibleTitles.isEmpty) continue;
      final titleLine = possibleTitles.first;
      final artist = _artistFromPlaylistSubtitle(subtitle.text);
      if (artist.isEmpty) continue;
      var title = _clean(titleLine.text);
      // OCR can merge tiny cover-art letters into a title at the song column.
      if (titleLine.bounds.left < imageWidth * 0.12 &&
          subtitle.bounds.left > imageWidth * 0.15) {
        title = title.replaceFirst(
          RegExp(r'^[a-z]{1,2}(?=[\u4e00-\u9fff])'),
          '',
        );
      }
      if (title.isEmpty) continue;
      usedTitles.add(titleLine);
      rows.add(
        ScreenshotSongDraft(
          imageId: imageId,
          row: rows.length,
          title: title,
          artist: artist,
          version: _version(title),
          rawText: '${titleLine.text}\n${subtitle.text}',
        ),
      );
    }
    // A recognised playlist layout must never fall back to guessing every
    // UI/attribution line as a song, even if no complete rows are visible.
    return rows;
  }

  static String _artistFromPlaylistSubtitle(String text) {
    final withoutBadge = text.trim().replaceFirst(
      RegExp(r'^.{0,10}?母[带帶制]?[\s)）\]】]*'),
      '',
    );
    final artist = withoutBadge.split(RegExp(r'\s*[-—]\s*')).first.trim();
    return artist.isEmpty || _isChrome(artist) ? '' : artist;
  }

  List<ScreenshotSongDraft>? _numberedRows(
    String imageId,
    List<ScreenshotTextLine> lines,
  ) {
    if (lines.isEmpty) return null;
    final imageWidth = lines
        .map((line) => line.bounds.right)
        .reduce((a, b) => a > b ? a : b);
    final anchors = [
      for (final line in lines)
        if (RegExp(r'^\d{1,4}$').hasMatch(line.text.trim()) &&
            line.bounds.left < imageWidth * 0.14)
          line,
    ];
    if (anchors.isEmpty) return null;
    anchors.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
    final rows = <ScreenshotSongDraft>[];
    for (var index = 0; index < anchors.length; index += 1) {
      final anchor = anchors[index];
      final center = anchor.bounds.center.dy;
      final start = index == 0
          ? center - 85
          : (anchors[index - 1].bounds.center.dy + center) / 2;
      final end = index == anchors.length - 1
          ? center + 110
          : (center + anchors[index + 1].bounds.center.dy) / 2;
      final content = [
        for (final line in lines)
          if (line.bounds.center.dy >= start &&
              line.bounds.center.dy < end &&
              line.bounds.left > anchor.bounds.right + 20 &&
              line.bounds.left < imageWidth * 0.82 &&
              !_isRowBadge(_clean(line.text)))
            line,
      ];
      final titles = [
        for (final line in content)
          if (line.bounds.center.dy <= center + 5) line,
      ]..sort((a, b) => b.bounds.height.compareTo(a.bounds.height));
      if (titles.isEmpty) continue;
      final titleLine = titles.first;
      final title = _clean(
        titleLine.text,
      ).replaceAll(RegExp(r'\s*(本周热播|昨日热播)$'), '');
      if (_isChrome(title) || title.isEmpty) continue;
      final subtitles = [
        for (final line in content)
          if (line.bounds.top >= titleLine.bounds.bottom - 5 &&
              line.bounds.center.dy <= titleLine.bounds.bottom + 70)
            line,
      ]..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      final artist = _artistFromRow(
        subtitles.map((line) => line.text).join(' '),
      );
      rows.add(
        ScreenshotSongDraft(
          imageId: imageId,
          row: rows.length,
          title: title,
          artist: artist,
          version: _version(title),
          rawText: '$title\n$artist',
        ),
      );
    }
    return rows;
  }

  static bool _isRowBadge(String text) =>
      _isChrome(text) ||
      RegExp(r'^(\d+[wW+]*|臻品母带|全景声|SQ|HQ|本周热播|昨日热播)$').hasMatch(text);

  static String _artistFromRow(String subtitle) {
    final cleaned = subtitle
        .replaceFirst(
          RegExp(
            r'^[\s\[\]【】()（）［］「」]*(?:[\u4e00-\u9fff]{1,3}母[带帶]|全景声|SQ|HQ)[\s\[\]【】()（）［］「」]*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (cleaned.isEmpty || _isRowBadge(cleaned)) return '';
    return cleaned.split(RegExp(r'[·・•]')).first.trim();
  }

  static String _clean(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^[|｜丨]+(?=[\u4e00-\u9fff])'), '')
      .replaceFirst(RegExp(r'^\s*\d{1,3}[.、\s]+'), '')
      .trim();

  static bool _isChrome(String value) {
    if (value.isEmpty || RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value)) {
      return true;
    }
    return RegExp(
      r'^(搜索|播放|暂停|下载|收藏|分享|更多|下一首|上一首|歌单|推荐|热榜|广告|VIP|会员|全部播放|播放全部|返回|取消|完成|设置)$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static (String, String) _splitTitleArtist(String text) {
    final parts = text.split(RegExp(r'\s*[-—·]\s*'));
    if (parts.length != 2 ||
        (!RegExp(r'[\u4e00-\u9fff]').hasMatch(text) &&
            !RegExp(r'\s[-—·]\s').hasMatch(text))) {
      return (text, '');
    }
    if (parts.first.trim().isEmpty || parts.last.trim().isEmpty) {
      return (text, '');
    }
    return (parts.first.trim(), parts[1].trim());
  }

  static bool _couldBeArtist(
    ScreenshotTextLine title,
    ScreenshotTextLine subtitle,
    String text,
  ) {
    if (_isChrome(text) || text.isEmpty || text.length > 70) return false;
    final gap = subtitle.bounds.top - title.bounds.bottom;
    final height = title.bounds.height > 0 ? title.bounds.height : 16.0;
    return gap >= -height * 0.3 &&
        gap <= height * 1.6 &&
        (subtitle.bounds.left - title.bounds.left).abs() <= height * 2;
  }

  static String _artistFromSubtitle(String text) {
    return _splitTitleArtist(text).$1;
  }

  static String _version(String title) {
    final match = RegExp(
      r'(live|现场(?:版)?|remix|混音(?:版)?|伴奏|翻唱|cover|纯音乐|instrumental|demo|acoustic)',
      caseSensitive: false,
    ).firstMatch(title);
    return match?.group(0)?.toLowerCase() ?? '';
  }

  static String _normal(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );
}
