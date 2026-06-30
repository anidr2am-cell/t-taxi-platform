import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
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
      padding: AppUi.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(context, title: l10n.t('passengers')),
          AppUi.surfaceCard(
            child: Column(
              children: [
                AppUi.counterRow(
                  label: l10n.t('adults'),
                  value: state.adults,
                  min: 1,
                  onChanged: (v) => controller.updatePassengersAndLuggage(adults: v),
                ),
                AppUi.counterRow(
                  label: l10n.t('children'),
                  value: state.children,
                  onChanged: (v) => controller.updatePassengersAndLuggage(children: v),
                ),
                AppUi.counterRow(
                  label: l10n.t('infants'),
                  value: state.infants,
                  onChanged: (v) => controller.updatePassengersAndLuggage(infants: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.sectionHeader(context, title: l10n.t('luggage')),
          AppUi.surfaceCard(
            child: Column(
              children: [
                AppUi.counterRow(
                  label: l10n.t('small_carriers'),
                  value: state.luggage20,
                  onChanged: (v) => controller.updatePassengersAndLuggage(luggage20: v),
                ),
                AppUi.counterRow(
                  label: l10n.t('large_carriers'),
                  value: state.luggage24,
                  onChanged: (v) => controller.updatePassengersAndLuggage(luggage24: v),
                ),
                AppUi.counterRow(
                  label: l10n.t('golf_bags'),
                  value: state.golfBags,
                  onChanged: (v) => controller.updatePassengersAndLuggage(golfBags: v),
                ),
                AppUi.counterRow(
                  label: l10n.t('special_luggage'),
                  value: state.specialLuggageCount,
                  onChanged: (v) => controller.updatePassengersAndLuggage(specialLuggageCount: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          AppUi.surfaceCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.t('name_sign'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              value: state.nameSign,
              onChanged: (v) => controller.updatePassengersAndLuggage(nameSign: v),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          if (controller.isLoading)
            WizardLoadingView(message: context.l10n.t('loading_recommendation'))
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
      return AppUi.surfaceCard(
        backgroundColor: AppTokens.warningLight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.directions_car_filled_outlined, color: AppTokens.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('multiple_vehicles_required'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (recommendation.message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      recommendation.message,
                      style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.accentLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTokens.accent.withValues(alpha: 0.15),
              borderRadius: AppTokens.borderRadiusSm,
            ),
            child: const Icon(Icons.recommend_outlined, color: AppTokens.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('recommended'),
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recommendation.recommendedVehicle ?? '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppTokens.textPrimary,
                  ),
                ),
                if (recommendation.message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    recommendation.message,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
