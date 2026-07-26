import 'package:flutter/material.dart';

import '../data/dispatch_models.dart';

Future<CompatibleVehicle?> showVehicleSelectSheet(
  BuildContext context,
  List<CompatibleVehicle> vehicles,
) {
  return showModalBottomSheet<CompatibleVehicle>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          key: const Key('vehicleSelectSheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('운행 차량 선택', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('이 콜에 사용할 차량을 선택해 주세요.'),
            const SizedBox(height: 12),
            ...vehicles.map(
              (vehicle) => ListTile(
                key: Key('vehicleOption-${vehicle.driverVehicleId}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_taxi_outlined),
                title: Text(vehicle.displayName),
                subtitle: vehicle.isExactMatch
                    ? const Text('예약 차량과 정확히 일치')
                    : const Text('호환 가능한 상위 차량'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(vehicle),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
