import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import 'step_destination_select.dart';
import 'step_origin_select.dart';
import 'step_service_select.dart';
import 'step_flight_lookup.dart';
import '../models/service_type_option.dart';
import '../services/flight_lookup_api_service.dart';
import 'wizard_compact.dart';

class StepRouteSelect extends StatefulWidget {
  const StepRouteSelect({
    super.key,
    required this.state,
    required this.controller,
    required this.languageCode,
    this.originFocusNode,
    this.destinationFocusNode,
    this.flightLookupApi,
  });

  final BookingWizardState state;
  final BookingWizardController controller;
  final String languageCode;
  final FocusNode? originFocusNode;
  final FocusNode? destinationFocusNode;
  final FlightLookupApiService? flightLookupApi;

  @override
  State<StepRouteSelect> createState() => _StepRouteSelectState();
}

class _StepRouteSelectState extends State<StepRouteSelect> {
  int _originEditingResetToken = 0;

  bool get _canSwap =>
      widget.state.origin != null || widget.state.destination != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final controller = widget.controller;
    final samePlaceError = controller.isSameOriginDestination
        ? l10n.t('wizard_same_place_error')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(context, title: l10n.t('select_service')),
        StepServiceSelect(
          embedded: true,
          selected: state.serviceType,
          onSelected: controller.selectService,
        ),
        const SizedBox(height: WizardCompact.sectionGap),
        if (state.serviceType == BookingServiceType.airportPickup)
          StepFlightLookup(
            state: state,
            controller: controller,
            flightLookupApi: widget.flightLookupApi,
            onFlightConfirmed: () {
              setState(() => _originEditingResetToken++);
            },
          ),
        AppUi.sectionHeader(context, title: l10n.t('origin')),
        StepOriginSelect(
          embedded: true,
          serviceType: state.serviceType,
          selected: state.origin,
          excludedRecentLocation: state.destination,
          languageCode: widget.languageCode,
          focusNode: widget.originFocusNode,
          editingResetToken: _originEditingResetToken,
          onSearchFailed: (category) => controller.reportPlaceSearchFailed(
            placeType: 'origin',
            errorCategory: category,
          ),
          onSelected: controller.setOrigin,
        ),
        const SizedBox(height: WizardCompact.fieldGap),
        Align(
          alignment: Alignment.center,
          child: Semantics(
            button: true,
            label: l10n.t('wizard_swap_route'),
            child: ExcludeSemantics(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _canSwap ? controller.swapOriginDestination : null,
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: Text(l10n.t('wizard_swap_route')),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WizardCompact.fieldGap),
        AppUi.sectionHeader(context, title: l10n.t('destination')),
        StepDestinationSelect(
          embedded: true,
          serviceType: state.serviceType,
          selected: state.destination,
          excludedRecentLocation: state.origin,
          languageCode: widget.languageCode,
          focusNode: widget.destinationFocusNode,
          onSearchFailed: (category) => controller.reportPlaceSearchFailed(
            placeType: 'destination',
            errorCategory: category,
          ),
          onSelected: controller.setDestination,
        ),
        if (samePlaceError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              samePlaceError,
              style: const TextStyle(color: AppTokens.error, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }
}
