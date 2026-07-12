import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_wizard_state.dart';
import '../models/country_option.dart';
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
  late final FocusNode _countryFocusNode;
  bool _localizedInitialCountry = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.customerName);
    _emailController = TextEditingController(text: widget.state.customerEmail);
    _phoneController = TextEditingController(text: widget.state.customerPhone);
    _countryController = TextEditingController(
      text: widget.state.customerCountryCode,
    );
    _countryFocusNode = FocusNode();
    _messengerTypeController = TextEditingController(
      text: widget.state.messengerType,
    );
    _messengerIdController = TextEditingController(
      text: widget.state.messengerId,
    );
    _requestsController = TextEditingController(
      text: widget.state.additionalRequests,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _countryFocusNode.dispose();
    _messengerTypeController.dispose();
    _messengerIdController.dispose();
    _requestsController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localizedInitialCountry) return;
    _localizedInitialCountry = true;
    final country = CountryCatalog.byCode(widget.state.customerCountryCode);
    if (country != null) {
      _countryController.text = country.localizedName(
        context.l10n.languageCode,
      );
    }
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

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          AppUi.sectionHeader(context, title: l10n.t('customer_info')),
          const SizedBox(height: 8),
        ],
        Semantics(
          label: _requiredSemanticsLabel(l10n, 'name'),
          textField: true,
          child: TextField(
            controller: _nameController,
            focusNode: widget.nameFocusNode,
            decoration: _fieldDecoration(l10n, l10n.t('name'), required: true),
            textInputAction: TextInputAction.next,
            onChanged: widget.onNameChanged,
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _emailController,
          decoration: _fieldDecoration(l10n, l10n.t('email')),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: widget.onEmailChanged,
        ),
        SizedBox(height: gap),
        Semantics(
          label: _requiredSemanticsLabel(l10n, 'phone'),
          textField: true,
          child: TextField(
            controller: _phoneController,
            decoration: _fieldDecoration(l10n, l10n.t('phone'), required: true),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onChanged: widget.onPhoneChanged,
          ),
        ),
        SizedBox(height: gap),
        Semantics(
          label: l10n.t('country'),
          textField: true,
          child: RawAutocomplete<CountryOption>(
            textEditingController: _countryController,
            focusNode: _countryFocusNode,
            displayStringForOption: (option) =>
                option.localizedName(l10n.languageCode),
            optionsBuilder: (value) => CountryCatalog.search(value.text),
            onSelected: (option) {
              _countryController.text = option.localizedName(l10n.languageCode);
              widget.onCountryChanged(option.code);
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: _fieldDecoration(
                  l10n,
                  l10n.t('country'),
                  hint: l10n.t('country_search_hint'),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => onSubmitted(),
                onChanged: widget.onCountryChanged,
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final items = options.toList(growable: false);
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 520,
                      maxHeight: 280,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final option = items[index];
                        return ListTile(
                          key: ValueKey('country_option_${option.code}'),
                          title: Text(option.localizedName(l10n.languageCode)),
                          trailing: Text(option.code),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _messengerTypeController,
          decoration: _fieldDecoration(
            l10n,
            l10n.t('messenger_type'),
            hint: l10n.t('messenger_type_hint'),
          ),
          textInputAction: TextInputAction.next,
          onChanged: widget.onMessengerTypeChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _messengerIdController,
          decoration: _fieldDecoration(l10n, l10n.t('messenger_id')),
          textInputAction: TextInputAction.next,
          onChanged: widget.onMessengerIdChanged,
        ),
        SizedBox(height: gap),
        TextField(
          controller: _requestsController,
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
