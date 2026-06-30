import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_location.dart';
import '../services/driver_location_api_service.dart';
import '../services/driver_location_socket_service.dart';
import '../widgets/driver_location_map.dart';

class AdminDriverMonitorPage extends StatefulWidget {
  const AdminDriverMonitorPage({
    super.key,
    this.api,
    this.socket,
  });

  final DriverLocationApiService? api;
  final DriverLocationSocketService? socket;

  @override
  State<AdminDriverMonitorPage> createState() => _AdminDriverMonitorPageState();
}

class _AdminDriverMonitorPageState extends State<AdminDriverMonitorPage> {
  bool _loading = true;
  bool _onlineOnly = true;
  bool _activeJobOnly = false;
  bool _staleOnly = false;
  String? _error;
  List<DriverLocation> _items = [];
  DriverLocation? _selected;
  late final DriverLocationApiService _api = widget.api ?? DriverLocationApiService();
  late final DriverLocationSocketService _socket = widget.socket ?? DriverLocationSocketService();

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
        final index = _items.indexWhere((item) => item.driverId == next.driverId);
        if (index >= 0) {
          _items[index] = next;
        } else {
          _items = [next, ..._items];
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
      final items = await _api.listAdminLocations(
        onlineOnly: _onlineOnly,
        activeJobOnly: _activeJobOnly,
        staleOnly: _staleOnly,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Driver Monitor', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Icon(_socket.connected ? Icons.cloud_done : Icons.cloud_off, size: 18),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Online only'),
                selected: _onlineOnly,
                onSelected: (value) => _toggle(() => _onlineOnly = value),
              ),
              FilterChip(
                label: const Text('Active jobs'),
                selected: _activeJobOnly,
                onSelected: (value) => _toggle(() => _activeJobOnly = value),
              ),
              FilterChip(
                label: const Text('Stale'),
                selected: _staleOnly,
                onSelected: (value) => _toggle(() => _staleOnly = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing: TextButton(onPressed: _load, child: const Text('Retry')),
              ),
            )
          else
            DriverLocationMap(
              locations: _items,
              height: 320,
              onTapLocation: (location) => setState(() => _selected = location),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('No active driver locations'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final selected = _selected?.driverId == item.driverId;
                      return Card(
                        color: selected ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
                        child: ListTile(
                          leading: Icon(item.stale ? Icons.location_off : Icons.location_on),
                          title: Text(item.displayName),
                          subtitle: Text([
                            if (item.vehicle != null) item.vehicle!,
                            if (item.activeBooking != null)
                              '${item.activeBooking!.bookingNumber} ${item.activeBooking!.status}',
                            if (item.lastSeenAt != null) 'Updated ${item.lastSeenAt}',
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: item.stale ? const Text('Stale') : const Text('Live'),
                          onTap: () => setState(() => _selected = item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
