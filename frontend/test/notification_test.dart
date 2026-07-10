import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/booking_notification_section.dart';
import 'package:frontend/features/driver/pages/driver_notifications_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/admin_notification/pages/admin_notification_queue_page.dart';
import 'package:frontend/features/admin_notification/services/admin_notification_api_service.dart';
import 'package:frontend/features/notification/services/notification_device_registration_service.dart';

void main() {
  testWidgets('guest booking notifications loading and list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            bookingId: 10,
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(),
            deviceRegistrationService: _FakeDeviceRegistrationService(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Trip completed'), findsOneWidget);
  });

  testWidgets('guest booking notifications empty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            bookingId: 10,
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(empty: true),
            deviceRegistrationService: _FakeDeviceRegistrationService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('No updates yet'), findsOneWidget);
  });

  testWidgets('guest booking notifications error retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(error: true),
            deviceRegistrationService: _FakeDeviceRegistrationService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('driver notification list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverNotificationsPage(
          api: _FakeDriverNotificationApi(),
          deviceRegistrationService: _FakeDeviceRegistrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Commission payment required'), findsOneWidget);
    expect(find.text('Settlement'), findsOneWidget);
  });

  testWidgets('driver chat notification opens driver chat page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverNotificationsPage(
          api: _FakeDriverNotificationApi(chatNotification: true),
          deviceRegistrationService: _FakeDeviceRegistrationService(),
          chatPageBuilder: (bookingNumber) =>
              Scaffold(body: Text('driver-chat:$bookingNumber')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    await tester.tap(find.text('New customer message'));
    await tester.pumpAndSettle();

    expect(find.text('driver-chat:TX202607010001'), findsOneWidget);
  });

  testWidgets('admin unread filter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminNotificationQueuePage(api: _FakeAdminNotificationApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unread only'), findsOneWidget);
    await tester.tap(find.text('Unread only'));
    await tester.pumpAndSettle();
    expect(_FakeAdminNotificationApi.lastUnreadOnly, isTrue);
  });

  testWidgets('admin mark all read', (tester) async {
    final api = _FakeAdminNotificationApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminNotificationQueuePage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(api.markAllCalls, 1);
  });

  testWidgets(
    'notification permission is not requested automatically on launch',
    (tester) async {
      final service = _FakeDeviceRegistrationService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminNotificationQueuePage(
              api: _FakeAdminNotificationApi(),
              deviceRegistrationService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.authEnableCalls, 0);
    },
  );

  testWidgets('admin enable notifications action reports success', (
    tester,
  ) async {
    final service = _FakeDeviceRegistrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminNotificationQueuePage(
            api: _FakeAdminNotificationApi(),
            deviceRegistrationService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable notifications'));
    await tester.pumpAndSettle();
    expect(service.authEnableCalls, 1);
    expect(find.text('Notifications enabled'), findsOneWidget);
  });

  testWidgets('guest enable notifications handles config missing', (
    tester,
  ) async {
    final service = _FakeDeviceRegistrationService(
      result: const NotificationDeviceRegistrationResult(
        NotificationDeviceRegistrationStatus.configMissing,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            bookingId: 10,
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(empty: true),
            deviceRegistrationService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable notifications'));
    await tester.pumpAndSettle();
    expect(service.guestEnableCalls, 1);
    expect(
      find.text('Push notifications are not configured for this environment'),
      findsOneWidget,
    );
  });
}

class _FakeDeviceRegistrationService
    extends NotificationDeviceRegistrationService {
  _FakeDeviceRegistrationService({
    this.result = const NotificationDeviceRegistrationResult(
      NotificationDeviceRegistrationStatus.registered,
    ),
  });

  final NotificationDeviceRegistrationResult result;
  int authEnableCalls = 0;
  int guestEnableCalls = 0;

  @override
  Future<NotificationDeviceRegistrationResult> enableAuthenticated({
    required Future<String?> Function() accessTokenLoader,
  }) async {
    authEnableCalls += 1;
    return result;
  }

  @override
  Future<NotificationDeviceRegistrationResult> enableGuest({
    required int? bookingId,
    required String? guestAccessToken,
  }) async {
    guestEnableCalls += 1;
    return result;
  }
}

class _FakeBookingNotificationApi extends BookingNotificationApi {
  _FakeBookingNotificationApi({this.empty = false, this.error = false});
  final bool empty;
  final bool error;

  @override
  Future<Map<String, dynamic>> listForBooking({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    if (error) throw const BookingNotificationApiException('Network error');
    if (empty) return {'items': []};
    return {
      'items': [
        {
          'notificationId': 1,
          'title': 'Trip completed',
          'body': 'Your trip has been completed.',
          'read': false,
        },
      ],
    };
  }
}

class _FakeDriverNotificationApi extends DriverApiService {
  _FakeDriverNotificationApi({this.chatNotification = false});

  final bool chatNotification;

  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async {
    if (chatNotification) {
      return {
        'items': [
          {
            'notificationId': 2,
            'notificationType': 'CHAT_MESSAGE',
            'title': 'New customer message',
            'body': 'Customer sent a message',
            'read': false,
            'payload': {'bookingNumber': 'TX202607010001'},
          },
        ],
      };
    }
    return {
      'items': [
        {
          'notificationId': 1,
          'notificationType': 'COMMISSION_PAYMENT_REQUIRED',
          'title': 'Commission payment required',
          'body': 'Please submit receipt',
          'read': false,
        },
      ],
    };
  }

  @override
  Future<void> markAllNotificationsRead() async {}

  @override
  Future<void> markNotificationRead(int notificationId) async {}
}

class _FakeAdminNotificationApi extends AdminNotificationApiService {
  _FakeAdminNotificationApi();
  static bool lastUnreadOnly = false;
  int markAllCalls = 0;

  @override
  Future<Map<String, dynamic>> listNotifications({
    bool? unreadOnly,
    String? notificationType,
  }) async {
    lastUnreadOnly = unreadOnly == true;
    return {
      'items': [
        {
          'notificationId': 1,
          'title': 'Receipt submitted',
          'body': 'Review needed',
          'read': false,
        },
      ],
    };
  }

  @override
  Future<void> markAllRead() async {
    markAllCalls += 1;
  }
}
