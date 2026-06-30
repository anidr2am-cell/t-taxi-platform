import 'package:flutter/material.dart';

import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/driver_location.dart';
import '../services/driver_location_api_service.dart';
import '../services/driver_location_socket_service.dart';
import 'driver_location_map.dart';

class GuestDriverTrackingSection extends StatefulWidget {
  const GuestDriverTrackingSection({
    super.key,
    required this.bookingId,
    required this.guestAccessToken,
    required this.bookingStatus,
    this.api,
    this.socket,
  });

  final int bookingId;
  final String guestAccessToken;
  final String bookingStatus;
  final DriverLocationApiService? api;
  final DriverLocationSocketService? socket;

  @override
  State<GuestDriverTrackingSection> createState() => _GuestDriverTrackingSectionState();
}

class _GuestDriverTrackingSectionState extends State<GuestDriverTrackingSection> {
  bool _loading = true;
  String? _error;
  GuestDriverLocationResult? _result;
  late final DriverLocationApiService _api = widget.api ?? DriverLocationApiService();
  late final DriverLocationSocketService _socket = widget.socket ?? DriverLocationSocketService();

  bool get _trackable => const {'DRIVER_ASSIGNED', 'DRIVER_ARRIVED', 'PICKED_UP'}
      .contains(widget.bookingStatus);

  @override
  void initState() {
    super.initState();
    if (_trackable) {
      _load();
      _connectSocket();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _socket.disconnect();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    _socket.onGuestChanged = (payload) {
      if (payload['bookingId'] != widget.bookingId) return;
      setState(() {
        _result = GuestDriverLocationResult.fromJson(payload);
      });
    };
    _socket.onStateChanged = () {
      if (mounted) setState(() {});
    };
    await _socket.connect(guestAccessToken: widget.guestAccessToken);
    _socket.subscribeGuest(widget.bookingId);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.getGuestDriverLocation(
        bookingId: widget.bookingId,
        guestAccessToken: widget.guestAccessToken,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(err, fallback: 'Could not load driver location');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_trackable) return const SizedBox.shrink();
    final driver = _result?.driver;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.local_taxi),
                Text('Track driver', style: Theme.of(context).textTheme.titleMedium),
                Icon(_socket.connected ? Icons.cloud_done : Icons.cloud_off, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              AppUi.errorState(message: _error!, onRetry: _load, retryLabel: 'Retry')
            else if (_result?.available != true || driver == null)
              const Text('Driver location is not available yet.')
            else ...[
              DriverLocationMap(locations: [driver], height: 220),
              const SizedBox(height: 12),
              Text(driver.displayName, style: Theme.of(context).textTheme.titleSmall),
              if (driver.vehicle != null) Text(driver.vehicle!),
              Text(driver.stale ? 'Location may be stale' : 'Location is live'),
              if (driver.lastSeenAt != null) Text('Updated ${driver.lastSeenAt}'),
            ],
          ],
        ),
      ),
    );
  }
}
