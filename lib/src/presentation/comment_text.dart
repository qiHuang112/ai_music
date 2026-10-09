final _commentLineBreaks = RegExp(r'\\\\|\\[rn]');

/// Cleans QQ's escaped line endings and unsupported object placeholders only.
/// Doubled backslashes and other escape sequences remain literal text.
String displayCommentText(String raw) {
  final text = raw.replaceAllMapped(_commentLineBreaks, (match) {
    return switch (match[0]) {
      r'\n' => '\n',
      r'\r' => '\r',
      _ => match[0]!,
    };
  });
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\uFFFC', '');
}
