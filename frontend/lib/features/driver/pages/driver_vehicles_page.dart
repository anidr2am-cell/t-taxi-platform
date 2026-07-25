import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/driver_vehicle.dart';
import '../services/driver_api_service.dart';
import 'driver_vehicle_add_page.dart';

class DriverVehiclesPage extends StatefulWidget {
  const DriverVehiclesPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverVehiclesPage> createState() => _DriverVehiclesPageState();
}

class _DriverVehiclesPageState extends State<DriverVehiclesPage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late Future<List<DriverVehicleItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.listVehicles();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _api.listVehicles();
    });
    await _future;
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    return switch (status.toUpperCase()) {
      'PENDING' => l10n.t('driver_vehicle_status_pending'),
      'REJECTED' => l10n.t('driver_vehicle_status_rejected'),
      _ => l10n.t('driver_vehicle_status_approved'),
    };
  }

  AppStatusTone _statusTone(String status) {
    return switch (status.toUpperCase()) {
      'PENDING' => AppStatusTone.warning,
      'REJECTED' => AppStatusTone.error,
      _ => AppStatusTone.success,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_vehicles_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => DriverVehicleAddPage(api: _api),
            ),
          );
          if (created == true && mounted) {
            await _reload();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.t('driver_vehicle_add')),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<DriverVehicleItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                children: [
                  Text(
                    userFacingError(
                      snapshot.error!,
                      fallback: l10n.t('driver_load_failed'),
                    ),
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <DriverVehicleItem>[];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                children: [
                  Text(l10n.t('driver_vehicles_empty')),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                96,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppTokens.spaceSm),
              itemBuilder: (context, index) {
                final vehicle = items[index];
                return AppUi.surfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vehicle.vehicleTypeName.isNotEmpty
                                  ? vehicle.vehicleTypeName
                                  : vehicle.vehicleTypeCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          AppUi.statusBadge(
                            _statusLabel(l10n, vehicle.approvalStatus),
                            tone: _statusTone(vehicle.approvalStatus),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        vehicle.plateNumber,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (vehicle.modelName?.isNotEmpty == true ||
                          vehicle.color?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (vehicle.modelName?.isNotEmpty == true)
                              vehicle.modelName,
                            if (vehicle.color?.isNotEmpty == true)
                              vehicle.color,
                          ].whereType<String>().join(' · '),
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                          ),
                        ),
                      ],
                      if (vehicle.isPrimary) ...[
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(
                          l10n.t('driver_vehicle_primary_badge'),
                          style: const TextStyle(
                            color: AppTokens.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (vehicle.approvalStatus == 'REJECTED' &&
                          vehicle.rejectionReason?.isNotEmpty == true) ...[
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(
                          vehicle.rejectionReason!,
                          style: const TextStyle(color: AppTokens.error),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
