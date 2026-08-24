import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-out [AuthController] for [BookingCompletePage] widget tests.
AuthController createSignedOutAuthController({http.Client? client}) {
  return AuthController(
    apiService: AuthApiService(
      client: client ?? MockClient((_) async => http.Response('{}', 500)),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: AuthTokenStorage(),
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
  );
}

Future<AuthController> prepareSignedOutAuthController({
  http.Client? client,
}) async {
  SharedPreferences.setMockInitialValues({});
  final controller = createSignedOutAuthController(client: client);
  await controller.initialize();
  return controller;
}

Widget wrapBookingCompleteTestApp({
  required Widget home,
  required AuthController authController,
  Locale locale = const Locale('en'),
  bool includeAppLocalizations = false,
}) {
  final delegates = <LocalizationsDelegate<dynamic>>[
    if (includeAppLocalizations) AppLocalizationsDelegate(locale.languageCode),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  return MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('en'),
      Locale('ko'),
      Locale('th'),
      Locale('ja'),
      Locale('zh'),
    ],
    localizationsDelegates: delegates,
    home: AuthScope(controller: authController, child: home),
  );
}

Future<void> pumpBookingCompleteTestApp(
  WidgetTester tester, {
  required Widget home,
  AuthController? authController,
  Locale locale = const Locale('en'),
  bool includeAppLocalizations = false,
  bool settle = false,
}) async {
  final controller =
      authController ?? await prepareSignedOutAuthController();
  if (!controller.isInitialized) {
    await controller.initialize();
  }

  await tester.pumpWidget(
    wrapBookingCompleteTestApp(
      home: home,
      authController: controller,
      locale: locale,
      includeAppLocalizations: includeAppLocalizations,
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  }
}
