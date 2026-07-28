import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../data/dispatch_models.dart';

Future<CompatibleVehicle?> showVehicleSelectSheet(
  BuildContext context,
  List<CompatibleVehicle> vehicles,
) {
  return showModalBottomSheet<CompatibleVehicle>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            key: const Key('vehicleSelectSheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.selectTripVehicleTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(l10n.selectVehicleForCallHint),
              const SizedBox(height: 12),
              ...vehicles.map(
                (vehicle) => ListTile(
                  key: Key('vehicleOption-${vehicle.driverVehicleId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_taxi_outlined),
                  title: Text(vehicle.displayName),
                  subtitle: Text(
                    vehicle.isExactMatch
                        ? l10n.exactVehicleMatch
                        : l10n.compatibleUpgradeVehicle,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(vehicle),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
