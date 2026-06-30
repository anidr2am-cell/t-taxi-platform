import 'package:flutter/material.dart';

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
        _error = err.toString();
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
        _statusError = err.toString();
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
          SnackBar(content: Text(err.toString())),
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
          const SnackBar(content: Text('Flight provider is not configured')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.toString())),
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

  String _cycleSummary(Map<String, dynamic>? cycle) {
    if (cycle == null) return 'No cycle yet';
    return 'selected ${_text(cycle['selected'])} · success ${_text(cycle['succeeded'])} · failed ${_text(cycle['failed'])} · skipped ${_text(cycle['skipped'])}';
  }

  Widget _syncStatusPanel() {
    if (_statusLoading) {
      return const LinearProgressIndicator();
    }
    if (_statusError != null) {
      return ListTile(
        title: const Text('Automatic flight sync status unavailable'),
        subtitle: Text(_statusError!),
        trailing: IconButton(
          tooltip: 'Refresh worker status',
          onPressed: _loadSyncStatus,
          icon: const Icon(Icons.refresh),
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Automatic flight sync',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (running)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  tooltip: 'Refresh worker status',
                  onPressed: _loadSyncStatus,
                  icon: const Icon(Icons.refresh),
                ),
                OutlinedButton(
                  onPressed: running ? null : _runSyncCycle,
                  child: Text(running ? 'Running' : 'Run sync cycle'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Worker: ${enabled ? 'Enabled' : 'Disabled'} · Provider: ${providerConfigured ? 'Configured' : 'Not configured'}'),
            Text('Last completed: ${_text(status['lastCycleCompletedAt'])}'),
            Text(_cycleSummary(lastCycle)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _syncStatusPanel(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_dateFilter ?? 'Date'),
              ),
              if (_dateFilter != null)
                TextButton(
                  onPressed: () {
                    setState(() => _dateFilter = null);
                    _load();
                  },
                  child: const Text('Clear date'),
                ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _flightSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Flight number',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _bookingSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Booking number',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              FilterChip(
                label: const Text('Delayed only'),
                selected: _delayedOnly,
                onSelected: (value) {
                  setState(() => _delayedOnly = value);
                  _load();
                },
              ),
              IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          ElevatedButton(onPressed: () => _load(), child: const Text('Retry')),
                        ],
                      ),
                    )
                  : _items.isEmpty
                      ? const Center(child: Text('No airport pickup flights found'))
                      : RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _items.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _items[index] as Map<String, dynamic>;
                              final bookingId = item['bookingId'] as int?;
                              final syncing = bookingId != null &&
                                  _syncingBookingIds.contains(bookingId);
                              return ListTile(
                                title: Text(
                                  '${_text(item['bookingNumber'])} · ${_text(item['flightNumber'])}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_text(item['departureAirportIata'])} → ${_text(item['arrivalAirportIata'])}',
                                    ),
                                    Text('Pickup: ${_text(item['scheduledPickupAt'])}'),
                                    Text('Scheduled arrival: ${_text(item['scheduledArrivalAt'])}'),
                                    Text('Estimated arrival: ${_text(item['estimatedArrivalAt'])}'),
                                    Text('Actual arrival: ${_text(item['actualArrivalAt'])}'),
                                    Text(
                                      'Delay: ${_text(item['delayMinutes'])} min · Status: ${_text(item['flightStatus'])}',
                                    ),
                                    Text(
                                      'Sync: ${_text(item['syncStatus'])} · Last: ${_text(item['lastSyncedAt'])}',
                                    ),
                                    if (item['syncError'] != null)
                                      Text('Sync error: ${item['syncError']}'),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: Wrap(
                                  spacing: 4,
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
                              );
                            },
                          ),
                        ),
        ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Page $_page · Total $_total'),
          ),
      ],
    );
  }
}
