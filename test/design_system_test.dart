import 'package:ai_music/src/presentation/design/vinyl_disc.dart';
import 'package:ai_music/src/presentation/design/glass_surface.dart';
import 'package:ai_music/src/presentation/design/ambient_backdrop.dart';
import 'package:ai_music/src/data/music_settings.dart';
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
                child: Turntable(playing: playing),
              ),
            );
          },
        ),
      ),
    );
    SpinningVinyl disc() => tester.widget(find.byType(SpinningVinyl));
    await tester.pump(const Duration(seconds: 1));
    expect(disc().spinning, isTrue);

    rebuild(() => playing = false);
    await tester.pump();
    // The platter coasts on its own clock and then stops it; a clock left
    // running would fail the test as a pending timer.
    await tester.pump(const Duration(seconds: 8));
    expect(disc().spinning, isFalse);
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

  testWidgets('neon rain skin paints its backdrop and materials', (
    tester,
  ) async {
    expect(AppThemePreference.fromStorage('neon'), AppThemePreference.neon);
    final theme = MusicAppTheme.create(
      Brightness.dark,
      palette: MusicPalette.neonRain,
    );
    expect(theme.extension<MusicTokens>()!.palette.neon, isTrue);
    expect(theme.colorScheme.primaryContainer, const Color(0xFFFF3D9A));
    // Night stays as it was.
    expect(
      MusicAppTheme.create(Brightness.dark).extension<MusicTokens>()!.palette,
      same(MusicPalette.dark),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Stack(
          fit: StackFit.expand,
          children: [
            const PageBackdrop(),
            Scaffold(
              body: AmbientBackdrop(
                drift: false,
                child: Column(
                  children: [
                    const SizedBox.square(
                      dimension: 220,
                      child: Turntable(playing: false),
                    ),
                    GlassSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: PlayPauseButton(
                          playing: true,
                          tooltip: 'pause',
                          onPressed: () {},
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) =>
                          Text('霓虹', style: MusicType.masthead(context)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text('霓虹'));
    expect(title.style!.shadows, isNotEmpty);
  });

  testWidgets('every appearance builds its backdrop and materials', (
    tester,
  ) async {
    for (final appearance in AppThemePreference.values) {
      expect(
        AppThemePreference.fromStorage(appearance.storageValue),
        appearance,
      );
      final palette = MusicPalette.of(appearance);
      final theme = MusicAppTheme.create(
        appearance.isDark ? Brightness.dark : Brightness.light,
        palette: palette,
      );
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(appearance),
          theme: theme,
          home: Stack(
            fit: StackFit.expand,
            children: [
              const PageBackdrop(),
              Scaffold(
                body: AmbientBackdrop(
                  drift: false,
                  child: ListView(
                    children: [
                      const SizedBox.square(
                        dimension: 220,
                        child: Turntable(playing: false),
                      ),
                      GlassSurface(
                        child: Row(
                          children: [
                            PlayPauseButton(
                              playing: true,
                              tooltip: 'pause',
                              onPressed: () {},
                            ),
                            PlayPauseButton(
                              playing: false,
                              size: 40,
                              tooltip: 'play',
                              onPressed: () {},
                            ),
                            GlassIconButton(
                              icon: Icons.skip_next,
                              tooltip: 'next',
                              onPressed: () {},
                            ),
                            const Text('song'),
                          ],
                        ),
                      ),
                      const Card(child: ListTile(title: Text('card'))),
                      const TextField(),
                      Builder(
                        builder: (context) =>
                            Text('标题', style: MusicType.masthead(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: appearance.name);
    }
  });
}
