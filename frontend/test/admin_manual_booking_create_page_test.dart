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
  _FakeDispatchApi(this.onCreate);

  final Future<Map<String, dynamic>> Function() onCreate;

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
