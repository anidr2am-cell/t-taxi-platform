import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/pages/account_page.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/customer_session.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerSession.resetSharedForTesting();
  });

  Future<AuthController> seedLoggedInController({
    required http.Client client,
    required AuthTokenStorage tokenStorage,
  }) async {
    await tokenStorage.saveSession(
      const AuthSession(
        accessToken: 'expired-access',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 36, role: 'CUSTOMER', email: 'line@example.com'),
      ),
    );
    final customerSession = CustomerSession(
      tokenStorage: tokenStorage,
      httpClient: client,
      baseUrl: 'http://localhost:3000',
    );
    final controller = AuthController(
      apiService: AuthApiService(
        client: client,
        baseUrl: 'http://localhost:3000',
        customerSession: customerSession,
      ),
      tokenStorage: tokenStorage,
      customerSession: customerSession,
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await controller.initialize();
    return controller;
  }

  Widget wrapAccountPage(AuthController authController) {
    return MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: [
        AppLocalizationsDelegate('ko'),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AuthScope(
        controller: authController,
        child: const AccountPage(),
      ),
    );
  }

  testWidgets(
    'account page uses auth controller session and refreshes expired mileage token',
    (tester) async {
      var refreshCalls = 0;
      var mileageCalls = 0;
      final tokenStorage = AuthTokenStorage();
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'accessToken': 'fresh-access', 'expiresIn': 3600},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/customer/mileage')) {
          mileageCalls++;
          final auth = request.headers['authorization'];
          if (auth == 'Bearer expired-access') {
            return http.Response(
              jsonEncode({
                'success': false,
                'error_code': 'UNAUTHORIZED',
                'message': 'Invalid or expired token',
              }),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'balance': 450},
            }),
            200,
          );
        }
        return http.Response('{}', 500);
      });

      final authController = await seedLoggedInController(
        client: client,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(wrapAccountPage(authController));
      await tester.pumpAndSettle();

      expect(refreshCalls, 1);
      expect(mileageCalls, 2);
      expect(find.byKey(const Key('account_mileage_balance')), findsOneWidget);
      expect(find.text('450P'), findsOneWidget);
      expect(await tokenStorage.readAccessToken(), 'fresh-access');
      expect(authController.isLoggedIn, isTrue);
    },
  );

  testWidgets(
    'account page rejects access-only storage without refresh token',
    (tester) async {
      final tokenStorage = AuthTokenStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AuthTokenStorage.accessTokenKey, 'access-only');
      await prefs.setString(
        AuthTokenStorage.userJsonKey,
        jsonEncode(
          const AuthUser(id: 36, role: 'CUSTOMER', email: 'line@example.com')
              .toJson(),
        ),
      );

      final client = MockClient((request) async {
        fail('No HTTP calls expected when refresh token is missing');
      });
      final customerSession = CustomerSession(
        tokenStorage: tokenStorage,
        httpClient: client,
        baseUrl: 'http://localhost:3000',
      );
      final authController = AuthController(
        apiService: AuthApiService(
          client: client,
          baseUrl: 'http://localhost:3000',
          customerSession: customerSession,
        ),
        tokenStorage: tokenStorage,
        customerSession: customerSession,
        googleSignInService: GoogleSignInService()..markInitializedForTest(),
      );
      await authController.initialize();
      expect(authController.isLoggedIn, isFalse);

      await tester.pumpWidget(wrapAccountPage(authController));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account_page_signed_out')), findsOneWidget);
    },
  );

  test(
    'default account wiring shares customer session between auth and mileage',
    () async {
      CustomerSession.resetSharedForTesting();
      final tokenStorage = AuthTokenStorage();
      final authController = AuthController(tokenStorage: tokenStorage);
      await authController.initialize();

      expect(
        identical(authController.customerSession, CustomerSession()),
        isTrue,
      );
    },
  );
}
