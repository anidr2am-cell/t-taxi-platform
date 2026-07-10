import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../chat/services/chat_socket_service.dart';
import '../services/booking_chat_api.dart';
import '../widgets/booking_chat_section.dart';

class CustomerBookingChatPage extends StatelessWidget {
  const CustomerBookingChatPage({
    super.key,
    required this.bookingNumber,
    required this.guestAccessToken,
    this.api,
    this.socketService,
  });

  final String bookingNumber;
  final String? guestAccessToken;
  final BookingChatApi? api;
  final ChatSocketService? socketService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('booking_chat_title'))),
      body: AppUi.centeredContent(
        child: SingleChildScrollView(
          padding: AppUi.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PickupAlertNotice(),
              const SizedBox(height: AppTokens.spaceMd),
              BookingChatSection(
                bookingNumber: bookingNumber,
                guestAccessToken: guestAccessToken,
                api: api,
                socketService: socketService,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickupAlertNotice extends StatelessWidget {
  const _PickupAlertNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.infoLight,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppTokens.info,
            size: 22,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('customer_chat_pickup_alert_notice_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.t('customer_chat_pickup_alert_notice_body'),
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
