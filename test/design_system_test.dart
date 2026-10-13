import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/design/controls.dart';
import 'package:ai_music/src/presentation/design/design_gallery_page.dart';
import 'package:ai_music/src/presentation/design/turntable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('theme exposes the palette and drops Latin tracking', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = MusicAppTheme.create(brightness);
      final palette = brightness == Brightness.dark
          ? MusicPalette.dark
          : MusicPalette.light;
      expect(theme.extension<MusicTokens>()?.palette, same(palette));
      expect(theme.colorScheme.primaryContainer, palette.accent);
      expect(theme.textTheme.bodyMedium?.letterSpacing, 0);
      expect(theme.textTheme.titleMedium?.letterSpacing, 0);
    }
  });

  testWidgets('gallery lays out on a small phone with large text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: const DesignGalleryPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Every section builds, including the ones below the fold.
    await tester.scrollUntilVisible(
      find.text('形状与动效'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery switches theme and play state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.dark),
        home: const DesignGalleryPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('播放'), findsNWidgets(2));

    // The deck's own button can sit below the fold; the mini player's cannot.
    await tester.tap(find.byTooltip('播放').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('暂停'), findsNWidgets(2));
    expect(find.text('NOW SPINNING'), findsOneWidget);
    expect(tester.widget<Turntable>(find.byType(Turntable)).playing, isTrue);
    await tester.tap(find.byTooltip('暂停').last);
    await tester.pumpAndSettle();
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.tap(find.byTooltip('浅色'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('深色'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a spinning record coasts to a stop', (tester) async {
    // flutter_test_config.dart stills perpetual motion; this test needs it.
    MusicMotion.perpetual = true;
    addTearDown(() => MusicMotion.perpetual = false);
    var playing = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.dark),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Center(
              child: SizedBox.square(
                dimension: 300,
                child: Turntable(playing: playing, progress: .5),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);

    rebuild(() => playing = false);
    // Without the stop the platter would hold pumpAndSettle open forever.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('groove slider seeks on tap and on drag release', (tester) async {
    final changes = <double>[];
    final ends = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicAppTheme.create(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: GrooveSlider(
                value: .2,
                onChanged: changes.add,
                onChangeEnd: ends.add,
              ),
            ),
          ),
        ),
      ),
    );
    final slider = find.byType(GrooveSlider);
    final left = tester.getTopLeft(slider);

    await tester.tapAt(left + const Offset(150, 16));
    await tester.pumpAndSettle();
    expect(ends.single, closeTo(.75, .01));

    ends.clear();
    changes.clear();
    await tester.dragFrom(left + const Offset(20, 16), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(ends.single, closeTo(.7, .1));
    expect(changes.every((value) => value >= 0 && value <= 1), isTrue);
  });

  testWidgets('tapping blank space dismisses the keyboard, a button does not', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DismissKeyboardOnTap(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focus),
                TextButton(onPressed: () => pressed++, child: const Text('go')),
                const Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(pressed, 1);
    expect(focus.hasFocus, isTrue);

    await tester.tapAt(const Offset(400, 500));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
