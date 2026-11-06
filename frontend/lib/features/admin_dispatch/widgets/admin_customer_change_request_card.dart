import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class AdminCustomerChangeRequestCard extends StatelessWidget {
  const AdminCustomerChangeRequestCard({super.key, required this.request});
  final Map<String, dynamic> request;
  @override
  Widget build(BuildContext context) => AppUi.surfaceCard(
    backgroundColor: AppTokens.warningLight,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.t('admin_customer_change_request_title')),
        Text(request['message']?.toString() ?? ''),
        Text(context.l10n.t('admin_customer_change_request_help')),
      ],
    ),
  );
}
