import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/line_oauth_callback_guard.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/pages/line_oauth_callback_page.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/services/line_oauth_callback_guard_storage_memory.dart';
import 'package:frontend/features/auth/services/line_oauth_callback_url_stub.dart';
import 'package:frontend/features/auth/services/line_oauth_state_storage_memory.dart';
import 'package:frontend/features/auth/services/line_oauth_state_storage_prefs.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';
import 'support/booking_location_test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugStripLineCallbackCodeHook = null;
  });

  test('buildLineOAuthCallbackRoute matches callback path', () {
    final route = buildLineOAuthCallbackRoute(
      RouteSettings(
        name: 'https://trider.taxi/auth/line/callback?code=abc',
      ),
    );

    expect(route, isNotNull);
  });

  test('buildLineCallbackUriWithoutCode removes code and state', () {
    final uri = Uri.parse(
      'https://trider.taxi/auth/line/callback?code=abc123&state=xyz',
    );

    expect(
      buildLineCallbackUriWithoutCode(uri).toString(),
      'https://trider.taxi/auth/line/callback',
    );
  });

  testWidgets('callback stores tokens and restores booking complete page', (
    tester,
  ) async {
    final guardStorage = MemoryLineOAuthCallbackGuardStorage();
    final stateStorage = MemoryLineOAuthStateStorage('csrf-state-token');
    final returnContext = SocialLoginReturnContext.fromBookingCompleteForLine(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      origin: testBookingLocation(name: 'BKK Airport'),
      destination: testBookingLocation(name: 'Pattaya'),
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await SocialLoginReturnStorage().save(returnContext);

    final authController = _buildAuthController(
      onRequest: (request) async {
        expect(request.url.path, '/api/v1/auth/social/line');
        expect(
          jsonDecode(request.body) as Map<String, dynamic>,
          {
            'code': 'mock-line-code',
            'redirectUri': 'https://trider.taxi/auth/line/callback',
          },
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'line@example.com',
                'role': 'CUSTOMER',
                'name': 'Minji',
                'phone': null,
                'locale': 'ko',
                'isActive': true,
              },
            },
          }),
          200,
        );
      },
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: LineOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/line/callback?code=mock-line-code&state=csrf-state-token',
          ),
          guardStorage: guardStorage,
          stateStorage: stateStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'access-token');
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    expect(find.text('TX202607010001'), findsOneWidget);

    final stored = await guardStorage.load();
    expect(stored?.code, 'mock-line-code');
    expect(stored?.outcome, LineOAuthCallbackOutcome.success);
    expect(await stateStorage.load(), isNull);
  });

  testWidgets('callback with returnToHome navigates to home route', (
    tester,
  ) async {
    final guardStorage = MemoryLineOAuthCallbackGuardStorage();
    final stateStorage = MemoryLineOAuthStateStorage('csrf-state-token');
    await SocialLoginReturnStorage().save(
      SocialLoginReturnContext.fromLandingForLine(
        baseUri: Uri.parse('https://trider.taxi/'),
      ),
    );

    final authController = _buildAuthController(
      onRequest: (request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'line@example.com',
                'role': 'CUSTOMER',
                'name': 'Minji',
                'phone': null,
                'locale': 'ko',
                'isActive': true,
              },
            },
          }),
          200,
        );
      },
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapOAuthCallbackTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        callbackPage: LineOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/line/callback?code=mock-line-code&state=csrf-state-token',
          ),
          guardStorage: guardStorage,
          stateStorage: stateStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kOAuthCallbackHomeRouteKey), findsOneWidget);
    expect(find.text('TX202607010001'), findsNothing);
    expect(authController.isLoggedIn, isTrue);
  });

  testWidgets('state mismatch rejects callback without API call', (
    tester,
  ) async {
    final guardStorage = MemoryLineOAuthCallbackGuardStorage();
    final stateStorage = MemoryLineOAuthStateStorage('expected-state');
    await SocialLoginReturnStorage().save(
      SocialLoginReturnContext.fromBookingCompleteForLine(
        result: _result(),
        serviceLabel: 'Airport Pickup',
        enableCustomerTools: true,
        baseUri: Uri.parse('https://trider.taxi/booking'),
      ),
    );
    var apiCallCount = 0;

    final authController = _buildAuthController(
      onRequest: (request) async {
        apiCallCount += 1;
        return http.Response('{}', 500);
      },
    );
    await authController.initialize();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: LineOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/line/callback?code=mock-line-code&state=wrong-state',
          ),
          guardStorage: guardStorage,
          stateStorage: stateStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(apiCallCount, 0);
    expect(
      find.text('LINE 로그인을 확인할 수 없습니다. 다시 시도해 주세요.'),
      findsOneWidget,
    );
    expect(await guardStorage.load(), isNull);
    expect(await stateStorage.load(), 'expected-state');
  });

  test('SharedPreferencesLineOAuthStateStorage round-trips oauth state', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = SharedPreferencesLineOAuthStateStorage();

    await storage.save('csrf-state-token');
    expect(await storage.load(), 'csrf-state-token');

    final cleared = await storage.loadAndClear();
    expect(cleared, 'csrf-state-token');
    expect(await storage.load(), isNull);
  });

  testWidgets('double load during pending uses guard replay without state error', (
    tester,
  ) async {
    final guardStorage = MemoryLineOAuthCallbackGuardStorage();
    final stateStorage = MemoryLineOAuthStateStorage('csrf-state-token');
    var apiCallCount = 0;
    final returnContext = SocialLoginReturnContext.fromBookingCompleteForLine(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await SocialLoginReturnStorage().save(returnContext);

    final authController = _buildAuthController(
      onRequest: (request) async {
        apiCallCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'line@example.com',
                'role': 'CUSTOMER',
                'name': 'Minji',
                'phone': null,
                'locale': 'ko',
                'isActive': true,
              },
            },
          }),
          200,
        );
      },
    );
    await authController.initialize();

    final callbackUri = Uri.parse(
      'https://trider.taxi/auth/line/callback?code=mock-line-code&state=csrf-state-token',
    );

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: LineOAuthCallbackPage(
          uri: callbackUri,
          guardStorage: guardStorage,
          stateStorage: stateStorage,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: LineOAuthCallbackPage(
          uri: callbackUri,
          guardStorage: guardStorage,
          stateStorage: stateStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(apiCallCount, 1);
    expect(
      find.text('LINE 로그인을 확인할 수 없습니다. 다시 시도해 주세요.'),
      findsNothing,
    );
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
  });

  testWidgets('replayed callback with same code skips second API call', (
    tester,
  ) async {
    final guardStorage = MemoryLineOAuthCallbackGuardStorage();
    final stateStorage = MemoryLineOAuthStateStorage();
    var apiCallCount = 0;
    final returnContext = SocialLoginReturnContext.fromBookingCompleteForLine(
      result: _result(),
      serviceLabel: 'Airport Pickup',
      enableCustomerTools: true,
      baseUri: Uri.parse('https://trider.taxi/booking'),
    );
    await SocialLoginReturnStorage().save(returnContext);

    final authController = _buildAuthController(
      onRequest: (request) async {
        apiCallCount += 1;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'line@example.com',
                'role': 'CUSTOMER',
                'name': 'Minji',
                'phone': null,
                'locale': 'ko',
                'isActive': true,
              },
            },
          }),
          200,
        );
      },
    );
    await authController.initialize();

    Future<void> pumpCallbackPage() {
      return tester.pumpWidget(
        wrapBookingCompleteTestApp(
          authController: authController,
          locale: const Locale('ko'),
          includeAppLocalizations: true,
          home: LineOAuthCallbackPage(
            uri: Uri.parse(
              'https://trider.taxi/auth/line/callback?code=mock-line-code&state=csrf-state-token',
            ),
            guardStorage: guardStorage,
            stateStorage: MemoryLineOAuthStateStorage('csrf-state-token'),
          ),
        ),
      );
    }

    await pumpCallbackPage();
    await tester.pumpAndSettle();
    expect(apiCallCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await pumpCallbackPage();
    await tester.pumpAndSettle();
    expect(apiCallCount, 1);
    expect(find.text('Minji님, 연결되었습니다'), findsOneWidget);
    expect(find.text('Invalid LINE authorization code'), findsNothing);
  });

  test('default slow loading hint delay is 8 seconds', () {
    expect(kLineCallbackLoadingHintDelay, const Duration(seconds: 8));
  });

  testWidgets('slow loading hint appears after timeout', (tester) async {
    final guardStorage = MemoryLineOAuthCallbackGuardStorage();
    final stateStorage = MemoryLineOAuthStateStorage('csrf-state-token');
    await SocialLoginReturnStorage().save(
      SocialLoginReturnContext.fromBookingCompleteForLine(
        result: _result(),
        serviceLabel: 'Airport Pickup',
        enableCustomerTools: true,
        baseUri: Uri.parse('https://trider.taxi/booking'),
      ),
    );

    final authController = _buildAuthController(
      onRequest: (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'line@example.com',
                'role': 'CUSTOMER',
                'name': 'Minji',
                'phone': null,
                'locale': 'ko',
                'isActive': true,
              },
            },
          }),
          200,
        );
      },
    );

    await tester.pumpWidget(
      wrapBookingCompleteTestApp(
        authController: authController,
        locale: const Locale('ko'),
        includeAppLocalizations: true,
        home: LineOAuthCallbackPage(
          uri: Uri.parse(
            'https://trider.taxi/auth/line/callback?code=mock-line-code&state=csrf-state-token',
          ),
          guardStorage: guardStorage,
          stateStorage: stateStorage,
          loadingHintDelay: const Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('처리 시간이 오래 걸리고 있어요. 새로고침해 주세요.'),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(
      find.text('처리 시간이 오래 걸리고 있어요. 새로고침해 주세요.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('line_callback_refresh_button')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });
}

AuthController _buildAuthController({
  required Future<http.Response> Function(http.Request request) onRequest,
}) {
  return AuthController(
    apiService: AuthApiService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/customer/bookings/claim')) {
          return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
        }
        return onRequest(request);
      }),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: AuthTokenStorage(),
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
  );
}

BookingCreateResult _result() {
  return BookingCreateResult(
    bookingNumber: 'TX202607010001',
    status: 'PENDING',
    paymentMethod: 'PAY_DRIVER',
    paymentStatus: 'UNPAID',
    totalAmount: 1500,
    currency: 'THB',
    guestAccessToken: 'guest-token',
    boardingQrToken: 'boarding-token',
    trustMessage: 'Booking received',
  );
}
