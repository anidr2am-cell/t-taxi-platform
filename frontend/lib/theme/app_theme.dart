import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  // Backward-compatible aliases
  static const Color primary = AppTokens.primary;
  static const Color primaryLight = AppTokens.primaryLight;
  static const Color accent = AppTokens.accent;
  static const Color success = AppTokens.success;
  static const Color background = AppTokens.background;

  static ThemeData get lightTheme {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppTokens.primary,
      onPrimary: Colors.white,
      secondary: AppTokens.accent,
      onSecondary: Colors.white,
      error: AppTokens.error,
      onError: Colors.white,
      surface: AppTokens.surface,
      onSurface: AppTokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppTokens.background,
      dividerColor: AppTokens.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppTokens.textPrimary,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppTokens.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTokens.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTokens.textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: AppTokens.textPrimary,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppTokens.textPrimary,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppTokens.textSecondary,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTokens.textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTokens.border,
          disabledForegroundColor: AppTokens.textMuted,
          elevation: 0,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusMd,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.primary,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppTokens.border),
          shape: RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusMd,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppTokens.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusMd,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppTokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusLg,
          side: const BorderSide(color: AppTokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.surface,
        hintStyle: const TextStyle(color: AppTokens.textMuted),
        labelStyle: const TextStyle(color: AppTokens.textSecondary),
        border: OutlineInputBorder(
          borderRadius: AppTokens.borderRadiusMd,
          borderSide: const BorderSide(color: AppTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTokens.borderRadiusMd,
          borderSide: const BorderSide(color: AppTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTokens.borderRadiusMd,
          borderSide: const BorderSide(color: AppTokens.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppTokens.surfaceMuted,
        selectedColor: AppTokens.primaryLight,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTokens.textPrimary,
        ),
        side: const BorderSide(color: AppTokens.border),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusSm),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppTokens.surface,
        selectedIconTheme: IconThemeData(color: AppTokens.primary),
        selectedLabelTextStyle: TextStyle(
          color: AppTokens.primary,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
        unselectedIconTheme: IconThemeData(color: AppTokens.textMuted),
        unselectedLabelTextStyle: TextStyle(
          color: AppTokens.textSecondary,
          fontSize: 11,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
      ),
    );
  }
}
