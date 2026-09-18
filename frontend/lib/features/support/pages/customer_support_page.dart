import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/services/booking_contact_connection_service.dart';
import '../widgets/support_contact_channels_section.dart';

class CustomerSupportPage extends StatelessWidget {
  const CustomerSupportPage({super.key, this.contactService});

  final BookingContactConnectionService? contactService;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width >= 900 ? 920.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(title: Text(l10n.t('support_title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: AppUi.pagePadding(context),
              children: [
                AppUi.surfaceCard(
                  padding: const EdgeInsets.all(AppTokens.spaceLg),
                  child: SupportContactChannelsSection(
                    contactService: contactService,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
