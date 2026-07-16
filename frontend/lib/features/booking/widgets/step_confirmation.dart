import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../utils/customer_booking_format.dart';
import '../utils/pricing_display.dart';
import '../models/booking_wizard_state.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';

class StepConfirmation extends StatelessWidget {
  final BookingWizardState state;
  final bool embedded;
  final ValueChanged<int>? onEditStep;

  const StepConfirmation({
    super.key,
    required this.state,
    this.embedded = false,
    this.onEditStep,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pricing = state.pricing;
    final total = pricing == null
        ? '-'
        : CustomerBookingFormat.money(pricing.totalAmount, pricing.currency);

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
          editStep: 1,
          children: [
            AppUi.summaryRow(
              label: l10n.t('service_type'),
              value: l10n.t(state.serviceType?.labelKey ?? ''),
            ),
            AppUi.summaryRow(
              label: l10n.t('origin'),
              value: _formatLocation(state.origin),
            ),
            AppUi.summaryRow(
              label: l10n.t('destination'),
              value: _formatLocation(state.destination),
            ),
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
          editStep: 4,
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
          ],
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: l10n.t('customer_confirmation_vehicle_payment'),
          editStep: 5,
          backgroundColor: AppTokens.primaryLight,
          children: [
            AppUi.summaryRow(
              label: l10n.t('vehicle'),
              value: state.selectedVehicle ?? '-',
            ),
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
          editStep: 6,
          children: [
            AppUi.summaryRow(label: l10n.t('name'), value: state.customerName),
            AppUi.summaryRow(
              label: l10n.t('phone'),
              value: state.customerPhone,
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

  String _formatLocation(LocationOption? location) {
    if (location == null) return '-';
    final name = location.name ?? location.displayName;
    if (location.address != null && location.address!.isNotEmpty) {
      return '$name — ${location.address}';
    }
    return name;
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
