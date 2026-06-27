import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/booking_chat_api.dart';
import 'package:frontend/features/chat/models/chat_connection_state.dart';
import 'package:frontend/features/chat/services/chat_socket_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class _FakeBookingChatApi extends BookingChatApi {
  @override
  Future<Map<String, dynamic>> getRoom({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async =>
      {'roomId': 1, 'sendingAllowed': true, 'unreadCount': 0};

  @override
  Future<List<dynamic>> listMessages({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async =>
      [];
}

class _FakeChatSocketService extends ChatSocketService {
  @override
  io.Socket connect({
    String? accessToken,
    String? guestAccessToken,
  }) {
    debugSetConnectionState(ChatConnectionState.connected);
    return io.io(
      'http://localhost:0',
      io.OptionBuilder().disableAutoConnect().build(),
    );
  }

  @override
  void joinRoom(
    String bookingNumber, {
    void Function(Map<String, dynamic> room)? onJoined,
  }) {
    debugMarkJoined(bookingNumber, 1);
    onJoined?.call({'roomId': 1, 'sendingAllowed': true, 'unreadCount': 0});
  }
}

void main() {
  testWidgets('boarding QR is shown before pickup', (tester) async {
    await tester.pumpWidget(_wrap(_page()));

    expect(find.text('Boarding QR'), findsOneWidget);
    expect(find.text('Dropoff QR'), findsNothing);
  });

  testWidgets('dropoff QR is unavailable before PICKED_UP', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _page(
          issueDropoffQr: () async => throw BookingApiException(
            'Dropoff QR can only be issued after pickup',
            'INVALID_STATUS_TRANSITION',
          ),
        ),
      ),
    );

    await _scrollToText(tester, 'Refresh dropoff QR');
    await tester.tap(find.text('Refresh dropoff QR'));
    await tester.pumpAndSettle();

    expect(find.text('Boarding QR'), findsOneWidget);
    expect(find.text('Dropoff QR'), findsNothing);
    expect(
      find.text(
        'Dropoff QR is available after pickup and before trip completion.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('dropoff QR loads after PICKED_UP', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _page(
          issueDropoffQr: () async => const DropoffQrIssueResult(
            bookingNumber: 'TX202607010001',
            status: 'PICKED_UP',
            dropoffQrToken: 'dropoff-token',
            dropoffQrExpiresAt: '2099-01-01 00:00:00',
          ),
        ),
      ),
    );

    await _scrollToText(tester, 'Refresh dropoff QR');
    await tester.tap(find.text('Refresh dropoff QR'));
    await tester.pumpAndSettle();

    expect(find.text('Dropoff QR'), findsOneWidget);
    expect(
      find.text('Show this QR to your driver at destination.'),
      findsOneWidget,
    );
    expect(find.text('Issue new dropoff QR'), findsOneWidget);
  });

  testWidgets('issue error supports retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _wrap(
        _page(
          issueDropoffQr: () async {
            attempts += 1;
            if (attempts == 1) {
              throw BookingApiException(
                'Temporary issue failed',
                'EXTERNAL_API_ERROR',
              );
            }
            return const DropoffQrIssueResult(
              bookingNumber: 'TX202607010001',
              status: 'PICKED_UP',
              dropoffQrToken: 'dropoff-token',
              dropoffQrExpiresAt: '2099-01-01 00:00:00',
            );
          },
        ),
      ),
    );

    await _scrollToText(tester, 'Refresh dropoff QR');
    await tester.tap(find.text('Refresh dropoff QR'));
    await tester.pumpAndSettle();
    expect(find.text('Temporary issue failed'), findsOneWidget);

    await _scrollToText(tester, 'Refresh dropoff QR');
    await tester.tap(find.text('Refresh dropoff QR'));
    await tester.pumpAndSettle();
    expect(find.text('Dropoff QR'), findsOneWidget);
  });

  testWidgets('completed state hides active QR', (tester) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'COMPLETED'))));

    expect(find.text('Trip completed'), findsOneWidget);
    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('Dropoff QR'), findsNothing);
    expect(find.text('Refresh dropoff QR'), findsNothing);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

BookingCompletePage _page({
  BookingCreateResult? result,
  Future<DropoffQrIssueResult> Function()? issueDropoffQr,
}) {
  return BookingCompletePage(
    result: result ?? _result(),
    serviceLabel: 'Airport Pickup',
    originLabel: 'BKK Airport',
    destinationLabel: 'Pattaya Hotel',
    issueDropoffQr: issueDropoffQr,
    chatApi: _FakeBookingChatApi(),
    chatSocketService: _FakeChatSocketService(),
  );
}

BookingCreateResult _result({String status = 'PENDING'}) {
  return BookingCreateResult(
    bookingNumber: 'TX202607010001',
    status: status,
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    chatRoomCode: 'CHAT-TX202607010001',
    boardingQrToken: 'boarding-token',
    trustMessage: 'Booking received',
  );
}
