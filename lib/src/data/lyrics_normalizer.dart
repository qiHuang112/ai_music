import 'dart:convert';

import '../domain/music_models.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

ResolvedLyrics? makeResolvedLyrics(Object? rawValue, String source) {
  final text = extractLyricsText(rawValue);
  if (!_isUsableLyricsText(text)) {
    return null;
  }
  final lines = text.split('\n').where((line) => line.trim().isNotEmpty).length;
  return ResolvedLyrics(
    source: source,
    text: text,
    lines: lines,
    timed: RegExp(r'\[\d{2}:\d{2}\.\d{2}\]').hasMatch(text),
  );
}

ResolvedLyrics? firstResolvedLyrics(List<ResolvedLyrics?> candidates) {
  for (final lyrics in candidates) {
    if (lyrics != null && lyrics.text.trim().isNotEmpty) {
      return lyrics;
    }
  }
  return null;
}

String extractLyricsText(Object? value) {
  if (value is String) {
    return normalizeLyricsText(value);
  }
  if (value is List) {
    for (final item in value) {
      final found = extractLyricsText(item);
      if (found.isNotEmpty) {
        return found;
      }
    }
    return '';
  }
  if (value is Map) {
    final map = asStringMap(value);
    const preferredKeys = [
      'lrc',
      'lyric',
      'lyrics',
      'lyricText',
      'lrcContent',
      'content',
      'about',
    ];
    for (final key in preferredKeys) {
      final found = extractLyricsText(map[key]);
      if (found.isNotEmpty) {
        return found;
      }
    }
    for (final entry in map.entries) {
      if (preferredKeys.contains(entry.key)) {
        continue;
      }
      final found = extractLyricsText(entry.value);
      if (found.isNotEmpty) {
        return found;
      }
    }
  }
  return '';
}

String normalizeLyricsText(Object? value) {
  final decoded = _decodeHtmlEntities(value?.toString() ?? '')
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>|</div>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  final lines = decoded
      .split('\n')
      .map((line) => _normalizeLyricLine(line.trim()))
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.join('\n');
}

List<LyricLine> parseLrcLines(String text) {
  final lines = <LyricLine>[];
  for (final rawLine in const LineSplitter().convert(
    normalizeLyricsText(text),
  )) {
    final matches = _timeTagPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) {
      continue;
    }
    final lyricText = _cleanLyricText(
      rawLine.replaceAll(_timeTagPattern, '').trim(),
    );
    if (lyricText.isEmpty) {
      continue;
    }
    for (final match in matches) {
      final time = _durationFromTag(match);
      if (time != null) {
        lines.add(LyricLine(time: time, text: lyricText));
      }
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return _isUsableLyricLines(lines) ? lines : const [];
}

String _normalizeLyricLine(String line) {
  return _cleanLyricText(line).replaceAllMapped(
    RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]|\[(\d{1,3})\.(\d{1,3})\]'),
    (match) => _normalizeLyricTimestamp(match.group(0) ?? ''),
  );
}

String _cleanLyricText(String text) {
  return text
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</p>|</div>|</li>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isUsableLyricsText(String text) {
  if (text.isEmpty ||
      RegExp(
        r'^(歌词获取失败|暂无歌词|无歌词|null|undefined)$',
        caseSensitive: false,
      ).hasMatch(text)) {
    return false;
  }
  if (RegExp(r'<br\s*/?>|<[^>]+>', caseSensitive: false).hasMatch(text)) {
    return false;
  }
  return true;
}

bool _isUsableLyricLines(List<LyricLine> lines) {
  if (lines.length < 2) {
    return lines.length == 1 &&
        !_looksLikeSongMetadata(lines.single.text) &&
        lines.single.text.length <= 42;
  }
  final texts = [for (final line in lines) line.text.trim()];
  final joined = texts.join('\n');
  if (RegExp(r'<br\s*/?>|<[^>]+>', caseSensitive: false).hasMatch(joined)) {
    return false;
  }
  final metadataLike = texts.where(_looksLikeSongMetadata).length;
  if (metadataLike >= 2 || metadataLike / texts.length > 0.35) {
    return false;
  }
  final uniqueCount = texts.toSet().length;
  if (lines.length >= 4 && uniqueCount <= 2) {
    return false;
  }
  if (lines.length >= 8 && uniqueCount / lines.length < 0.35) {
    return false;
  }
  final averageLength =
      texts.fold<int>(0, (sum, text) => sum + text.length) / texts.length;
  if (averageLength > 42) {
    return false;
  }
  return true;
}

bool _looksLikeSongMetadata(String text) {
  return RegExp(
    r'(作词|作曲|编曲|演唱|歌手|所属专辑|发行时间|上传者|歌词来源|lyrics by|composer|lyricist)',
    caseSensitive: false,
  ).hasMatch(text);
}

String _normalizeLyricTimestamp(String tag) {
  final mmssNoFraction = RegExp(r'^\[(\d{1,2}):(\d{2})\]$').firstMatch(tag);
  if (mmssNoFraction != null) {
    final minutes = int.parse(
      mmssNoFraction.group(1)!,
    ).toString().padLeft(2, '0');
    final seconds = int.parse(
      mmssNoFraction.group(2)!,
    ).toString().padLeft(2, '0');
    return '[$minutes:$seconds.00]';
  }

  final mmss = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{1,3})\]$').firstMatch(tag);
  if (mmss != null) {
    final minutes = int.parse(mmss.group(1)!).toString().padLeft(2, '0');
    final seconds = int.parse(mmss.group(2)!).toString().padLeft(2, '0');
    final fraction = mmss.group(3)!.padRight(2, '0').substring(0, 2);
    return '[$minutes:$seconds.$fraction]';
  }

  final secondsOnly = RegExp(r'^\[(\d{1,3})\.(\d{1,3})\]$').firstMatch(tag);
  if (secondsOnly != null) {
    final totalSeconds = int.parse(secondsOnly.group(1)!);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final fraction = secondsOnly.group(2)!.padRight(2, '0').substring(0, 2);
    return '[$minutes:$seconds.$fraction]';
  }

  return tag;
}

String _decodeHtmlEntities(String text) {
  String fromCodePoint(String value, int radix) {
    try {
      return String.fromCharCode(int.parse(value, radix: radix));
    } catch (_) {
      return '';
    }
  }

  return text
      .replaceAll(RegExp(r'&(?:nbsp|#160);', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
      .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
      .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
      .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
      .replaceAll(RegExp(r'&#39;|&apos;', caseSensitive: false), "'")
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
        (match) => fromCodePoint(match.group(1)!, 16),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => fromCodePoint(match.group(1)!, 10),
      );
}

final _timeTagPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

Duration? _durationFromTag(RegExpMatch match) {
  final minutes = int.tryParse(match.group(1) ?? '');
  final seconds = int.tryParse(match.group(2) ?? '');
  if (minutes == null || seconds == null) {
    return null;
  }
  final fraction = match.group(3) ?? '0';
  final milliseconds = switch (fraction.length) {
    1 => int.parse(fraction) * 100,
    2 => int.parse(fraction) * 10,
    _ => int.parse(fraction.padRight(3, '0').substring(0, 3)),
  };
  return Duration(
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}
