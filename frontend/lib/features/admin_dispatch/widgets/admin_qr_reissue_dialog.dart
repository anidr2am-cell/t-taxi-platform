import 'package:flutter/material.dart';
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
      title: Text('$qrType QR token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Copy this token now. It is shown once and cannot be recovered later.',
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
                const SnackBar(content: Text('Token copied')),
              );
            }
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
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
      title: Text('Reissue $qrType QR'),
      content: Text(
        'This invalidates the previous $qrType QR token and issues a new one-time token for testing.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reissue')),
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
