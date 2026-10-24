import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'support/booking_complete_test_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/booking_contact_connect_args.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/pages/booking_contact_connect_page.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/services/booking_analytics.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeContactService extends BookingContactConnectionService {
  _FakeContactService({required this.channels, required this.connection})
    : super(baseUrl: 'http://test');

  int confirmCalls = 0;
  bool failConfirm = false;
  final List<ContactChannel> channels;
  ContactConnectionState connection;

  @override
  Future<List<ContactChannel>> getPublicChannels() async => channels;

  @override
  Future<ContactConnectionState> getConnection({
    required String bookingNumber,
    required String guestAccessToken,
  }) async => connection;

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
    confirmCalls++;
    if (failConfirm)
      throw BookingContactConnectionException('QA confirm failed');
    connection = ContactConnectionState(
      bookingNumber: bookingNumber,
      contactStatus: 'CONFIRM_REQUESTED',
      connectionChannel: connection.connectionChannel,
      connectionStatus: 'CONFIRM_REQUESTED',
    );
    return connection;
  }
}

class _SlowConfirmFakeService extends _FakeContactService {
  _SlowConfirmFakeService({required super.channels, required super.connection});

  Completer<ContactConnectionState>? confirmCompleter;

  @override
  Future<ContactConnectionState> confirmSent({
    required String bookingNumber,
    required String guestAccessToken,
  }) async {
    confirmCalls++;
    confirmCompleter = Completer<ContactConnectionState>();
    return confirmCompleter!.future;
  }

  void completeConfirm() {
    connection = ContactConnectionState(
      bookingNumber: connection.bookingNumber,
      contactStatus: 'CONFIRM_REQUESTED',
      connectionChannel: connection.connectionChannel,
      connectionStatus: 'CONFIRM_REQUESTED',
    );
    confirmCompleter?.complete(connection);
  }
}

class _PollingGuardFakeService extends _FakeContactService {
  _PollingGuardFakeService({
    required super.channels,
    required super.connection,
  });

  int getConnectionCalls = 0;
  Completer<ContactConnectionState>? pendingRefresh;

  @override
  Future<ContactConnectionState> getConnection({
    required String bookingNumber,
    required String guestAccessToken,
  }) async {
    getConnectionCalls++;
    if (getConnectionCalls == 1) {
      return connection;
    }
    pendingRefresh = Completer<ContactConnectionState>();
    return pendingRefresh!.future;
  }

  void completePendingRefresh() {
    pendingRefresh?.complete(connection);
    pendingRefresh = null;
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
      final ordered = orderContactChannels(const [
        ContactChannel(code: 'LINE', displayName: 'LINE'),
        ContactChannel(code: 'KAKAO', displayName: 'KakaoTalk'),
        ContactChannel(code: 'WHATSAPP', displayName: 'WhatsApp'),
      ], 'ko');
      expect(ordered.map((c) => c.code).toList(), [
        'KAKAO',
        'LINE',
        'WHATSAPP',
      ]);
    });

    test('orders channels for English locale', () {
      final ordered = orderContactChannels(const [
        ContactChannel(code: 'LINE', displayName: 'LINE'),
        ContactChannel(code: 'KAKAO', displayName: 'KakaoTalk'),
        ContactChannel(code: 'WHATSAPP', displayName: 'WhatsApp'),
      ], 'en');
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
      bool settle = true,
      String language = 'en',
    }) async {
      final auth = createSignedOutAuthController();
      await auth.initialize();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: MaterialApp(
            builder: (context, child) =>
                AuthScope(controller: auth, child: child!),
            locale: Locale(language),
            localizationsDelegates: [
              AppLocalizationsDelegate(language),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale(language)],
            home: BookingContactConnectPage(
              bookingNumber: 'TX202608130001',
              args: args,
              service: service,
              analytics: analytics,
            ),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
        return;
      }

      await tester.pump();
      for (var i = 0; i < 50; i++) {
        if (find.text('TX202608130001').evaluate().isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> _expectSnackbarAboveCtaForChannel(
      WidgetTester tester,
      String channelCode,
      String channelLabel,
    ) async {
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
        channels: [
          ContactChannel(code: channelCode, displayName: channelLabel),
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

      await tester.tap(find.widgetWithText(OutlinedButton, channelLabel));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contact_connect_cta_bar')), findsOneWidget);
      expect(find.text('I sent the message'), findsOneWidget);
      expect(find.text('Booking reference copied'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);

      final ctaRect = tester.getRect(
        find.byKey(const Key('contact_connect_cta_bar')),
      );
      final snackTextRect = tester.getRect(
        find.text('Booking reference copied'),
      );
      expect(snackTextRect.bottom, lessThanOrEqualTo(ctaRect.top));
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

    testWidgets(
      'stored preferred channel still shows connect button before connection starts',
      (tester) async {
        final service = _FakeContactService(
          channels: const [
            ContactChannel(code: 'KAKAO', displayName: 'KakaoTalk'),
            ContactChannel(code: 'LINE', displayName: 'LINE'),
          ],
          connection: ContactConnectionState(
            bookingNumber: 'TX202608130001',
            contactStatus: 'PENDING',
            contactChannel: 'LINE',
            contactChannelManaged: true,
          ),
        );
        await pumpPage(
          tester,
          service: service,
          args: BookingContactConnectArgs(
            result: _result(),
            serviceLabel: 'Airport pickup',
            preferredChannel: 'LINE',
          ),
        );
        expect(find.textContaining('LINE'), findsWidgets);
        expect(find.text('KakaoTalk'), findsNothing);
        expect(find.byKey(const Key('contact_connect_cta_bar')), findsNothing);
      },
    );

    testWidgets('copy snackbar floats above confirm CTA', (tester) async {
      await _expectSnackbarAboveCtaForChannel(tester, 'LINE', 'LINE');
    });

    testWidgets('copy snackbar floats above confirm CTA for KakaoTalk', (
      tester,
    ) async {
      await _expectSnackbarAboveCtaForChannel(tester, 'KAKAO', 'KakaoTalk');
    });

    testWidgets('copy snackbar floats above confirm CTA for WhatsApp', (
      tester,
    ) async {
      await _expectSnackbarAboveCtaForChannel(tester, 'WHATSAPP', 'WhatsApp');
    });

    testWidgets(
      'confirm overlay shows while confirm-sent request is in flight',
      (tester) async {
        final service = _SlowConfirmFakeService(
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
          settle: false,
        );

        await tester.tap(find.text('I sent the message'));
        await tester.pump();

        expect(
          find.byKey(const Key('contact_connect_confirm_overlay')),
          findsOneWidget,
        );

        service.completeConfirm();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const Key('contact_connect_confirm_overlay')),
          findsNothing,
        );
        expect(find.byType(BookingCompletePage), findsOneWidget);
        expect(service.connection.contactStatus, 'CONFIRM_REQUESTED');
        expect(analyticsSink.named('contact_connect_succeeded'), isEmpty);
      },
    );

    testWidgets(
      'reopening confirm-requested contact goes to completion without polling',
      (tester) async {
        final service = _PollingGuardFakeService(
          channels: const [ContactChannel(code: 'LINE', displayName: 'LINE')],
          connection: const ContactConnectionState(
            bookingNumber: 'TX202608130001',
            contactStatus: 'CONFIRM_REQUESTED',
            connectionChannel: 'LINE',
            connectionStatus: 'CONFIRM_REQUESTED',
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
        expect(find.byType(BookingCompletePage), findsOneWidget);
        await tester.pump(const Duration(seconds: 20));
        expect(service.getConnectionCalls, 1);
        expect(analyticsSink.named('contact_connect_succeeded'), isEmpty);
      },
    );

    testWidgets('confirm sent opens completion without admin verification', (
      tester,
    ) async {
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
      await tester.pumpAndSettle();

      expect(find.byType(BookingCompletePage), findsOneWidget);
      expect(service.connection.contactStatus, 'CONFIRM_REQUESTED');
      expect(analyticsSink.named('contact_connect_succeeded'), isEmpty);
      expect(analyticsSink.named('contact_confirm_requested'), hasLength(1));
    });

    testWidgets('failed message confirmation stays on contact screen', (
      tester,
    ) async {
      final service = _FakeContactService(
        channels: const [ContactChannel(code: 'LINE', displayName: 'LINE')],
        connection: const ContactConnectionState(
          bookingNumber: 'TX202608130001',
          contactStatus: 'PENDING',
          connectionChannel: 'LINE',
        ),
      )..failConfirm = true;
      await pumpPage(
        tester,
        service: service,
        args: BookingContactConnectArgs(
          result: _result(),
          serviceLabel: 'Airport pickup',
        ),
      );
      await tester.tap(find.text('I sent the message'));
      await tester.pumpAndSettle();
      expect(find.byType(BookingCompletePage), findsNothing);
      expect(find.byType(BookingContactConnectPage), findsOneWidget);
      expect(
        find.text(AppLocalizations('en').t('ui_load_failed')),
        findsOneWidget,
      );
      expect(service.confirmCalls, 1);
    });

    for (final language in ['ko', 'en', 'th', 'ja', 'zh']) {
      testWidgets('sent-message completion notice at 375px in $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(375, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _FakeContactService(
          channels: const [ContactChannel(code: 'LINE', displayName: 'LINE')],
          connection: const ContactConnectionState(
            bookingNumber: 'TX202608130001',
            contactStatus: 'PENDING',
            connectionChannel: 'LINE',
          ),
        );
        await pumpPage(
          tester,
          language: language,
          service: service,
          args: BookingContactConnectArgs(
            result: _result(),
            serviceLabel: 'Airport pickup',
          ),
        );
        await tester.tap(
          find.text(
            AppLocalizations(language).t('contact_connect_confirm_sent'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BookingCompletePage), findsOneWidget);
        expect(
          find.byKey(const Key('contact-sent-complete-notice')),
          findsOneWidget,
        );
        expect(
          find.text(
            AppLocalizations(
              language,
            ).t('contact_connect_sent_complete_notice'),
          ),
          findsOneWidget,
        );
        expect(service.connection.contactStatus, 'CONFIRM_REQUESTED');
        expect(service.confirmCalls, 1);
        expect(analyticsSink.named('contact_connect_succeeded'), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    test(
      'contact snapshot preserves booking amount, payment and access details',
      () {
        final original = BookingCreateResult(
          bookingId: 7,
          bookingNumber: 'TX202608130001',
          status: 'OPEN',
          paymentMethod: 'PAY_DRIVER',
          paymentStatus: 'UNPAID',
          paymentCurrency: 'THB',
          paymentInstructions: const {'note': 'keep'},
          totalAmount: 1500,
          currency: 'THB',
          guestAccessToken: 'guest',
          boardingQrToken: 'qr',
          trustMessage: 'keep',
          canCancel: true,
          trackingAvailable: true,
          cancellationDeadline: '2026-11-01T10:00:00Z',
          isUrgentRequest: true,
          contactConnectionRequired: true,
        );
        final updated = original.withContactState(
          contactStatus: 'CONFIRM_REQUESTED',
          contactChannel: 'LINE',
          bookingStatus: 'DRIVER_ASSIGNED',
        );
        expect(updated.contactStatus, 'CONFIRM_REQUESTED');
        expect(updated.contactChannel, 'LINE');
        expect(updated.status, 'DRIVER_ASSIGNED');
        expect(updated.totalAmount, original.totalAmount);
        expect(updated.paymentMethod, original.paymentMethod);
        expect(updated.paymentInstructions, original.paymentInstructions);
        expect(updated.guestAccessToken, original.guestAccessToken);
        expect(updated.boardingQrToken, original.boardingQrToken);
        expect(updated.canCancel, original.canCancel);
        expect(updated.cancellationDeadline, original.cancellationDeadline);
        expect(updated.isUrgentRequest, isTrue);
        expect(updated.contactConnectionRequired, isTrue);
      },
    );

    test(
      'resolveContactCompletionTarget uses server urgent flag on reload',
      () {
        final connection = ContactConnectionState(
          bookingNumber: 'TX202608130001',
          contactStatus: 'VERIFIED',
          isUrgentRequest: true,
          bookingStatus: 'OPEN',
        );
        final result = connection.toMinimalCreateResult(
          guestAccessToken: 'guest-token',
        );

        expect(
          resolveContactCompletionTarget(
            connection: connection,
            result: result,
          ),
          ContactCompletionTarget.urgentFlow,
        );
      },
    );

    test('toMinimalCreateResult preserves urgent flag', () {
      final state = ContactConnectionState(
        bookingNumber: 'TX202608130001',
        contactStatus: 'VERIFIED',
        isUrgentRequest: true,
        bookingStatus: 'OPEN',
        totalAmount: 1500,
        currency: 'THB',
      );
      final result = state.toMinimalCreateResult(
        guestAccessToken: 'guest-token',
      );
      expect(result.isUrgentRequest, isTrue);
      expect(result.bookingNumber, 'TX202608130001');
      expect(result.guestAccessToken, 'guest-token');
    });
  });
}
