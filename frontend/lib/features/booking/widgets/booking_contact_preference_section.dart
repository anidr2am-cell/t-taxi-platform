import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import 'booking_messenger_icon.dart';
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

  String _label(AppLocalizations l10n, String type) =>
      l10n.t(BookingContactPreference.labelKey(type));

  Widget _icon(String type) => bookingMessengerIcon(type);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final savedType = BookingContactPreference.normalize(
      widget.state.messengerType,
    );
    final type = !BookingContactPreference.values.contains(savedType)
        ? BookingContactPreference.defaultFor(languageCode: l10n.languageCode)
        : savedType;
    final isPhone = BookingContactPreference.usesPhone(type);
    final isKakao = type == BookingContactPreference.kakao;
    final emergencyPhone = BookingContactPreference.allowsEmergencyPhone(type);
    final showsPhone =
        BookingContactPreference.requiresPhone(type) || emergencyPhone;
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
        DropdownButtonFormField<String>(
          key: ValueKey('booking-messenger-select-$type'),
          initialValue: type,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.t('booking_contact_method_title'),
          ),
          items: [
            for (final value in BookingContactPreference.values)
              DropdownMenuItem(
                value: value,
                child: Row(
                  children: [
                    _icon(value),
                    const SizedBox(width: AppTokens.spaceSm),
                    Flexible(child: Text(_label(l10n, value))),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) widget.onTypeChanged(value);
          },
        ),
        const SizedBox(height: AppTokens.spaceMd),
        if (showsPhone) ...[
          Text(
            isKakao
                ? l10n.t('booking_contact_kakao_phone_required')
                : (isPhone || BookingContactPreference.requiresPhone(type))
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
                      const ['+66', '+82', '+81', '+86', '+7'].contains(dialCode)
                      ? dialCode
                      : '+66',
                  items: const ['+66', '+82', '+81', '+86', '+7']
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
                    labelText: BookingContactPreference.requiresPhone(type)
                        ? '${l10n.t('field_required')} ${l10n.t('phone')}'
                        : l10n.t('phone'),
                    hintText: l10n.t('booking_contact_phone_hint'),
                    helperText: isKakao
                        ? l10n.t('booking_contact_kakao_phone_help')
                        : type == BookingContactPreference.line
                        ? l10n.t('contact_phone_required_help')
                        : null,
                    helperMaxLines: 4,
                  ),
                  onChanged: widget.onPhoneChanged,
                ),
              ),
            ],
          ),
        ],
        if (!isPhone) ...[
          if (showsPhone) const SizedBox(height: AppTokens.spaceMd),
          TextField(
            key: const ValueKey('booking-messenger-id'),
            controller: _idController,
            decoration: InputDecoration(
              labelText: isKakao
                  ? l10n.t('booking_contact_kakao_id_optional')
                  : type == BookingContactPreference.line
                  ? '${l10n.t('field_required')} ${l10n.t('booking_contact_line_id')}'
                  : l10n
                        .t('booking_contact_optional_id')
                        .replaceAll('{channel}', _label(l10n, type)),
              helperText: type == BookingContactPreference.line
                  ? l10n.t('booking_contact_id_searchable_notice')
                  : null,
            ),
            onChanged: widget.onMessengerIdChanged,
          ),
        ],
        if (widget.loginPrompt != null && (isKakao || emergencyPhone)) ...[
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
