import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../config/app_config.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../../../utils/user_facing_error.dart';
import '../../booking/widgets/booking_review_form.dart';

class BookingNotificationApi {
  const BookingNotificationApi();

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  Future<Map<String, dynamic>> listForBooking({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final uri = Uri.parse('$_base/bookings/$bookingNumber/notifications');
    final headers = <String, String>{'Accept': 'application/json'};
    if (customerAccessToken != null && customerAccessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerAccessToken';
    }
    if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      headers['X-Guest-Access-Token'] = guestAccessToken;
    }
    final response = await http.get(uri, headers: headers);
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw BookingNotificationApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
      );
    }
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }
}

class BookingNotificationApiException implements Exception {
  const BookingNotificationApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BookingNotificationSection extends StatefulWidget {
  const BookingNotificationSection({
    super.key,
    required this.bookingNumber,
    this.bookingId,
    this.guestAccessToken,
    this.api,
    this.deviceRegistrationService,
  });

  final String bookingNumber;
  final int? bookingId;
  final String? guestAccessToken;
  final BookingNotificationApi? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;

  @override
  State<BookingNotificationSection> createState() => _BookingNotificationSectionState();
}

class _BookingNotificationSectionState extends State<BookingNotificationSection> {
  late final BookingNotificationApi _api = widget.api ?? const BookingNotificationApi();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ?? NotificationDeviceRegistrationService();
  bool _loading = true;
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
      final token = widget.guestAccessToken
          ?? await const BookingReviewApi().loadGuestToken(widget.bookingNumber);
      final data = await _api.listForBooking(
        bookingNumber: widget.bookingNumber,
        guestAccessToken: token,
      );
      setState(() {
        _items = data['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(err, fallback: 'Could not load notifications');
        _loading = false;
      });
    }
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications) return;
    setState(() {
      _enablingNotifications = true;
      _pushStatus = null;
    });
    final token = widget.guestAccessToken
        ?? await const BookingReviewApi().loadGuestToken(widget.bookingNumber);
    final result = await _deviceRegistration.enableGuest(
      bookingId: widget.bookingId,
      guestAccessToken: token,
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Updates', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: _enablingNotifications ? null : _enableNotifications,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(_enablingNotifications ? 'Enabling...' : 'Enable notifications'),
                ),
              ],
            ),
            if (_pushStatus != null) ...[
              const SizedBox(height: 4),
              Text(_pushStatus!),
            ],
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const Text('No updates yet')
            else
              ..._items.take(5).map((item) {
                final map = Map<String, dynamic>.from(item as Map);
                final read = map['read'] == true;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    map['title'] as String? ?? 'Notification',
                    style: TextStyle(
                      fontWeight: read ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(map['body'] as String? ?? ''),
                );
              }),
          ],
        ),
      ),
    );
  }
}
