import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../admin/widgets/admin_copy_button.dart';

class AdminGateArrivalLink extends StatefulWidget {
  const AdminGateArrivalLink({super.key, required this.bookingNumber});
  final String bookingNumber;
  @override
  State<AdminGateArrivalLink> createState() => _AdminGateArrivalLinkState();
}

class _AdminGateArrivalLinkState extends State<AdminGateArrivalLink> {
  String? _locale;
  @override
  Widget build(BuildContext context) {
    final lang = _locale ?? context.l10n.languageCode;
    final url = Uri.https('trider.taxi', '/booking/lookup', {
      'bookingNumber': widget.bookingNumber,
      'lang': lang,
      'arrival': 'gate7',
    }).toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(context.l10n.t('gate_arrival_link'))),
                AdminCopyButton(
                  text: url,
                  label: context.l10n.t('gate_arrival_link'),
                ),
              ],
            ),
            DropdownButton<String>(
              value: lang,
              isExpanded: true,
              items: AppLocalizations.customerSupportedLanguages
                  .map(
                    (code) => DropdownMenuItem(
                      value: code,
                      child: Text(AppLocalizations.languageNames[code]!),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _locale = value),
            ),
            SelectableText(url),
            Text(context.l10n.t('gate_arrival_intro')),
          ],
        ),
      ),
    );
  }
}
