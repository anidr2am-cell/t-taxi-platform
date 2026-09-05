import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../account/services/coupon_api_service.dart';
import '../utils/customer_booking_format.dart';
import '../utils/location_display.dart';
import '../models/booking_wizard_state.dart';
import '../models/booking_wizard_steps.dart';
import '../models/service_type_option.dart';
import '../utils/pricing_display.dart';

class StepConfirmation extends StatelessWidget {
  final BookingWizardState state;
  final bool embedded;
  final ValueChanged<int>? onEditStep;
  final List<CustomerCouponItem> availableCoupons;
  final bool loadingCoupons;
  final ValueChanged<int?>? onCouponSelected;
  final num? estimatedTotal;
  final num? couponDiscount;

  const StepConfirmation({
    super.key,
    required this.state,
    this.embedded = false,
    this.onEditStep,
    this.availableCoupons = const [],
    this.loadingCoupons = false,
    this.onCouponSelected,
    this.estimatedTotal,
    this.couponDiscount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pricing = state.pricing;
    final displayTotal = estimatedTotal ?? pricing?.totalAmount;
    final total = displayTotal == null
        ? '-'
        : CustomerBookingFormat.money(displayTotal, pricing?.currency ?? 'THB');

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('customer_confirmation_title'),
          subtitle: l10n.t('customer_confirmation_subtitle'),
        ),
        _section(
          context,
          title: l10n.t('customer_confirmation_trip'),
          editStep: BookingWizardSteps.route,
          children: [
            AppUi.summaryRow(
              label: l10n.t('service_type'),
              value: l10n.t(state.serviceType?.labelKey ?? ''),
            ),
            bookingLocationOptionSummaryRow(
              label: l10n.t('origin'),
              location: state.origin,
            ),
            bookingLocationOptionSummaryRow(
              label: l10n.t('destination'),
              location: state.destination,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: l10n.t('pickup_datetime'),
          editStep: BookingWizardSteps.schedule,
          children: [
            AppUi.summaryRow(
              label: l10n.t('pickup_datetime'),
              value: CustomerBookingFormat.pickupDate(
                l10n,
                state.pickupDate,
                state.pickupTime,
              ),
            ),
            if (state.serviceType == BookingServiceType.airportPickup &&
                state.flightNumber.trim().isNotEmpty)
              AppUi.summaryRow(
                label: l10n.t('flight_number'),
                value: state.flightNumber.trim().toUpperCase(),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: l10n.t('customer_confirmation_passengers'),
          editStep: BookingWizardSteps.vehicle,
          children: [
            AppUi.summaryRow(label: l10n.t('adults'), value: '${state.adults}'),
            AppUi.summaryRow(
              label: l10n.t('children'),
              value: '${state.children}',
            ),
            AppUi.summaryRow(
              label: l10n.t('infants'),
              value: '${state.infants}',
            ),
            AppUi.summaryRow(
              label: l10n.t('small_carriers'),
              value: '${state.luggage20}',
            ),
            AppUi.summaryRow(
              label: l10n.t('large_carriers'),
              value: '${state.luggage24}',
            ),
            AppUi.summaryRow(
              label: l10n.t('golf_bags'),
              value: '${state.golfBags}',
            ),
            AppUi.summaryRow(
              label: l10n.t('special_luggage'),
              value: '${state.specialLuggageCount}',
            ),
            if (state.nameSign)
              AppUi.summaryRow(
                label: l10n.t('name_sign'),
                value: l10n.t('yes'),
              ),
            if (state.nameSign &&
                (state.nameSignText?.trim().isNotEmpty ?? false))
              AppUi.summaryRow(
                label: l10n.t('name_sign_text_label'),
                value: state.nameSignText!.trim(),
              ),
            if (state.preferFemaleDriver)
              AppUi.summaryRow(
                label: l10n.t('booking_prefer_female_driver'),
                value: l10n.t('yes'),
              ),
            AppUi.summaryRow(
              label: l10n.t('vehicle'),
              value: state.selectedVehicle ?? '-',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: l10n.t('customer_confirmation_vehicle_payment'),
          editStep: BookingWizardSteps.vehicle,
          backgroundColor: AppTokens.primaryLight,
          children: [
            if (pricing != null) ...[
              AppUi.summaryRow(
                label: l10n.t('base_price'),
                value: CustomerBookingFormat.money(
                  pricing.basePrice,
                  pricing.currency,
                ),
              ),
              for (final item in pricing.additionalCharges)
                AppUi.summaryRow(
                  label: PricingDisplay.chargeItemLabel(l10n, item),
                  value: CustomerBookingFormat.money(
                    item.amount,
                    pricing.currency,
                  ),
                ),
              if (couponDiscount != null && couponDiscount! > 0)
                AppUi.summaryRow(
                  label: l10n.t('booking_coupon_discount_label'),
                  value: '-${CustomerBookingFormat.money(couponDiscount!, pricing.currency)}',
                ),
            ],
            if (availableCoupons.isNotEmpty || loadingCoupons) ...[
              const Divider(height: 24),
              Text(
                l10n.t('booking_coupon_section_title'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              if (loadingCoupons)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else
                DropdownButtonFormField<int?>(
                  value: state.selectedCouponId,
                  decoration: InputDecoration(
                    labelText: l10n.t('booking_coupon_section_title'),
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(l10n.t('booking_coupon_none')),
                    ),
                    ...availableCoupons.map(
                      (coupon) => DropdownMenuItem<int?>(
                        value: coupon.id,
                        child: Text(
                          '${coupon.title} (-${coupon.discountAmount} ${l10n.t('thb')})',
                        ),
                      ),
                    ),
                  ],
                  onChanged: onCouponSelected,
                ),
            ],
            const Divider(height: 24),
            AppUi.summaryRow(
              label: l10n.t('total'),
              value: total,
              emphasize: true,
            ),
            AppUi.summaryRow(
              label: l10n.t('customer_payment_method'),
              value: CustomerBookingFormat.paymentMethod(l10n, 'PAY_DRIVER'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: l10n.t('customer_confirmation_customer'),
          editStep: BookingWizardSteps.customer,
          children: [
            AppUi.summaryRow(label: l10n.t('name'), value: state.customerName),
            AppUi.summaryRow(
              label: l10n.t('phone'),
              value: state.customerPhone,
            ),
            if (state.messengerType.trim().isNotEmpty)
              AppUi.summaryRow(
                label: l10n.t('messenger_type'),
                value: state.messengerType.trim(),
              ),
            if (state.messengerId.trim().isNotEmpty)
              AppUi.summaryRow(
                label: l10n.t('messenger_id'),
                value: state.messengerId.trim(),
              ),
            if (state.customerEmail.trim().isNotEmpty)
              AppUi.summaryRow(
                label: l10n.t('email'),
                value: state.customerEmail.trim(),
              ),
            if (state.additionalRequests.trim().isNotEmpty)
              AppUi.summaryRow(
                label: l10n.t('additional_requests'),
                value: state.additionalRequests.trim(),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AppUi.surfaceCard(
          backgroundColor: AppTokens.accentLight,
          child: Text(
            l10n.t('customer_price_conditions'),
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );

    if (embedded) return content;

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: content,
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required int editStep,
    required List<Widget> children,
    Color? backgroundColor,
  }) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      backgroundColor: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (onEditStep != null)
                TextButton.icon(
                  onPressed: () => onEditStep!(editStep),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.t('customer_confirmation_edit')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
