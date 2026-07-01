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

  static const _requiredLabelStyle = TextStyle(
    color: AppTokens.error,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );

  static const _fieldLabelStyle = TextStyle(
    color: AppTokens.textSecondary,
    fontSize: 12,
    height: 1.1,
  );

  static Widget buildFieldLabel({
    required String label,
    bool required = false,
    String? requiredLabel,
  }) {
    if (!required || requiredLabel == null) {
      return Text(label, style: _fieldLabelStyle);
    }

    return Text.rich(
      TextSpan(
        style: _fieldLabelStyle,
        children: [
          TextSpan(text: requiredLabel, style: _requiredLabelStyle),
          TextSpan(text: ' $label'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    bool required = false,
    String? requiredLabel,
  }) {
    return InputDecoration(
      label: buildFieldLabel(
        label: label,
        required: required,
        requiredLabel: requiredLabel,
      ),
      hintText: hint,
      prefixIcon: prefixIcon,
      floatingLabelBehavior: FloatingLabelBehavior.always,
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
