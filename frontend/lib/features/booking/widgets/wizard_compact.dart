import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// Compact layout tokens for the customer booking wizard only.
class WizardCompact {
  WizardCompact._();

  static const sectionGap = 8.0;
  static const fieldGap = 8.0;
  static const cardPadding = 12.0;
  static const headerPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);
  static const bodyPadding = EdgeInsets.fromLTRB(12, 0, 12, 12);
  static const minTouchHeight = 44.0;

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    bool required = false,
    String? requiredLabel,
  }) {
    final requiredMark = required && requiredLabel != null
        ? Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              requiredLabel,
              style: const TextStyle(
                color: AppTokens.error,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          )
        : null;

    Widget? prefix;
    if (requiredMark != null && prefixIcon != null) {
      prefix = Row(
        mainAxisSize: MainAxisSize.min,
        children: [requiredMark, prefixIcon],
      );
    } else if (requiredMark != null) {
      prefix = requiredMark;
    }

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix != null ? null : prefixIcon,
      prefix: prefix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: const OutlineInputBorder(),
      constraints: const BoxConstraints(minHeight: minTouchHeight),
    );
  }

  static TextStyle hintTextStyle = const TextStyle(
    color: AppTokens.textSecondary,
    fontSize: 12,
    height: 1.35,
  );

  static TextStyle validationTextStyle = const TextStyle(
    color: AppTokens.warning,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
}
