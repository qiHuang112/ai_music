import 'package:flutter/material.dart';

/// Edit these palettes to recolor every screen, dialog and player together.
class MusicPalette {
  const MusicPalette({
    required this.ink,
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.panel,
    required this.tint,
    required this.field,
    required this.text,
    required this.muted,
    required this.line,
    required this.accentEnd,
    required this.playerStart,
    required this.playerEnd,
    required this.playerEdge,
    required this.cache,
  });

  final Color ink, accent, onAccent, background, panel, tint, field;
  final Color text, muted, line;
  final Color accentEnd, playerStart, playerEnd, playerEdge, cache;

  static const light = MusicPalette(
    ink: Color(0xFF087F64),
    accent: Color(0xFF12B886),
    onAccent: Color(0xFF083E2F),
    background: Color(0xFFF8FCF9),
    panel: Color(0xFFFFFFFF),
    tint: Color(0xFFE5F9EF),
    field: Color(0xFFF0F8F3),
    text: Color(0xFF172620),
    muted: Color(0xFF5D7368),
    line: Color(0xFFDCEEE2),
    accentEnd: Color(0xFF43CCBA),
    playerStart: Color(0xFFF1FFF5),
    playerEnd: Color(0xFFEDF8F6),
    playerEdge: Color(0xFFFFFFFF),
    cache: Color(0xFFB2C8BD),
  );

  static const dark = MusicPalette(
    ink: Color(0xFF56DDB1),
    accent: Color(0xFF36CEA0),
    onAccent: Color(0xFF062F24),
    background: Color(0xFF131C17),
    panel: Color(0xFF202C25),
    tint: Color(0xFF203E2C),
    field: Color(0xFF27372D),
    text: Color(0xFFE6ECE8),
    muted: Color(0xFFA3AFA7),
    line: Color(0xFF304237),
    accentEnd: Color(0xFF80D1D8),
    playerStart: Color(0xFF1E322D),
    playerEnd: Color(0xFF171F24),
    playerEdge: Color(0x4871B7A1),
    cache: Color(0xFF506C5E),
  );
}

/// Shared geometry. Colors belong to ColorScheme, never individual pages.
abstract final class MusicUi {
  static const pagePadding = 20.0;
  static const radius = 18.0;
  static const fieldRadius = 16.0;
  static const coverRadius = 12.0;
  static const sectionGap = 24.0;
  static const playerCoverMaxWidth = 260.0;
  static const readingMaxWidth = 720.0;
  static const miniPlayerRadius = 26.0;
  static const miniPlayerInsets = EdgeInsets.fromLTRB(12, 8, 12, 10);
  static const pageInsets = EdgeInsets.fromLTRB(20, 16, 20, 24);
  static const horizontalInsets = EdgeInsets.symmetric(horizontal: pagePadding);
  static MusicSurfaces surfaces(BuildContext context) =>
      Theme.of(context).extension<MusicSurfaces>() ??
      MusicSurfaces.fromPalette(
        Theme.of(context).brightness == Brightness.dark
            ? MusicPalette.dark
            : MusicPalette.light,
      );
  static LinearGradient playerGradient(BuildContext context) {
    final colors = surfaces(context);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [colors.playerStart, colors.playerEnd],
    );
  }

  static LinearGradient accentGradient(BuildContext context) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Theme.of(context).colorScheme.primaryContainer,
      surfaces(context).accentEnd,
    ],
  );
  static Color playerBorder(BuildContext context) =>
      surfaces(context).playerEdge;
  static Color cacheColor(BuildContext context) => surfaces(context).cache;
  static bool compactActions(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 420 ||
      MediaQuery.textScalerOf(context).scale(14) > 18;
}

/// Branded materials interpolate with the user's light/dark theme selection.
@immutable
class MusicSurfaces extends ThemeExtension<MusicSurfaces> {
  const MusicSurfaces({
    required this.accentEnd,
    required this.playerStart,
    required this.playerEnd,
    required this.playerEdge,
    required this.cache,
  });
  factory MusicSurfaces.fromPalette(MusicPalette p) => MusicSurfaces(
    accentEnd: p.accentEnd,
    playerStart: p.playerStart,
    playerEnd: p.playerEnd,
    playerEdge: p.playerEdge,
    cache: p.cache,
  );
  final Color accentEnd, playerStart, playerEnd, playerEdge, cache;
  @override
  MusicSurfaces copyWith({
    Color? accentEnd,
    Color? playerStart,
    Color? playerEnd,
    Color? playerEdge,
    Color? cache,
  }) => MusicSurfaces(
    accentEnd: accentEnd ?? this.accentEnd,
    playerStart: playerStart ?? this.playerStart,
    playerEnd: playerEnd ?? this.playerEnd,
    playerEdge: playerEdge ?? this.playerEdge,
    cache: cache ?? this.cache,
  );
  @override
  MusicSurfaces lerp(covariant MusicSurfaces? other, double t) {
    if (other == null) return this;
    return MusicSurfaces(
      accentEnd: Color.lerp(accentEnd, other.accentEnd, t)!,
      playerStart: Color.lerp(playerStart, other.playerStart, t)!,
      playerEnd: Color.lerp(playerEnd, other.playerEnd, t)!,
      playerEdge: Color.lerp(playerEdge, other.playerEdge, t)!,
      cache: Color.lerp(cache, other.cache, t)!,
    );
  }
}

/// A static ambient wash, isolated from scrolling and playback repaint work.
class MusicPageBackdrop extends StatelessWidget {
  const MusicPageBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.25,
                    colors: [
                      Color.alphaBlend(
                        colors.secondaryContainer.withValues(alpha: .62),
                        colors.surface,
                      ),
                      colors.surface,
                    ],
                    stops: const [0, .8],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.bottomLeft,
                      radius: 1.1,
                      colors: [
                        MusicUi.surfaces(
                          context,
                        ).accentEnd.withValues(alpha: .035),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

abstract final class MusicAppTheme {
  static ThemeData create(Brightness brightness, {MusicPalette? palette}) {
    final p =
        palette ??
        (brightness == Brightness.dark
            ? MusicPalette.dark
            : MusicPalette.light);
    final colors =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: p.ink,
          onPrimary: brightness == Brightness.dark
              ? p.onAccent
              : MusicPalette.light.panel,
          primaryContainer: p.accent,
          onPrimaryContainer: p.onAccent,
          secondary: p.ink,
          secondaryContainer: p.tint,
          onSecondaryContainer: p.text,
          surface: p.background,
          surfaceContainerLowest: p.panel,
          surfaceContainerLow: p.panel,
          surfaceContainer: p.tint,
          surfaceContainerHigh: p.field,
          surfaceContainerHighest: p.field,
          onSurface: p.text,
          onSurfaceVariant: p.muted,
          outlineVariant: p.line,
          surfaceTint: Colors.transparent,
        );
    final base = ThemeData(colorScheme: colors, useMaterial3: true);
    final text = base.textTheme
        .apply(bodyColor: p.text, displayColor: p.text)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: p.muted,
          ),
        );
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(MusicUi.fieldRadius),
      borderSide: BorderSide.none,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      textTheme: text,
      extensions: [MusicSurfaces.fromPalette(p)],
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: MusicUi.pagePadding,
        toolbarHeight: 64,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MusicUi.radius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.ink,
        textColor: p.text,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall?.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 40,
        horizontalTitleGap: 12,
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.field,
        hintStyle: text.bodyLarge?.copyWith(color: p.muted),
        prefixIconColor: p.ink,
        suffixIconColor: p.muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: field,
        enabledBorder: field,
        disabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: p.ink)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.line),
          minimumSize: const Size(48, 48),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.text,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.field,
        selectedColor: p.tint,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: text.bodySmall?.copyWith(color: p.text),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.ink,
        linearTrackColor: p.field,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: p.ink,
        thumbColor: p.ink,
        secondaryActiveTrackColor: p.text.withValues(alpha: .28),
        inactiveTrackColor: p.text.withValues(alpha: .08),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.panel,
        modalBackgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: p.line,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.text,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.background),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
