import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/pages/account_page.dart';
import 'package:frontend/features/account/services/mileage_api_service.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/pages/my_bookings_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMileageApiService extends MileageApiService {
  _FakeMileageApiService(this.result, {this.error});

  final MileageBalanceResult? result;
  final Object? error;

  @override
  Future<MileageBalanceResult> getMileageBalance() async {
    if (error != null) {
      throw error!;
    }
    return result!;
  }
}

Future<AuthController> _prepareLoggedInController() async {
  SharedPreferences.setMockInitialValues({
    AuthTokenStorage.accessTokenKey: 'saved-access',
    AuthTokenStorage.refreshTokenKey: 'saved-refresh',
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

Widget _wrapAccountPage({
  required AuthController authController,
  MileageApiService? mileageApiService,
}) {
  return MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routes: {
      '/my-bookings': (_) => const MyBookingsPage(),
    },
    home: AuthScope(
      controller: authController,
      child: AccountPage(mileageApiService: mileageApiService),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account page renders profile, mileage balance, and menus', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 1250),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_page')), findsOneWidget);
    expect(find.text('Saved User'), findsOneWidget);
    expect(find.text('saved@example.com'), findsOneWidget);
    expect(find.byKey(const Key('account_auth_provider_badge')), findsOneWidget);
    expect(find.text('카카오로 로그인'), findsOneWidget);
    expect(find.byKey(const Key('account_mileage_balance')), findsOneWidget);
    expect(find.text('1,250P'), findsOneWidget);
    expect(find.byKey(const Key('account_my_bookings_menu')), findsOneWidget);
    expect(find.byKey(const Key('account_logout_menu')), findsOneWidget);
  });

  testWidgets('account page shows mileage loading then error state', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          null,
          error: const MileageApiException('failed'),
        ),
      ),
    );

    await tester.pump();
    expect(find.byKey(const Key('account_mileage_loading')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_mileage_error')), findsOneWidget);
    expect(find.text('불러오기 실패'), findsOneWidget);
  });

  testWidgets('account page my bookings menu navigates to my bookings', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account_my_bookings_menu')));
    await tester.pumpAndSettle();

    expect(find.byType(MyBookingsPage), findsOneWidget);
  });

  testWidgets('account page logout signs out and shows snackbar', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account_logout_menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '로그아웃'));
    await tester.pumpAndSettle();

    expect(authController.isLoggedIn, isFalse);
    expect(find.text('로그아웃되었습니다'), findsOneWidget);
  });
}
