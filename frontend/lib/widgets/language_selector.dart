import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../providers/booking_provider.dart';
import 'package:provider/provider.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleState>();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.language, color: Colors.white),
      onSelected: (code) => context.read<LocaleState>().setLanguage(code),
      itemBuilder: (context) => AppLocalizations.supportedLanguages
          .map((code) => PopupMenuItem(
                value: code,
                child: Row(
                  children: [
                    if (locale.languageCode == code)
                      const Icon(Icons.check, size: 18, color: Colors.green),
                    if (locale.languageCode == code) const SizedBox(width: 8),
                    Text(AppLocalizations.languageNames[code] ?? code),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
