import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/pricing_result.dart';
import 'wizard_status_views.dart';

class StepVehicleSelect extends StatelessWidget {
  final BookingWizardState state;
  final BookingWizardController controller;

  const StepVehicleSelect({
    super.key,
    required this.state,
    required this.controller,
  });

  IconData _iconForVehicle(String vehicle) {
    if (vehicle.contains('Van') || vehicle.contains('VAN')) {
      return Icons.airport_shuttle_outlined;
    }
    if (vehicle.contains('SUV')) {
      return Icons.directions_car_filled_outlined;
    }
    return Icons.directions_car_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recommendation = state.recommendation;

    if (controller.isLoading) {
      return WizardLoadingView(message: context.l10n.t('calculating_price'));
    }

    if (state.errorMessage != null && state.pricing == null) {
      return WizardErrorView(
        message: state.errorMessage!,
        onRetry: () => controller.loadPricing(),
      );
    }

    if (recommendation == null) {
      return WizardEmptyView(message: l10n.t('complete_passengers_first'));
    }

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('select_vehicle'),
            subtitle: recommendation.multipleVehicles
                ? null
                : '${l10n.t('recommended')}: ${recommendation.recommendedVehicle}',
          ),
          ...BookingWizardController.vehicleTierOrder.map((vehicle) {
            final enabled = controller.isVehicleEnabled(vehicle);
            final selected = state.selectedVehicle == vehicle;
            final isRecommended = recommendation.recommendedVehicle == vehicle;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppUi.selectionTile(
                title: vehicle,
                subtitle: enabled
                    ? (isRecommended ? recommendation.message : null)
                    : l10n.t('vehicle_not_available'),
                icon: _iconForVehicle(vehicle),
                selected: selected,
                onTap: enabled ? () => controller.selectVehicle(vehicle) : null,
              ),
            );
          }),
          if (state.pricing != null) ...[
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.sectionHeader(context, title: l10n.t('pricing_summary')),
            _PricingBreakdown(pricing: state.pricing!, l10n: l10n),
          ],
        ],
      ),
    );
  }
}

class _PricingBreakdown extends StatelessWidget {
  final PricingResult pricing;
  final AppLocalizations l10n;

  const _PricingBreakdown({required this.pricing, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.summaryRow(
            label: l10n.t('base_price'),
            value: '${pricing.basePrice} ${pricing.currency}',
          ),
          for (final item in pricing.additionalCharges)
            AppUi.summaryRow(
              label: item.description,
              value: '${item.amount} ${pricing.currency}',
            ),
          const Divider(height: 24),
          AppUi.summaryRow(
            label: l10n.t('total'),
            value: '${pricing.totalAmount} ${pricing.currency}',
            emphasize: true,
          ),
        ],
      ),
    );
  }
}
