import 'dart:async';
import 'package:frontend/features/admin_dispatch/models/admin_calling_codes.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/features/admin_coupon/services/admin_coupon_api_service.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_manual_booking_create_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/booking/models/location_option.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/vehicle_type_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _FakeCouponApi extends AdminCouponApiService {
  const _FakeCouponApi();

  @override
  Future<List<AdminCustomerSearchResult>> searchCustomers(String query) async {
    return const [];
  }
}

BookingApiService _fakeBookingApi({int totalAmount = 1000}) {
  return BookingApiService.test(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/bookings/pricing/calculate')) {
        return http.Response(
          '{"data":{"currency":"THB","totalAmount":$totalAmount,"chargeItems":[]}}',
          200,
        );
      }
      return http.Response('{"message":"not found"}', 404);
    }),
    baseUrl: 'http://test.invalid',
  );
}

VehicleTypeApiService _fakeVehicleTypeApi() => VehicleTypeApiService(
  client: MockClient((_) async => http.Response(
    '{"data":[{"code":"SEDAN"},{"code":"SUV"},{"code":"VIP_SUV"},{"code":"VAN"}]}',
    200,
  )),
  baseUrl: 'http://test.invalid',
);

class _FakeDispatchApi extends AdminDispatchApiService {
  _FakeDispatchApi(
    this.onCreate, {
    this.editDetail,
  });

  final Future<Map<String, dynamic>> Function() onCreate;
  final Map<String, dynamic>? editDetail;

  @override
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    return editDetail ??
        {
          'bookingNumber': bookingNumber,
          'manualCallActions': {'canEdit': true},
          'scheduledPickupAt': '2026-09-24T10:00:00.000Z',
          'specialRequests': 'memo',
          'route': {
            'origin': {'address': 'Origin Rd', 'name': 'Origin'},
            'destination': {'address': 'Dest Rd', 'name': 'Dest'},
          },
          'vehicle': {'typeCode': 'VAN'},
          'passengers': {'adults': 2},
          'pricing': {
            'paymentMethod': 'PAY_DRIVER',
            'chargeItems': [
              {'chargeType': 'OTHER', 'amount': 800},
            ],
          },
          'customer': {
            'customerUserId': 42,
            'name': 'Guest',
            'phone': '+66123456789',
          },
          'options': {'nameSign': false},
        };
  }

  @override
  Future<Map<String, dynamic>> createManualBooking({
    Map<String,dynamic>? golf,
    required Map<String, dynamic> origin,
    required Map<String, dynamic> destination,
    required String scheduledPickupAt,
    required String vehicleTypeCode,
    required int payoutAmount,
    int? customerChargeAmount,
    required String paymentCollection,
    required Map<String, dynamic> customer,
    String? memo,
    Map<String, dynamic>? passengers,
    Map<String, dynamic>? luggage,
    String? serviceTypeCode,
    bool nameSign = false,
    String? nameSignText,
    bool preferFemaleDriver = false,
    String? originAirportIata,
    Map<String, dynamic>? transfer,
    int? driverId,
  }) {
    return onCreate();
  }

  @override
  Future<List<dynamic>> listDrivers({bool? archived, String? bookingNumber}) async {
    return [
      {
        'driverId': 2,
        'displayName': 'QA Driver',
        'activeState': 'ACTIVE',
        'driverStatus': 'OFFLINE',
        'assignmentEligible': true,
        'archive': {'isArchived': false},
        'primaryVehicle': {'vehicleTypeCode': 'SEDAN'},
      },
      {
        'driverId': 14,
        'displayName': 'Suspended Driver',
        'activeState': 'ACTIVE',
        'driverStatus': 'SUSPENDED',
        'assignmentEligible': false,
        'archive': {'isArchived': false},
        'primaryVehicle': {'vehicleTypeCode': 'SEDAN'},
      },
    ];
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

Future<void> _pumpAdminPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _wrap(
      AdminManualBookingCreatePage(
        bookingApi: _fakeBookingApi(),
        vehicleTypeApi: _fakeVehicleTypeApi(),
        couponApi: const _FakeCouponApi(),
        dispatchApi: _FakeDispatchApi(() async {
          throw StateError('should not submit');
        }),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(const Key('adminManualBookingSubmit'));
  await tester.scrollUntilVisible(
    submit,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
}

void main() {
  test(
    'worldwide calling codes are unique and normalize international input',
    () {
      expect(adminCallingCodes.length, 206);
      expect(adminCallingCodes.toSet().length, adminCallingCodes.length);
      for (final code in [
        '+1',
        '+7',
        '+33',
        '+44',
        '+49',
        '+61',
        '+91',
        '+255',
        '+358',
        '+971',
        '+998',
      ]) {
        expect(adminCallingCodes, contains(code));
      }
      expect(normalizeAdminManualPhone('+44', '07911 123456'), '+447911123456');
      expect(normalizeAdminManualPhone('+1', '202-555-0123'), '+12025550123');
      expect(normalizeAdminManualPhone('+971', '0501234567'), '+971501234567');
    },
  );
  testWidgets('admin selector scrolls to and selects worldwide code', (
    tester,
  ) async {
    await _pumpAdminPage(tester);
    final selector = find.byKey(const ValueKey('adminManualPhoneDialCode-+66'));
    await tester.scrollUntilVisible(
      selector,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('adminCallingCountrySearch')), '+998');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('adminCallingCountry-UZ')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('adminManualPhoneDialCode-+998')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });



  test('normalizes domestic admin phone input to E.164', () {
    expect(
      normalizeAdminManualPhone('+82', '010-1234-5678'),
      '+821012345678',
    );
    expect(normalizeAdminManualPhone('+66', '081-234-5678'), '+66812345678');
    expect(
      normalizeAdminManualPhone('+82', '+821012345678'),
      '+821012345678',
    );
  });

  testWidgets('blocks submit when payout amount is missing', (tester) async {
    await _pumpAdminPage(tester);
    await _tapSubmit(tester);
    expect(find.text('필수 항목을 모두 입력해주세요'), findsOneWidget);
  });

  testWidgets('fills customer amount from customer pricing and preserves edits', (tester) async {
    await tester.pumpWidget(_wrap(AdminManualBookingCreatePage(
      bookingApi: _fakeBookingApi(totalAmount: 1100),
      vehicleTypeApi: _fakeVehicleTypeApi(),
      couponApi: const _FakeCouponApi(),
      dispatchApi: _FakeDispatchApi(() async => throw StateError('no submit')),
      initialOrigin: const LocationOption(
        id: 'bkk', displayName: 'BKK', kind: LocationKind.airport, code: 'BKK'),
      initialDestination: const LocationOption(
        id: 'pattaya', displayName: 'Pattaya', kind: LocationKind.city, code: 'PATTAYA'),
      initialServiceTypeCode: 'AIRPORT_PICKUP',
    )));
    await tester.pumpAndSettle();
    final amount = find.byKey(const Key('adminManualBookingCustomerChargeAmount'));
    await tester.scrollUntilVisible(amount, 500, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(tester.widget<TextFormField>(amount).controller!.text, '1100');

    await tester.enterText(amount, '1250');
    final service = find.byKey(const Key('adminManualBookingServiceType'));
    await tester.scrollUntilVisible(service, -500, scrollable: find.byType(Scrollable).first);
    await tester.tap(service);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('도시간 이동').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(amount, 500, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextFormField>(amount).controller!.text, '1250');
    final refill = find.byKey(const Key('adminManualBookingRefillStandardPrice'));
    expect(refill, findsOneWidget);
    await tester.ensureVisible(refill);
    await tester.pump();
    await tester.tap(refill);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(amount).controller!.text, '1100');
  });

  testWidgets('active vehicle list excludes VIP_VAN', (tester) async {
    await _pumpAdminPage(tester);
    final picker = find.byKey(const Key('adminManualBookingVehicleType'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('VIP_VAN'), findsNothing);
    expect(find.text('VAN'), findsOneWidget);
  });

  testWidgets('direct create blocks duplicate submit and opens created booking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final createResult = Completer<Map<String, dynamic>>();
    final dispatchApi = _FakeDispatchApi(() => createResult.future);
    await tester.pumpWidget(_wrap(AdminManualBookingCreatePage(
      bookingApi: _fakeBookingApi(totalAmount: 1000),
      vehicleTypeApi: _fakeVehicleTypeApi(),
      couponApi: const _FakeCouponApi(),
      dispatchApi: dispatchApi,
      initialOrigin: const LocationOption(
        id: 'bkk', displayName: 'BKK', kind: LocationKind.airport, code: 'BKK'),
      initialDestination: const LocationOption(
        id: 'pattaya', displayName: 'Pattaya', kind: LocationKind.city, code: 'PATTAYA'),
      initialServiceTypeCode: 'AIRPORT_PICKUP',
      initialPickupAt: DateTime.now().add(const Duration(days: 3)),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adminManualDispatchDirect')));
    await tester.pumpAndSettle();
    final driver = find.byKey(const Key('adminManualDirectDriver'));
    await tester.tap(driver);
    await tester.pump();
    await tester.tap(find.textContaining('QA Driver').last);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('adminManualBookingPayoutAmount')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('adminManualBookingPayoutAmount')),
      '800',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('adminManualBookingGuestName')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('adminManualBookingGuestName')),
      'QA Guest',
    );
    await tester.enterText(
      find.byKey(const Key('adminManualBookingGuestPhone')),
      '0812345678',
    );
    final submit = find.byKey(const Key('adminManualBookingSubmit'));
    await tester.scrollUntilVisible(
      submit,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(submit);
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    createResult.complete({'bookingNumber': 'TX202610130001'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('TX202610130001'), findsWidgets);
    expect(find.textContaining('기사가 배정되었습니다'), findsOneWidget);
    expect(find.textContaining('오픈콜이 생성되었습니다'), findsNothing);
    expect(find.byType(AdminManualBookingCreatePage), findsNothing);
  });

  testWidgets('direct dispatch lists eligible drivers and messenger fields', (
    tester,
  ) async {
    await _pumpAdminPage(tester);
    final direct = find.byKey(const Key('adminManualDispatchDirect'));
    await tester.ensureVisible(direct);
    await tester.tap(direct);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('adminManualDirectDriver')), findsOneWidget);
    await tester.tap(find.byKey(const Key('adminManualDirectDriver')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('QA Driver'), findsWidgets);
    expect(find.textContaining('Suspended Driver'), findsNothing);
    await tester.tap(find.textContaining('QA Driver').last);
    await tester.pump(const Duration(milliseconds: 400));

    final messenger = find.byKey(const Key('adminManualMessengerType'));
    await tester.scrollUntilVisible(
      messenger,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(messenger);
    await tester.pump();
    await tester.tap(messenger);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('카카오톡').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('adminManualMessengerId')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adminManualPhoneDialCode-+82')),
      findsOneWidget,
    );
    expect(find.text('카카오톡 ID (선택)'), findsOneWidget);
    expect(find.text('전화번호가 없으면 고객에게 연락하기 어려울 수 있습니다'), findsOneWidget);
    expect(find.text('카카오톡 가입 전화번호 (필수)'), findsNothing);
    await tester.tap(messenger);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('WhatsApp').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('adminManualMessengerId')), findsNothing);
    expect(
      find.byKey(const ValueKey('adminManualPhoneDialCode-+66')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('adminManualBookingGuestPhone')), findsOneWidget);
    expect(
      find.text('생성 후 바로 배정', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('edit mode tolerates sparse booking detail maps', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AdminManualBookingCreatePage(
          bookingApi: _fakeBookingApi(),
          vehicleTypeApi: _fakeVehicleTypeApi(),
          couponApi: const _FakeCouponApi(),
          dispatchApi: _FakeDispatchApi(
            () async => throw StateError('no create'),
            editDetail: {
              'bookingNumber': 'TX202609240002',
              'manualCallActions': {'canEdit': true},
              'route': {},
              'pricing': {'paymentMethod': 'PAY_DRIVER'},
              'customer': {},
            },
          ),
          editBookingNumber: 'TX202609240002',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('데이터를 불러오지 못했습니다. 다시 시도해 주세요.'), findsNothing);
    expect(find.text('관리자 콜 수정'), findsOneWidget);
  });

  testWidgets('edit mode parses string coordinates from booking detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AdminManualBookingCreatePage(
          bookingApi: _fakeBookingApi(),
          vehicleTypeApi: _fakeVehicleTypeApi(),
          couponApi: const _FakeCouponApi(),
          dispatchApi: _FakeDispatchApi(
            () async => throw StateError('no create'),
            editDetail: {
              'bookingNumber': 'TX202609230002',
              'manualCallActions': {'canEdit': true},
              'route': {
                'origin': {
                  'address': 'Origin',
                  'lat': '13.756330',
                  'lng': '100.501765',
                },
                'destination': {'address': 'Dest'},
              },
              'vehicle': {'typeCode': 'VAN'},
              'passengers': {'adults': 2},
              'pricing': {
                'paymentMethod': 'PAY_DRIVER',
                'chargeItems': [
                  {'chargeType': 'OTHER', 'amount': '1200'},
                ],
              },
              'customer': {'name': 'Guest'},
              'options': {},
            },
          ),
          editBookingNumber: 'TX202609230002',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('데이터를 불러오지 못했습니다. 다시 시도해 주세요.'), findsNothing);
    expect(find.text('관리자 콜 수정'), findsOneWidget);
  });

  testWidgets('edit mode loads admin manual booking detail into the form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AdminManualBookingCreatePage(
          bookingApi: _fakeBookingApi(),
          vehicleTypeApi: _fakeVehicleTypeApi(),
          couponApi: const _FakeCouponApi(),
          dispatchApi: _FakeDispatchApi(() async => throw StateError('no create')),
          editBookingNumber: 'TX202609240001',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('데이터를 불러오지 못했습니다. 다시 시도해 주세요.'), findsNothing);
    expect(find.text('관리자 콜 수정'), findsOneWidget);
  });

  testWidgets('edit mode restores passenger and luggage counters', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AdminManualBookingCreatePage(
          bookingApi: _fakeBookingApi(),
          vehicleTypeApi: _fakeVehicleTypeApi(),
          couponApi: const _FakeCouponApi(),
          dispatchApi: _FakeDispatchApi(
            () async => throw StateError('no create'),
            editDetail: {
              'bookingNumber': 'TX202609240003',
              'manualCallActions': {'canEdit': true},
              'scheduledPickupAt': '2026-09-24T03:30:00.000Z',
              'route': {
                'origin': {'address': 'A'},
                'destination': {'address': 'B'},
              },
              'vehicle': {'typeCode': 'SEDAN'},
              'serviceType': {'code': 'CITY_TRANSFER'},
              'passengers': {'adults': 2, 'children': 1, 'infants': 0},
              'luggage': {
                'carriers20Inch': 1,
                'carriers24InchPlus': 2,
                'golfBags': 0,
                'specialItems': 'wheelchair',
              },
              'serviceType': {'code': 'AIRPORT_PICKUP'},
              'flight': {'flightNumber': 'TG123', 'airportIata': 'BKK'},
              'pricing': {
                'paymentMethod': 'PAY_DRIVER',
                'chargeItems': [
                  {'chargeType': 'OTHER', 'amount': 500},
                ],
              },
              'customer': {'name': 'Guest'},
              'options': {'preferFemaleDriver': true},
            },
          ),
          editBookingNumber: 'TX202609240003',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('데이터를 불러오지 못했습니다. 다시 시도해 주세요.'), findsNothing);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('수하물'), 400, scrollable: scrollable);
    expect(find.text('인원'), findsOneWidget);
    expect(find.text('수하물'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('여성 기사 선호'),
      400,
      scrollable: scrollable,
    );
    expect(find.text('여성 기사 선호'), findsOneWidget);
  });

  testWidgets('still blocks submit when payout is filled but trip fields are missing', (
    tester,
  ) async {
    await _pumpAdminPage(tester);
    await tester.ensureVisible(find.byKey(const Key('adminManualBookingPayoutAmount')));
    await tester.enterText(
      find.byKey(const Key('adminManualBookingPayoutAmount')),
      '800',
    );
    await _tapSubmit(tester);
    expect(find.text('필수 항목을 모두 입력해주세요'), findsOneWidget);
  });
}
