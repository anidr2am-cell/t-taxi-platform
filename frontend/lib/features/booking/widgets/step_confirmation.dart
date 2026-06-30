import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_wizard_state.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';

class StepConfirmation extends StatelessWidget {
  final BookingWizardState state;

  const StepConfirmation({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pricing = state.pricing;

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('booking_summary'),
            subtitle: l10n.t('landing_highlight_fixed_price'),
          ),
          AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppUi.summaryRow(
                  label: l10n.t('service_type'),
                  value: l10n.t(state.serviceType?.labelKey ?? ''),
                ),
                AppUi.summaryRow(label: l10n.t('origin'), value: _formatLocation(state.origin)),
                AppUi.summaryRow(label: l10n.t('destination'), value: _formatLocation(state.destination)),
                AppUi.summaryRow(
                  label: l10n.t('pickup_datetime'),
                  value: '${state.pickupDate ?? '-'} ${state.pickupTime ?? ''}'.trim(),
                ),
                AppUi.summaryRow(label: l10n.t('adults'), value: '${state.adults}'),
                AppUi.summaryRow(label: l10n.t('children'), value: '${state.children}'),
                AppUi.summaryRow(label: l10n.t('infants'), value: '${state.infants}'),
                AppUi.summaryRow(label: l10n.t('small_carriers'), value: '${state.luggage20}'),
                AppUi.summaryRow(label: l10n.t('large_carriers'), value: '${state.luggage24}'),
                AppUi.summaryRow(label: l10n.t('golf_bags'), value: '${state.golfBags}'),
                AppUi.summaryRow(label: l10n.t('special_luggage'), value: '${state.specialLuggageCount}'),
                if (state.nameSign)
                  AppUi.summaryRow(label: l10n.t('name_sign'), value: l10n.t('yes')),
                AppUi.summaryRow(label: l10n.t('vehicle'), value: state.selectedVehicle ?? '-'),
              ],
            ),
          ),
          if (pricing != null) ...[
            const SizedBox(height: 16),
            AppUi.surfaceCard(
              backgroundColor: AppTokens.primaryLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('total'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTokens.primaryDark,
                        ),
                  ),
                  const SizedBox(height: 12),
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
            ),
          ],
        ],
      ),
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
}
