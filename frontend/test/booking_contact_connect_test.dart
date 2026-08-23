import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_contact_connect_args.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/pages/booking_contact_connect_page.dart';
import 'package:frontend/features/booking/services/booking_analytics.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeContactService extends BookingContactConnectionService {
  _FakeContactService({
    required this.channels,
    required this.connection,
  }) : super(baseUrl: 'http://test');

  final List<ContactChannel> channels;
  ContactConnectionState connection;

  @override
  Future<List<ContactChannel>> getPublicChannels() async => channels;

  @override
  Future<ContactConnectionState> getConnection({
    required String bookingNumber,
    required String guestAccessToken,
  }) async =>
      connection;

  @override
  Future<ContactConnectionState> startConnection({
    required String bookingNumber,
    required String channel,
    required String guestAccessToken,
  }) async {
    connection = ContactConnectionState(
      bookingNumber: bookingNumber,
      contactStatus: 'PENDING',
      connectionChannel: channel,
      connectionStatus: 'PENDING',
    );
    return connection;
  }

  @override
  Future<ContactConnectionState> confirmSent({
    required String bookingNumber,
    required String guestAccessToken,
  }) async {
    connection = ContactConnectionState(
      bookingNumber: bookingNumber,
      contactStatus: 'CONFIRM_REQUESTED',
      connectionChannel: connection.connectionChannel,
      connectionStatus: 'CONFIRM_REQUESTED',
    );
    return connection;
  }
}

BookingCreateResult _result({String contactStatus = 'PENDING'}) {
  return BookingCreateResult(
    bookingNumber: 'TX202608130001',
    status: 'PENDING',
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    boardingQrToken: 'qr-token',
    trustMessage: 'Booking received',
    contactStatus: contactStatus,
    contactConnectionRequired: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contact channel ordering', () {
    test('orders channels for Korean locale', () {
      final ordered = orderContactChannels(
        const [
          ContactChannel(code: 'LINE', displayName: 'LINE'),
          ContactChannel(code: 'KAKAO', displayName: 'KakaoTalk'),
          ContactChannel(code: 'WHATSAPP', displayName: 'WhatsApp'),
        ],
        'ko',
      );
      expect(ordered.map((c) => c.code).toList(), ['KAKAO', 'LINE', 'WHATSAPP']);
    });

    test('orders channels for English locale', () {
      final ordered = orderContactChannels(
        const [
          ContactChannel(code: 'LINE', displayName: 'LINE'),
          ContactChannel(code: 'KAKAO', displayName: 'KakaoTalk'),
          ContactChannel(code: 'WHATSAPP', displayName: 'WhatsApp'),
        ],
        'en',
      );
      expect(ordered.map((c) => c.code).toList(), [
        'WHATSAPP',
        'LINE',
        'KAKAO',
      ]);
    });
  });

  group('BookingContactConnectRouteLoader', () {
    test('parses booking number from query', () {
      expect(
        BookingContactConnectRouteLoader.bookingNumberFromUri(
          Uri.parse('/booking/contact-connect?bookingNumber=TX202608130001'),
        ),
        'TX202608130001',
      );
      expect(
        BookingContactConnectRouteLoader.bookingNumberFromUri(
          Uri.parse('/booking/contact-connect?bookingNumber=bad'),
        ),
        isNull,
      );
    });
  });

  group('BookingContactConnectPage', () {
    late RecordingBookingAnalyticsSink analyticsSink;
    late BookingAnalytics analytics;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      analyticsSink = RecordingBookingAnalyticsSink();
      analytics = BookingAnalytics(analyticsSink);
    });

    Future<void> pumpPage(
      WidgetTester tester, {
      required _FakeContactService service,
      BookingContactConnectArgs? args,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate('en')],
            supportedLocales: const [Locale('en')],
            home: BookingContactConnectPage(
              bookingNumber: 'TX202608130001',
              args: args,
              service: service,
              analytics: analytics,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows booking number and enabled channels', (tester) async {
      final service = _FakeContactService(
        channels: const [
          ContactChannel(code: 'WHATSAPP', displayName: 'WhatsApp'),
          ContactChannel(code: 'LINE', displayName: 'LINE'),
        ],
        connection: ContactConnectionState(
          bookingNumber: 'TX202608130001',
          contactStatus: 'PENDING',
        ),
      );

      await pumpPage(
        tester,
        service: service,
        args: BookingContactConnectArgs(
          result: _result(),
          serviceLabel: 'Airport pickup',
        ),
      );

      expect(find.text('TX202608130001'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('LINE'), findsOneWidget);
      expect(analyticsSink.named('contact_connect_viewed'), hasLength(1));
    });

    testWidgets('copy snackbar floats above confirm CTA', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          return null;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final service = _FakeContactService(
        channels: const [
          ContactChannel(code: 'LINE', displayName: 'LINE'),
        ],
        connection: const ContactConnectionState(
          bookingNumber: 'TX202608130001',
          contactStatus: 'PENDING',
        ),
      );

      await pumpPage(
        tester,
        service: service,
        args: BookingContactConnectArgs(
          result: _result(),
          serviceLabel: 'Airport pickup',
        ),
      );

      expect(find.byKey(const Key('contact_connect_cta_bar')), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'LINE'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contact_connect_cta_bar')), findsOneWidget);
      expect(find.text('I sent the message'), findsOneWidget);
      expect(find.text('Booking reference copied'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);

      final ctaRect = tester.getRect(find.byKey(const Key('contact_connect_cta_bar')));
      final snackTextRect =
          tester.getRect(find.text('Booking reference copied'));
      expect(snackTextRect.bottom, lessThanOrEqualTo(ctaRect.top));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/contact_connect_line_snackbar_375.png'),
      );
    });

    testWidgets('confirm sent shows waiting state', (tester) async {
      final service = _FakeContactService(
        channels: const [
          ContactChannel(code: 'WHATSAPP', displayName: 'WhatsApp'),
        ],
        connection: ContactConnectionState(
          bookingNumber: 'TX202608130001',
          contactStatus: 'PENDING',
          connectionChannel: 'WHATSAPP',
        ),
      );

      await pumpPage(
        tester,
        service: service,
        args: BookingContactConnectArgs(
          result: _result(),
          serviceLabel: 'Airport pickup',
        ),
      );

      await tester.tap(find.text('I sent the message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Waiting for T-Rider'), findsOneWidget);
      expect(analyticsSink.named('contact_confirm_requested'), hasLength(1));
    });

    test('resolveContactCompletionTarget uses server urgent flag on reload', () {
      final connection = ContactConnectionState(
        bookingNumber: 'TX202608130001',
        contactStatus: 'VERIFIED',
        isUrgentRequest: true,
        bookingStatus: 'OPEN',
      );
      final result = connection.toMinimalCreateResult(guestAccessToken: 'guest-token');

      expect(
        resolveContactCompletionTarget(connection: connection, result: result),
        ContactCompletionTarget.urgentFlow,
      );
    });

    test('toMinimalCreateResult preserves urgent flag', () {
      final state = ContactConnectionState(
        bookingNumber: 'TX202608130001',
        contactStatus: 'VERIFIED',
        isUrgentRequest: true,
        bookingStatus: 'OPEN',
        totalAmount: 1500,
        currency: 'THB',
      );
      final result = state.toMinimalCreateResult(guestAccessToken: 'guest-token');
      expect(result.isUrgentRequest, isTrue);
      expect(result.bookingNumber, 'TX202608130001');
      expect(result.guestAccessToken, 'guest-token');
    });
  });
}
