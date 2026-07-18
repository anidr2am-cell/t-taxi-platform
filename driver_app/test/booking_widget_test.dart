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
import 'package:tride_driver/features/bookings/presentation/booking_list_screen.dart';

import 'test_fakes.dart';

Future<void> pumpBookingList(
  WidgetTester tester,
  FakeBookingReader reader, {
  Future<void> Function()? onUnauthorized,
  Future<void> Function()? onLogout,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BookingListScreen(
        repository: reader,
        onUnauthorized: onUnauthorized ?? () async {},
        onLogout: onLogout ?? () async {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows list loading state', (tester) async {
    final reader = FakeBookingReader()..listCompleter = Completer();
    await pumpBookingList(tester, reader);
    await tester.pump();
    expect(find.byKey(const Key('bookingListLoading')), findsOneWidget);
  });

  testWidgets('shows assigned bookings', (tester) async {
    await pumpBookingList(tester, FakeBookingReader());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(find.text('TX202607180001'), findsOneWidget);
    expect(find.text('기사 배정'), findsOneWidget);
    expect(find.text('예상 수입 THB 900'), findsOneWidget);
  });

  testWidgets('shows empty list state', (tester) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(items: const []);
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListEmpty')), findsOneWidget);
    expect(find.text('오늘 배정된 예약이 없습니다.'), findsOneWidget);
  });

  testWidgets('shows list error and retries', (tester) async {
    final reader = FakeBookingReader()
      ..listError = const ApiException(ApiFailureKind.unavailable);
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListError')), findsOneWidget);

    reader.listError = null;
    await tester.tap(find.byKey(const Key('bookingListRetryButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(reader.listCount, 2);
  });

  testWidgets('refresh button reloads the list', (tester) async {
    final reader = FakeBookingReader();
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refreshButton')));
    await tester.pumpAndSettle();
    expect(reader.listCount, 2);
  });

  testWidgets('selecting a list item requests detail and shows loading', (
    tester,
  ) async {
    final reader = FakeBookingReader()..detailCompleter = Completer();
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX202607180001')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('detailLoading')), findsOneWidget);
    expect(reader.requestedBookingNumber, 'TX202607180001');
  });

  testWidgets('detail success displays read-only operational fields', (
    tester,
  ) async {
    await pumpBookingList(tester, FakeBookingReader());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX202607180001')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(find.text('운행 정보'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Synthetic fixture note'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Synthetic fixture note'), findsOneWidget);
    expect(find.text('THB 900'), findsOneWidget);
    expect(find.textContaining('전화'), findsNothing);
  });

  testWidgets('detail error retries successfully', (tester) async {
    final reader = FakeBookingReader()
      ..detailError = const ApiException(ApiFailureKind.server);
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX202607180001')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detailError')), findsOneWidget);

    reader.detailError = null;
    await tester.tap(find.byKey(const Key('detailRetryButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(reader.detailCount, 2);
  });

  testWidgets('missing reassigned booking offers return to list', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailError = const ApiException(
        ApiFailureKind.unknown,
        statusCode: 404,
        errorCode: 'BOOKING_NOT_FOUND',
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX202607180001')));
    await tester.pumpAndSettle();
    expect(find.text('이 예약은 더 이상 배정 내역에서 확인할 수 없습니다.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detailBackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
  });

  testWidgets('booking 401 clears local token and returns to login', (
    tester,
  ) async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    final authController = AuthController(
      AuthRepository(api: FakeAuthApi(), storage: storage),
    );
    final reader = FakeBookingReader()
      ..listError = const ApiException(ApiFailureKind.unauthorized);
    await tester.pumpWidget(
      DriverApp(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        authController: authController,
        bookingRepository: reader,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기사 로그인'), findsOneWidget);
    expect(find.text('로그인이 만료되었습니다. 다시 로그인해 주세요.'), findsOneWidget);
    expect(storage.tokens, isNull);
    expect(storage.clearCount, 1);
  });

  testWidgets('logout action remains connected to auth flow', (tester) async {
    var logoutCount = 0;
    await pumpBookingList(
      tester,
      FakeBookingReader(),
      onLogout: () async => logoutCount++,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logoutButton')));
    await tester.pump();
    expect(logoutCount, 1);
  });
}
