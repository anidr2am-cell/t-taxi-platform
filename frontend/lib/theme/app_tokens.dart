import 'package:flutter/material.dart';

/// T-Ride design tokens — premium airport transfer / Thailand travel tone.
abstract final class AppTokens {
  // Brand
  static const Color primary = Color(0xFF0B6E6E);
  static const Color primaryDark = Color(0xFF084F50);
  static const Color primaryLight = Color(0xFFE8F6F6);
  static const Color accent = Color(0xFFC9922E);
  static const Color accentLight = Color(0xFFFFF4E5);

  // Neutrals
  static const Color background = Color(0xFFF4F7F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEEF2F4);
  static const Color border = Color(0xFFDDE5E8);
  static const Color textPrimary = Color(0xFF1E2A32);
  static const Color textSecondary = Color(0xFF5F727D);
  static const Color textMuted = Color(0xFF8A9AA4);

  // Semantic
  static const Color success = Color(0xFF1B7F4B);
  static const Color successLight = Color(0xFFE8F5EE);
  static const Color warning = Color(0xFFB86E00);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color error = Color(0xFFC0392B);
  static const Color errorLight = Color(0xFFFDECEA);
  static const Color info = Color(0xFF1565A8);
  static const Color infoLight = Color(0xFFE8F1FA);

  // Spacing
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // Radius
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static BorderRadius get borderRadiusSm => BorderRadius.circular(radiusSm);
  static BorderRadius get borderRadiusMd => BorderRadius.circular(radiusMd);
  static BorderRadius get borderRadiusLg => BorderRadius.circular(radiusLg);
  static BorderRadius get borderRadiusXl => BorderRadius.circular(radiusXl);

  static const double maxContentWidth = 720;

  static List<BoxShadow> cardShadow({Color? color}) => [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B6E6E), Color(0xFF0A5254)],
  );
}