import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../utils/pricing_display.dart';
import '../models/booking_complete_review.dart';

class BookingCompleteReviewSection extends StatelessWidget {
  const BookingCompleteReviewSection({super.key, required this.review});

  final BookingCompleteReview review;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pricing = review.pricing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.surfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppUi.summaryRow(
                label: l10n.t('pickup_datetime'),
                value: '${review.pickupDate ?? '-'} ${review.pickupTime ?? ''}'.trim(),
              ),
              if (review.showFlightNumber)
                AppUi.summaryRow(
                  label: l10n.t('flight_number'),
                  value: review.flightNumber.trim(),
                ),
              AppUi.summaryRow(label: l10n.t('adults'), value: '${review.adults}'),
              if (review.children > 0)
                AppUi.summaryRow(label: l10n.t('children'), value: '${review.children}'),
              if (review.infants > 0)
                AppUi.summaryRow(label: l10n.t('infants'), value: '${review.infants}'),
              if (review.luggage20 > 0)
                AppUi.summaryRow(
                  label: l10n.t('small_carriers'),
                  value: '${review.luggage20}',
                ),
              if (review.luggage24 > 0)
                AppUi.summaryRow(
                  label: l10n.t('large_carriers'),
                  value: '${review.luggage24}',
                ),
              if (review.golfBags > 0)
                AppUi.summaryRow(label: l10n.t('golf_bags'), value: '${review.golfBags}'),
              if (review.specialLuggageCount > 0)
                AppUi.summaryRow(
                  label: l10n.t('special_luggage'),
                  value: '${review.specialLuggageCount}',
                ),
              if (review.nameSign)
                AppUi.summaryRow(label: l10n.t('name_sign'), value: l10n.t('yes')),
              if (review.selectedVehicle != null)
                AppUi.summaryRow(
                  label: l10n.t('vehicle'),
                  value: review.selectedVehicle!,
                ),
              if (review.customerName.trim().isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('name'),
                  value: review.customerName.trim(),
                ),
              if (review.customerEmail.trim().isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('email'),
                  value: review.customerEmail.trim(),
                ),
              if (review.customerPhone.trim().isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('phone'),
                  value: review.customerPhone.trim(),
                ),
              if (review.showCountryCode)
                AppUi.summaryRow(
                  label: l10n.t('country'),
                  value: review.customerCountryCode.trim(),
                ),
              if (review.messengerType.trim().isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('messenger_type'),
                  value: review.messengerType.trim(),
                ),
              if (review.messengerId.trim().isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('messenger_id'),
                  value: review.messengerId.trim(),
                ),
              if (review.showAdditionalRequests)
                AppUi.summaryRow(
                  label: l10n.t('additional_requests'),
                  value: review.additionalRequests.trim(),
                ),
            ],
          ),
        ),
        if (review.showPricingBreakdown && pricing != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.primaryLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('pricing_summary'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTokens.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                AppUi.summaryRow(
                  label: l10n.t('base_price'),
                  value: '${pricing.basePrice} ${pricing.currency}',
                ),
                for (final item in pricing.additionalCharges)
                  AppUi.summaryRow(
                    label: PricingDisplay.chargeItemLabel(l10n, item),
                    value: '${item.amount} ${pricing.currency}',
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
