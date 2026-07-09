import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:frontend/features/booking/widgets/booking_chat_section.dart';
import 'package:frontend/features/booking/services/booking_chat_api.dart';
import 'package:frontend/features/chat/models/chat_connection_state.dart';
import 'package:frontend/features/chat/services/chat_message_list.dart';
import 'package:frontend/features/chat/services/chat_realtime_session.dart';
import 'package:frontend/features/chat/services/chat_socket_service.dart';
import 'package:frontend/features/driver/pages/driver_chat_page.dart';
import 'package:frontend/features/driver/services/driver_chat_api.dart';
import 'package:frontend/features/admin_chat/pages/admin_chat_queue_page.dart';
import 'package:frontend/features/admin_chat/services/admin_chat_api_service.dart';

class FakeBookingChatApi extends BookingChatApi {
  FakeBookingChatApi({
    this.room = const {'roomId': 1, 'sendingAllowed': true, 'unreadCount': 0},
    this.messages = const [],
    this.sendError,
  });

  final Map<String, dynamic> room;
  final List<dynamic> messages;
  final String? sendError;
  int sendCount = 0;
  int listMessagesCount = 0;

  @override
  Future<Map<String, dynamic>> getRoom({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    return room;
  }

  @override
  Future<List<dynamic>> listMessages({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    listMessagesCount += 1;
    return messages;
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    sendCount += 1;
    if (sendError != null) throw BookingChatApiException(sendError!);
    return {
      'messageId': 1,
      'clientMessageId': clientMessageId,
      'senderDisplayName': 'Guest',
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> markRead({
    required String bookingNumber,
    required int upToMessageId,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    return {'unreadCount': 0};
  }
}

class FakeDriverChatApi extends DriverChatApi {
  FakeDriverChatApi({this.unread = 1, this.sendError});

  final int unread;
  final String? sendError;
  int sendCount = 0;
  String? sentBookingNumber;

  @override
  Future<Map<String, dynamic>> getRoom(String bookingNumber) async {
    return {'roomId': 2, 'sendingAllowed': true, 'unreadCount': unread};
  }

  @override
  Future<List<dynamic>> listMessages(String bookingNumber) async => [];

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
  }) async {
    sendCount += 1;
    sentBookingNumber = bookingNumber;
    if (sendError != null) throw DriverChatApiException(sendError!);
    return {
      'messageId': 2,
      'clientMessageId': clientMessageId,
      'senderDisplayName': 'Driver',
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> markRead({
    required String bookingNumber,
    required int upToMessageId,
  }) async => {'unreadCount': 0};
}

class FakeAdminChatApi extends AdminChatApiService {
  @override
  Future<Map<String, dynamic>> listChats({
    bool unreadOnly = false,
    String? search,
  }) async {
    final items = [
      {
        'bookingNumber': 'TX202607010001',
        'customerDisplayName': 'Kim',
        'driverDisplayName': 'Driver A',
        'lastMessageText': 'On my way to pickup',
        'lastMessageAt': DateTime.now().toIso8601String(),
        'unreadCount': unreadOnly ? 2 : 0,
      },
    ];
    return {'items': items, 'total': items.length};
  }

  @override
  Future<Map<String, dynamic>> getRoom(String bookingNumber) async {
    return {'roomId': 3, 'sendingAllowed': true, 'unreadCount': 0};
  }

  @override
  Future<List<dynamic>> listMessages(String bookingNumber) async => [];

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String bookingNumber,
    required String text,
    required String clientMessageId,
  }) async {
    return {
      'messageId': 3,
      'clientMessageId': clientMessageId,
      'senderDisplayName': 'Admin',
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}

class TestChatSocketService extends ChatSocketService {
  TestChatSocketService({
    this.stayOffline = false,
    this.connectAsError = false,
  });

  final bool stayOffline;
  final bool connectAsError;

  @override
  io.Socket connect({String? accessToken, String? guestAccessToken}) {
    debugSetConnectionState(
      connectAsError
          ? ChatConnectionState.error
          : stayOffline
          ? ChatConnectionState.offline
          : ChatConnectionState.connected,
    );
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

  void simulateMessage(Map<String, dynamic> payload) {
    debugInjectMessage(payload);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({
    'driver_access_token': 'driver-token',
    'admin_access_token': 'admin-token',
  });

  test('ChatMessageList deduplicates by messageId and clientMessageId', () {
    final list = [
      {'messageId': 1, 'clientMessageId': 'a', 'text': 'one'},
    ];
    final merged = ChatMessageList.upsert(list, {
      'messageId': 1,
      'clientMessageId': 'a',
      'text': 'one updated',
    });
    expect(merged.length, 1);
    expect((merged.first as Map)['text'], 'one updated');

    final withClient = ChatMessageList.upsert(
      [
        {'clientMessageId': 'pending-1', 'text': 'opt'},
      ],
      {'messageId': 5, 'clientMessageId': 'pending-1', 'text': 'confirmed'},
    );
    expect(withClient.length, 1);
    expect((withClient.first as Map)['messageId'], 5);
  });

  testWidgets('customer chat loads REST history and shows live connection', (
    tester,
  ) async {
    final socket = TestChatSocketService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: FakeBookingChatApi(),
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Live'), findsOneWidget);
    expect(
      find.text('No messages yet. Send the first message.'),
      findsOneWidget,
    );
  });

  testWidgets('incoming socket message appears without refresh', (
    tester,
  ) async {
    final socket = TestChatSocketService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: FakeBookingChatApi(),
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.simulateMessage({
      'bookingNumber': 'TX202607010001',
      'roomId': 1,
      'message': {
        'messageId': 99,
        'senderDisplayName': 'Driver',
        'text': 'On my way',
        'createdAt': DateTime.now().toIso8601String(),
      },
    });
    await tester.pump();

    expect(find.text('On my way'), findsOneWidget);
  });

  testWidgets('duplicate REST and socket message displayed once', (
    tester,
  ) async {
    final api = FakeBookingChatApi(
      messages: [
        {
          'messageId': 10,
          'clientMessageId': 'dup-1',
          'senderDisplayName': 'Guest',
          'text': 'Hello',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
    );
    final socket = TestChatSocketService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: api,
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.simulateMessage({
      'bookingNumber': 'TX202607010001',
      'roomId': 1,
      'message': {
        'messageId': 10,
        'clientMessageId': 'dup-1',
        'senderDisplayName': 'Guest',
        'text': 'Hello',
        'createdAt': DateTime.now().toIso8601String(),
      },
    });
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('customer send uses REST with guest path', (tester) async {
    final api = FakeBookingChatApi();
    final socket = TestChatSocketService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: api,
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(api.sendCount, 1);
  });

  testWidgets('driver reassigned send failure is surfaced', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverChatPage(
          bookingNumber: 'TX202607010001',
          api: FakeDriverChatApi(sendError: 'Chat is not accessible'),
          socketService: TestChatSocketService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('driver_chat_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Chat is not accessible'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('driver send button enables with text and sends booking number', (
    tester,
  ) async {
    final api = FakeDriverChatApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DriverChatPage(
          bookingNumber: 'TX202607010001',
          api: api,
          socketService: TestChatSocketService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final buttonFinder = find.byKey(const Key('driver_chat_send_button'));
    FilledButton button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('driver_chat_message_input')),
      'Driver hello',
    );
    await tester.pump();
    button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNotNull);

    await tester.tap(buttonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.sendCount, 1);
    expect(api.sentBookingNumber, 'TX202607010001');
    expect(find.text('Driver hello'), findsOneWidget);
    final input = tester.widget<TextField>(
      find.byKey(const Key('driver_chat_message_input')),
    );
    expect(input.controller?.text, isEmpty);
  });

  testWidgets('disconnected send uses REST instead of silent loss', (
    tester,
  ) async {
    final api = FakeBookingChatApi();
    final socket = TestChatSocketService(stayOffline: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: api,
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Queued msg');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.sendCount, 1);
    expect(find.text('Queued msg'), findsOneWidget);
    expect(find.textContaining('queued'), findsNothing);
  });

  testWidgets('driver chat loads and sends through REST when socket errors', (
    tester,
  ) async {
    final api = FakeDriverChatApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DriverChatPage(
          bookingNumber: 'TX202607010001',
          api: api,
          socketService: TestChatSocketService(connectAsError: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Connection error'), findsNothing);
    expect(find.text('Offline'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Driver hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('driver_chat_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.sendCount, 1);
    expect(find.text('Driver hello'), findsOneWidget);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, isEmpty);
  });

  testWidgets('admin chat queue has no horizontal overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminChatQueuePage(api: FakeAdminChatApi())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TX202607010001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer chat has no horizontal overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: FakeBookingChatApi(),
            socketService: TestChatSocketService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('admin selected chat receives live message', (tester) async {
    final socket = TestChatSocketService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminChatDetailPage(
            bookingNumber: 'TX202607010001',
            onBack: () {},
            api: FakeAdminChatApi(),
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    socket.simulateMessage({
      'bookingNumber': 'TX202607010001',
      'roomId': 3,
      'message': {
        'messageId': 50,
        'senderDisplayName': 'Customer',
        'text': 'Admin live',
        'createdAt': DateTime.now().toIso8601String(),
      },
    });
    await tester.pump();
    expect(find.text('Admin live'), findsOneWidget);
  });

  testWidgets('message from another booking does not appear in current room', (
    tester,
  ) async {
    final socket = TestChatSocketService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingChatSection(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: FakeBookingChatApi(),
            socketService: socket,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.simulateMessage({
      'bookingNumber': 'TX202607010099',
      'roomId': 99,
      'message': {
        'messageId': 77,
        'text': 'wrong room',
        'senderDisplayName': 'Other',
      },
    });
    await tester.pump();
    expect(find.text('wrong room'), findsNothing);
  });

  test('ChatRealtimeSession reconnect reloads history', () async {
    final api = FakeBookingChatApi(messages: []);
    var loadCount = 0;
    final socket = TestChatSocketService();
    final session = ChatRealtimeSession(
      bookingNumber: 'TX202607010001',
      loadRoom: () async {
        loadCount += 1;
        return api.getRoom(
          bookingNumber: 'TX202607010001',
          guestAccessToken: 't',
        );
      },
      loadMessages: () async {
        loadCount += 1;
        return api.listMessages(
          bookingNumber: 'TX202607010001',
          guestAccessToken: 't',
        );
      },
      sendRest: ({required String text, required String clientMessageId}) =>
          api.sendMessage(
            bookingNumber: 'TX202607010001',
            text: text,
            clientMessageId: clientMessageId,
            guestAccessToken: 't',
          ),
      markReadRest: (id) => api.markRead(
        bookingNumber: 'TX202607010001',
        upToMessageId: id,
        guestAccessToken: 't',
      ),
      newClientMessageId: BookingChatApi.newClientMessageId,
      loadGuestAccessToken: () async => 't',
      socketService: socket,
    );

    await session.start();
    expect(loadCount >= 2, isTrue);

    await session.retryConnection();
    expect(loadCount >= 4, isTrue);
    session.dispose();
  });
}
