import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
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
  static const _messengerTypeOptions = <String>[
    'LINE',
    'WhatsApp',
    'KAKAO TALK',
    'WeChat',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _messengerIdController;
  late final TextEditingController _requestsController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.customerName);
    _phoneController = TextEditingController(text: widget.state.customerPhone);
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
    _phoneController.dispose();
    _messengerIdController.dispose();
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

  String? _selectedMessengerTypeValue() {
    final normalized = widget.state.messengerType.trim();
    if (normalized.isEmpty) return null;
    return _messengerTypeOptions.contains(normalized) ? normalized : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final copy = _CustomerContactCopy(l10n.languageCode);
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
            decoration: _fieldDecoration(l10n, l10n.t('name'), required: true),
            textInputAction: TextInputAction.next,
            onChanged: widget.onNameChanged,
          ),
        ),
        SizedBox(height: gap),
        AppUi.sectionHeader(context, title: copy.sectionTitle),
        const SizedBox(height: 8),
        AppUi.surfaceCard(
          padding: cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: _requiredSemanticsLabel(l10n, 'phone'),
                textField: true,
                child: TextField(
                  controller: _phoneController,
                  decoration: _fieldDecoration(
                    l10n,
                    l10n.t('phone'),
                    required: true,
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: widget.onPhoneChanged,
                ),
              ),
              SizedBox(height: gap),
              Text(
                copy.messengerPairHint,
                style: WizardCompact.hintTextStyle,
              ),
              const SizedBox(height: 6),
              Semantics(
                label: _requiredSemanticsLabel(l10n, 'messenger_type'),
                child: DropdownButtonFormField<String>(
                  value: _selectedMessengerTypeValue(),
                  isExpanded: true,
                  decoration: _fieldDecoration(
                    l10n,
                    l10n.t('messenger_type'),
                    required: true,
                  ),
                  hint: Text(
                    l10n.t('messenger_type'),
                    style: WizardCompact.hintTextStyle,
                  ),
                  items: _messengerTypeOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      widget.onMessengerTypeChanged(value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 6),
              Semantics(
                label: _requiredSemanticsLabel(l10n, 'messenger_id'),
                textField: true,
                child: TextField(
                  controller: _messengerIdController,
                  decoration: _fieldDecoration(
                    l10n,
                    l10n.t('messenger_id'),
                    required: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: widget.onMessengerIdChanged,
                ),
              ),
              SizedBox(height: gap),
              Container(
                padding: cardPadding,
                decoration: BoxDecoration(
                  color: AppTokens.warningLight,
                  borderRadius: AppTokens.borderRadiusMd,
                  border: Border.all(color: AppTokens.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppTokens.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.t('customer_contact_sns_notice'),
                        style: const TextStyle(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

class _CustomerContactCopy {
  _CustomerContactCopy(this.languageCode);

  final String languageCode;

  String get sectionTitle {
    switch (languageCode) {
      case 'ko':
        return '연락처';
      case 'zh':
        return '联系方式';
      case 'ja':
        return '連絡先';
      case 'th':
        return 'ช่องทางติดต่อ';
      default:
        return 'Contact';
    }
  }

  String get messengerPairHint {
    switch (languageCode) {
      case 'ko':
        return '메신저 종류와 아이디를 함께 입력해 주세요.';
      case 'zh':
        return '请同时填写 messenger 类型和 ID。';
      case 'ja':
        return 'メッセンジャーの種類と ID を両方入力してください。';
      case 'th':
        return 'กรุณากรอกประเภทและ ID ของ Messenger ให้ครบคู่กัน';
      default:
        return 'Please enter both messenger type and ID.';
    }
  }
}
