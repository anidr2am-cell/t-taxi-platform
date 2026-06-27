import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/booking_notification_section.dart';
import 'package:frontend/features/driver/pages/driver_notifications_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/admin_notification/pages/admin_notification_queue_page.dart';
import 'package:frontend/features/admin_notification/services/admin_notification_api_service.dart';

void main() {
  testWidgets('guest booking notifications loading and list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(),
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
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(empty: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Updates'), findsNothing);
  });

  testWidgets('guest booking notifications error retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingNotificationSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: _FakeBookingNotificationApi(error: true),
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
        home: DriverNotificationsPage(api: _FakeDriverNotificationApi()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Commission payment required'), findsOneWidget);
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
        home: Scaffold(
          body: AdminNotificationQueuePage(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(api.markAllCalls, 1);
  });
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
  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async {
    return {
      'items': [
        {
          'notificationId': 1,
          'title': 'Commission payment required',
          'body': 'Please submit receipt',
          'read': false,
        },
      ],
    };
  }

  @override
  Future<void> markAllNotificationsRead() async {}
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
