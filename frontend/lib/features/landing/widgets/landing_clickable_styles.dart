import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

abstract final class LandingClickableStyles {
  static const Color background = Color(0xFFE8F3F1);
  static const Color hover = Color(0xFFDCECE8);
  static const Color pressed = Color(0xFFCEE3DE);
  static const Color border = Color(0xFFC9DEDA);
  static const Color selectedBackground = AppTokens.primaryDark;
  static const Color disabledBackground = Color(0xFFE8ECEE);
  static const Color disabledForeground = Color(0xFF8A9AA4);
  static const Color icon = AppTokens.primaryDark;
  static const Color ctaBackground = Color(0xFFD9A441);
  static const Color ctaForeground = Color(0xFF132B2E);

  static Color resolveSurface(
    Set<WidgetState> states, {
    bool selected = false,
  }) {
    if (states.contains(WidgetState.disabled)) {
      return disabledBackground;
    }
    if (selected) {
      return selectedBackground;
    }
    if (states.contains(WidgetState.pressed)) {
      return pressed;
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return hover;
    }
    return background;
  }

  static Color resolveForeground(
    Set<WidgetState> states, {
    bool selected = false,
  }) {
    if (states.contains(WidgetState.disabled)) {
      return disabledForeground;
    }
    return selected ? Colors.white : icon;
  }

  static ButtonStyle iconButtonStyle({
    bool selected = false,
    Size minimumSize = const Size(44, 44),
  }) {
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(minimumSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => resolveSurface(states, selected: selected),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => resolveForeground(states, selected: selected),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return pressed;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return hover;
        }
        return null;
      }),
      side: WidgetStatePropertyAll(
        BorderSide(color: selected ? selectedBackground : border),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ButtonStyle heroCtaStyle({required bool compact}) {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: ctaBackground,
      foregroundColor: ctaForeground,
      disabledBackgroundColor: disabledBackground,
      disabledForegroundColor: disabledForeground,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      textStyle: TextStyle(
        fontSize: compact ? 17 : 18,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
    );
  }
}
