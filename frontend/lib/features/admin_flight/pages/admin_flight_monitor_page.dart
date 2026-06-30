import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_dispatch/pages/admin_booking_detail_page.dart';
import '../../admin_dispatch/services/admin_dispatch_api_service.dart';
import '../services/admin_flight_api_service.dart';

class AdminFlightMonitorPage extends StatefulWidget {
  const AdminFlightMonitorPage({super.key, this.api, this.dispatchApi});

  final AdminFlightApiService? api;
  final AdminDispatchApiService? dispatchApi;

  @override
  State<AdminFlightMonitorPage> createState() => _AdminFlightMonitorPageState();
}

class _AdminFlightMonitorPageState extends State<AdminFlightMonitorPage> {
  late final AdminFlightApiService _api =
      widget.api ?? const AdminFlightApiService();
  late final AdminDispatchApiService _dispatchApi =
      widget.dispatchApi ?? const AdminDispatchApiService();

  final _flightSearchController = TextEditingController();
  final _bookingSearchController = TextEditingController();

  bool _loading = true;
  bool _statusLoading = true;
  bool _runningCycle = false;
  String? _error;
  String? _statusError;
  Map<String, dynamic>? _syncStatus;
  List<dynamic> _items = [];
  int _page = 1;
  int _total = 0;
  String? _dateFilter;
  bool _delayedOnly = false;
  final Set<int> _syncingBookingIds = {};

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
    _load();
  }

  @override
  void dispose() {
    _flightSearchController.dispose();
    _bookingSearchController.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = page == 1;
      _error = null;
    });
    try {
      final data = await _api.listFlights(
        date: _dateFilter,
        flightNumber: _flightSearchController.text.trim(),
        bookingNumber: _bookingSearchController.text.trim(),
        delayedOnly: _delayedOnly,
        page: page,
      );
      setState(() {
        _page = data['page'] as int? ?? page;
        _total = data['total'] as int? ?? 0;
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  Future<void> _loadSyncStatus() async {
    setState(() {
      _statusLoading = true;
      _statusError = null;
    });
    try {
      final status = await _api.getSyncStatus();
      setState(() {
        _syncStatus = status;
        _statusLoading = false;
      });
    } catch (err) {
      setState(() {
        _statusError = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _statusLoading = false;
      });
    }
  }

  Future<void> _runSyncCycle() async {
    if (_runningCycle) return;
    setState(() => _runningCycle = true);
    try {
      await _api.runSyncCycle();
      await Future.wait([_loadSyncStatus(), _load()]);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) setState(() => _runningCycle = false);
    }
  }

  Future<void> _pickDate() async {
    final initial = _dateFilter != null ? DateTime.tryParse(_dateFilter!) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _dateFilter =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
    await _load();
  }

  Future<void> _syncItem(Map<String, dynamic> item) async {
    final bookingId = item['bookingId'] as int?;
    if (bookingId == null || _syncingBookingIds.contains(bookingId)) return;
    setState(() => _syncingBookingIds.add(bookingId));
    try {
      final updated = await _api.syncFlight(bookingId);
      setState(() {
        final index = _items.indexWhere((row) => row['bookingId'] == bookingId);
        if (index >= 0) _items[index] = updated;
      });
      if (!mounted) return;
      final syncStatus = updated['syncStatus'] as String?;
      final syncError = updated['syncError'] as String?;
      if (syncStatus == 'NOT_CONFIGURED' || syncError == 'CONFIG_MISSING') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('admin_flight_provider_missing'))),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingBookingIds.remove(bookingId));
      }
    }
  }

  Future<void> _openBooking(Map<String, dynamic> item) async {
    final bookingNumber = item['bookingNumber'] as String?;
    if (bookingNumber == null || bookingNumber.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _dispatchApi,
          onChanged: _load,
        ),
      ),
    );
  }

  String _text(dynamic value) => value == null ? '-' : '$value';

  double _filterFieldWidth(BuildContext context, double desktopWidth) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return desktopWidth;
    if (width >= 768) return (width - 96) / 2;
    return width - (AppTokens.spaceMd * 2);
  }

  String _cycleSummary(Map<String, dynamic>? cycle) {
    if (cycle == null) return 'No cycle yet';
    return 'selected ${_text(cycle['selected'])} · success ${_text(cycle['succeeded'])} · failed ${_text(cycle['failed'])} · skipped ${_text(cycle['skipped'])}';
  }

  Widget _syncStatusPanel() {
    final l10n = context.l10n;

    if (_statusLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceMd),
        child: LinearProgressIndicator(),
      );
    }
    if (_statusError != null) {
      return Padding(
        padding: AppUi.pagePadding(context).copyWith(bottom: 0),
        child: AppUi.errorState(
          message: '${l10n.t('admin_flight_sync_unavailable')}\n$_statusError',
          onRetry: _loadSyncStatus,
          retryLabel: l10n.t('admin_dispatch_retry'),
        ),
      );
    }

    final status = _syncStatus ?? {};
    final lastCycle = status['lastCycle'] is Map
        ? Map<String, dynamic>.from(status['lastCycle'] as Map)
        : null;
    final enabled = status['enabled'] == true;
    final providerConfigured = status['providerConfigured'] == true;
    final running = status['running'] == true || _runningCycle;

    return Padding(
      padding: AppUi.pagePadding(context).copyWith(bottom: 0),
      child: AppUi.surfaceCard(
        backgroundColor: AppTokens.primaryLight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    l10n.t('admin_flight_sync_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTokens.primaryDark,
                    ),
                  ),
                ),
                if (running)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  tooltip: l10n.t('admin_dashboard_refresh'),
                  onPressed: _loadSyncStatus,
                  icon: const Icon(Icons.refresh),
                ),
                OutlinedButton(
                  onPressed: running ? null : _runSyncCycle,
                  child: Text(running ? l10n.t('admin_flight_running') : l10n.t('admin_flight_run_sync')),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                AppUi.statusBadge(
                  enabled ? l10n.t('admin_flight_worker_enabled') : l10n.t('admin_flight_worker_disabled'),
                  tone: enabled ? AppStatusTone.success : AppStatusTone.neutral,
                ),
                AppUi.statusBadge(
                  providerConfigured
                      ? l10n.t('admin_flight_provider_configured')
                      : l10n.t('admin_flight_provider_not_configured'),
                  tone: providerConfigured ? AppStatusTone.success : AppStatusTone.warning,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n
                  .t('admin_flight_last_completed')
                  .replaceAll('{value}', _text(status['lastCycleCompletedAt'])),
            ),
            Text(_cycleSummary(lastCycle)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      children: [
        _syncStatusPanel(),
        AppUi.adminFilterBar(
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(_dateFilter ?? l10n.t('admin_flight_date')),
            ),
            if (_dateFilter != null)
              TextButton(
                onPressed: () {
                  setState(() => _dateFilter = null);
                  _load();
                },
                child: Text(l10n.t('admin_flight_clear_date')),
              ),
            SizedBox(
              width: _filterFieldWidth(context, 160),
              child: TextField(
                controller: _flightSearchController,
                decoration: InputDecoration(
                  labelText: l10n.t('admin_flight_flight_number'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _load(),
              ),
            ),
            SizedBox(
              width: _filterFieldWidth(context, 180),
              child: TextField(
                controller: _bookingSearchController,
                decoration: InputDecoration(
                  labelText: l10n.t('admin_flight_booking_number'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            FilterChip(
              label: Text(l10n.t('admin_flight_delayed_only')),
              selected: _delayedOnly,
              onSelected: (value) {
                setState(() => _delayedOnly = value);
                _load();
              },
            ),
            IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
          ],
        ),
        Expanded(
          child: _loading
              ? AppUi.loadingState()
              : _error != null
                  ? AppUi.errorState(
                      message: _error!,
                      onRetry: () => _load(),
                      retryLabel: l10n.t('admin_dispatch_retry'),
                    )
                  : _items.isEmpty
                      ? AppUi.emptyState(
                          title: l10n.t('admin_flight_empty'),
                          icon: Icons.flight_land_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.separated(
                            padding: AppUi.pagePadding(context),
                            itemCount: _items.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: AppTokens.spaceSm),
                            itemBuilder: (context, index) {
                              final item = _items[index] as Map<String, dynamic>;
                              final bookingId = item['bookingId'] as int?;
                              final syncing = bookingId != null &&
                                  _syncingBookingIds.contains(bookingId);
                              final flightStatus =
                                  item['flightStatus'] as String? ?? '';
                              final delayMinutes = item['delayMinutes'] as num? ?? 0;

                              return AppUi.adminQueueCard(
                                onTap: () => _openBooking(item),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: AppTokens.spaceSm,
                                      runSpacing: AppTokens.spaceSm,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          '${_text(item['bookingNumber'])} · ${_text(item['flightNumber'])}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        AppUi.statusBadge(
                                          flightStatus.isEmpty ? 'UNKNOWN' : flightStatus,
                                          tone: AppUi.toneForFlightRowStatus(flightStatus),
                                        ),
                                        if (delayMinutes > 0)
                                          AppUi.statusBadge(
                                            l10n
                                                .t('admin_flight_delay_minutes')
                                                .replaceAll('{minutes}', '$delayMinutes'),
                                            tone: AppStatusTone.warning,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: AppTokens.spaceSm),
                                    AppUi.summaryRow(
                                      label: l10n.t('admin_flight_route'),
                                      value:
                                          '${_text(item['departureAirportIata'])} → ${_text(item['arrivalAirportIata'])}',
                                    ),
                                    AppUi.summaryRow(
                                      label: l10n.t('admin_flight_pickup'),
                                      value: _text(item['scheduledPickupAt']),
                                    ),
                                    Text(
                                      l10n
                                          .t('admin_flight_sync_line')
                                          .replaceAll('{status}', _text(item['syncStatus']))
                                          .replaceAll('{last}', _text(item['lastSyncedAt'])),
                                      style: const TextStyle(
                                        color: AppTokens.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (item['syncError'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          l10n
                                              .t('admin_flight_sync_error')
                                              .replaceAll('{message}', '${item['syncError']}'),
                                          style: const TextStyle(
                                            color: AppTokens.error,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: AppTokens.spaceSm),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          tooltip: 'Open booking',
                                          onPressed: () => _openBooking(item),
                                          icon: const Icon(Icons.open_in_new),
                                        ),
                                        syncing
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : IconButton(
                                                tooltip: 'Sync flight',
                                                onPressed: () => _syncItem(item),
                                                icon: const Icon(Icons.sync),
                                              ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceSm),
            child: Text(
              'Page $_page · Total $_total',
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ),
      ],
    );
  }
}
