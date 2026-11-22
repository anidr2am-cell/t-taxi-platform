import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../utils/customer_booking_format.dart';
import '../utils/location_display.dart';

class BookingSummaryBar extends StatefulWidget {
  const BookingSummaryBar({
    super.key,
    required this.state,
    required this.controller,
  });

  final BookingWizardState state;
  final BookingWizardController controller;

  @override
  State<BookingSummaryBar> createState() => _BookingSummaryBarState();
}

class _BookingSummaryBarState extends State<BookingSummaryBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final expanded = _expanded || MediaQuery.sizeOf(context).width >= 1000;
    final routeLine = _routeLine(l10n, state);
    final scheduleLine = _scheduleLine(l10n, state);
    final vehicleLine = state.selectedVehicle == null
        ? null
        : l10n.t('cx_vehicle_${state.selectedVehicle}');
    final priceLine = state.pricing == null
        ? (state.errorMessage == 'pricing_inquiry_required'
              ? l10n.t('fare_inquiry_title')
              : l10n.t(
                  widget.controller.isLoading
                      ? 'ux_calculating'
                      : 'ux_fare_pending',
                ))
        : CustomerBookingFormat.money(
            state.pricing!.totalAmount,
            state.pricing!.currency,
          );

    final compactParts = <String>[
      if (routeLine != null) routeLine,
      if (scheduleLine != null) scheduleLine,
      if (vehicleLine != null) vehicleLine,
      priceLine,
    ];
    if (compactParts.isEmpty) return const SizedBox.shrink();

    final compactText = compactParts.join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              child: Semantics(
                button: true,
                label: _expanded
                    ? l10n.t('wizard_summary_collapse')
                    : l10n.t('wizard_summary_expand'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          compactText,
                          maxLines: expanded ? null : 2,
                          overflow: expanded ? null : TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontSize: 16, height: 1.4),
                        ),
                      ),
                      IconButton(
                        key: const Key('summary_edit_route'),
                        tooltip: l10n.t('ux_route_edit'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => widget.controller.goToStep(0),
                      ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTokens.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.controller.routeNeedsReview)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.t('ux_route_updated')),
              ),
            if (expanded) ...[
              const Divider(height: 16),
              if (routeLine != null)
                AppUi.summaryRow(
                  label: l10n.t('customer_confirmation_trip'),
                  value: routeLine,
                ),
              if (scheduleLine != null)
                AppUi.summaryRow(
                  label: l10n.t('pickup_datetime'),
                  value: scheduleLine,
                ),
              AppUi.summaryRow(
                label: l10n.t('passengers'),
                value:
                    '${l10n.t('adults')} ${state.adults} · ${l10n.t('children')} ${state.children} · ${l10n.t('infants')} ${state.infants}',
              ),
              AppUi.summaryRow(
                label: l10n.t('luggage'),
                value:
                    '20″ ${state.luggage20} · 24″+ ${state.luggage24} · ${l10n.t('golf_bags')} ${state.golfBags}',
              ),
              if (vehicleLine != null)
                AppUi.summaryRow(label: l10n.t('vehicle'), value: vehicleLine),
              AppUi.summaryRow(
                label: l10n.t('total'),
                value: priceLine,
                emphasize: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _routeLine(AppLocalizations l10n, BookingWizardState state) {
    final origin = state.origin;
    final destination = state.destination;
    if (origin == null || destination == null) return null;
    final from =
        resolveLocationOptionParts(origin).primaryName ?? origin.displayName;
    final to =
        resolveLocationOptionParts(destination).primaryName ??
        destination.displayName;
    return '$from → $to';
  }

  String? _scheduleLine(AppLocalizations l10n, BookingWizardState state) {
    if (state.pickupDate == null || state.pickupTime == null) return null;
    return CustomerBookingFormat.pickupDate(
      l10n,
      state.pickupDate,
      state.pickupTime,
    );
  }
}
