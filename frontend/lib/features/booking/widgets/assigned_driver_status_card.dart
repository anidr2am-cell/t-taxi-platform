import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../models/guest_booking_lookup_result.dart';
import 'guest_driver_vehicle_photo.dart';

class AssignedDriverStatusCard extends StatelessWidget {
  const AssignedDriverStatusCard({
    super.key,
    required this.result,
    this.apiBaseUrl,
  });

  final GuestBookingLookupResult result;
  final String? apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final driverName = result.driverName?.trim();
    if (driverName == null || driverName.isEmpty) {
      return const SizedBox.shrink();
    }

    final vehicleLines = <String>[
      if (result.vehicleType?.trim().isNotEmpty == true) result.vehicleType!.trim(),
      if (result.vehicleColor?.trim().isNotEmpty == true) result.vehicleColor!.trim(),
      if (result.vehiclePlateNumber?.trim().isNotEmpty == true) result.vehiclePlateNumber!.trim(),
    ];

    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('guest_lookup_driver_status'),
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.summaryRow(
            label: l10n.t('guest_lookup_driver'),
            value: driverName,
          ),
          if (result.driverPhone?.trim().isNotEmpty == true)
            AppUi.summaryRow(
              label: l10n.t('guest_lookup_driver_phone'),
              value: result.driverPhone!.trim(),
            ),
          if (vehicleLines.isNotEmpty)
            AppUi.summaryRow(
              label: l10n.t('guest_lookup_vehicle'),
              value: vehicleLines.join(' · '),
            ),
          if (result.vehiclePhotoUrl?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppTokens.spaceMd),
            GuestDriverVehiclePhoto(
              photoPath: result.vehiclePhotoUrl!,
              guestAccessToken: result.guestAccessToken,
              apiBaseUrl: apiBaseUrl,
            ),
          ],
        ],
      ),
    );
  }
}
