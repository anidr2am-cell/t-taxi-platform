import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../pages/driver_booking_detail_page.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../services/driver_api_service.dart';

class DriverNotificationsPage extends StatefulWidget {
  const DriverNotificationsPage({super.key, this.api, this.deviceRegistrationService});

  final DriverApiService? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;

  @override
  State<DriverNotificationsPage> createState() => _DriverNotificationsPageState();
}

class _DriverNotificationsPageState extends State<DriverNotificationsPage> {
  late final DriverApiService _api = widget.api ?? const DriverApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ?? NotificationDeviceRegistrationService();
  bool _loading = true;
  bool _markingAll = false;
  bool _enablingNotifications = false;
  String? _error;
  String? _pushStatus;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.listNotifications();
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      if (driverIsAuthError(err) && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) driverHandleApiError(context, err);
        });
      }
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _api.markAllNotificationsRead();
      await _load();
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      setState(() => _markingAll = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await _api.markNotificationRead(id);
      await _load();
    } catch (err) {
      setState(() => _error = err.toString());
    }
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications) return;
    setState(() {
      _enablingNotifications = true;
      _pushStatus = null;
    });
    final result = await _deviceRegistration.enableAuthenticated(
      accessTokenLoader: _api.getSavedToken,
    );
    setState(() {
      _pushStatus = _messageForPushResult(result);
      _enablingNotifications = false;
    });
  }

  String _messageForPushResult(NotificationDeviceRegistrationResult result) {
    switch (result.status) {
      case NotificationDeviceRegistrationStatus.registered:
        return 'Notifications enabled';
      case NotificationDeviceRegistrationStatus.permissionDenied:
        return 'Notification permission was denied';
      case NotificationDeviceRegistrationStatus.unsupported:
        return 'Push notifications are not supported in this browser';
      case NotificationDeviceRegistrationStatus.configMissing:
        return 'Push notifications are not configured for this environment';
      case NotificationDeviceRegistrationStatus.failed:
        return result.message ?? 'Notification registration failed';
    }
  }

  void _openTarget(Map<String, dynamic> item) {
    final payload = Map<String, dynamic>.from(
      item['payload'] as Map? ?? {},
    );
    final bookingNumber = payload['bookingNumber'] as String?;
    final type = item['notificationType'] as String? ?? '';

    if (bookingNumber != null && bookingNumber.isNotEmpty) {
      if (type.contains('COMMISSION') ||
          type.contains('RECEIPT') ||
          type.contains('SETTLEMENT')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverSettlementDetailPage(
              bookingNumber: bookingNumber,
              api: const DriverSettlementApiService(),
            ),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverBookingDetailPage(
              bookingNumber: bookingNumber,
              api: _api,
            ),
          ),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('driver_notification_no_target'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('driver_nav_notifications')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _enablingNotifications ? null : _enableNotifications,
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Enable notifications',
          ),
          IconButton(
            onPressed: _markingAll ? null : _markAll,
            icon: const Icon(Icons.done_all),
            tooltip: l10n.t('driver_mark_all_read'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      ElevatedButton(
                        onPressed: _load,
                        child: Text(l10n.t('driver_retry')),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_pushStatus != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(_pushStatus!),
                      ),
                    Expanded(
                      child: _items.isEmpty
                          ? Center(child: Text(l10n.t('driver_notifications_empty')))
                          : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(_items[index] as Map);
                          final read = item['read'] == true;
                          return ListTile(
                            title: Text(
                              item['title'] as String? ?? 'Notification',
                              style: TextStyle(
                                fontWeight: read ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(item['body'] as String? ?? ''),
                            trailing: read
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.check),
                                    onPressed: () => _markRead(item['notificationId'] as int),
                                  ),
                            onTap: () {
                              if (!read) {
                                _markRead(item['notificationId'] as int);
                              }
                              _openTarget(item);
                            },
                          );
                        },
                      ),
                    ),
                    ),
                  ],
                ),
    );
  }
}
