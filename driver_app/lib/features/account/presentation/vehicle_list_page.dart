import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/account_api.dart';
import '../data/account_models.dart';
import 'vehicle_add_page.dart';

class VehicleListPage extends StatefulWidget {
  const VehicleListPage({
    super.key,
    required this.api,
    required this.onUnauthorized,
  });

  final AccountDataSource api;
  final Future<void> Function() onUnauthorized;

  @override
  State<VehicleListPage> createState() => _VehicleListPageState();
}

class _VehicleListPageState extends State<VehicleListPage> {
  List<DriverVehicle>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await widget.api.getVehicles();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차량 관리')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addVehicleFab'),
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => VehicleAddPage(api: widget.api)),
          );
          if (created == true) await _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('차량 추가'),
      ),
      body: _items == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: FilledButton(onPressed: _load, child: const Text('다시 시도')),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _items!.isEmpty
                  ? ListView(
                      key: const Key('vehicleEmpty'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('등록된 차량이 없습니다.')),
                      ],
                    )
                  : ListView.separated(
                      key: const Key('vehicleList'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _items!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) =>
                          _VehicleCard(vehicle: _items![index]),
                    ),
            ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});

  final DriverVehicle vehicle;

  Color _statusColor(BuildContext context) => switch (vehicle.approvalStatus) {
    'PENDING' => Colors.orange,
    'REJECTED' => Theme.of(context).colorScheme.error,
    _ => Colors.green,
  };

  String get _statusLabel => switch (vehicle.approvalStatus) {
    'PENDING' => '승인 대기',
    'REJECTED' => '승인 거절',
    _ => '승인 완료',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  key: Key('vehicleStatus-${vehicle.approvalStatus}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      color: _statusColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              vehicle.plateNumber,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (vehicle.modelName?.isNotEmpty == true ||
                vehicle.color?.isNotEmpty == true)
              Text(
                [vehicle.modelName, vehicle.color]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
              ),
            if (vehicle.isPrimary)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(label: Text('주 차량')),
              ),
            if (vehicle.approvalStatus == 'REJECTED' &&
                vehicle.rejectionReason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '거절 사유: ${vehicle.rejectionReason}',
                  key: const Key('vehicleRejectionReason'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
