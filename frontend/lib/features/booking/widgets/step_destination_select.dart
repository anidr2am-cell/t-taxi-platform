import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';
import 'google_places_search_field.dart';

class StepDestinationSelect extends StatelessWidget {
  final BookingServiceType? serviceType;
  final LocationOption? selected;
  final String languageCode;
  final ValueChanged<LocationOption> onSelected;
  final bool embedded;
  final FocusNode? focusNode;

  const StepDestinationSelect({
    super.key,
    required this.serviceType,
    required this.selected,
    required this.languageCode,
    required this.onSelected,
    this.embedded = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final content = GooglePlacesSearchField(
      label: l10n.t('search_place'),
      languageCode: languageCode,
      selected: selected,
      compact: embedded,
      focusNode: focusNode,
      onSelected: onSelected,
    );

    if (embedded) return content;

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('destination'),
            subtitle: l10n.t('search_place'),
          ),
          content,
        ],
      ),
    );
  }
}
