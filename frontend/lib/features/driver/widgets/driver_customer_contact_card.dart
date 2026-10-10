import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../driver_trip_contact.dart';
import '../models/driver_booking.dart';

class DriverCustomerContactCard extends StatelessWidget {
  const DriverCustomerContactCard({
    super.key,
    required this.contact,
    this.legacyPhone,
  });

  final DriverCustomerContact? contact;
  final String? legacyPhone;

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _formatPhone(String value) {
    final digits = DriverTripContact.phoneDigits(value);
    if (digits.startsWith('82') && digits.length == 12) {
      return '+82 ${digits.substring(2, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}';
    }
    if (digits.startsWith('66') && digits.length == 11) {
      return '+66 ${digits.substring(2, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
    }
    return value;
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.l10n.t('driver_contact_copied'))),
      );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTokens.primary,
        side: const BorderSide(color: AppTokens.border),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = _nonEmpty(contact?.messengerType)?.toUpperCase();
    final id = _nonEmpty(contact?.messengerId);
    final phone = _nonEmpty(contact?.phone) ?? _nonEmpty(legacyPhone);
    final hasMessenger = type != null && id != null;
    final messengerUsesPhone = type == 'WHATSAPP' || type == 'SMS';
    final showEmergencyPhone =
        phone != null &&
        hasMessenger &&
        (!messengerUsesPhone || !DriverTripContact.samePhone(phone, id));

    String channelLabel(String code) => switch (code) {
      'KAKAO' => l10n.t('driver_contact_kakao'),
      'LINE' => l10n.t('driver_contact_line'),
      'WHATSAPP' => l10n.t('driver_contact_whatsapp'),
      'SMS' => l10n.t('driver_contact_phone_sms'),
      _ => code,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: AppTokens.cardDecorationFlat(
        color: AppTokens.primaryLight,
        borderColor: AppTokens.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('driver_contact_title'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTokens.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (hasMessenger) ...[
            Text(
              '${channelLabel(type!)} · ${messengerUsesPhone ? _formatPhone(id!) : id}',
              key: const ValueKey('driverCustomerMessenger'),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                if (type == 'KAKAO' || type == 'LINE')
                  _action(
                    icon: Icons.copy_outlined,
                    label: l10n.t('driver_contact_copy_id'),
                    onPressed: () => _copy(context, id!),
                  ),
                if (type == 'WHATSAPP' &&
                    DriverTripContact.whatsappUri(id) != null)
                  _action(
                    icon: Icons.chat_outlined,
                    label: l10n.t('driver_contact_open_whatsapp'),
                    onPressed: () => DriverTripContact.openWhatsApp(id!),
                  ),
                if (type == 'SMS' &&
                    DriverTripContact.hasCallablePhone(id)) ...[
                  _action(
                    icon: Icons.phone_outlined,
                    label: l10n.t('driver_contact_call'),
                    onPressed: () => DriverTripContact.callPhone(id!),
                  ),
                  if (DriverTripContact.smsUri(id) != null)
                    _action(
                      icon: Icons.sms_outlined,
                      label: l10n.t('driver_contact_sms'),
                      onPressed: () => DriverTripContact.sendSms(id!),
                    ),
                ],
              ],
            ),
            if (type == 'KAKAO') ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                l10n.t('driver_contact_kakao_help'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
              ),
            ],
          ] else if (phone != null) ...[
            Text(
              '${l10n.t('driver_contact_phone')} · ${_formatPhone(phone)}',
              key: const ValueKey('driverCustomerLegacyPhone'),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            _action(
              icon: Icons.phone_outlined,
              label: l10n.t('driver_contact_call'),
              onPressed: () => DriverTripContact.callPhone(phone),
            ),
          ] else
            Text(
              l10n.t('driver_contact_unavailable'),
              key: const ValueKey('driverCustomerContactUnavailable'),
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          if (showEmergencyPhone) ...[
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              '${l10n.t('driver_contact_emergency_phone')} · ${_formatPhone(phone!)}',
              key: const ValueKey('driverCustomerEmergencyPhone'),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            _action(
              icon: Icons.phone_outlined,
              label: l10n.t('driver_contact_call'),
              onPressed: () => DriverTripContact.callPhone(phone!),
            ),
          ],
        ],
      ),
    );
  }
}
