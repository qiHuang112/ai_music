import 'dart:ui';

import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ScreenshotSongParser();

  ScreenshotTextLine line(
    String text,
    double y, {
    double x = 36,
    double height = 18,
    double width = 180,
  }) => ScreenshotTextLine(
    text: text,
    bounds: Rect.fromLTWH(x, y, width, height),
  );

  test('real OCR-style compact separators and larger page title', () {
    final songs = parser.parse([
      (
        'sample',
        [
          line('测试歌单', 80, height: 54),
          line('稻香-周杰伦', 250, height: 36),
          line('哎呀-王蓉', 350, height: 36),
        ],
      ),
    ]);

    expect(songs.map((song) => song.title), ['稻香', '哎呀']);
    expect(songs.map((song) => song.artist), ['周杰伦', '王蓉']);
  });

  test('keeps image and row order while removing overlapping songs', () {
    final songs = parser.parse([
      (
        'first',
        [
          line('搜索', 0),
          line('1 稻香', 40),
          line('周杰伦 - 魔杰座', 62),
          line('晴天 (Live)', 110),
          line('周杰伦', 132),
        ],
      ),
      (
        'second',
        [line('稻香', 30), line('周杰伦', 52), line('晴天', 100), line('周杰伦', 122)],
      ),
    ]);

    expect(songs.map((song) => song.title), ['稻香', '晴天 (Live)', '晴天']);
    expect(songs.map((song) => song.artist), everyElement('周杰伦'));
    expect(songs.map((song) => song.imageId), ['first', 'first', 'second']);
    expect(songs.map((song) => song.row), [0, 1, 1]);
    expect(songs[1].version, 'live');
  });

  test('leaves unknown artist blank instead of inventing it', () {
    final songs = parser.parse([
      ('one', [line('剩下的果实', 40)]),
      ('two', [line('剩下的果实', 40)]),
    ]);
    expect(songs, hasLength(2));
    expect(songs.first.artist, '');
    expect(songs.first.copyWith(artist: '麻园诗人').artist, '麻园诗人');
  });

  test('does not split an English hyphenated title without a separator', () {
    final songs = parser.parse([
      ('one', [line('Shape-of-You', 40)]),
    ]);
    expect(songs.single.title, 'Shape-of-You');
    expect(songs.single.artist, '');
  });

  test('groups numbered music rows and ignores badges and page chrome', () {
    final songs = parser.parse([
      (
        'miui-playlist',
        [
          line('暴露年龄！90后MP3里的经典老歌', 110, x: 150, height: 44),
          line('全部播放(630)', 275, x: 100, height: 36),
          line('1', 405, x: 55, height: 28, width: 25),
          line('晴天', 370, x: 150, height: 42),
          line('臻品母带', 430, x: 150, height: 22),
          line('周杰伦·叶惠美', 430, x: 280, height: 24),
          line('5700w+', 395, x: 920, height: 16),
          line('2', 555, x: 55, height: 28, width: 25),
          line('Always Online', 515, x: 150, height: 42),
          line('臻品母带', 575, x: 150, height: 22),
          line('林俊杰·联想idea Pad S9/S10笔记本', 575, x: 280),
          line('2600w+', 545, x: 920),
          line('我是一个粉刷匠-贝瓦儿歌', 1980, x: 180),
        ],
      ),
    ]);

    expect(songs.map((song) => song.title), ['晴天', 'Always Online']);
    expect(songs.map((song) => song.artist), ['周杰伦', '林俊杰']);
  });

  test(
    'preserves numbered rows and removes overlapping screenshot repeats',
    () {
      final songs = parser.parse([
        (
          'first',
          [
            line('6', 1100, x: 55, width: 25),
            line('森林狂想曲', 1060, x: 150, height: 42),
            line('黛青塔娜·森林狂想曲', 1120, x: 270),
            line('7', 1250, x: 55, width: 25),
            line('冬天的秘密', 1210, x: 150, height: 42),
            line('周传雄·恋人创世纪', 1270, x: 270),
          ],
        ),
        (
          'second',
          [
            line('7', 240, x: 55, width: 25),
            line('冬天的秘密', 200, x: 150, height: 42),
            line('周传雄·恋人创世纪', 260, x: 270),
            line('8', 390, x: 55, width: 25),
            line('痴心绝对', 350, x: 150, height: 42),
            line('李圣杰·关于你的歌', 410, x: 270),
          ],
        ),
      ]);

      expect(songs.map((song) => song.title), ['森林狂想曲', '冬天的秘密', '痴心绝对']);
      expect(songs.map((song) => song.artist), ['黛青塔娜', '周传雄', '李圣杰']);
    },
  );

  test('removes OCR variants of quality badge from artist subtitle', () {
    final songs = parser.parse([
      (
        'real-layout',
        [
          line('1', 400, x: 55, width: 25),
          line('晴天', 370, x: 150, height: 42),
          line('［國品母帶］', 430, x: 150),
          line('周杰伦•叶惠美', 430, x: 280),
          line('2', 550, x: 55, width: 25),
          line('你不知道的事', 520, x: 150, height: 42),
          line('（鹽品母帶）王力宏•十八般武艺', 580, x: 150),
        ],
      ),
    ]);

    expect(songs.map((song) => song.title), ['晴天', '你不知道的事']);
    expect(songs.map((song) => song.artist), ['周杰伦', '王力宏']);
  });

  test('one visible numbered song does not turn page chrome into songs', () {
    final songs = parser.parse([
      (
        'single-row',
        [
          line('全部播放(630)', 260, x: 100),
          line('21', 410, x: 55, width: 35),
          line('雨天的心事', 375, x: 150, height: 42),
          line('臻品母带', 435, x: 150),
          line('无咎无求•雨天调频', 435, x: 270),
          line('我是一个粉刷匠-贝瓦儿歌', 1890, x: 180),
        ],
      ),
    ]);

    expect(songs, hasLength(1));
    expect(songs.single.title, '雨天的心事');
    expect(songs.single.artist, '无咎无求');
  });
}
