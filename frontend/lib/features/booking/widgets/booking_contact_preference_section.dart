import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_wizard_state.dart';
import '../utils/booking_contact_preference.dart';

class BookingContactPreferenceSection extends StatefulWidget {
  const BookingContactPreferenceSection({
    super.key,
    required this.state,
    required this.onTypeChanged,
    required this.onMessengerIdChanged,
    required this.onPhoneChanged,
    required this.onDialCodeChanged,
    this.loginPrompt,
  });

  final BookingWizardState state;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onMessengerIdChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onDialCodeChanged;
  final Widget? loginPrompt;

  @override
  State<BookingContactPreferenceSection> createState() =>
      _BookingContactPreferenceSectionState();
}

class _BookingContactPreferenceSectionState
    extends State<BookingContactPreferenceSection> {
  late final TextEditingController _idController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(text: widget.state.messengerId);
    _phoneController = TextEditingController(text: widget.state.customerPhone);
  }

  @override
  void didUpdateWidget(BookingContactPreferenceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_idController.text != widget.state.messengerId) {
      _idController.text = widget.state.messengerId;
    }
    if (_phoneController.text != widget.state.customerPhone) {
      _phoneController.text = widget.state.customerPhone;
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _label(AppLocalizations l10n, String type) => switch (type) {
    BookingContactPreference.kakao => l10n.t('booking_contact_kakao'),
    BookingContactPreference.line => l10n.t('booking_contact_line'),
    BookingContactPreference.whatsapp => l10n.t('booking_contact_whatsapp'),
    _ => l10n.t('booking_contact_phone_sms'),
  };

  IconData _icon(String type) => switch (type) {
    BookingContactPreference.sms => Icons.phone_outlined,
    _ => Icons.chat_bubble_outline,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final savedType = BookingContactPreference.normalize(
      widget.state.messengerType,
    );
    final type = savedType.isEmpty
        ? BookingContactPreference.defaultFor(languageCode: l10n.languageCode)
        : savedType;
    final isPhone = BookingContactPreference.usesPhone(type);
    final emergencyPhone = BookingContactPreference.allowsEmergencyPhone(type);
    final dialCode = widget.state.customerCountryCode.trim().isEmpty
        ? BookingContactPreference.defaultDialCode(l10n.languageCode)
        : widget.state.customerCountryCode.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('booking_contact_method_title'),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Text(
          l10n.t('booking_contact_method_description'),
          style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          mainAxisSpacing: AppTokens.spaceSm,
          crossAxisSpacing: AppTokens.spaceSm,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final value in BookingContactPreference.values)
              InkWell(
                key: ValueKey('booking-contact-$value'),
                borderRadius: AppTokens.borderRadiusMd,
                onTap: () => widget.onTypeChanged(value),
                child: Container(
                  decoration: BoxDecoration(
                    color: type == value
                        ? AppTokens.primaryLight
                        : AppTokens.surface,
                    borderRadius: AppTokens.borderRadiusMd,
                    border: Border.all(
                      color: type == value
                          ? AppTokens.primary
                          : AppTokens.border,
                      width: type == value ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_icon(value), color: AppTokens.primary, size: 20),
                      const SizedBox(width: AppTokens.spaceXs),
                      Flexible(
                        child: Text(
                          _label(l10n, value),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        if (!isPhone)
          TextField(
            key: const ValueKey('booking-messenger-id'),
            controller: _idController,
            decoration: InputDecoration(
              labelText:
                  '${l10n.t('field_required')} ${type == BookingContactPreference.kakao ? l10n.t('booking_contact_kakao_id') : l10n.t('booking_contact_line_id')}',
              helperText: l10n.t('booking_contact_id_searchable_notice'),
            ),
            onChanged: widget.onMessengerIdChanged,
          ),
        if (isPhone || emergencyPhone) ...[
          if (!isPhone) const SizedBox(height: AppTokens.spaceMd),
          Text(
            isPhone
                ? l10n.t('booking_contact_phone_required')
                : l10n.t('booking_contact_emergency_phone_optional'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 105,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('booking-phone-dial-code'),
                  initialValue:
                      const ['+66', '+82', '+81', '+86'].contains(dialCode)
                      ? dialCode
                      : '+66',
                  items: const ['+66', '+82', '+81', '+86']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) widget.onDialCodeChanged(value);
                  },
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: TextField(
                  key: const ValueKey('booking-contact-phone'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isPhone
                        ? '${l10n.t('field_required')} ${l10n.t('phone')}'
                        : l10n.t('phone'),
                    hintText: l10n.t('booking_contact_phone_hint'),
                  ),
                  onChanged: widget.onPhoneChanged,
                ),
              ),
            ],
          ),
        ],
        if (widget.loginPrompt != null && emergencyPhone) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            type == BookingContactPreference.kakao
                ? l10n.t('booking_contact_kakao_login_hint')
                : l10n.t('booking_contact_line_login_hint'),
            style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
          ),
          widget.loginPrompt!,
        ],
      ],
    );
  }
}
