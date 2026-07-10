import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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
          child: BookingChatSection(
            bookingNumber: bookingNumber,
            guestAccessToken: guestAccessToken,
            api: api,
            socketService: socketService,
          ),
        ),
      ),
    );
  }
}
