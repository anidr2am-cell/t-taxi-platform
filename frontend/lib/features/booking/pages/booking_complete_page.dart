import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../models/booking_create_result.dart';

class BookingCompletePage extends StatelessWidget {
  final BookingCreateResult result;
  final String serviceLabel;
  final String originLabel;
  final String destinationLabel;

  const BookingCompletePage({
    super.key,
    required this.result,
    required this.serviceLabel,
    required this.originLabel,
    required this.destinationLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('booking_complete'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 64),
            const SizedBox(height: 16),
            Text(
              result.trustMessage.isNotEmpty
                  ? result.trustMessage
                  : l10n.t('booking_trust_message'),
              style: TextStyle(color: Colors.grey.shade800, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _row(l10n.t('reservation_number'), result.bookingNumber),
                    _row(l10n.t('status'), l10n.t('status_pending')),
                    _row(
                      l10n.t('total'),
                      '${result.totalAmount} ${result.currency}',
                      bold: true,
                    ),
                    _row(l10n.t('payment_method'), l10n.t('pay_driver_at_destination')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('booking_summary'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _row(l10n.t('service_type'), serviceLabel),
                    _row(l10n.t('origin'), originLabel),
                    _row(l10n.t('destination'), destinationLabel),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.t('boarding_qr_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('boarding_qr_hint'),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: result.boardingQrToken,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(l10n.t('chat_after_driver_assignment')),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: Text(l10n.t('app_title')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
