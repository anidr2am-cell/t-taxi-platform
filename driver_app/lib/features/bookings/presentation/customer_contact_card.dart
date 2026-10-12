import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../data/booking_models.dart';

class CustomerContactCard extends StatelessWidget {
  const CustomerContactCard({super.key, required this.contact});

  final CustomerContact contact;

  String _digits(String? value) => (value ?? '').replaceAll(RegExp(r'\D'), '');

  Future<void> _copy(BuildContext context, String value) async {
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.contactCopied)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.contactCopyFailed)));
      }
    }
  }

  Future<void> _open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final type = contact.messengerType;
    final id = contact.messengerId;
    final phone = contact.phone;
    final messengerDigits = _digits(id);
    final phoneIsDuplicate =
        (type == 'WHATSAPP' || type == 'SMS') &&
        messengerDigits.isNotEmpty && messengerDigits == _digits(phone);

    Widget actions(List<Widget> children) =>
        Wrap(spacing: 8, runSpacing: 8, children: children);
    final rows = <Widget>[];
    if (type == 'KAKAO' || type == 'LINE') {
      if (id != null && id.isNotEmpty) {
        rows.add(
          SelectableText(
            '${type == 'KAKAO' ? l10n.contactKakao : 'LINE'} · $id',
          ),
        );
        rows.add(
          actions([
            OutlinedButton.icon(
              onPressed: () => _copy(context, id),
              icon: const Icon(Icons.copy),
              label: Text(l10n.contactCopyId),
            ),
          ]),
        );
      }
      if (type == 'KAKAO') rows.add(Text(l10n.contactKakaoHelp));
    } else if (type == 'WHATSAPP' && id != null && messengerDigits.isNotEmpty) {
      rows.add(SelectableText('WhatsApp · $id'));
      rows.add(
        actions([
          OutlinedButton.icon(
            onPressed: () => _open(Uri.parse('https://wa.me/$messengerDigits')),
            icon: const Icon(Icons.chat),
            label: Text(l10n.contactOpenWhatsApp),
          ),
        ]),
      );
    } else if (type == 'SMS' && id != null && messengerDigits.isNotEmpty) {
      rows.add(SelectableText('${l10n.contactPhoneSms} · $id'));
      rows.add(
        actions([
          OutlinedButton.icon(
            onPressed: () => _open(Uri(scheme: 'tel', path: id)),
            icon: const Icon(Icons.call),
            label: Text(l10n.contactCall),
          ),
          OutlinedButton.icon(
            onPressed: () => _open(Uri(scheme: 'sms', path: id)),
            icon: const Icon(Icons.sms),
            label: Text(l10n.contactSms),
          ),
        ]),
      );
    }
    if (phone != null && _digits(phone).isNotEmpty && !phoneIsDuplicate) {
      rows.add(
        SelectableText(
          '${type == null ? l10n.contactPhoneSms : l10n.contactEmergencyPhone} · $phone',
        ),
      );
      rows.add(
        actions([
          OutlinedButton.icon(
            onPressed: () => _open(Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.call),
            label: Text(l10n.contactCall),
          ),
        ]),
      );
    }
    if (rows.isEmpty) rows.add(Text(l10n.contactUnavailable));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.customerContactTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...rows.expand((row) => [row, const SizedBox(height: 8)]),
          ],
        ),
      ),
    );
  }
}
