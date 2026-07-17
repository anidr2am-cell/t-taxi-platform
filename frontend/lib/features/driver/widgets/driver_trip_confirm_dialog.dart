import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Confirmation dialog before driver trip status transitions.
Future<bool> confirmDriverTripAction({
  required BuildContext context,
  required String titleKey,
  required String messageKey,
  String? confirmKey,
  String? cancelKey,
  Widget? extraContent,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.t(titleKey)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.t(messageKey)),
          if (extraContent != null) ...[
            const SizedBox(height: 12),
            extraContent,
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.t(cancelKey ?? 'driver_confirm_no')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.t(confirmKey ?? 'driver_confirm_yes')),
        ),
      ],
    ),
  );
  return result == true;
}
