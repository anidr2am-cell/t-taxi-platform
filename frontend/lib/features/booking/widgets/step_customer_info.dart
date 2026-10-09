import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_wizard_state.dart';
import 'wizard_compact.dart';
import 'booking_contact_preference_section.dart';

class StepCustomerInfo extends StatefulWidget {
  final BookingWizardState state;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String>? onMessengerTypeChanged;
  final ValueChanged<String>? onMessengerIdChanged;
  final ValueChanged<String> onAdditionalRequestsChanged;
  final Widget? loginPrompt;
  final bool embedded;
  final FocusNode? nameFocusNode;

  const StepCustomerInfo({
    super.key,
    required this.state,
    required this.onNameChanged,
    required this.onEmailChanged,
    required this.onPhoneChanged,
    required this.onCountryChanged,
    this.onMessengerTypeChanged,
    this.onMessengerIdChanged,
    required this.onAdditionalRequestsChanged,
    this.loginPrompt,
    this.embedded = false,
    this.nameFocusNode,
  });

  @override
  State<StepCustomerInfo> createState() => _StepCustomerInfoState();
}

class _StepCustomerInfoState extends State<StepCustomerInfo> {
  late final TextEditingController _nameController;
  late final TextEditingController _requestsController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.customerName);
    _requestsController = TextEditingController(
      text: widget.state.additionalRequests,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _requestsController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    AppLocalizations l10n,
    String label, {
    String? hint,
    bool required = false,
  }) {
    return WizardCompact.inputDecoration(
      label: label,
      hint: hint,
      required: required,
      requiredLabel: required ? l10n.t('field_required') : null,
    );
  }

  String _requiredSemanticsLabel(AppLocalizations l10n, String fieldKey) {
    return '${l10n.t('field_required')} ${l10n.t(fieldKey)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gap = widget.embedded ? WizardCompact.fieldGap : 12.0;
    final cardPadding = widget.embedded
        ? const EdgeInsets.all(WizardCompact.cardPadding)
        : const EdgeInsets.all(AppTokens.spaceMd);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          AppUi.sectionHeader(context, title: l10n.t('customer_info')),
          const SizedBox(height: 8),
        ],
        if (widget.embedded) SizedBox(height: WizardCompact.fieldGap),
        Semantics(
          label: _requiredSemanticsLabel(l10n, 'name'),
          textField: true,
          child: TextField(
            controller: _nameController,
            focusNode: widget.nameFocusNode,
            scrollPadding: WizardCompact.fieldScrollPadding,
            decoration: _fieldDecoration(l10n, l10n.t('name'), required: true),
            textInputAction: TextInputAction.next,
            onChanged: widget.onNameChanged,
          ),
        ),
        SizedBox(height: gap),
        AppUi.surfaceCard(
          padding: cardPadding,
          child: BookingContactPreferenceSection(
            state: widget.state,
            onTypeChanged: widget.onMessengerTypeChanged ?? (_) {},
            onMessengerIdChanged: widget.onMessengerIdChanged ?? (_) {},
            onPhoneChanged: widget.onPhoneChanged,
            onDialCodeChanged: widget.onCountryChanged,
            loginPrompt: widget.loginPrompt,
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _requestsController,
          scrollPadding: WizardCompact.fieldScrollPadding,
          decoration: _fieldDecoration(l10n, l10n.t('additional_requests')),
          maxLines: 3,
          onChanged: widget.onAdditionalRequestsChanged,
        ),
      ],
    );

    if (widget.embedded) return content;

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: content,
    );
  }
}
