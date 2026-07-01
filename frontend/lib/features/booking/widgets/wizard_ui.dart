import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import 'wizard_compact.dart';

class WizardUi {
  WizardUi._();

  static Widget selectionTile({
    required String title,
    String? subtitle,
    IconData? icon,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return AppUi.surfaceCard(
      onTap: onTap,
      backgroundColor: selected ? AppTokens.primaryLight : AppTokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: WizardCompact.minTouchHeight),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTokens.primary.withValues(alpha: 0.12)
                      : AppTokens.surfaceMuted,
                  borderRadius: AppTokens.borderRadiusSm,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? AppTokens.primary : AppTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected ? AppTokens.primaryDark : AppTokens.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: selected ? AppTokens.primary : AppTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  static Widget counterRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int min = 0,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: WizardCompact.minTouchHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: Icon(
                Icons.remove_circle_outline,
                size: 22,
                color: value > min ? AppTokens.primary : AppTokens.textMuted,
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => onChanged(value + 1),
              icon: const Icon(Icons.add_circle_outline, size: 22, color: AppTokens.primary),
            ),
          ],
        ),
      ),
    );
  }

  static Widget sectionHint(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WizardCompact.fieldGap),
      child: Text(message, style: WizardCompact.validationTextStyle),
    );
  }

  static Widget infoHint(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WizardCompact.fieldGap),
      child: Text(message, style: WizardCompact.hintTextStyle),
    );
  }
}
