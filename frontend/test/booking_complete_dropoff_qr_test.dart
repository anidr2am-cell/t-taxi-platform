import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_complete_review.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
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
  }) async => {'roomId': 1, 'sendingAllowed': true, 'unreadCount': 0};

  @override
  Future<List<dynamic>> listMessages({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async => [];
}

class _FakeChatSocketService extends ChatSocketService {
  @override
  io.Socket connect({String? accessToken, String? guestAccessToken}) {
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
  testWidgets('customer tools enabled before assignment keeps chat hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_page()));

    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('Ride completion QR'), findsNothing);
    expect(find.text('Refresh dropoff QR'), findsNothing);
    expect(find.text('Issue new dropoff QR'), findsNothing);
    expect(find.text('Booking chat'), findsNothing);
  });

  testWidgets('customer tools keep driver chat hidden after assignment', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'ON_ROUTE'))));

    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('Ride completion QR'), findsNothing);
    expect(find.text('Booking chat'), findsNothing);
  });

  testWidgets('completed state shows completion message without QR', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'COMPLETED'))));

    expect(find.text('Trip completed'), findsOneWidget);
    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('Ride completion QR'), findsNothing);
  });

  testWidgets('completed booking with token and no review shows review form', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'COMPLETED'))));

    expect(find.text('Trip completed'), findsOneWidget);
    expect(find.text('How was your ride?'), findsOneWidget);
    expect(find.text('Submit rating'), findsOneWidget);
  });

  testWidgets('completed booking with existing review hides submit form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _page(
          result: _result(status: 'COMPLETED'),
          review: const BookingCompleteReview(
            customerName: 'Kim',
            customerPhone: '+66123456789',
          ),
        ),
      ),
    );

    expect(find.text('Kim'), findsOneWidget);
    expect(find.text('How was your ride?'), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets(
    'completed booking without notification still shows review form',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_page(result: _result(status: 'COMPLETED', bookingId: null))),
      );

      expect(find.text('Trip completed'), findsOneWidget);
      expect(find.text('How was your ride?'), findsOneWidget);
    },
  );

  testWidgets('in-progress booking does not show review form', (tester) async {
    await tester.pumpWidget(_wrap(_page(result: _result(status: 'PICKED_UP'))));

    expect(find.text('How was your ride?'), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

BookingCompletePage _page({
  BookingCreateResult? result,
  BookingCompleteReview? review,
}) {
  return BookingCompletePage(
    result: result ?? _result(),
    serviceLabel: 'Airport Pickup',
    originLabel: 'BKK Airport',
    destinationLabel: 'Pattaya Hotel',
    review: review,
    chatApi: _FakeBookingChatApi(),
    chatSocketService: _FakeChatSocketService(),
    enableCustomerTools: true,
  );
}

BookingCreateResult _result({String status = 'PENDING', int? bookingId = 1}) {
  return BookingCreateResult(
    bookingId: bookingId,
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
