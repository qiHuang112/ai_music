import 'package:ai_music/src/presentation/comment_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('literal QQ newline sequences become real line breaks', () {
    expect(displayCommentText(r'第一行\n第二行\r第三行\r\n第四行'), '第一行\n第二行\n第三行\n第四行');
  });

  test(
    'real and mixed CRLF endings normalize without doubling blank lines',
    () {
      expect(displayCommentText('甲\r\n乙\r丙\n\n丁'), '甲\n乙\n丙\n\n丁');
      expect(displayCommentText('甲\\r\n乙\r\\n丙'), '甲\n乙\n丙');
    },
  );

  test(
    'object replacement placeholders disappear without removing content',
    () {
      expect(displayCommentText('\uFFFC这首歌\uFFFC真好听\uFFFC'), '这首歌真好听');
      expect(displayCommentText('甲\uFFFC\n乙'), '甲\n乙');
    },
  );

  test('emoji, joined emoji and multilingual content remain unchanged', () {
    const original = '喜欢这首歌🎵 🌈 👩🏽‍🎤 👨‍👩‍👧‍👦 🇨🇳\nCafé 좋아요';
    expect(displayCommentText(original), original);
  });

  test(
    'ordinary backslashes, unknown escapes and escaped slashes stay literal',
    () {
      const original = r'C:\music\song.mp3 | \t | \u4f60 | \/ | \\n | \\r';
      expect(displayCommentText(original), original);
      expect(displayCommentText('结尾\\'), '结尾\\');
    },
  );

  test('display does not decode HTML, strip tags or trim original spacing', () {
    const original = '  &amp; &lt;你好&gt; <em>原文</em>  \n';
    expect(displayCommentText(original), original);
  });

  test(
    'empty and already readable text are unchanged and cleanup is idempotent',
    () {
      expect(displayCommentText(''), '');
      const original = '原本正常的评论。\n第二段保留。';
      expect(displayCommentText(original), original);
      final cleaned = displayCommentText('甲\\n乙\uFFFC\r\n丙');
      expect(displayCommentText(cleaned), cleaned);
    },
  );
}
