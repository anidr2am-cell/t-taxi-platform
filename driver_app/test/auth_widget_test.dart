import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/app/app.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/locale/locale_controller.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/auth/data/auth_repository.dart';
import 'package:tride_driver/features/auth/presentation/auth_controller.dart';

import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

Future<(FakeAuthApi, FakeTokenStorage, AuthController, LocaleController)>
pumpApp(
  WidgetTester tester, {
  FakeAuthApi? api,
  FakeTokenStorage? storage,
  FakeAccountApi? accountApi,
  LocaleController? localeController,
  FakeDriverApplicationApi? driverApplicationApi,
}) async {
  final fakeApi = api ?? FakeAuthApi();
  final fakeStorage = storage ?? FakeTokenStorage();
  final controller = AuthController(
    AuthRepository(api: fakeApi, storage: fakeStorage),
  );
  final resolvedLocaleController =
      localeController ?? await createTestLocaleController();
  await tester.pumpWidget(
    DriverApp(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      authController: controller,
      localeController: resolvedLocaleController,
      bookingRepository: FakeBookingReader()
        ..listResult = bookingList(items: const []),
      dispatchRepository: FakeDispatchReader(),
      accountApi: accountApi,
      tokenStorage: fakeStorage,
      driverApplicationApi: driverApplicationApi ?? FakeDriverApplicationApi(),
    ),
  );
  await tester.pumpAndSettle();
  return (fakeApi, fakeStorage, controller, resolvedLocaleController);
}

Future<void> enterCredentials(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('loginIdField')), '0812345678');
  await tester.enterText(find.byKey(const Key('passwordField')), 'password');
}

void main() {
  testWidgets('renders login screen', (tester) async {
    await pumpApp(tester);
    expect(find.text('기사 로그인'), findsOneWidget);
    expect(find.byKey(const Key('loginButton')), findsOneWidget);
  });

  testWidgets(
    'login language selector menu opens and switches locale',
    (tester) async {
      final localeController = await createTestLocaleController(
        localeCode: 'ko',
      );
      await pumpApp(tester, localeController: localeController);

      expect(find.byKey(const Key('languageSelectorMenu')), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(localeController.locale.languageCode, 'ko');

      await tester.tap(find.byKey(const Key('languageSelectorMenu')));
      await tester.pumpAndSettle();

      expect(find.text('한국어'), findsWidgets);
      expect(find.text('ไทย'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(Overlay),
          matching: find.text('ไทย'),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(localeController.locale.languageCode, 'th');

      await tester.tap(find.byKey(const Key('languageSelectorMenu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Overlay),
          matching: find.text('한국어'),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(localeController.locale.languageCode, 'ko');
    },
  );

  testWidgets('validates required login fields', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump();
    expect(find.text('기사 계정을 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    await pumpApp(tester);
    EditableText field() => tester.widget(
      find.descendant(
        of: find.byKey(const Key('passwordField')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field().obscureText, isTrue);
    await tester.tap(find.byKey(const Key('passwordVisibilityButton')));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('disables login button while request is running', (tester) async {
    final api = FakeAuthApi()..loginCompleter = Completer();
    await pumpApp(tester, api: api);
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('loginButton')),
    );
    expect(button.onPressed, isNull);
    api.loginCompleter!.complete(driverSession());
    await tester.pumpAndSettle();
  });

  testWidgets('successful login shows the new calls tab', (tester) async {
    await pumpApp(tester);
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();
    expect(find.text('새 콜'), findsWidgets);
    expect(find.text('온라인으로 전환하면 새 콜을 볼 수 있습니다'), findsOneWidget);
  });

  testWidgets('invalid login shows a safe failure message', (tester) async {
    final api = FakeAuthApi()
      ..loginError = const ApiException(ApiFailureKind.invalidCredentials);
    await pumpApp(tester, api: api);
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();
    expect(find.text('계정 또는 비밀번호를 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('network failure shows a safe network message', (tester) async {
    final api = FakeAuthApi()
      ..loginError = const ApiException(ApiFailureKind.unavailable);
    await pumpApp(tester, api: api);
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();
    expect(find.text('서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('saved token automatically restores login', (tester) async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    final result = await pumpApp(tester, storage: storage);
    expect(find.text('새 콜'), findsWidgets);
    expect(result.$1.meCount, 1);
  });

  testWidgets('logout returns to login screen', (tester) async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    await pumpApp(tester, storage: storage, accountApi: FakeAccountApi());
    await tester.tap(find.text('계정'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('logoutButton')),
      240,
      scrollable: find.byType(Scrollable),
    );
    expect(find.byKey(const Key('logoutButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('logoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('기사 로그인'), findsOneWidget);
    expect(storage.clearCount, 1);
  });

  testWidgets('login screen shows signup and status check buttons', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('loginSignUpButton')), findsOneWidget);
    expect(find.byKey(const Key('loginCheckApplicationStatusButton')), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    expect(find.text('가입 신청 상태 확인'), findsOneWidget);
  });

  testWidgets('signup button opens driver application form', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('loginSignUpButton')));
    await tester.pumpAndSettle();
    expect(find.text('기사 등록 신청'), findsOneWidget);
  });

  testWidgets('status check button opens application status page', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('loginCheckApplicationStatusButton')));
    await tester.pumpAndSettle();
    expect(find.text('가입 신청 상태'), findsOneWidget);
    expect(find.byKey(const Key('driverApplicationStatusManualForm')), findsOneWidget);
  });

  testWidgets('saved application info highlights status check button', (
    tester,
  ) async {
    final storage = FakeTokenStorage()
      ..driverApplicationInfo = const DriverApplicationStoredInfo(
        applicationNumber: 'DA-SAVED',
        statusToken: 'token',
        submittedAt: '2026-07-28',
      );
    await pumpApp(tester, storage: storage);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is FilledButton &&
            widget.key == const Key('loginCheckApplicationStatusButton'),
      ),
      findsOneWidget,
    );
  });
}
