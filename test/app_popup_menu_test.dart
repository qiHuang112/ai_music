import 'package:ai_music/src/presentation/app_popup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_music/src/presentation/design/app_icons.dart';

void main() {
  for (final horizontal in [false, true]) {
    testWidgets(
      '${horizontal ? 'horizontal' : 'vertical'} overflow opens and closes in 120ms and still selects correctly',
      (tester) async {
        var selection = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MusicPopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(horizontal ? AppIcons.more : AppIcons.moreVertical),
                onSelected: (value) => selection = value,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'pin', child: Text('Pin')),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('More'));
        await tester.pump();
        final route = ModalRoute.of(tester.element(find.text('Share')))!;
        await tester.pump(const Duration(milliseconds: 60));
        expect(route.animation!.status, AnimationStatus.forward);
        await tester.pump(const Duration(milliseconds: 61));
        expect(route.animation!.status, AnimationStatus.completed);

        Navigator.of(tester.element(find.text('Share'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 121));
        await tester.pump();
        expect(find.text('Share'), findsNothing);
        expect(selection, isEmpty);

        await tester.tap(find.byTooltip('More'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 121));
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(selection, 'share');
        expect(find.text('Pin'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
