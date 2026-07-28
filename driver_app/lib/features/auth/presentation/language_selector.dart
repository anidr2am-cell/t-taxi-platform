import 'package:flutter/material.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../l10n/app_localizations.dart';

/// Compact language toggle for the app bar (top-right).
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    required this.controller,
    this.compact = true,
  });

  final LocaleController controller;
  final bool compact;

  static const _korean = Locale('ko');
  static const _thai = Locale('th');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isKorean = controller.locale.languageCode == 'ko';

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton(
          key: const Key('languageSelectorToggle'),
          onPressed: () => controller.setLocale(isKorean ? _thai : _korean),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            isKorean ? l10n.languageThai : l10n.languageKorean,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return PopupMenuButton<Locale>(
      key: const Key('languageSelectorMenu'),
      tooltip: l10n.selectLanguage,
      initialValue: controller.locale,
      onSelected: controller.setLocale,
      itemBuilder: (context) => [
        CheckedPopupMenuItem<Locale>(
          value: _korean,
          checked: isKorean,
          child: Text(l10n.languageKorean),
        ),
        CheckedPopupMenuItem<Locale>(
          value: _thai,
          checked: !isKorean,
          child: Text(l10n.languageThai),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 20),
            const SizedBox(width: 4),
            Text(isKorean ? l10n.languageKorean : l10n.languageThai),
          ],
        ),
      ),
    );
  }
}
