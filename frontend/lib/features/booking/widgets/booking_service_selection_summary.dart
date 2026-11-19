import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/service_type_option.dart';

/// The whole field opens the service choices, including its selected label.
class BookingServiceSelectionSummary extends StatelessWidget {
  const BookingServiceSelectionSummary({
    super.key,
    required this.service,
    required this.onChange,
  });

  final BookingServiceType service;
  final VoidCallback onChange;

  IconData get _icon => switch (service) {
    BookingServiceType.airportPickup => Icons.flight_land,
    BookingServiceType.airportDropoff => Icons.flight_takeoff,
    BookingServiceType.cityTransfer => Icons.location_city,
    BookingServiceType.golfTransfer => Icons.golf_course,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = l10n.t(service.labelKey);
    return Semantics(
      button: true,
      label:
          '${l10n.t('select_service')}: $label, ${l10n.t('change_location')}',
      child: Material(
        color: AppTokens.primaryLight,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusMd,
          side: const BorderSide(color: AppTokens.primary),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('booking_selected_service_change'),
          onTap: onChange,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Row(
              children: [
                Icon(_icon, color: AppTokens.primary, size: 28),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Text(
                    label,
                    key: const ValueKey('booking_selected_service_label'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Text(
                  l10n.t('change_location'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTokens.primary,
                  ),
                ),
                const Icon(Icons.expand_more, color: AppTokens.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
