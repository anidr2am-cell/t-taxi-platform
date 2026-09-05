import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/pages/coupons_page.dart';
import 'package:frontend/features/account/services/coupon_api_service.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCouponApiService extends CouponApiService {
  _FakeCouponApiService(this.items);

  final List<CustomerCouponItem> items;

  @override
  Future<List<CustomerCouponItem>> listCoupons() async => items;
}

Future<AuthController> _prepareLoggedInController() async {
  SharedPreferences.setMockInitialValues({
    AuthTokenStorage.accessTokenKey: 'access-token',
    AuthTokenStorage.refreshTokenKey: 'refresh-token',
    AuthTokenStorage.userJsonKey: jsonEncode({
      'id': 7,
      'email': 'saved@example.com',
      'role': 'CUSTOMER',
      'name': 'Saved User',
      'phone': null,
      'locale': 'ko',
      'isActive': true,
      'authProvider': 'KAKAO',
      'linkedProviders': ['KAKAO'],
    }),
  });

  final controller = AuthController(
    apiService: AuthApiService(
      client: MockClient((_) async => http.Response('{}', 500)),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: AuthTokenStorage(),
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
  );
  await controller.initialize();
  return controller;
}

Widget _wrapCouponsPage({
  required AuthController authController,
  required CouponApiService couponApiService,
}) {
  return MaterialApp(
    locale: const Locale('ko'),
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ko')],
    home: AuthScope(
      controller: authController,
      child: CouponsPage(couponApiService: couponApiService),
    ),
  );
}

void main() {
  testWidgets('coupons page separates available and used coupons', (tester) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapCouponsPage(
        authController: authController,
        couponApiService: _FakeCouponApiService(const [
          CustomerCouponItem(
            id: 1,
            title: 'Welcome',
            discountAmount: 200,
            status: 'AVAILABLE',
            issuedAt: '2026-09-01T10:00:00+07:00',
          ),
          CustomerCouponItem(
            id: 2,
            title: 'Used promo',
            discountAmount: 300,
            status: 'USED',
            usedAt: '2026-09-02T12:00:00+07:00',
            bookingNumber: 'TX202609020001',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Used promo'), findsOneWidget);
    expect(find.textContaining('TX202609020001'), findsOneWidget);
    expect(find.text('사용 가능한 쿠폰'), findsOneWidget);
    expect(find.text('사용한 쿠폰'), findsOneWidget);
  });

  testWidgets('coupons page renders legacy coupons without imageUrl', (tester) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapCouponsPage(
        authController: authController,
        couponApiService: _FakeCouponApiService(const [
          CustomerCouponItem(
            id: 3,
            title: 'Legacy only',
            discountAmount: 100,
            status: 'AVAILABLE',
            imageUrl: null,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Legacy only'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
