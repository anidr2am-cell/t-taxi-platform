import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_coupon/services/admin_coupon_api_service.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_manual_booking_create_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _FakeCouponApi extends AdminCouponApiService {
  const _FakeCouponApi();

  @override
  Future<List<AdminCustomerSearchResult>> searchCustomers(String query) async {
    return const [];
  }
}

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
    String? serviceTypeCode,
    bool nameSign = false,
    String? nameSignText,
  }) {
    return onCreate();
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
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
}

void main() {
  testWidgets('blocks submit when payout amount is missing', (tester) async {
    await _pumpAdminPage(tester);
    await _tapSubmit(tester);
    expect(find.text('필수 항목을 모두 입력해주세요'), findsOneWidget);
  });

  testWidgets('edit mode tolerates sparse booking detail maps', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AdminManualBookingCreatePage(
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

  testWidgets('edit mode loads admin manual booking detail into the form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AdminManualBookingCreatePage(
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
