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
  });

  final Color ink, accent, onAccent, background, panel, tint, field;
  final Color text, muted, line;

  static const light = MusicPalette(
    ink: Color(0xFF087F64),
    accent: Color(0xFF12B886),
    onAccent: Color(0xFF083E2F),
    background: Color(0xFFF8FCF9),
    panel: Color(0xFFFFFFFF),
    tint: Color(0xFFE5F9EF),
    field: Color(0xFFF0F8F3),
    text: Color(0xFF172620),
    muted: Color(0xFF69746E),
    line: Color(0xFFDCEEE2),
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
  );
}

/// Shared geometry. Colors belong to ColorScheme, never individual pages.
abstract final class MusicUi {
  static const pagePadding = 20.0;
  static const radius = 18.0;
  static const fieldRadius = 16.0;
  static const coverRadius = 12.0;
  static const sectionGap = 24.0;
  static const playerCoverMaxWidth = 320.0;
  static const miniPlayerRadius = 26.0;
  static const miniPlayerInsets = EdgeInsets.fromLTRB(12, 8, 12, 10);
  static const pageInsets = EdgeInsets.fromLTRB(20, 16, 20, 24);
  static const horizontalInsets = EdgeInsets.symmetric(horizontal: pagePadding);
  static bool compactActions(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 420 ||
      MediaQuery.textScalerOf(context).scale(14) > 18;
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
