import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_dispatch/services/admin_dispatch_api_service.dart';
import '../models/driver_location.dart';
import '../services/driver_location_api_service.dart';
import '../services/driver_location_socket_service.dart';
import '../widgets/driver_location_map.dart';

class AdminDriverMonitorPage extends StatefulWidget {
  const AdminDriverMonitorPage({
    super.key,
    this.api,
    this.dispatchApi,
    this.socket,
  });

  final DriverLocationApiService? api;
  final AdminDispatchApiService? dispatchApi;
  final DriverLocationSocketService? socket;

  @override
  State<AdminDriverMonitorPage> createState() => _AdminDriverMonitorPageState();
}

class _AdminDriverMonitorPageState extends State<AdminDriverMonitorPage> {
  bool _loading = true;
  bool _onlineOnly = false;
  bool _activeAccountOnly = true;
  bool _activeJobOnly = false;
  bool _staleOnly = false;
  String? _error;
  List<Map<String, dynamic>> _drivers = [];
  List<DriverLocation> _locations = [];
  DriverLocation? _selected;
  late final DriverLocationApiService _api = widget.api ?? DriverLocationApiService();
  late final AdminDispatchApiService _dispatchApi =
      widget.dispatchApi ?? const AdminDispatchApiService();
  late final DriverLocationSocketService _socket =
      widget.socket ?? DriverLocationSocketService();

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
  }

  @override
  void dispose() {
    _socket.disconnect();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('admin_access_token');
    if (token == null || token.isEmpty) return;
    _socket.onAdminChanged = (payload) {
      final next = DriverLocation.fromJson(payload);
      setState(() {
        final index = _locations.indexWhere((item) => item.driverId == next.driverId);
        if (index >= 0) {
          _locations[index] = next;
        } else {
          _locations = [next, ..._locations];
        }
      });
    };
    _socket.onStateChanged = () {
      if (mounted) setState(() {});
    };
    await _socket.connect(accessToken: token);
    _socket.subscribeAdmin();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _dispatchApi.listDrivers(),
        _api.listAdminLocations(
          onlineOnly: false,
          activeJobOnly: false,
          staleOnly: false,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = (results[0] as Iterable)
            .map((row) => Map<String, dynamic>.from(row as Map<String, dynamic>))
            .toList(growable: false);
        _locations = results[1] as List<DriverLocation>;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.toString();
      });
    }
  }

  void _toggle(VoidCallback update) {
    setState(update);
  }

  List<Map<String, dynamic>> get _filteredDrivers {
    return _drivers.where((driver) {
      if (_activeAccountOnly && driver['activeState'] != 'ACTIVE') return false;
      if (_onlineOnly && driver['onlineState'] != 'ONLINE') return false;
      if (_activeJobOnly && (driver['activeAssignmentCount'] as num? ?? 0) == 0) {
        return false;
      }
      return true;
    }).toList();
  }

  List<DriverLocation> get _filteredLocations {
    final allowedIds = _filteredDrivers.map((d) => d['driverId'] as int).toSet();
    var items = _locations.where((item) => allowedIds.contains(item.driverId));
    if (_onlineOnly) {
      items = items.where((item) => item.online == true);
    }
    if (_activeJobOnly) {
      items = items.where((item) => item.activeBooking != null);
    }
    if (_staleOnly) {
      items = items.where((item) => item.stale);
    }
    return items.toList();
  }

  DriverLocation? _locationForDriver(int driverId) {
    for (final item in _locations) {
      if (item.driverId == driverId) return item;
    }
    return null;
  }

  String _vehicleLabel(Map<String, dynamic> driver) {
    final vehicle = driver['primaryVehicle'];
    if (vehicle is Map) {
      final code = vehicle['vehicleTypeCode'] as String?;
      final plate = vehicle['plateNumber'] as String?;
      return [code, plate].whereType<String>().where((v) => v.isNotEmpty).join(' · ');
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final drivers = _filteredDrivers;
    final mapLocations = _filteredLocations;

    return Padding(
      padding: AppUi.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('admin_drivers'),
            subtitle: l10n.t('admin_driver_management_help'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _socket.connected ? Icons.cloud_done : Icons.cloud_off,
                  size: 18,
                  color: _socket.connected ? AppTokens.success : AppTokens.textMuted,
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.t('admin_dispatch_retry'),
                ),
              ],
            ),
          ),
          AppUi.adminFilterBar(
            children: [
              FilterChip(
                label: Text(l10n.t('admin_driver_filter_active_accounts')),
                selected: _activeAccountOnly,
                onSelected: (value) => _toggle(() => _activeAccountOnly = value),
              ),
              FilterChip(
                label: Text(l10n.t('admin_driver_filter_online_only')),
                selected: _onlineOnly,
                onSelected: (value) => _toggle(() => _onlineOnly = value),
              ),
              FilterChip(
                label: Text(l10n.t('admin_driver_filter_active_jobs')),
                selected: _activeJobOnly,
                onSelected: (value) => _toggle(() => _activeJobOnly = value),
              ),
              FilterChip(
                label: Text(l10n.t('admin_driver_filter_stale_locations')),
                selected: _staleOnly,
                onSelected: (value) => _toggle(() => _staleOnly = value),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            AppUi.errorState(
              message: _error!,
              onRetry: _load,
              retryLabel: l10n.t('admin_dispatch_retry'),
            ),
          ],
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: AppUi.surfaceCard(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: AppTokens.borderRadiusLg,
                      child: LayoutBuilder(
                        builder: (context, constraints) => DriverLocationMap(
                          locations: mapLocations,
                          height: constraints.maxHeight,
                          onTapLocation: (location) => setState(() => _selected = location),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_loading && mapLocations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                    child: Text(
                      l10n.t('admin_no_driver_locations'),
                      style: const TextStyle(color: AppTokens.textSecondary),
                    ),
                  ),
                const SizedBox(height: AppTokens.spaceSm),
                Expanded(
                  flex: 3,
                  child: _loading
                      ? const SizedBox.shrink()
                      : drivers.isEmpty
                          ? AppUi.emptyState(
                              title: l10n.t('admin_no_drivers_found'),
                              icon: Icons.person_off_outlined,
                            )
                          : ListView.separated(
                              itemCount: drivers.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: AppTokens.spaceSm),
                              itemBuilder: (context, index) {
                                final driver = drivers[index];
                                final driverId = driver['driverId'] as int;
                                final location = _locationForDriver(driverId);
                                final selected = _selected?.driverId == driverId;
                                final vehicleLabel = _vehicleLabel(driver);
                                final online = driver['onlineState'] == 'ONLINE';
                                final activeJobs =
                                    driver['activeAssignmentCount'] as num? ?? 0;

                                return AppUi.adminQueueCard(
                                  onTap: () => setState(() => _selected = location),
                                  backgroundColor: selected
                                      ? AppTokens.primaryLight
                                      : AppTokens.surface,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: online
                                              ? AppTokens.successLight
                                              : AppTokens.surfaceMuted,
                                          borderRadius: AppTokens.borderRadiusSm,
                                        ),
                                        child: Icon(
                                          online
                                              ? Icons.person_pin_circle
                                              : Icons.person_off_outlined,
                                          color: online
                                              ? AppTokens.success
                                              : AppTokens.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: AppTokens.spaceSm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              driver['displayName'] as String? ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: AppTokens.spaceSm,
                                              runSpacing: 4,
                                              children: [
                                                AppUi.statusBadge(
                                                  online
                                                      ? l10n.t('admin_driver_online')
                                                      : l10n.t('admin_driver_offline'),
                                                  tone: online
                                                      ? AppStatusTone.success
                                                      : AppStatusTone.neutral,
                                                ),
                                                AppUi.statusBadge(
                                                  '${l10n.t('admin_driver_active_jobs')}: $activeJobs',
                                                  tone: activeJobs > 0
                                                      ? AppStatusTone.info
                                                      : AppStatusTone.neutral,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              vehicleLabel.isNotEmpty
                                                  ? vehicleLabel
                                                  : l10n.t('admin_driver_no_vehicle'),
                                              style: const TextStyle(
                                                color: AppTokens.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (location?.activeBooking != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '${location!.activeBooking!.bookingNumber} ${location.activeBooking!.status}',
                                                style: const TextStyle(
                                                  color: AppTokens.primaryDark,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                            if (location?.lastSeenAt != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '${l10n.t('admin_driver_last_seen')} ${location!.lastSeenAt}',
                                                style: const TextStyle(
                                                  color: AppTokens.textMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          if (location == null)
                                            AppUi.statusBadge(
                                              l10n.t('admin_driver_no_location'),
                                              tone: AppStatusTone.neutral,
                                            )
                                          else
                                            AppUi.statusBadge(
                                              location.stale
                                                  ? l10n.t('admin_driver_location_stale')
                                                  : l10n.t('admin_driver_location_live'),
                                              tone: location.stale
                                                  ? AppStatusTone.warning
                                                  : AppStatusTone.success,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
