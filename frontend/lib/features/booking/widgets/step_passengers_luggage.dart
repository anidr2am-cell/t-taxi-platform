import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common_widgets.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/vehicle_recommendation.dart';
import 'wizard_status_views.dart';

class StepPassengersLuggage extends StatelessWidget {
  final BookingWizardState state;
  final BookingWizardController controller;
  final VoidCallback? onRetryRecommendation;

  const StepPassengersLuggage({
    super.key,
    required this.state,
    required this.controller,
    this.onRetryRecommendation,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('passengers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          CounterRow(
            label: l10n.t('adults'),
            value: state.adults,
            min: 1,
            onChanged: (v) => controller.updatePassengersAndLuggage(adults: v),
          ),
          CounterRow(
            label: l10n.t('children'),
            value: state.children,
            onChanged: (v) => controller.updatePassengersAndLuggage(children: v),
          ),
          CounterRow(
            label: l10n.t('infants'),
            value: state.infants,
            onChanged: (v) => controller.updatePassengersAndLuggage(infants: v),
          ),
          const SizedBox(height: 16),
          Text(l10n.t('luggage'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          CounterRow(
            label: l10n.t('small_carriers'),
            value: state.luggage20,
            onChanged: (v) => controller.updatePassengersAndLuggage(luggage20: v),
          ),
          CounterRow(
            label: l10n.t('large_carriers'),
            value: state.luggage24,
            onChanged: (v) => controller.updatePassengersAndLuggage(luggage24: v),
          ),
          CounterRow(
            label: l10n.t('golf_bags'),
            value: state.golfBags,
            onChanged: (v) => controller.updatePassengersAndLuggage(golfBags: v),
          ),
          CounterRow(
            label: l10n.t('special_luggage'),
            value: state.specialLuggageCount,
            onChanged: (v) => controller.updatePassengersAndLuggage(specialLuggageCount: v),
          ),
          SwitchListTile(
            title: Text(l10n.t('name_sign')),
            value: state.nameSign,
            onChanged: (v) => controller.updatePassengersAndLuggage(nameSign: v),
          ),
          const SizedBox(height: 16),
          if (controller.isLoading)
            const WizardLoadingView(message: 'Loading recommendation...')
          else if (state.errorMessage != null)
            WizardErrorView(
              message: state.errorMessage!,
              onRetry: onRetryRecommendation,
            )
          else if (state.recommendation != null)
            _RecommendationCard(recommendation: state.recommendation!),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final VehicleRecommendation recommendation;

  const _RecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (recommendation.multipleVehicles) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('multiple_vehicles_required'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(recommendation.message),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.t('recommended')}: ${recommendation.recommendedVehicle}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (recommendation.message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(recommendation.message),
              ),
          ],
        ),
      ),
    );
  }
}
