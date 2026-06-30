import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_status.dart';
import '../services/driver_api_service.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key, this.api, this.deviceRegistrationService});

  final DriverApiService? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ?? NotificationDeviceRegistrationService();
  Future<Map<String, dynamic>>? _ratingFuture;
  Future<DriverStatus>? _statusFuture;
  bool _statusUpdating = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _ratingFuture = _api.getRatingSummary();
    _statusFuture = _api.getStatus();
  }

  void _refreshStatus() {
    setState(() {
      _statusFuture = _api.getStatus();
      _statusError = null;
    });
  }

  Future<void> _setOnlineState(bool online, DriverStatus? current) async {
    if (_statusUpdating) return;
    if (!online && current?.hasActiveJob == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Go offline?'),
          content: const Text('You have an active job. Going offline is blocked until the job is finished.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Try anyway')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _statusUpdating = true;
      _statusError = null;
    });
    try {
      final next = online ? await _api.goOnline() : await _api.goOffline();
      if (!mounted) return;
      setState(() {
        _statusFuture = Future.value(next);
        _statusUpdating = false;
      });
    } catch (err) {
      if (!mounted) return;
      if (driverIsAuthError(err)) {
        driverHandleApiError(context, err);
        return;
      }
      setState(() {
        _statusUpdating = false;
        _statusError = err.toString();
        _statusFuture = _api.getStatus();
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _deviceRegistration.deactivateAuthenticated(
        accessTokenLoader: _api.getSavedToken,
      );
    } catch (_) {
      // Push cleanup is best effort; never block logout.
    }
    await _api.logout();
    if (!mounted) return;
    driverRedirectToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_nav_profile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _ratingFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Card(
                  child: ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('…'),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    title: Text(l10n.t('driver_rating_error')),
                    subtitle: Text(snapshot.error.toString()),
                  ),
                );
              }
              final rating = snapshot.data ?? {};
              final avg = rating['averageRating'];
              final count = rating['reviewCount'] ?? 0;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber, size: 32),
                  title: Text(
                    avg == null
                        ? l10n.t('driver_no_ratings')
                        : '$avg ${l10n.t('driver_rating_average')}',
                  ),
                  subtitle: Text('$count ${l10n.t('driver_rating_count')}'),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<DriverStatus>(
            future: _statusFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Card(
                  child: ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('Loading driver status'),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Driver status unavailable'),
                    subtitle: Text(snapshot.error.toString()),
                    trailing: IconButton(
                      onPressed: _refreshStatus,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              }
              final status = snapshot.data;
              final online = status?.online == true;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            online ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: online ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              online ? 'Online' : 'Offline',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(status?.status ?? 'OFFLINE'),
                        ],
                      ),
                      if (status?.lastSeenAt != null) ...[
                        const SizedBox(height: 6),
                        Text('Last seen ${status!.lastSeenAt}'),
                      ],
                      if (_statusError != null) ...[
                        const SizedBox(height: 8),
                        Text(_statusError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 12),
                      if (_statusUpdating) const LinearProgressIndicator(),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _statusUpdating || online
                                  ? null
                                  : () => _setOnlineState(true, status),
                              child: const Text('Go online'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _statusUpdating || !online
                                  ? null
                                  : () => _setOnlineState(false, status),
                              child: const Text('Go offline'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(l10n.t('driver_logout')),
            ),
          ),
        ],
      ),
    );
  }
}
