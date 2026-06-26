import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
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
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.t('booking_summary'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                l10n.t('booking_preview_only'),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const Divider(height: 24),
              _row(l10n.t('service_type'), l10n.t(state.serviceType?.labelKey ?? '')),
              _row(l10n.t('origin'), _formatLocation(state.origin)),
              _row(l10n.t('destination'), _formatLocation(state.destination)),
              _row(l10n.t('adults'), '${state.adults}'),
              _row(l10n.t('children'), '${state.children}'),
              _row(l10n.t('infants'), '${state.infants}'),
              _row(l10n.t('small_carriers'), '${state.luggage20}'),
              _row(l10n.t('large_carriers'), '${state.luggage24}'),
              _row(l10n.t('golf_bags'), '${state.golfBags}'),
              _row(l10n.t('special_luggage'), '${state.specialLuggageCount}'),
              if (state.nameSign) _row(l10n.t('name_sign'), l10n.t('yes')),
              _row(l10n.t('vehicle'), state.selectedVehicle ?? '-'),
              if (pricing != null) ...[
                const Divider(height: 24),
                _row(l10n.t('base_price'), '${pricing.basePrice} ${pricing.currency}'),
                for (final item in pricing.additionalCharges)
                  _row(item.description, '${item.amount} ${pricing.currency}'),
                _row(
                  l10n.t('total'),
                  '${pricing.totalAmount} ${pricing.currency}',
                  bold: true,
                ),
              ],
            ],
          ),
        ),
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

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
