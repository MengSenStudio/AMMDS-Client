import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// 深色主题（文档 #5.1）。
ThemeData buildDarkTheme() =>
    buildAppThemeData(brightness: Brightness.dark, colors: AppColors.dark);

/// 依据设计令牌构建 Flutter [ThemeData]。
///
/// 浅色与深色共用同一套结构，仅颜色不同，
/// 保证两套主题的组件形态与间距完全一致。
ThemeData buildAppThemeData({
  required Brightness brightness,
  required AppColors colors,
}) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.brand,
    onPrimary: Colors.white,
    primaryContainer: colors.brandSubtle,
    onPrimaryContainer: colors.brand,
    secondary: colors.info,
    onSecondary: Colors.white,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    surfaceContainerHighest: colors.surfaceVariant,
    onSurfaceVariant: colors.textSecondary,
    error: colors.error,
    onError: Colors.white,
    outline: colors.border,
    outlineVariant: colors.divider,
  );

  final base = isDark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.surface,
    dividerColor: colors.divider,
    splashFactory: InkRipple.splashFactory,
    extensions: <ThemeExtension<dynamic>>[colors],
    textTheme: base.textTheme
        .apply(bodyColor: colors.textPrimary, displayColor: colors.textPrimary)
        .copyWith(
          headlineMedium: AppTypography.headline.copyWith(
            color: colors.textPrimary,
          ),
          titleLarge: AppTypography.title.copyWith(color: colors.textPrimary),
          titleMedium: AppTypography.subtitle.copyWith(
            color: colors.textPrimary,
          ),
          bodyLarge: AppTypography.body.copyWith(color: colors.textPrimary),
          bodyMedium: AppTypography.body.copyWith(color: colors.textPrimary),
          bodySmall: AppTypography.bodySmall.copyWith(
            color: colors.textSecondary,
          ),
          labelLarge: AppTypography.button.copyWith(color: colors.textPrimary),
          labelSmall: AppTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.title.copyWith(color: colors.textPrimary),
      iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: colors.divider,
      thickness: 0.5,
      space: 0.5,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.divider),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceVariant,
      hintStyle: AppTypography.body.copyWith(color: colors.textTertiary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colors.brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colors.error),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.brandSubtle,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        AppTypography.caption.copyWith(color: colors.textSecondary),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.brandSubtle,
      selectedIconTheme: IconThemeData(color: colors.brand, size: 22),
      unselectedIconTheme: IconThemeData(color: colors.textSecondary, size: 22),
      selectedLabelTextStyle: AppTypography.body.copyWith(
        color: colors.brand,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: AppTypography.body.copyWith(
        color: colors.textSecondary,
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: colors.textPrimary,
      iconColor: colors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.brand,
      linearTrackColor: colors.surfaceVariant,
      circularTrackColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? colors.surfaceVariant : const Color(0xFF2C2C2C),
      contentTextStyle: AppTypography.body.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
    splashColor: colors.brandSubtle,
    highlightColor: colors.brandSubtle.withValues(alpha: 0.4),
  );
}
