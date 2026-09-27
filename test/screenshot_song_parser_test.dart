import 'dart:ui';
import 'dart:io';
import 'dart:convert';

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

  ScreenshotTextLine box(
    String text,
    double left,
    double top,
    double right,
    double bottom,
  ) => ScreenshotTextLine(
    text: text,
    bounds: Rect.fromLTRB(left, top, right, bottom),
  );

  test('groups a real unnumbered NetEase playlist without page controls', () {
    final songs = parser.parse([
      (
        'netease',
        [
          box('林志.', 50, 766, 108, 784),
          box('7:49 6', 199, 45, 317, 76),
          box('214', 213, 370, 266, 402),
          box('搔放全部', 195, 573, 366, 613),
          box('18首 含7首VIP歌曲,1分钱领VIP>', 182, 636, 695, 672),
          box('离人', 195, 746, 273, 785),
          box('國濟母制林志炫 - 绝对收藏株志炫', 196, 809, 663, 842),
          box('龙猫(《龙猫》)', 177, 916, 497, 964),
          box('超清母带贵族乐团 -嘘,龙猫睡着了(宫崎骏...', 185, 977, 856, 1013),
          box('oe小燕子', 48, 1081, 316, 1127),
          box('超清母带贝乐虎儿歌-贝乐虎歌', 195, 1151, 663, 1183),
          box('萱草花 (哼唱版) (电影《你好,李煥英..', 180, 1259, 926, 1306),
          box('VP 超清母 张小斐-萱草花(哼唱版)', 186, 1319, 727, 1355),
          box('萱草花(电影《你好,李焕英》主题曲)', 195, 1432, 897, 1474),
          box('P]超清母带张小斐-你好,李煥英电影原声,..', 196, 1493, 859, 1525),
          box('悠蓝曲', 195, 1601, 313, 1637),
          box('超清母带刘惜君-悠蓝曲', 194, 1664, 529, 1696),
          box('风吹表浪', 196, 1774, 358, 1813),
          box('F超濟母带季健 - 想念你', 194, 1835, 554, 1868),
          box('+ 5903', 807, 371, 944, 406),
          box('觀马马嘟嘟骑', 102, 1932, 396, 1984),
          box('登录获取更懂你的好音乐', 90, 2045, 514, 2082),
          box('中儿,K(H由即】', 199, 2125, 500, 2147),
          box('Dehors (外面)- JORDANN', 190, 2188, 641, 2226),
          box('去登录', 853, 2047, 957, 2080),
          box('三', 918, 2184, 967, 2230),
        ],
      ),
    ]);

    expect(songs.map((song) => song.title), [
      '离人',
      '龙猫(《龙猫》)',
      '小燕子',
      '萱草花 (哼唱版) (电影《你好,李煥英..',
      '萱草花(电影《你好,李焕英》主题曲)',
      '悠蓝曲',
      '风吹表浪',
    ]);
    expect(songs.map((song) => song.artist), [
      '林志炫',
      '贵族乐团',
      '贝乐虎儿歌',
      '张小斐',
      '张小斐',
      '刘惜君',
      '季健',
    ]);
  });

  test(
    'two real three-line playlists produce 14 songs, not UI and contributors',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/netease_two_images_ocr.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final images = [
        for (final entry in fixture.entries)
          (
            entry.key,
            [
              for (final row in entry.value as List)
                box(
                  row['text'] as String,
                  (row['bounds'][0] as num).toDouble(),
                  (row['bounds'][1] as num).toDouble(),
                  (row['bounds'][2] as num).toDouble(),
                  (row['bounds'][3] as num).toDouble(),
                ),
            ],
          ),
      ];
      final songs = parser.parse(images);
      expect(songs, hasLength(14));
      expect(songs.take(7).map((song) => song.title), [
        '幸攝拍手歌(哄睡版)',
        '虫儿飞(哄睡版)',
        '蜗牛与黄鹏鸟(哄睡版)',
        '春天在哪里(吹睡版)',
        '大风车(哄睡版)',
        '嘘嘘嘘小宝宝要睡党',
        '深度睡眠催眠曲5分钟入睡',
      ]);
      expect(songs.skip(7).map((song) => song.title), [
        '催眠流水声快速入睡',
        '要儿安抚音白噪音睡眠',
        "Can't Smile Without You",
        '龙猫(《龙猫》)',
        '勃拉姆斯摇篮曲',
        '舒伯特摇篮曲',
        '催眠曲5分钟入睡(阿尔法脑波音乐)',
      ]);
      expect(songs.map((song) => song.artist), [
        '贝乐虎し歌',
        '贝乐虎し歌',
        '贝乐虎儿歌',
        'し歌多多',
        '贝乐虎し歌',
        '闫瑜',
        '闫瑜',
        '闫瑜',
        '闫瑜',
        'Judson Mancebo',
        '贵族乐团',
        '摇篮曲月亮摇篮曲河',
        '舒伯特摇篮曲',
        '闫瑜',
      ]);
      expect(
        songs.take(7).every((song) => song.imageId == '1000000585.jpg'),
        isTrue,
      );
      expect(
        songs.skip(7).every((song) => song.imageId == '1000000586.jpg'),
        isTrue,
      );
      // The selected pair has no overlap; repeating either image must deduplicate.
      expect(parser.parse([...images, images.first]), hasLength(14));
    },
  );

  test(
    'recognised playlist with no full row does not parse chrome as songs',
    () {
      expect(
        parser.parse([
          (
            'empty',
            [
              box('|42首,2小时26分钟', 180, 336, 488, 373),
              box('歌单成员 添加', 239, 543, 635, 573),
              box('登录获取更懂你的好音乐', 90, 2045, 514, 2082),
              box('Dehors (外面)- JORDANN', 190, 2188, 641, 2226),
            ],
          ),
        ]),
        isEmpty,
      );
    },
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

  test(
    'QQ numbered rows 1 through 5 keep title artist pairs and ignore page count',
    () {
      final titles = ['晴天', '稻香', '青花瓷', '七里香', '夜曲'];
      final songs = parser.parse([
        (
          'qq-numbered',
          [
            line('42首', 230, x: 180),
            for (var i = 0; i < 5; i++) ...[
              line('${i + 1}', 400 + i * 150, x: 55, width: 25),
              line(titles[i], 370 + i * 150, x: 150, height: 42, width: 700),
              line('臻品母带', 430 + i * 150, x: 150),
              line('周杰伦·专辑', 430 + i * 150, x: 280),
            ],
            line('登录获取好音乐', 1900, x: 150),
          ],
        ),
      ]);
      expect(songs.map((song) => song.title), titles);
      expect(songs.map((song) => song.artist), List.filled(5, '周杰伦'));
      expect(songs.map((song) => song.row), [0, 1, 2, 3, 4]);
    },
  );

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
