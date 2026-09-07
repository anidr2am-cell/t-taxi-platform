import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/pages/profile_completion_page.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/customer_profile_api_service.dart';
import 'package:frontend/features/auth/services/customer_session.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/services/social_login_navigation.dart';
import 'package:frontend/features/auth/utils/profile_completion.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/auth/widgets/profile_completion_gate.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_complete_test_helpers.dart';

AuthUser _user({String? phone}) {
  return AuthUser(
    id: 42,
    role: 'CUSTOMER',
    email: 'social@example.com',
    name: 'Customer',
    phone: phone,
    authProvider: 'KAKAO',
  );
}

Future<AuthController> _controllerWithSession({
  String? phone,
  http.Client? client,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tokenStorage = AuthTokenStorage();
  await tokenStorage.saveSession(
    AuthSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      user: _user(phone: phone),
      expiresIn: 3600,
    ),
  );
  final controller = AuthController(
    apiService: AuthApiService(
      client: client ?? MockClient((_) async => http.Response('{}', 500)),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: tokenStorage,
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
  );
  await controller.initialize();
  return controller;
}

Future<AuthController> _controllerWithLegacyPersistedSession(
  Map<String, dynamic> userJson,
) async {
  SharedPreferences.setMockInitialValues({
    AuthTokenStorage.accessTokenKey: 'legacy-access-token',
    AuthTokenStorage.refreshTokenKey: 'legacy-refresh-token',
    AuthTokenStorage.userJsonKey: jsonEncode(userJson),
    AuthTokenStorage.accessTokenExpiresAtKey: DateTime.now()
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String(),
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

final _testLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizationsDelegate('ko'),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _wrapApp({
  required AuthController authController,
  required Widget home,
}) {
  return MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: _testLocalizationDelegates,
    home: AuthScope(
      controller: authController,
      child: ProfileCompletionGate(child: home),
    ),
  );
}

class _DelayedLoadSessionTokenStorage extends AuthTokenStorage {
  _DelayedLoadSessionTokenStorage(this._session, this._delay);

  final AuthSession _session;
  final Duration _delay;

  @override
  Future<AuthSession?> loadSession() async {
    await Future<void>.delayed(_delay);
    return _session;
  }
}

class _RecordingProfileApiService extends CustomerProfileApiService {
  _RecordingProfileApiService(this.onUpdate)
    : super(session: CustomerSession(baseUrl: 'http://localhost:3000'));

  final Future<AuthUser> Function({
    required String name,
    required String phone,
    String? phoneCountryCode,
  })
  onUpdate;

  @override
  Future<AuthUser> updateProfile({
    required String name,
    required String phone,
    String? phoneCountryCode,
  }) {
    return onUpdate(
      name: name,
      phone: phone,
      phoneCountryCode: phoneCountryCode,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authNeedsProfileCompletion is true only when phone is null or blank', () {
    expect(authUserNeedsProfileCompletion(null), isFalse);
    expect(authUserNeedsProfileCompletion(_user(phone: null)), isTrue);
    expect(authUserNeedsProfileCompletion(_user(phone: '  ')), isTrue);
    expect(authUserNeedsProfileCompletion(_user(phone: '+821012345678')), isFalse);
  });

  test('guest without persisted session never needs profile completion', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AuthController(
      apiService: AuthApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await controller.initialize();

    expect(controller.isLoggedIn, isFalse);
    expect(controller.user, isNull);
    expect(authNeedsProfileCompletion(controller), isFalse);
    expect(controller.needsProfileCompletion, isFalse);
  });

  testWidgets('guest user is not blocked by profile completion gate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AuthController(
      apiService: AuthApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: AuthTokenStorage(),
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.isLoggedIn, isFalse);
    expect(find.text('Home landing'), findsOneWidget);
    expect(find.text('프로필 완성'), findsNothing);
  });

  testWidgets('legacy persisted social session without phone opens onboarding gate', (
    tester,
  ) async {
    final controller = await _controllerWithLegacyPersistedSession({
      'id': 88,
      'role': 'CUSTOMER',
      'email': 'kakao.social@example.com',
      'name': 'Customer',
      'phone': null,
      'locale': 'ko',
      'isActive': true,
      'authProvider': 'KAKAO',
      'linkedProviders': ['KAKAO'],
    });

    expect(controller.isLoggedIn, isTrue);
    expect(controller.hadPersistedSessionAtInit, isTrue);
    expect(controller.user?.phone, isNull);

    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home landing'), findsNothing);
    expect(find.text('프로필 완성'), findsOneWidget);
  });

  testWidgets('legacy persisted session missing phone key opens onboarding gate', (
    tester,
  ) async {
    final controller = await _controllerWithLegacyPersistedSession({
      'id': 91,
      'role': 'CUSTOMER',
      'email': 'line.social@example.com',
      'name': 'LINE User',
      'locale': 'ko',
      'isActive': true,
      'authProvider': 'LINE',
    });

    expect(controller.isLoggedIn, isTrue);
    expect(controller.user?.phone, isNull);

    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('프로필 완성'), findsOneWidget);
  });

  testWidgets('legacy persisted email signup session with phone skips gate', (
    tester,
  ) async {
    final controller = await _controllerWithLegacyPersistedSession({
      'id': 12,
      'role': 'CUSTOMER',
      'email': 'member@example.com',
      'name': 'Email Member',
      'phone': '+821099887766',
      'locale': 'ko',
      'isActive': true,
    });

    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home landing'), findsOneWidget);
    expect(find.text('프로필 완성'), findsNothing);
  });

  testWidgets('gate rebuilds after async auth initialization on cold start', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AuthController(
      apiService: AuthApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
        baseUrl: 'http://localhost:3000',
      ),
      tokenStorage: _DelayedLoadSessionTokenStorage(
        AuthSession(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          user: _user(phone: null),
          expiresIn: 3600,
        ),
        const Duration(milliseconds: 100),
      ),
      googleSignInService: GoogleSignInService()..markInitializedForTest(),
    );
    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pump();

    expect(find.text('Home landing'), findsOneWidget);
    expect(find.text('프로필 완성'), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('Home landing'), findsNothing);
    expect(find.text('프로필 완성'), findsOneWidget);
  });

  testWidgets('restored session with null phone shows profile completion gate', (
    tester,
  ) async {
    final controller = await _controllerWithSession(phone: null);

    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home landing'), findsNothing);
    expect(find.text('프로필 완성'), findsOneWidget);
    expect(find.byKey(const Key('profile_completion_submit_button')), findsOneWidget);
  });

  testWidgets('restored session with phone skips profile completion gate', (
    tester,
  ) async {
    final controller = await _controllerWithSession(phone: '+821012345678');

    await tester.pumpWidget(
      _wrapApp(
        authController: controller,
        home: const Scaffold(body: Text('Home landing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home landing'), findsOneWidget);
    expect(find.text('프로필 완성'), findsNothing);
  });

  testWidgets('navigateAfterAuthenticatedSession routes null-phone user to onboarding', (
    tester,
  ) async {
    final controller = await _controllerWithSession(phone: null);
    const returnContext = SocialLoginReturnContext(
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
      serviceLabel: '',
      returnToHome: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: _testLocalizationDelegates,
        routes: {
          ProfileCompletionPage.routeName: (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            return AuthScope(
              controller: controller,
              child: ProfileCompletionPage(
                returnContext: args is ProfileCompletionRouteArgs
                    ? args.returnContext
                    : null,
              ),
            );
          },
        },
        home: AuthScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () {
                    navigateAfterAuthenticatedSession(
                      context,
                      authController: controller,
                      returnContext: returnContext,
                    );
                  },
                  child: const Text('Continue login'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue login'));
    await tester.pumpAndSettle();

    expect(find.text('프로필 완성'), findsOneWidget);
    expect(find.text('Continue login'), findsNothing);
  });

  testWidgets('phone user continues to home without onboarding', (tester) async {
    final controller = await _controllerWithSession(phone: '+821012345678');
    const returnContext = SocialLoginReturnContext(
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
      serviceLabel: '',
      returnToHome: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: _testLocalizationDelegates,
        routes: {
          '/start': (_) => AuthScope(
            controller: controller,
            child: Builder(
              builder: (context) {
                return Scaffold(
                  body: FilledButton(
                    onPressed: () {
                      navigateAfterAuthenticatedSession(
                        context,
                        authController: controller,
                        returnContext: returnContext,
                      );
                    },
                    child: const Text('Continue login'),
                  ),
                );
              },
            ),
          ),
          '/': (_) => const Scaffold(body: Text('Home landing')),
        },
        initialRoute: '/start',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue login'));
    await tester.pumpAndSettle();

    expect(find.text('프로필 완성'), findsNothing);
    expect(find.text('Home landing'), findsOneWidget);
  });

  testWidgets('successful onboarding updates session and navigates home', (
    tester,
  ) async {
    final controller = await _controllerWithSession(phone: null);
    const returnContext = SocialLoginReturnContext(
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
      serviceLabel: '',
      returnToHome: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: _testLocalizationDelegates,
        routes: {
          '/': (_) => const Scaffold(body: Text('Home landing')),
          ProfileCompletionPage.routeName: (_) => AuthScope(
            controller: controller,
            child: ProfileCompletionPage(
              returnContext: returnContext,
              apiService: _RecordingProfileApiService(({required name, required phone, phoneCountryCode}) async {
                return _user(phone: phone).copyWith(name: name);
              }),
            ),
          ),
        },
        initialRoute: ProfileCompletionPage.routeName,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Alice Kim');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '+821012345678');
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile_completion_submit_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.user?.phone, '+821012345678');
    expect(controller.user?.name, 'Alice Kim');
    expect(find.text('Home landing'), findsOneWidget);
  });

  testWidgets('409 duplicate phone shows inline error and stays on onboarding', (
    tester,
  ) async {
    final controller = await _controllerWithSession(phone: null);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: _testLocalizationDelegates,
        home: AuthScope(
          controller: controller,
          child: ProfileCompletionPage(
            apiService: _RecordingProfileApiService(({required name, required phone, phoneCountryCode}) async {
              throw const CustomerProfileApiException(
                '이미 다른 계정에서 사용 중인 전화번호입니다',
                statusCode: 409,
                field: 'phone',
              );
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Alice Kim');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '+821012345678');
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile_completion_submit_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('프로필 완성'), findsOneWidget);
    expect(find.textContaining('이미 다른 계정'), findsWidgets);
    expect(controller.user?.phone, isNull);
  });
}
