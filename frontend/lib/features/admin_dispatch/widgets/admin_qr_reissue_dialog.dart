import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../services/admin_dispatch_api_service.dart';

Future<void> showAdminQrReissueTokenDialog({
  required BuildContext context,
  required String qrType,
  required String token,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.t('admin_ui_type_qr_token').replaceAll('{type}', qrType)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('admin_ui_copy_this_token_now_it_is_shown_once_and_cannot_be_recovered_later'),
          ),
          const SizedBox(height: 12),
          SelectableText(
            token,
            key: const Key('adminQrReissueToken'),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: token));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(context.l10n.t('admin_ui_token_copied'))),
              );
            }
          },
          child: Text(context.l10n.t('admin_ui_copy')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.l10n.t('admin_ui_done')),
        ),
      ],
    ),
  );
}

Future<String?> confirmAdminQrReissue({
  required BuildContext context,
  required String qrType,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.t('admin_ui_reissue_type_qr').replaceAll('{type}', qrType)),
      content: Text(
        context.l10n.t('admin_ui_this_invalidates_the_previous_type_qr_token_and_issues_a_new_one_time_token_for_testing').replaceAll('{type}', qrType),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.t('admin_ui_cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.t('admin_ui_reissue'))),
      ],
    ),
  );
  return confirmed == true ? qrType : null;
}

Future<void> handleAdminQrReissue({
  required BuildContext context,
  required AdminDispatchApiService api,
  required String bookingNumber,
  required String qrType,
}) async {
  final confirmed = await confirmAdminQrReissue(context: context, qrType: qrType);
  if (confirmed == null || !context.mounted) return;

  final result = await api.reissueQr(bookingNumber, qrType);
  final token = qrType == 'BOARDING'
      ? result['boardingQrToken'] as String?
      : result['dropoffQrToken'] as String?;
  if (!context.mounted || token == null || token.isEmpty) return;

  await showAdminQrReissueTokenDialog(
    context: context,
    qrType: qrType,
    token: token,
  );
}
