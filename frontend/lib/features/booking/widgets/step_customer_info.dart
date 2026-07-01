import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_wizard_state.dart';
import 'wizard_compact.dart';

class StepCustomerInfo extends StatefulWidget {
  final BookingWizardState state;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onMessengerTypeChanged;
  final ValueChanged<String> onMessengerIdChanged;
  final ValueChanged<String> onAdditionalRequestsChanged;
  final bool embedded;
  final FocusNode? nameFocusNode;

  const StepCustomerInfo({
    super.key,
    required this.state,
    required this.onNameChanged,
    required this.onEmailChanged,
    required this.onPhoneChanged,
    required this.onCountryChanged,
    required this.onMessengerTypeChanged,
    required this.onMessengerIdChanged,
    required this.onAdditionalRequestsChanged,
    this.embedded = false,
    this.nameFocusNode,
  });

  @override
  State<StepCustomerInfo> createState() => _StepCustomerInfoState();
}

class _StepCustomerInfoState extends State<StepCustomerInfo> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _countryController;
  late final TextEditingController _messengerTypeController;
  late final TextEditingController _messengerIdController;
  late final TextEditingController _requestsController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.customerName);
    _emailController = TextEditingController(text: widget.state.customerEmail);
    _phoneController = TextEditingController(text: widget.state.customerPhone);
    _countryController = TextEditingController(text: widget.state.customerCountryCode);
    _messengerTypeController = TextEditingController(text: widget.state.messengerType);
    _messengerIdController = TextEditingController(text: widget.state.messengerId);
    _requestsController = TextEditingController(text: widget.state.additionalRequests);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _messengerTypeController.dispose();
    _messengerIdController.dispose();
    _requestsController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    if (widget.embedded) {
      return WizardCompact.inputDecoration(label: label, hint: hint);
    }
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gap = widget.embedded ? WizardCompact.fieldGap : 12.0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          AppUi.sectionHeader(context, title: l10n.t('customer_info')),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _nameController,
          focusNode: widget.nameFocusNode,
          decoration: _fieldDecoration(l10n.t('name')),
          textInputAction: TextInputAction.next,
          onChanged: widget.onNameChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _emailController,
          decoration: _fieldDecoration(l10n.t('email')),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: widget.onEmailChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _phoneController,
          decoration: _fieldDecoration(l10n.t('phone')),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onChanged: widget.onPhoneChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _countryController,
          decoration: _fieldDecoration(
            l10n.t('country'),
            hint: l10n.t('country_code_hint'),
          ),
          textInputAction: TextInputAction.next,
          onChanged: widget.onCountryChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _messengerTypeController,
          decoration: _fieldDecoration(
            l10n.t('messenger_type'),
            hint: l10n.t('messenger_type_hint'),
          ),
          textInputAction: TextInputAction.next,
          onChanged: widget.onMessengerTypeChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _messengerIdController,
          decoration: _fieldDecoration(l10n.t('messenger_id')),
          textInputAction: TextInputAction.next,
          onChanged: widget.onMessengerIdChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _requestsController,
          decoration: _fieldDecoration(l10n.t('additional_requests')),
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
