import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../admin/widgets/admin_copy_button.dart';
import '../utils/admin_driver_check_messages.dart';

class AdminDriverCheckCards extends StatefulWidget {
  const AdminDriverCheckCards({
    super.key,
    required this.detail,
    this.copyText,
    this.onDecision,
  });
  final Map<String, dynamic> detail;
  final Future<void> Function(String)? copyText;

  final Future<void> Function(String)? onDecision;
  @override
  State<AdminDriverCheckCards> createState() => _AdminDriverCheckCardsState();
}

class _AdminDriverCheckCardsState extends State<AdminDriverCheckCards> {
  bool _saving = false;
  String? _error;
  Future<void> _decide(String choice) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l.t(
            choice == 'PAID'
                ? 'admin_collection_paid'
                : 'admin_collection_direct',
          ),
        ),
        content: Text(
          l.t(
            choice == 'PAID'
                ? 'admin_collection_paid_confirm'
                : 'admin_collection_direct_confirm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('admin_receipt_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('admin_collection_save')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onDecision!(choice);
    } catch (_) {
      if (mounted) setState(() => _error = l.t('admin_collection_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = widget.detail;
    final summary = detail['driverFinancialSummary'] is Map
        ? detail['driverFinancialSummary'] as Map
        : {};
    final required = summary['collectionDecisionRequired'] == true;
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_driver_check_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('admin_driver_check_notice')),
          if (summary['requiresCollectionDecision'] == true) ...[
            Text(
              l10n.t(
                required
                    ? 'admin_collection_required'
                    : 'admin_collection_saved',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (_error != null) Text(_error!),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                FilledButton(
                  onPressed: _saving || widget.onDecision == null
                      ? null
                      : () => _decide('PAID'),
                  child: Text(l10n.t('admin_collection_paid')),
                ),
                OutlinedButton(
                  onPressed:
                      _saving ||
                          widget.onDecision == null ||
                          summary['paymentStatus'] == 'PAID'
                      ? null
                      : () => _decide('CUSTOMER_DIRECT'),
                  child: Text(l10n.t('admin_collection_direct')),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppTokens.spaceSm),
          for (final message
              in (_saving
                  ? <AdminDriverCheckMessage>[]
                  : buildAdminDriverCheckMessages(detail)))
            ExpansionTile(
              initiallyExpanded: true,
              key: ValueKey('adminDriverCheck-${message.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
              title: Row(
                children: [
                  Expanded(child: Text(l10n.t(message.titleKey))),
                  AdminCopyButton(
                    text: message.thai,
                    label:
                        '${l10n.t(message.titleKey)} · ${l10n.t('admin_driver_check_thai')}',
                    copyText: widget.copyText,
                  ),
                ],
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.t('admin_driver_check_thai'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                SelectableText(message.thai),
                const SizedBox(height: AppTokens.spaceMd),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.t('admin_driver_check_korean'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                SelectableText(message.korean),
              ],
            ),
        ],
      ),
    );
  }
}
