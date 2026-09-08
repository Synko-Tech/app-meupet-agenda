import 'package:flutter/material.dart';

import 'app_brand_colors.dart';
import 'app_radius.dart';
import 'app_semantic_colors.dart';
import 'app_typography.dart';

/// Theme entry point for the MeuPet Agenda app.
///
/// Screens should read colors/typography from `Theme.of(context)` and
/// `context.brand` (see [AppBrandColors]).
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final brand = isDark ? AppBrandColors.dark : AppBrandColors.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppSemanticColors.primary,
      brightness: brightness,
      primary: isDark
          ? AppSemanticColors.darkPrimary
          : AppSemanticColors.primary,
      onPrimary: isDark
          ? AppSemanticColors.darkOnPrimary
          : AppSemanticColors.onPrimary,
      primaryContainer: isDark
          ? AppSemanticColors.darkPrimaryContainer
          : AppSemanticColors.primaryContainer,
      onPrimaryContainer: isDark
          ? AppSemanticColors.darkOnPrimaryContainer
          : AppSemanticColors.onPrimaryContainer,
      secondary: isDark
          ? AppSemanticColors.darkMuted
          : AppSemanticColors.secondary,
      surface: isDark
          ? AppSemanticColors.darkSurface
          : AppSemanticColors.surface,
      surfaceContainerLowest: isDark
          ? AppSemanticColors.darkBackground
          : AppSemanticColors.background,
      surfaceContainerLow: isDark
          ? AppSemanticColors.darkSurfaceMuted
          : AppSemanticColors.surfaceMuted,
      surfaceContainer: isDark
          ? AppSemanticColors.darkSurfaceMuted
          : AppSemanticColors.surfaceMuted,
      surfaceContainerHigh: isDark
          ? AppSemanticColors.darkSurfaceMuted
          : AppSemanticColors.surfaceMuted,
      surfaceContainerHighest: isDark
          ? AppSemanticColors.darkBorder
          : AppSemanticColors.border,
      error: isDark ? AppSemanticColors.darkDanger : AppSemanticColors.danger,
      onError: isDark
          ? AppSemanticColors.darkOnCoral
          : AppSemanticColors.onPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? AppSemanticColors.darkBackground
          : AppSemanticColors.background,
      fontFamily: AppTypography.bodyFont,
      extensions: [brand],
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: _display(isDark, 36),
      displayMedium: _display(isDark, 30),
      displaySmall: _display(isDark, 26),
      headlineLarge: _display(isDark, 26),
      headlineMedium: _display(isDark, 23),
      headlineSmall: _display(isDark, 20),
      titleLarge: _body(isDark, 18, FontWeight.w800),
      titleMedium: _body(isDark, 16, FontWeight.w800),
      titleSmall: _body(isDark, 14, FontWeight.w700),
      bodyLarge: _body(isDark, 16, FontWeight.w400),
      bodyMedium: _body(isDark, 14, FontWeight.w400),
      bodySmall: _body(isDark, 12, FontWeight.w400),
      labelLarge: _body(isDark, 15, FontWeight.w700),
      labelMedium: _body(isDark, 13, FontWeight.w700),
      labelSmall: _body(isDark, 11, FontWeight.w700),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark
            ? AppSemanticColors.darkText
            : AppSemanticColors.text,
        centerTitle: false,
        titleTextStyle: _body(isDark, 18, FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark
            ? AppSemanticColors.darkSurface
            : AppSemanticColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgRadius,
          side: BorderSide(
            color: isDark
                ? AppSemanticColors.darkBorder
                : AppSemanticColors.border,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppSemanticColors.darkSurfaceMuted
            : AppSemanticColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? AppSemanticColors.darkBorder
                : AppSemanticColors.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? AppSemanticColors.darkBorder
                : AppSemanticColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? AppSemanticColors.darkPrimary
                : AppSemanticColors.primary,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? AppSemanticColors.darkDanger
                : AppSemanticColors.danger,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? AppSemanticColors.darkDanger
                : AppSemanticColors.danger,
            width: 1.6,
          ),
        ),
        labelStyle: _body(isDark, 14, FontWeight.w600),
        hintStyle: _body(isDark, 14, FontWeight.w400)?.copyWith(
          color: isDark ? AppSemanticColors.darkMuted : AppSemanticColors.muted,
        ),
        helperStyle: _body(isDark, 12, FontWeight.w400)?.copyWith(
          color: isDark ? AppSemanticColors.darkMuted : AppSemanticColors.muted,
        ),
        errorStyle: _body(isDark, 12, FontWeight.w600)?.copyWith(
          color: isDark
              ? AppSemanticColors.darkDanger
              : AppSemanticColors.danger,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: isDark
              ? AppSemanticColors.darkSurfaceMuted
              : AppSemanticColors.surfaceMuted,
          disabledForegroundColor: isDark
              ? AppSemanticColors.darkMuted
              : AppSemanticColors.muted,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: _body(isDark, 15, FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark
              ? AppSemanticColors.darkText
              : AppSemanticColors.text,
          disabledForegroundColor: isDark
              ? AppSemanticColors.darkMuted
              : AppSemanticColors.muted,
          minimumSize: const Size(48, 48),
          side: BorderSide(
            color: isDark
                ? AppSemanticColors.darkBorder
                : AppSemanticColors.border,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: _body(isDark, 15, FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: _body(isDark, 14, FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: isDark
            ? AppSemanticColors.darkSurface
            : AppSemanticColors.surface,
        indicatorColor: isDark
            ? AppSemanticColors.darkPrimaryContainer
            : AppSemanticColors.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => _body(isDark, 12, FontWeight.w600)?.copyWith(
            color: states.contains(WidgetState.selected)
                ? isDark
                      ? AppSemanticColors.darkPrimary
                      : AppSemanticColors.primary
                : isDark
                ? AppSemanticColors.darkMuted
                : AppSemanticColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? isDark
                      ? AppSemanticColors.darkPrimary
                      : AppSemanticColors.primary
                : isDark
                ? AppSemanticColors.darkMuted
                : AppSemanticColors.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? AppSemanticColors.darkSurface
            : AppSemanticColors.surface,
        indicatorColor: isDark
            ? AppSemanticColors.darkPrimaryContainer
            : AppSemanticColors.primaryContainer,
        selectedIconTheme: IconThemeData(
          color: isDark
              ? AppSemanticColors.darkOnPrimaryContainer
              : AppSemanticColors.onPrimaryContainer,
        ),
        selectedLabelTextStyle: _body(isDark, 12, FontWeight.w700)?.copyWith(
          color: isDark
              ? AppSemanticColors.darkPrimary
              : AppSemanticColors.primary,
        ),
        unselectedLabelTextStyle: _body(isDark, 12, FontWeight.w500)?.copyWith(
          color: isDark ? AppSemanticColors.darkMuted : AppSemanticColors.muted,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? AppSemanticColors.darkSurfaceMuted
            : AppSemanticColors.surface,
        selectedColor: isDark
            ? AppSemanticColors.darkPrimaryContainer
            : AppSemanticColors.primaryContainer,
        side: BorderSide(
          color: isDark
              ? AppSemanticColors.darkBorder
              : AppSemanticColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
        labelStyle: _body(isDark, 13, FontWeight.w600),
        secondaryLabelStyle: _body(isDark, 13, FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? isDark
                    ? AppSemanticColors.darkPrimaryContainer
                    : AppSemanticColors.primaryContainer
              : null,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppSemanticColors.darkSurface : brand.navy,
        contentTextStyle: _body(
          false,
          14,
          FontWeight.w600,
        )?.copyWith(color: isDark ? AppSemanticColors.darkText : Colors.white),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? AppSemanticColors.darkSurface
            : AppSemanticColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.fullTopRadius,
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? AppSemanticColors.darkSurface
            : AppSemanticColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
        titleTextStyle: _body(isDark, 18, FontWeight.w800),
        contentTextStyle: _body(isDark, 14, FontWeight.w400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: isDark
            ? AppSemanticColors.darkBorder
            : AppSemanticColors.border,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppSemanticColors.darkBorder : AppSemanticColors.border,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: isDark ? AppSemanticColors.darkText : AppSemanticColors.text,
      ),
    );
  }

  static TextStyle? _display(bool isDark, double size) {
    return TextStyle(
      fontFamily: AppTypography.displayFont,
      fontSize: size,
      height: 1.15,
      fontWeight: FontWeight.w400,
      color: isDark ? AppSemanticColors.darkText : AppSemanticColors.text,
    );
  }

  static TextStyle? _body(bool isDark, double size, FontWeight weight) {
    return TextStyle(
      fontFamily: AppTypography.bodyFont,
      fontSize: size,
      height: 1.4,
      fontWeight: weight,
      color: isDark ? AppSemanticColors.darkText : AppSemanticColors.text,
    );
  }
}
