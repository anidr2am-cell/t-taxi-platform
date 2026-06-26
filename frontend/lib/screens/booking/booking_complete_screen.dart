import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/booking_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/language_selector.dart';

class BookingCompleteScreen extends StatefulWidget {
  const BookingCompleteScreen({super.key});

  @override
  State<BookingCompleteScreen> createState() => _BookingCompleteScreenState();
}

class _BookingCompleteScreenState extends State<BookingCompleteScreen> {
  bool _showChat = false;

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingState>();
    final reservation = booking.createdReservation!;
    final l10n = context.l10n;
    final status = ReservationStatusExt.fromApi(reservation['status'] as String? ?? 'pending');
    final roomId = 'room_${reservation['reservation_number']}';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('booking_complete')),
        actions: const [LanguageSelector()],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    l10n.t('booking_complete'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _infoRow(l10n.t('reservation_number'), reservation['reservation_number'] as String? ?? ''),
                          _infoRow(l10n.t('vehicle'), reservation['selected_vehicle_type'] as String? ?? ''),
                          _infoRow(
                            l10n.t('amount'),
                            '${reservation['total_price']} ${l10n.t('thb')}',
                          ),
                          _infoRow(l10n.t('status'), l10n.t(status.labelKey)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_showChat)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _showChat = true),
                        icon: const Icon(Icons.chat),
                        label: Text(l10n.t('chat_driver')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  if (_showChat) ...[
                    const SizedBox(height: 16),
                    Text(l10n.t('chat_driver'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 400,
                      child: Card(
                        child: ChatPanel(
                          roomId: roomId,
                          senderRole: 'customer',
                          senderName: reservation['customer_name'] as String? ?? 'Customer',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () {
                  context.read<BookingState>().reset();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Text(l10n.t('app_title')),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: !_showChat
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showChat = true),
              backgroundColor: AppTheme.accent,
              icon: const Icon(Icons.chat),
              label: Text(l10n.t('chat_driver')),
            )
          : null,
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
