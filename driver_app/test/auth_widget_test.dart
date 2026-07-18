import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/app/app.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/auth/data/auth_repository.dart';
import 'package:tride_driver/features/auth/presentation/auth_controller.dart';

import 'test_fakes.dart';

Future<(FakeAuthApi, FakeTokenStorage, AuthController)> pumpApp(
  WidgetTester tester, {
  FakeAuthApi? api,
  FakeTokenStorage? storage,
}) async {
  final fakeApi = api ?? FakeAuthApi();
  final fakeStorage = storage ?? FakeTokenStorage();
  final controller = AuthController(
    AuthRepository(api: fakeApi, storage: fakeStorage),
  );
  await tester.pumpWidget(
    DriverApp(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      authController: controller,
      bookingRepository: FakeBookingReader()
        ..listResult = bookingList(items: const []),
    ),
  );
  await tester.pumpAndSettle();
  return (fakeApi, fakeStorage, controller);
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

  testWidgets('successful login shows the booking list', (tester) async {
    await pumpApp(tester);
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 배정 예약'), findsOneWidget);
    expect(find.text('오늘 배정된 예약이 없습니다.'), findsOneWidget);
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
    expect(find.text('오늘의 배정 예약'), findsOneWidget);
    expect(result.$1.meCount, 1);
  });

  testWidgets('logout returns to login screen', (tester) async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    await pumpApp(tester, storage: storage);
    await tester.tap(find.byKey(const Key('logoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('기사 로그인'), findsOneWidget);
    expect(storage.clearCount, 1);
  });
}
