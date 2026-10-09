import 'matching_traditional_chars.dart';

/// Comparison keys only: never rewrite displayed titles or artist credits.
class SongMatchIdentity {
  SongMatchIdentity(String title, String artist, {String version = ''})
    : artists = artistNamesForMatch(artist) {
    final versions = <String>{};
    var base = withoutSongContext(title);
    base = base.replaceAllMapped(RegExp(r'[（(]([^（）()]*)[）)]'), (match) {
      final annotation = match[1]!;
      // QQ's generic "(Version)" does not identify a different performance.
      // Keep descriptive versions such as 浴室氛围版 or Club Version intact.
      if (annotation.trim().toLowerCase() == 'version') return '';
      final found = _versionMarkers(annotation);
      if (found.isNotEmpty) {
        versions.addAll(found);
        return '';
      }
      // A title credit is not an artist identity. Retain the actual artist field.
      if (RegExp(r'^(?:原唱|翻自)\s*[:：]').hasMatch(annotation.trim())) {
        if (annotation.trim().startsWith('翻自')) versions.add('cover');
        return '';
      }
      return match[0]!;
    });
    // A bare suffix is accepted only when the entire suffix is a known marker.
    // Do not remove English substrings such as "live" in the song "Alive".
    final suffix = RegExp(
      r'(?:\s*[-—]\s*|\s+|(?<=[\u4e00-\u9fff]))'
      r'(live|现场(?:版)?|remix|混音(?:版)?|伴奏|instrumental|翻唱|cover|'
      r'demo|acoustic|纯音乐|哼唱(?:版)?|钢琴版|[哄吹]睡版|英文版|中文版|'
      r'国语版|粤语版|dj(?:[\w\u4e00-\u9fff]{0,8})?版)\s*$',
      caseSensitive: false,
    ).firstMatch(base);
    if (suffix != null) {
      versions.addAll(_versionMarkers(suffix[1]!));
      base = base.substring(0, suffix.start);
    }
    versions.addAll(_versionMarkers(version));
    this.title = normalizeSongText(base);
    final ordered = versions.toList()..sort();
    this.version = ordered.join('|');
  }

  late final String title;
  late final String version;
  final Set<String> artists;

  String get artistKey => (artists.toList()..sort()).join('|');
  String get key => '$title\u001f$artistKey\u001f$version';

  bool sameArtists(SongMatchIdentity other) =>
      artists.isNotEmpty && artistKey == other.artistKey;

  bool sameRecording(SongMatchIdentity other) =>
      title.isNotEmpty &&
      title == other.title &&
      sameArtists(other) &&
      version == other.version;
}

String withoutSongContext(String value) {
  // Strip only trailing soundtrack/work context, including truncated OCR text.
  final annotation = RegExp(
    r'\s*(?:[（(]\s*(?:电影|电视剧|动画|选自《|《)|[-—]\s*(?:电影|电视剧|动画|选自《|《)|《)',
  ).firstMatch(value);
  return annotation != null && annotation.start > 0
      ? value.substring(0, annotation.start).trim()
      : value;
}

final _traditionalCharacters = <int, int>{
  for (var i = 0; i < matchingTraditionalCharacterPairs.length; i += 2)
    matchingTraditionalCharacterPairs.codeUnitAt(i):
        matchingTraditionalCharacterPairs.codeUnitAt(i + 1),
};

String normalizeSongText(String value) => String.fromCharCodes(
  value.runes.map((rune) {
    if (rune >= 0xff01 && rune <= 0xff5e) return rune - 0xfee0;
    return _traditionalCharacters[rune] ?? rune;
  }),
).toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

Set<String> artistNamesForMatch(String value) => value
    .split(
      RegExp(
        r'\s*(?:[/、,&，;；+]|\bfeat\.?\s+|\bft\.?\s+)\s*',
        caseSensitive: false,
      ),
    )
    .map(normalizeSongText)
    .where((name) => name.isNotEmpty)
    .toSet();

Set<String> _versionMarkers(String value) {
  final text = normalizeTraditionalForVersion(value).toLowerCase();
  final result = <String>{};
  for (final entry in _versionPatterns.entries) {
    if (entry.value.hasMatch(text)) result.add(entry.key);
  }
  return result;
}

String normalizeTraditionalForVersion(String value) => String.fromCharCodes(
  value.runes.map((rune) => _traditionalCharacters[rune] ?? rune),
);

final _versionPatterns = <String, RegExp>{
  'lullaby': RegExp(r'[哄吹]睡版'),
  'english': RegExp(r'英文版'),
  'chinese': RegExp(r'中文版|国语版'),
  'cantonese': RegExp(r'粤语版'),
  'humming': RegExp(r'哼唱|\bhumming\b'),
  'piano': RegExp(r'钢琴版'),
  'live': RegExp(r'\blive\b|现场'),
  'remix': RegExp(r'\bremix\b|混音'),
  'dj': RegExp(r'\bdj(?:\b|[\u4e00-\u9fff])'),
  'instrumental': RegExp(r'伴奏|纯音乐|\binstrumental\b'),
  'cover': RegExp(r'翻唱|翻自|\bcover\b'),
  'demo': RegExp(r'\bdemo\b'),
  'acoustic': RegExp(r'\bacoustic\b'),
};
