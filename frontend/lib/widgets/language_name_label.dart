import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_fonts.dart';

/// Native-script language name for selectors and menus.
class LanguageNameLabel extends StatelessWidget {
  const LanguageNameLabel({
    super.key,
    required this.languageCode,
    this.style,
  });

  final String languageCode;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.languageNames[languageCode] ?? languageCode;
    final resolvedStyle = style ??
        AppFonts.languageLabel(context, languageCode: languageCode);

    return DefaultTextStyle(
      style: resolvedStyle,
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: resolvedStyle,
      ),
    );
  }
}
