import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/admin_calling_codes.dart';

Future<AdminCallingCountry?> showAdminCallingCountryPicker(
  BuildContext context, {
  required String selectedCountryCode,
}) => showDialog<AdminCallingCountry>(
  context: context,
  builder: (_) => _CountryDialog(selectedCountryCode: selectedCountryCode),
);

class _CountryDialog extends StatefulWidget {
  const _CountryDialog({required this.selectedCountryCode});
  final String selectedCountryCode;

  @override
  State<_CountryDialog> createState() => _CountryDialogState();
}

class _CountryDialogState extends State<_CountryDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final countries =
        adminCallingCountries.where((c) => c.matches(_query)).toList()..sort(
          (a, b) =>
              a.name(l10n.languageCode).compareTo(b.name(l10n.languageCode)),
        );
    return AlertDialog(
      title: Text(l10n.t('admin_phone_country_title')),
      content: SizedBox(
        width: AppTokens.maxContentWidth,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            TextField(
              key: const Key('adminCallingCountrySearch'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.t('admin_phone_country_search'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Expanded(
              child: countries.isEmpty
                  ? Center(child: Text(l10n.t('admin_phone_country_empty')))
                  : ListView.builder(
                      itemCount: countries.length,
                      itemBuilder: (_, index) {
                        final country = countries[index];
                        return ListTile(
                          key: ValueKey('adminCallingCountry-${country.code}'),
                          selected: country.code == widget.selectedCountryCode,
                          title: Text(country.name(l10n.languageCode)),
                          subtitle: Text(
                            '${country.names['en']} · ${country.code}',
                          ),
                          trailing: Text(country.dialCode),
                          onTap: () => Navigator.of(context).pop(country),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('admin_phone_country_cancel')),
        ),
      ],
    );
  }
}
