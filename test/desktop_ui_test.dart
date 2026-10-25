import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/desktop_home.dart';
import 'package:ai_music/src/presentation/desktop_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => AppStringsScope(
  language: AppLanguage.zh,
  child: MaterialApp(
    theme: MusicAppTheme.create(Brightness.dark),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('scrubber commits a click on release and drags in between', (
    tester,
  ) async {
    final changes = <double>[];
    final ends = <double>[];
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 200,
          child: DesktopScrubber(
            value: .25,
            semanticLabel: '播放进度',
            onChanged: changes.add,
            onChangeEnd: ends.add,
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(DesktopScrubber));
    await tester.tapAt(Offset(box.left + 150, box.center.dy));
    await tester.pump();
    expect(ends.single, closeTo(.75, .01));

    final drag = await tester.startGesture(
      Offset(box.left + 20, box.center.dy),
    );
    await drag.moveBy(const Offset(40, 0));
    await drag.moveBy(const Offset(40, 0));
    await drag.up();
    await tester.pump();
    expect(changes, isNotEmpty);
    expect(ends.last, closeTo(.5, .02));
  });

  testWidgets('scrubber grows under the pointer', (tester) async {
    await tester.pumpWidget(
      _host(SizedBox(width: 200, child: DesktopScrubber(value: .5))),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(DesktopScrubber)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('segmented control reports the chosen option', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: DesktopSegmented<String>(
            values: const ['歌词', '热评', '队列'],
            selected: '歌词',
            label: (value) => value,
            onSelected: (value) => chosen = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('队列'));
    expect(chosen, '队列');
  });

  testWidgets('tool button shows its tooltip and acts once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        DesktopToolButton(
          icon: Icons.lyrics_outlined,
          tooltip: '歌词',
          active: true,
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('歌词'));
    expect(taps, 1);
  });

  test('greeting follows the clock', () {
    expect(desktopGreeting(true, DateTime(2026, 1, 1, 8)), '早上好');
    expect(desktopGreeting(true, DateTime(2026, 1, 1, 15)), '下午好');
    expect(desktopGreeting(true, DateTime(2026, 1, 1, 21)), '晚上好');
    expect(desktopGreeting(true, DateTime(2026, 1, 1, 2)), '夜深了');
    expect(desktopGreeting(false, DateTime(2026, 1, 1, 8)), 'Good morning');
  });
}
