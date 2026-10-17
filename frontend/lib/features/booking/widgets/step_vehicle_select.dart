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
import 'fare_inquiry_card.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
      if (controller.isLoading) {
        return WizardLoadingView(message: l10n.t('loading_recommendation'));
      }
      return const SizedBox.shrink();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded && !recommendation.multipleVehicles)
          AppUi.sectionHeader(
            context,
            title: l10n.t('select_vehicle'),
            subtitle:
                '${l10n.t('recommended')}: ${l10n.t('cx_vehicle_${recommendation.recommendedVehicle}')}',
          ),
        if (embedded && !recommendation.multipleVehicles)
          Padding(
            padding: const EdgeInsets.only(bottom: WizardCompact.fieldGap),
            child: Text(
              '${l10n.t('recommended')}: ${l10n.t('cx_vehicle_${recommendation.recommendedVehicle}')}',
              style: WizardCompact.hintTextStyle,
            ),
          ),
        AppUi.surfaceCard(
          backgroundColor: AppTokens.infoLight,
          padding: const EdgeInsets.all(WizardCompact.cardPadding),
          child: Text(
            l10n.t('customer_vehicle_guidance'),
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: WizardCompact.fieldGap),
        ...BookingWizardController.customerVehicleTierOrder.map((vehicle) {
          final enabled = controller.isVehicleEnabled(vehicle);
          final selected = state.selectedVehicle == vehicle;
          final price = controller.vehiclePrices[vehicle];
          final error = controller.vehiclePriceErrors[vehicle];
          final rules = recommendation.capacityRules.where(
            (r) => r['vehicleCode'] == vehicle,
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            child: Material(
              color: enabled
                  ? (selected ? AppTokens.primaryLight : AppTokens.surface)
                  : AppTokens.surfaceMuted,
              shape: RoundedRectangleBorder(
                borderRadius: AppTokens.borderRadiusMd,
                side: BorderSide(
                  color: selected ? AppTokens.primary : AppTokens.border,
                ),
              ),
              child: InkWell(
                borderRadius: AppTokens.borderRadiusMd,
                onTap: enabled ? () => controller.selectVehicle(vehicle) : null,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CustomerVehicleArtwork(vehicle: vehicle),
                          const SizedBox(width: AppTokens.spaceSm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.t('cx_vehicle_$vehicle'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (recommendation.recommendedVehicle ==
                                    vehicle)
                                  Text(
                                    l10n.t('recommended'),
                                    style: const TextStyle(
                                      color: AppTokens.primary,
                                    ),
                                  ),
                                Text(
                                  price != null
                                      ? '${price.totalAmount} ${price.currency}'
                                      : error == 'pricing_inquiry_required'
                                      ? l10n.t('pricing_inquiry_required')
                                      : controller.isLoading
                                      ? l10n.t('calculating_price')
                                      : l10n.t('cx_vehicle_error'),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle,
                              color: AppTokens.primary,
                            ),
                        ],
                      ),
                      for (final r in rules)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppTokens.spaceSm,
                          ),
                          child: Text(
                            l10n
                                .t('cx_capacity')
                                .replaceAll('{p}', '${r['passengers']}')
                                .replaceAll('{s}', '${r['luggage20']}')
                                .replaceAll('{l}', '${r['luggage24']}')
                                .replaceAll('{g}', '${r['golfBags']}'),
                          ),
                        ),
                      if (!enabled)
                        Text(
                          l10n.t('customer_vehicle_not_suitable'),
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        Text(
          l10n.t('cx_capacity_note'),
          style: const TextStyle(color: AppTokens.textSecondary),
        ),
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
            child: state.errorMessage == 'pricing_inquiry_required'
                ? (embedded ? const SizedBox.shrink() : const FareInquiryCard())
                : WizardErrorView(
                    message: state.errorMessage!,
                    onRetry: controller.loadPricing,
                  ),
          )
        else if (state.pricing != null) ...[
          const SizedBox(height: WizardCompact.fieldGap),
          if (!embedded)
            AppUi.sectionHeader(context, title: l10n.t('pricing_summary')),
          _PricingBreakdown(
            pricing: state.pricing!,
            l10n: l10n,
            compact: embedded,
          ),
          const SizedBox(height: WizardCompact.fieldGap),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.accentLight,
            padding: const EdgeInsets.all(WizardCompact.cardPadding),
            child: Text(
              l10n.t('customer_price_conditions'),
              style: const TextStyle(
                color: AppTokens.textSecondary,
                height: 1.45,
              ),
            ),
          ),
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

/// Replace the asset path with a licensed JPG/PNG/WebP to switch to photography.
class CustomerVehicleArtwork extends StatelessWidget {
  const CustomerVehicleArtwork({super.key, required this.vehicle});
  final String vehicle;
  static const assets = {'SEDAN':'assets/images/vehicle_sedan.svg','SUV':'assets/images/vehicle_suv.svg','VAN':'assets/images/vehicle_van.svg'};
  @override
  Widget build(BuildContext context) {
    final asset=assets[vehicle]!;
    return asset.endsWith('.svg') ? SvgPicture.asset(asset,width:80,height:48) : Image.asset(asset,width:80,height:48,fit:BoxFit.contain);
  }
}
