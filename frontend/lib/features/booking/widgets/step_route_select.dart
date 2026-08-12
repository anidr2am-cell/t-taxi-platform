import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import 'step_destination_select.dart';
import 'step_origin_select.dart';
import 'step_service_select.dart';
import 'wizard_compact.dart';

class StepRouteSelect extends StatelessWidget {
  const StepRouteSelect({
    super.key,
    required this.state,
    required this.controller,
    required this.languageCode,
    this.originFocusNode,
    this.destinationFocusNode,
  });

  final BookingWizardState state;
  final BookingWizardController controller;
  final String languageCode;
  final FocusNode? originFocusNode;
  final FocusNode? destinationFocusNode;

  bool get _canSwap => state.origin != null || state.destination != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final samePlaceError = controller.isSameOriginDestination
        ? l10n.t('wizard_same_place_error')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('select_service'),
        ),
        StepServiceSelect(
          embedded: true,
          selected: state.serviceType,
          onSelected: controller.selectService,
        ),
        const SizedBox(height: WizardCompact.sectionGap),
        AppUi.sectionHeader(
          context,
          title: l10n.t('origin'),
        ),
        StepOriginSelect(
          embedded: true,
          serviceType: state.serviceType,
          selected: state.origin,
          languageCode: languageCode,
          focusNode: originFocusNode,
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
        AppUi.sectionHeader(
          context,
          title: l10n.t('destination'),
        ),
        StepDestinationSelect(
          embedded: true,
          serviceType: state.serviceType,
          selected: state.destination,
          languageCode: languageCode,
          focusNode: destinationFocusNode,
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
