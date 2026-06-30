import 'package:flutter/material.dart';

import '../../notification/services/notification_device_registration_service.dart';
import '../services/admin_notification_api_service.dart';

class AdminNotificationQueuePage extends StatefulWidget {
  const AdminNotificationQueuePage({super.key, this.api, this.deviceRegistrationService});

  final AdminNotificationApiService? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;

  @override
  State<AdminNotificationQueuePage> createState() => _AdminNotificationQueuePageState();
}

class _AdminNotificationQueuePageState extends State<AdminNotificationQueuePage> {
  late final AdminNotificationApiService _api = widget.api ?? const AdminNotificationApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ?? NotificationDeviceRegistrationService();
  bool _loading = true;
  bool _markingAll = false;
  bool _enablingNotifications = false;
  String? _error;
  String? _pushStatus;
  List<dynamic> _items = [];
  bool _unreadOnly = false;
  String? _typeFilter;

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
      final data = await _api.listNotifications(
        unreadOnly: _unreadOnly,
        notificationType: _typeFilter,
      );
      setState(() {
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

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _api.markAllRead();
      await _load();
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      setState(() => _markingAll = false);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Unread only'),
                selected: _unreadOnly,
                onSelected: (v) {
                  setState(() => _unreadOnly = v);
                  _load();
                },
              ),
              DropdownButton<String?>(
                value: _typeFilter,
                hint: const Text('Type'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All types')),
                  DropdownMenuItem(value: 'BOOKING_CREATED', child: Text('Booking created')),
                  DropdownMenuItem(value: 'RECEIPT_SUBMITTED', child: Text('Receipt submitted')),
                  DropdownMenuItem(value: 'REVIEW_SUBMITTED', child: Text('Review submitted')),
                ],
                onChanged: (v) {
                  setState(() => _typeFilter = v);
                  _load();
                },
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ElevatedButton(
                onPressed: _markingAll ? null : _markAll,
                child: Text(_markingAll ? 'Marking...' : 'Mark all read'),
              ),
              OutlinedButton.icon(
                onPressed: _enablingNotifications ? null : _enableNotifications,
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(_enablingNotifications ? 'Enabling...' : 'Enable notifications'),
              ),
              if (_pushStatus != null) Text(_pushStatus!),
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
                          ElevatedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : _items.isEmpty
                      ? const Center(child: Text('No notifications'))
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
                                        onPressed: () async {
                                          await _api.markRead(item['notificationId'] as int);
                                          await _load();
                                        },
                                      ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
