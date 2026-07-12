import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'lookup posts booking number and phone then persists guest access',
    () async {
      Uri? requestedUri;
      Map<String, dynamic>? body;
      final service = GuestBookingLookupService(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          requestedUri = request.url;
          body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode({'success': true, 'data': _lookupJson()}),
            200,
          );
        }),
      );

      final result = await service.lookup(
        bookingNumber: 'tx202607010001',
        phone: '+66 (81) 234-5678',
      );

      expect(requestedUri!.path, '/api/v1/public/bookings/lookup');
      expect(body, {
        'bookingNumber': 'tx202607010001',
        'phone': '+66 (81) 234-5678',
      });
      expect(result.bookingNumber, 'TX202607010001');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('guest_access_token_TX202607010001'),
        'guest-token',
      );
    },
  );

  test('lookup persists customer phone for refresh', () async {
    final service = GuestBookingLookupService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': true, 'data': _lookupJson()}),
          200,
        );
      }),
    );

    await service.lookup(
      bookingNumber: 'TX202607010001',
      phone: '+66 81 234 5678',
    );

    final cached = await service.loadCached();
    expect(cached?.customerPhone, '+66 81 234 5678');
  });

  test('create summary keeps boarding QR recoverable before pickup', () {
    final result = GuestBookingLookupResult.fromCreateSummary(
      bookingId: 10,
      bookingNumber: 'TX202607010001',
      status: 'PENDING',
      totalAmount: 1500,
      currency: 'THB',
      paymentMethod: 'PAY_DRIVER',
      guestAccessToken: 'guest-token',
      customerPhone: '+66 81 234 5678',
      serviceTypeName: 'Airport Pickup',
      originAddress: 'BKK Airport',
      destinationAddress: 'Pattaya Hotel',
    );

    expect(result.capabilities.boardingQrRecoverable, true);
    expect(result.capabilities.boardingQrPreviouslyIssued, true);
  });

  testWidgets('lookup page restores cached booking on refresh', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(cached: _result()),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TX202607010001'), findsOneWidget);
    expect(find.text('Customer onboard'), findsOneWidget);
    expect(find.text('Boarding QR'), findsNothing);
    expect(find.text('Issue dropoff QR'), findsNothing);
    expect(
      find.text('You are on the way to your destination.'),
      findsOneWidget,
    );
  });

  testWidgets('lookup page refresh updates status', (tester) async {
    final service = _FakeLookupService(
      cached: _result().copyWith(customerPhone: '+66 81 234 5678'),
      refreshedStatus: 'ON_ROUTE',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: service,
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer onboard'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guest_lookup_refresh')));
    await tester.pumpAndSettle();

    expect(find.text('On the way'), findsOneWidget);
    expect(service.refreshCount, 1);
  });

  testWidgets('lookup page does not show or issue boarding QR', (tester) async {
    final json = _lookupJson();
    json['status'] = 'DRIVER_ARRIVED';
    json['capabilities'] = {
      'chatAvailable': true,
      'notificationsAvailable': true,
      'dropoffQrIssueAvailable': false,
      'reviewAvailable': false,
      'boardingQrRecoverable': true,
      'boardingQrPreviouslyIssued': true,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(
            cached: GuestBookingLookupResult.fromJson(json),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Boarding QR'), findsNothing);
  });

  testWidgets('lookup page refresh does not call boarding QR issue API', (
    tester,
  ) async {
    final api = _CountingBookingApi();
    final json = _lookupJson();
    json['status'] = 'DRIVER_ARRIVED';
    json['capabilities'] = {
      'chatAvailable': true,
      'notificationsAvailable': true,
      'dropoffQrIssueAvailable': false,
      'reviewAvailable': false,
      'boardingQrRecoverable': true,
      'boardingQrPreviouslyIssued': true,
    };
    final lookupService = _FakeLookupService(
      cached: GuestBookingLookupResult.fromJson(json),
    );

    await tester.pumpWidget(
      MaterialApp(home: GuestBookingLookupPage(lookupService: lookupService)),
    );
    await tester.pumpAndSettle();

    expect(api.boardingIssueCalls, 0);
    expect(api.dropoffIssueCalls, 0);

    await tester.tap(find.byKey(const ValueKey('guest_lookup_refresh')));
    await tester.pumpAndSettle();

    expect(api.boardingIssueCalls, 0);
    expect(api.dropoffIssueCalls, 0);
  });

  testWidgets('lookup page shows controlled not-found error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(errorCode: 'BOOKING_NOT_FOUND'),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_booking_number')),
      'TX202607010001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_phone')),
      '+66 81 234 5670',
    );
    await tester.tap(find.text('Find booking'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Booking not found. Please check your booking number and phone.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('malformed successful response becomes controlled error state', (
    tester,
  ) async {
    final service = GuestBookingLookupService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'bookingNumber': 'TX202607010001'},
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: service,
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_booking_number')),
      'TX202607010001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guest_lookup_phone')),
      '+66 81 234 5678',
    );
    await tester.tap(find.text('Find booking'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to load booking. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('lookup page has no horizontal overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(cached: _result()),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('lookup page shows cancelled guidance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(
            cached: _result().copyWith(status: 'CANCELLED'),
          ),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('This booking was cancelled.'), findsOneWidget);
  });

  testWidgets('SETTLEMENT_PENDING customer copy avoids settlement wording', (
    tester,
  ) async {
    final json = _lookupJson();
    json['status'] = 'SETTLEMENT_PENDING';
    final result = GuestBookingLookupResult.fromJson(json);

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(cached: result),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trip ended'), findsOneWidget);
    expect(find.textContaining('settlement', findRichText: true), findsNothing);
    expect(find.textContaining('Settlement'), findsNothing);
    expect(find.textContaining('Please rate your driver'), findsOneWidget);
  });

  testWidgets('submitted review shows thank you card without submit form', (
    tester,
  ) async {
    final json = _lookupJson();
    json['status'] = 'COMPLETED';
    json['capabilities'] = {
      'chatAvailable': false,
      'notificationsAvailable': true,
      'dropoffQrIssueAvailable': false,
      'reviewAvailable': false,
      'boardingQrRecoverable': false,
      'boardingQrPreviouslyIssued': false,
    };
    json['review'] = {
      'eligible': true,
      'submitted': true,
      'rating': 4,
      'tags': ['ON_TIME'],
      'comment': 'Smooth ride',
    };
    final result = GuestBookingLookupResult.fromJson(json);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('zh'),
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(cached: result),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本次乘车体验如何？'), findsNothing);
    expect(find.text('提交评分'), findsNothing);
    expect(find.text('感谢您的评价'), findsOneWidget);
    expect(find.text('Smooth ride'), findsOneWidget);
  });

  test('fromJson parses canReview from lookup response', () {
    final json = _lookupJson();
    json['status'] = 'COMPLETED';
    json['canReview'] = true;
    json['capabilities'] = {
      'chatAvailable': false,
      'notificationsAvailable': true,
      'dropoffQrIssueAvailable': false,
      'reviewAvailable': true,
      'boardingQrRecoverable': false,
      'boardingQrPreviouslyIssued': false,
    };
    final result = GuestBookingLookupResult.fromJson(json);
    expect(result.canReview, isTrue);
  });

  test('fromJson falls back to reviewAvailable when canReview is absent', () {
    final json = _lookupJson();
    json['status'] = 'COMPLETED';
    json['capabilities'] = {
      'chatAvailable': false,
      'notificationsAvailable': true,
      'dropoffQrIssueAvailable': false,
      'reviewAvailable': true,
      'boardingQrRecoverable': false,
      'boardingQrPreviouslyIssued': false,
    };
    final result = GuestBookingLookupResult.fromJson(json);
    expect(result.canReview, isTrue);
  });

  testWidgets(
    'completed booking with canReview shows review form from lookup review state',
    (tester) async {
      final json = _lookupJson();
      json['status'] = 'COMPLETED';
      json['canReview'] = true;
      json['capabilities'] = {
        'chatAvailable': false,
        'notificationsAvailable': true,
        'dropoffQrIssueAvailable': false,
        'reviewAvailable': true,
        'boardingQrRecoverable': false,
        'boardingQrPreviouslyIssued': false,
      };
      json['review'] = {
        'eligible': true,
        'submitted': false,
        'rating': null,
        'tags': [],
        'comment': null,
        'createdAt': null,
      };
      final result = GuestBookingLookupResult.fromJson(json);
      final reviewApi = _FailingGetReviewApi();

      await tester.pumpWidget(
        MaterialApp(
          home: GuestBookingLookupPage(
            lookupService: _FakeLookupService(cached: result),
            enableCustomerTools: false,
            reviewApi: reviewApi,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('How was your ride?'), findsOneWidget);
      expect(find.text('Submit rating'), findsOneWidget);
      expect(reviewApi.getCalls, 0);
    },
  );

  testWidgets(
    'completed booking with canReview and null review still shows review form',
    (tester) async {
      final json = _lookupJson();
      json['status'] = 'COMPLETED';
      json['canReview'] = true;
      json['capabilities'] = {
        'chatAvailable': false,
        'notificationsAvailable': true,
        'dropoffQrIssueAvailable': false,
        'reviewAvailable': true,
        'boardingQrRecoverable': false,
        'boardingQrPreviouslyIssued': false,
      };
      final result = GuestBookingLookupResult.fromJson(json);
      final reviewApi = _FailingGetReviewApi();

      await tester.pumpWidget(
        MaterialApp(
          home: GuestBookingLookupPage(
            lookupService: _FakeLookupService(cached: result),
            enableCustomerTools: false,
            reviewApi: reviewApi,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('How was your ride?'), findsOneWidget);
      expect(find.text('Submit rating'), findsOneWidget);
      expect(reviewApi.getCalls, 0);
    },
  );

  testWidgets(
    'canReview true with submitted review shows thank you card first',
    (tester) async {
      final json = _lookupJson();
      json['status'] = 'COMPLETED';
      json['canReview'] = true;
      json['capabilities'] = {
        'chatAvailable': false,
        'notificationsAvailable': true,
        'dropoffQrIssueAvailable': false,
        'reviewAvailable': true,
        'boardingQrRecoverable': false,
        'boardingQrPreviouslyIssued': false,
      };
      json['review'] = {
        'eligible': true,
        'submitted': true,
        'rating': 5,
        'tags': ['FRIENDLY'],
        'comment': 'Great',
      };
      final result = GuestBookingLookupResult.fromJson(json);

      await tester.pumpWidget(
        MaterialApp(
          home: GuestBookingLookupPage(
            lookupService: _FakeLookupService(cached: result),
            enableCustomerTools: false,
            reviewApi: _FailingGetReviewApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thank you for your feedback.'), findsOneWidget);
      expect(find.text('Submit rating'), findsNothing);
      expect(find.text('Great'), findsOneWidget);
    },
  );

  testWidgets('canReview false without submitted review hides review form', (
    tester,
  ) async {
    final json = _lookupJson();
    json['status'] = 'PICKED_UP';
    json['canReview'] = false;
    final result = GuestBookingLookupResult.fromJson(json);

    await tester.pumpWidget(
      MaterialApp(
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(cached: result),
          enableCustomerTools: false,
          reviewApi: _FailingGetReviewApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How was your ride?'), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets(
    'successful review submission refreshes lookup and keeps submitted state',
    (tester) async {
      final pendingJson = _lookupJson();
      pendingJson['status'] = 'COMPLETED';
      pendingJson['canReview'] = true;
      pendingJson['capabilities'] = {
        'chatAvailable': false,
        'notificationsAvailable': true,
        'dropoffQrIssueAvailable': false,
        'reviewAvailable': true,
        'boardingQrRecoverable': false,
        'boardingQrPreviouslyIssued': false,
      };
      pendingJson['review'] = {
        'eligible': true,
        'submitted': false,
        'tags': [],
      };

      final submittedJson = Map<String, dynamic>.from(pendingJson);
      submittedJson['canReview'] = false;
      submittedJson['review'] = {
        'eligible': true,
        'submitted': true,
        'rating': 5,
        'tags': ['FRIENDLY'],
        'comment': 'Great',
      };

      final service = _FakeLookupService(
        cached: GuestBookingLookupResult.fromJson(
          pendingJson,
        ).copyWith(customerPhone: '+66 81 234 5678'),
        refreshedResult: GuestBookingLookupResult.fromJson(
          submittedJson,
        ).copyWith(customerPhone: '+66 81 234 5678'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GuestBookingLookupPage(
            lookupService: service,
            enableCustomerTools: false,
            reviewApi: _SubmittingLookupReviewApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('review_rating_5')));
      await tester.pump();
      final submitButton = find.widgetWithText(ElevatedButton, 'Submit rating');
      await tester.ensureVisible(submitButton);
      await tester.pump();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(service.refreshCount, 1);
      expect(find.text('Thank you for your feedback.'), findsOneWidget);
      expect(find.text('Submit rating'), findsNothing);
      expect(find.text('Great'), findsOneWidget);
    },
  );

  testWidgets('ja locale shows localized review guidance on trip end', (
    tester,
  ) async {
    final json = _lookupJson();
    json['status'] = 'SETTLEMENT_PENDING';
    final result = GuestBookingLookupResult.fromJson(json);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('ja'),
        home: GuestBookingLookupPage(
          lookupService: _FakeLookupService(cached: result),
          enableCustomerTools: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('運行終了'), findsOneWidget);
    expect(find.textContaining('ドライバーを評価'), findsOneWidget);
    expect(find.text('How was your ride?'), findsNothing);
  });
}

Widget _localizedApp({required Locale locale, required Widget home}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('en'),
      Locale('ko'),
      Locale('zh'),
      Locale('ja'),
      Locale('th'),
    ],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

Map<String, dynamic> _lookupJson() => {
  'bookingNumber': 'TX202607010001',
  'status': 'PICKED_UP',
  'scheduledPickupAt': '2026-07-01T09:30:00+07:00',
  'serviceType': {'name': 'Airport Pickup'},
  'route': {
    'origin': {'address': 'BKK Airport'},
    'destination': {'address': 'Pattaya Hotel'},
  },
  'pricing': {
    'totalAmount': 1500,
    'currency': 'THB',
    'paymentMethod': 'PAY_DRIVER',
  },
  'assignedDriver': {'name': 'Driver A', 'phone': '+66 80 000 0000'},
  'capabilities': {
    'chatAvailable': true,
    'notificationsAvailable': true,
    'dropoffQrIssueAvailable': true,
    'reviewAvailable': false,
    'boardingQrRecoverable': false,
    'boardingQrPreviouslyIssued': true,
  },
  'guestAccess': {'token': 'guest-token', 'expiresAt': '2099-07-02T00:00:00Z'},
};

GuestBookingLookupResult _result() {
  return GuestBookingLookupResult.fromJson(_lookupJson());
}

class _FailingGetReviewApi extends BookingReviewApi {
  int getCalls = 0;

  @override
  Future<Map<String, dynamic>> getReview({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    getCalls += 1;
    throw const BookingReviewApiException('Review GET should not be called');
  }
}

class _SubmittingLookupReviewApi extends BookingReviewApi {
  @override
  Future<Map<String, dynamic>> submitReview({
    required String bookingNumber,
    required int rating,
    List<String>? tags,
    String? comment,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    return {
      'eligible': true,
      'submitted': true,
      'rating': rating,
      'tags': tags ?? [],
      'comment': comment,
    };
  }
}

class _FakeLookupService extends GuestBookingLookupService {
  _FakeLookupService({
    this.cached,
    this.errorCode,
    this.refreshedStatus,
    this.refreshedResult,
  }) : super(
         baseUrl: 'http://localhost:3000',
         client: MockClient((_) async => http.Response('{}', 200)),
       );

  final GuestBookingLookupResult? cached;
  final String? errorCode;
  final String? refreshedStatus;
  final GuestBookingLookupResult? refreshedResult;
  int refreshCount = 0;

  @override
  Future<GuestBookingLookupResult?> loadCached() async => cached;

  @override
  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
  }) async {
    if (errorCode != null) {
      throw BookingApiException('Booking not found', errorCode);
    }
    refreshCount += 1;
    final base = cached ?? _result();
    if (refreshedResult != null) {
      return refreshedResult!;
    }
    if (refreshedStatus != null && refreshCount > 0) {
      return base.copyWith(status: refreshedStatus);
    }
    return base;
  }
}

class _CountingBookingApi extends BookingApiService {
  _CountingBookingApi()
    : super.test(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      );

  int boardingIssueCalls = 0;
  int dropoffIssueCalls = 0;

  @override
  Future<BoardingQrIssueResult> issueBoardingQr({
    required String bookingNumber,
    required String? guestAccessToken,
    bool forceReissue = false,
  }) async {
    boardingIssueCalls += 1;
    throw UnimplementedError();
  }

  @override
  Future<DropoffQrIssueResult> issueDropoffQr({
    required String bookingNumber,
    required String? guestAccessToken,
  }) async {
    dropoffIssueCalls += 1;
    throw UnimplementedError();
  }
}

class _FakeBookingApi extends BookingApiService {
  _FakeBookingApi()
    : super.test(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      );

  int boardingIssueCalls = 0;
  String? lastGuestAccessToken;

  @override
  Future<BoardingQrIssueResult> issueBoardingQr({
    required String bookingNumber,
    required String? guestAccessToken,
    bool forceReissue = false,
  }) async {
    boardingIssueCalls += 1;
    lastGuestAccessToken = guestAccessToken;
    return BoardingQrIssueResult(
      bookingNumber: bookingNumber,
      status: 'DRIVER_ARRIVED',
      boardingQrToken: 'recovered-boarding-token',
      boardingQrExpiresAt: '2099-01-01 00:00:00',
    );
  }
}
