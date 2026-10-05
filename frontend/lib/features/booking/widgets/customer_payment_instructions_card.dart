import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class CustomerPaymentInstructionsCard extends StatelessWidget {
  const CustomerPaymentInstructionsCard({
    super.key,
    required this.paymentMethod,
    this.paymentCurrency,
    this.instructions = const {},
  });

  final String paymentMethod;
  final String? paymentCurrency;
  final Map<String, dynamic> instructions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final method = paymentMethod.toUpperCase();
    if (method == 'PAY_DRIVER') {
      return _messageCard(
        context,
        Icons.payments_outlined,
        l10n.t('payment_pay_driver_description'),
      );
    }
    if (method == 'CARD') {
      return _messageCard(
        context,
        Icons.credit_card_outlined,
        l10n.t('payment_card_description'),
      );
    }
    if (method != 'BANK_TRANSFER') return const SizedBox.shrink();

    final currency = (paymentCurrency ?? 'KRW').toUpperCase();
    final qrUrl = '${instructions['qrImageUrl'] ?? ''}'.trim();
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.accentLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.t('customer_payment_bank_transfer')} ($currency)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (instructions.isEmpty)
            Text(l10n.t('payment_details_contact_admin'))
          else if (currency == 'KRW') ...[
            AppUi.summaryRow(
              label: l10n.t('admin_settings_bank_name'),
              value: '${instructions['bankName'] ?? '-'}',
            ),
            AppUi.summaryRow(
              label: l10n.t('admin_settings_account_name'),
              value: '${instructions['accountName'] ?? '-'}',
            ),
            AppUi.summaryRow(
              label: l10n.t('admin_settings_account_number'),
              value: '${instructions['accountNumber'] ?? '-'}',
            ),
          ] else if (qrUrl.isNotEmpty)
            Center(
              child: Image.network(
                qrUrl.startsWith('http') ? qrUrl : '${AppConfig.apiBaseUrl}$qrUrl',
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),
            )
          else
            Text(l10n.t('payment_details_contact_admin')),
          const SizedBox(height: 10),
          Text(
            l10n.t('payment_depositor_name_notice'),
            style: const TextStyle(
              color: AppTokens.warning,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(BuildContext context, IconData icon, String message) {
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.accentLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTokens.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(height: 1.45))),
        ],
      ),
    );
  }
}
