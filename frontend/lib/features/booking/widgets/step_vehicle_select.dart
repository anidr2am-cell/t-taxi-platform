import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recommendation = state.recommendation;

    if (controller.isLoading) {
      return const WizardLoadingView(message: 'Calculating price...');
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('select_vehicle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...BookingWizardController.vehicleTierOrder.map((vehicle) {
            final enabled = controller.isVehicleEnabled(vehicle);
            final selected = state.selectedVehicle == vehicle;
            return Card(
              color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
              child: ListTile(
                enabled: enabled,
                title: Text(vehicle),
                subtitle: enabled
                    ? null
                    : Text(l10n.t('vehicle_not_available')),
                trailing: selected ? const Icon(Icons.check_circle) : null,
                onTap: enabled ? () => controller.selectVehicle(vehicle) : null,
              ),
            );
          }),
          if (state.pricing != null) ...[
            const SizedBox(height: 24),
            Text(l10n.t('pricing_summary'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row(l10n.t('base_price'), pricing.basePrice, pricing.currency),
            ...pricing.additionalCharges.map<Widget>((item) => _row(
                  item.description,
                  item.amount,
                  pricing.currency,
                )),
            const Divider(),
            _row(
              l10n.t('total'),
              pricing.totalAmount,
              pricing.currency,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, num amount, String currency, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Text(
            '$amount $currency',
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }
}
