import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';
import 'google_places_search_field.dart';

class StepDestinationSelect extends StatelessWidget {
  final BookingServiceType? serviceType;
  final LocationOption? selected;
  final LocationOption? excludedRecentLocation;
  final String languageCode;
  final ValueChanged<LocationOption> onSelected;
  final void Function(String errorCategory)? onSearchFailed;
  final bool embedded;
  final FocusNode? focusNode;
  final Object? editingResetToken;

  const StepDestinationSelect({
    super.key,
    required this.serviceType,
    required this.selected,
    this.excludedRecentLocation,
    required this.languageCode,
    required this.onSelected,
    this.onSearchFailed,
    this.embedded = false,
    this.focusNode,
    this.editingResetToken,
  });

  bool get _showAirportShortcuts =>
      serviceType == BookingServiceType.airportDropoff;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final content = GooglePlacesSearchField(
      label: l10n.t('search_place'),
      languageCode: languageCode,
      selected: selected,
      excludedRecentLocation: excludedRecentLocation,
      showAirportShortcuts: _showAirportShortcuts,
      airportShortcutsLabelKey: _showAirportShortcuts
          ? 'airport_shortcuts_destination'
          : null,
      compact: embedded,
      focusNode: focusNode,
      editingResetToken: editingResetToken,
      placeType: 'destination',
      onSearchFailed: onSearchFailed,
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
