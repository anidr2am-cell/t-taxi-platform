import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/widgets/wizard_compact.dart';

class ProfileCompletionForm extends StatefulWidget {
  const ProfileCompletionForm({
    super.key,
    required this.initialName,
    required this.initialPhone,
    required this.onNameChanged,
    required this.onPhoneChanged,
    this.phoneError,
  });

  final String initialName;
  final String initialPhone;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final String? phoneError;

  @override
  State<ProfileCompletionForm> createState() => _ProfileCompletionFormState();
}

class _ProfileCompletionFormState extends State<ProfileCompletionForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void didUpdateWidget(covariant ProfileCompletionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialName != widget.initialName &&
        _nameController.text != widget.initialName) {
      _nameController.text = widget.initialName;
    }
    if (oldWidget.initialPhone != widget.initialPhone &&
        _phoneController.text != widget.initialPhone) {
      _phoneController.text = widget.initialPhone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    AppLocalizations l10n,
    String label, {
    String? errorText,
    bool required = false,
  }) {
    return WizardCompact.inputDecoration(
      label: label,
      required: required,
      requiredLabel: required ? l10n.t('field_required') : null,
    ).copyWith(errorText: errorText);
  }

  String _requiredSemanticsLabel(AppLocalizations l10n, String fieldKey) {
    return '${l10n.t('field_required')} ${l10n.t(fieldKey)}';
  }

  String _contactSectionTitle(AppLocalizations l10n) {
    switch (l10n.languageCode) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const gap = WizardCompact.fieldGap;
    const cardPadding = EdgeInsets.all(WizardCompact.cardPadding);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: _requiredSemanticsLabel(l10n, 'name'),
          textField: true,
          child: TextField(
            controller: _nameController,
            scrollPadding: WizardCompact.fieldScrollPadding,
            decoration: _fieldDecoration(l10n, l10n.t('name'), required: true),
            textInputAction: TextInputAction.next,
            onChanged: widget.onNameChanged,
          ),
        ),
        const SizedBox(height: gap),
        AppUi.sectionHeader(context, title: _contactSectionTitle(l10n)),
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
                  scrollPadding: WizardCompact.fieldScrollPadding,
                  decoration: _fieldDecoration(
                    l10n,
                    l10n.t('phone'),
                    required: true,
                    errorText: widget.phoneError,
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onChanged: widget.onPhoneChanged,
                ),
              ),
              const SizedBox(height: gap),
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
      ],
    );
  }
}
