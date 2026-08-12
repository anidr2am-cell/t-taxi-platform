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
    final routeLine = _routeLine(l10n, state);
    final scheduleLine = _scheduleLine(l10n, state);
    final vehicleLine = state.selectedVehicle;
    final priceLine = state.pricing == null
        ? null
        : CustomerBookingFormat.money(
            state.pricing!.totalAmount,
            state.pricing!.currency,
          );

    final compactParts = <String>[
      if (routeLine != null) routeLine,
      if (scheduleLine != null) scheduleLine,
      if (vehicleLine != null) vehicleLine,
      if (priceLine != null) priceLine,
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
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppTokens.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            ),
            if (_expanded) ...[
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
              if (vehicleLine != null)
                AppUi.summaryRow(
                  label: l10n.t('vehicle'),
                  value: vehicleLine,
                ),
              if (priceLine != null)
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
    final from = resolveLocationOptionParts(origin).primaryName ??
        origin.displayName;
    final to = resolveLocationOptionParts(destination).primaryName ??
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
