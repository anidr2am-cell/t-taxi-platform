import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/pricing_result.dart';
import '../utils/pricing_display.dart';
import 'wizard_compact.dart';
import 'wizard_status_views.dart';
import 'wizard_ui.dart';

class StepVehicleSelect extends StatelessWidget {
  final BookingWizardState state;
  final BookingWizardController controller;
  final bool embedded;

  const StepVehicleSelect({
    super.key,
    required this.state,
    required this.controller,
    this.embedded = false,
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

    if (!controller.canLoadRecommendation()) {
      return const SizedBox.shrink();
    }

    if (controller.isLoading && recommendation == null) {
      return WizardLoadingView(message: l10n.t('loading_recommendation'));
    }

    if (state.errorMessage != null &&
        recommendation == null &&
        !controller.isLoading) {
      return WizardErrorView(
        message: state.errorMessage!,
        onRetry: controller.loadRecommendation,
      );
    }

    if (recommendation == null) {
      return const SizedBox.shrink();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded && !recommendation.multipleVehicles)
          AppUi.sectionHeader(
            context,
            title: l10n.t('select_vehicle'),
            subtitle: '${l10n.t('recommended')}: ${recommendation.recommendedVehicle}',
          ),
        if (embedded && !recommendation.multipleVehicles)
          Padding(
            padding: const EdgeInsets.only(bottom: WizardCompact.fieldGap),
            child: Text(
              '${l10n.t('recommended')}: ${recommendation.recommendedVehicle}',
              style: WizardCompact.hintTextStyle,
            ),
          ),
        ...BookingWizardController.customerVehicleTierOrder.map((vehicle) {
          final enabled = controller.isVehicleEnabled(vehicle);
          final selected = state.selectedVehicle == vehicle;
          final isRecommended = recommendation.recommendedVehicle == vehicle;
          return Padding(
            padding: EdgeInsets.only(bottom: embedded ? WizardCompact.fieldGap : 10),
            child: embedded
                ? WizardUi.selectionTile(
                    title: vehicle,
                    subtitle: enabled
                        ? (isRecommended ? recommendation.message : null)
                        : l10n.t('vehicle_not_available'),
                    icon: _iconForVehicle(vehicle),
                    selected: selected,
                    onTap: enabled ? () => controller.selectVehicle(vehicle) : null,
                  )
                : AppUi.selectionTile(
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
        if (state.selectedVehicle == null)
          WizardUi.infoHint(l10n.t('wizard_pricing_after_vehicle'))
        else if (controller.isLoading && state.pricing == null)
          Padding(
            padding: const EdgeInsets.only(top: WizardCompact.fieldGap),
            child: WizardLoadingView(message: l10n.t('calculating_price')),
          )
        else if (state.errorMessage != null && state.pricing == null)
          Padding(
            padding: const EdgeInsets.only(top: WizardCompact.fieldGap),
            child: WizardErrorView(
              message: state.errorMessage!,
              onRetry: controller.loadPricing,
            ),
          )
        else if (state.pricing != null) ...[
          const SizedBox(height: WizardCompact.fieldGap),
          if (!embedded)
            AppUi.sectionHeader(context, title: l10n.t('pricing_summary')),
          _PricingBreakdown(pricing: state.pricing!, l10n: l10n, compact: embedded),
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

class _PricingBreakdown extends StatelessWidget {
  final PricingResult pricing;
  final AppLocalizations l10n;
  final bool compact;

  const _PricingBreakdown({
    required this.pricing,
    required this.l10n,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      padding: compact
          ? const EdgeInsets.all(WizardCompact.cardPadding)
          : const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.summaryRow(
            label: l10n.t('base_price'),
            value: '${pricing.basePrice} ${pricing.currency}',
          ),
          for (final item in pricing.additionalCharges)
            AppUi.summaryRow(
              label: PricingDisplay.chargeItemLabel(l10n, item),
              value: '${item.amount} ${pricing.currency}',
            ),
          Divider(height: compact ? 16 : 24),
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
