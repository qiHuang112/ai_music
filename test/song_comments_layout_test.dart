import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/song_comments.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/song_comments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = SongCommentQuery(
  title: '回忆观影券（伴奏）与那些一起听歌的日子',
  artist: 'IN-K / 王忻辰 / 还有一起听歌的朋友',
);

void main() {
  const scenarios = [
    (
      name: 'narrow Chinese at 2x text',
      size: Size(320, 760),
      scale: 2.0,
      language: AppLanguage.zh,
      brightness: Brightness.light,
    ),
    (
      name: 'short landscape English',
      size: Size(740, 320),
      scale: 1.0,
      language: AppLanguage.en,
      brightness: Brightness.light,
    ),
    (
      name: 'narrow English dark theme',
      size: Size(320, 640),
      scale: 1.3,
      language: AppLanguage.en,
      brightness: Brightness.dark,
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('comments layout: ${scenario.name}', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _LayoutRepository(scenario.language);
      await tester.pumpWidget(
        MaterialApp(
          theme: MusicAppTheme.create(scenario.brightness),
          home: AppStringsScope(
            language: scenario.language,
            child: MediaQuery(
              data: MediaQueryData(
                size: scenario.size,
                textScaler: TextScaler.linear(scenario.scale),
              ),
              child: SongCommentsPage(query: _query, repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repository.calls, [SongCommentPlatform.netease]);

      // Both controls must be reachable at the actual viewport size, rather
      // than merely present below an overflowing fixed-height header.
      final qq = find.byKey(const ValueKey('comments-platform-qq'));
      expect(qq.hitTestable(), findsOneWidget);
      await tester.tap(qq);
      await tester.pumpAndSettle();
      expect(repository.calls, [
        SongCommentPlatform.netease,
        SongCommentPlatform.qq,
      ]);
      expect(
        find.text(repository.content(SongCommentPlatform.qq, 0)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final netease = find.byKey(const ValueKey('comments-platform-netease'));
      expect(netease.hitTestable(), findsOneWidget);
      await tester.tap(netease);
      await tester.pumpAndSettle();
      expect(repository.calls.length, 2);
      expect(
        find.text(repository.content(SongCommentPlatform.netease, 0)),
        findsOneWidget,
      );

      final list = find.byType(ListView);
      expect(list, findsOneWidget);
      expect(tester.getSize(list).height, greaterThan(40));
      final controller = tester.widget<ListView>(list).controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      final before = controller.offset;
      await tester.drag(list, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(before));
      expect(tester.takeException(), isNull);

      final lastComment = find.text(
        repository.content(SongCommentPlatform.netease, 8),
      );
      // Exercise repeated swipes through the reading area, not a special gutter.
      for (var i = 0; i < 80 && lastComment.evaluate().isEmpty; i++) {
        final viewport = tester.getRect(list);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.dragFrom(
          Offset(viewport.center.dx, viewport.bottom - 20),
          Offset(0, -viewport.height * .7),
        );
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      expect(
        lastComment,
        findsOneWidget,
        reason:
            'List offset ${controller.offset} of '
            '${controller.position.maxScrollExtent}',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _LayoutRepository extends SongCommentsRepository {
  _LayoutRepository(this.language);

  final AppLanguage language;
  final calls = <SongCommentPlatform>[];

  String content(SongCommentPlatform platform, int index) =>
      language == AppLanguage.zh
      ? '${platform.name} · 第 ${index + 1} 条。每次听见这首歌，就想起那些一起走过的路。'
            '\n后来我们去了不同的城市，熟悉的旋律依然让人觉得亲切。'
      : '${platform.name} · Comment ${index + 1}. This song reminds me of the long '
            'walks we took together.\nWe live in different cities now, but the '
            'same familiar melody still brings those evenings back.';

  @override
  Future<SongCommentsResult> load(
    SongCommentQuery query,
    SongCommentPlatform platform, {
    bool refresh = false,
    int page = 0,
    String? cursor,
  }) async {
    calls.add(platform);
    return SongCommentsResult(
      platform: platform,
      status: SongCommentsStatus.ready,
      pageUrl: query.searchUrl(platform),
      song: CommentSong(
        id: 'layout-${platform.name}',
        title: query.title,
        artist: query.artist,
      ),
      comments: [
        for (var i = 0; i < 9; i++)
          SongComment(
            id: '${platform.name}-$i',
            author: language == AppLanguage.zh
                ? '在不同城市依然一起听歌的老朋友'
                : 'An old friend listening from another city',
            content: content(platform, i),
            likes: 7654321 - i,
            createdAt: DateTime(2026, 10, 8),
          ),
      ],
    );
  }
}
