import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/vehicle_recommendation.dart';
import 'wizard_compact.dart';
import 'name_sign_info_card.dart';
import 'wizard_status_views.dart';
import 'wizard_ui.dart';

class StepPassengersLuggage extends StatelessWidget {
  final BookingWizardState state;
  final BookingWizardController controller;
  final VoidCallback? onRetryRecommendation;
  final bool embedded;

  const StepPassengersLuggage({
    super.key,
    required this.state,
    required this.controller,
    this.onRetryRecommendation,
    this.embedded = false,
  });

  Widget _counter({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int min = 0,
    required bool compact,
  }) {
    if (compact) {
      return WizardUi.counterRow(
        label: label,
        value: value,
        min: min,
        onChanged: onChanged,
      );
    }
    return AppUi.counterRow(
      label: label,
      value: value,
      min: min,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gap = embedded ? WizardCompact.fieldGap : AppTokens.spaceMd;
    final cardPadding = embedded
        ? const EdgeInsets.symmetric(horizontal: WizardCompact.cardPadding, vertical: 4)
        : const EdgeInsets.all(AppTokens.spaceMd);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded) AppUi.sectionHeader(context, title: l10n.t('passengers')),
        AppUi.surfaceCard(
          padding: cardPadding,
          child: Column(
            children: [
              _counter(
                compact: embedded,
                label: l10n.t('adults'),
                value: state.adults,
                min: 1,
                onChanged: (v) => controller.updatePassengersAndLuggage(adults: v),
              ),
              _counter(
                compact: embedded,
                label: l10n.t('children'),
                value: state.children,
                onChanged: (v) => controller.updatePassengersAndLuggage(children: v),
              ),
              _counter(
                compact: embedded,
                label: l10n.t('infants'),
                value: state.infants,
                onChanged: (v) => controller.updatePassengersAndLuggage(infants: v),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        if (!embedded) AppUi.sectionHeader(context, title: l10n.t('luggage')),
        if (embedded)
          Text(l10n.t('luggage'), style: WizardCompact.hintTextStyle),
        if (embedded) const SizedBox(height: 4),
        AppUi.surfaceCard(
          padding: cardPadding,
          child: Column(
            children: [
              _counter(
                compact: embedded,
                label: l10n.t('small_carriers'),
                value: state.luggage20,
                onChanged: (v) => controller.updatePassengersAndLuggage(luggage20: v),
              ),
              _counter(
                compact: embedded,
                label: l10n.t('large_carriers'),
                value: state.luggage24,
                onChanged: (v) => controller.updatePassengersAndLuggage(luggage24: v),
              ),
              _counter(
                compact: embedded,
                label: l10n.t('golf_bags'),
                value: state.golfBags,
                onChanged: (v) => controller.updatePassengersAndLuggage(golfBags: v),
              ),
              _counter(
                compact: embedded,
                label: l10n.t('special_luggage'),
                value: state.specialLuggageCount,
                onChanged: (v) =>
                    controller.updatePassengersAndLuggage(specialLuggageCount: v),
              ),
            ],
          ),
        ),
        SizedBox(height: embedded ? WizardCompact.fieldGap : AppTokens.spaceSm),
        AppUi.surfaceCard(
          padding: cardPadding,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: embedded,
            title: Text(
              l10n.t('name_sign'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: embedded ? 14 : 16,
              ),
            ),
            value: state.nameSign,
            onChanged: (v) => controller.updatePassengersAndLuggage(nameSign: v),
          ),
        ),
        NameSignInfoCard(visible: state.nameSign),
        if (!embedded) ...[
          SizedBox(height: gap),
          if (controller.isLoading)
            WizardLoadingView(message: l10n.t('loading_recommendation'))
          else if (state.errorMessage != null)
            WizardErrorView(
              message: state.errorMessage!,
              onRetry: onRetryRecommendation,
            )
          else if (state.recommendation != null)
            _RecommendationCard(recommendation: state.recommendation!),
        ],
      ],
    );

    if (embedded) return content;

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: content,
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
