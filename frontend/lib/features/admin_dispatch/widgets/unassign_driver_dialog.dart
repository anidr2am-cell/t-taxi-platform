import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

const int kAdminUnassignReasonMaxLength = 255;

Future<String?> showUnassignDriverDialog({
  required BuildContext context,
  required String bookingNumber,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => UnassignDriverDialog(bookingNumber: bookingNumber),
  );
}

class UnassignDriverDialog extends StatefulWidget {
  final String bookingNumber;

  const UnassignDriverDialog({super.key, required this.bookingNumber});

  @override
  State<UnassignDriverDialog> createState() => _UnassignDriverDialogState();
}

class _UnassignDriverDialogState extends State<UnassignDriverDialog> {
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _canConfirm {
    final reason = _reasonController.text.trim();
    return reason.isNotEmpty && reason.length <= kAdminUnassignReasonMaxLength;
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || reason.length > kAdminUnassignReasonMaxLength) return;
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTokens.error),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(child: Text(l10n.t('admin_dispatch_unassign_driver_title'))),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.t('admin_dispatch_unassign_driver_message')),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                '${l10n.t('reservation_number')}: ${widget.bookingNumber}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                backgroundColor: AppTokens.errorLight,
                child: Text(
                  l10n.t('admin_dispatch_unassign_driver_warning'),
                  style: const TextStyle(
                    color: AppTokens.error,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              TextField(
                key: const ValueKey('admin_unassign_reason'),
                controller: _reasonController,
                maxLength: kAdminUnassignReasonMaxLength,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.t('admin_dispatch_unassign_driver_reason'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('back')),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTokens.error,
            foregroundColor: Colors.white,
          ),
          onPressed: _canConfirm ? _confirm : null,
          icon: const Icon(Icons.link_off_outlined),
          label: Text(l10n.t('admin_dispatch_unassign_driver_confirm')),
        ),
      ],
    );
  }
}
