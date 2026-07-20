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
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/presentation/booking_accept_controller.dart';
import 'package:tride_driver/features/bookings/presentation/booking_detail_screen.dart';
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

Future<void> pumpDetail(
  WidgetTester tester,
  FakeBookingReader reader, {
  BookingAcceptController? acceptController,
  Future<void> Function()? onUnauthorized,
  VoidCallback? onAccepted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BookingDetailScreen(
        bookingNumber: 'TX209912319999',
        repository: reader,
        onUnauthorized: onUnauthorized ?? () async {},
        onAccepted: onAccepted,
        acceptController: acceptController,
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    expect(find.text('TX209912319999'), findsOneWidget);
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

  testWidgets('refresh failure replaces stale list and retry recovers', (
    tester,
  ) async {
    final reader = FakeBookingReader();
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(find.text('TX209912319999'), findsOneWidget);

    reader.listError = const ApiException(ApiFailureKind.unavailable);
    await tester.tap(find.byKey(const Key('refreshButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bookingListError')), findsOneWidget);
    expect(find.byKey(const Key('bookingListSuccess')), findsNothing);
    expect(find.text('TX209912319999'), findsNothing);

    reader.listError = null;
    await tester.tap(find.byKey(const Key('bookingListRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(find.text('TX209912319999'), findsOneWidget);
    expect(reader.listCount, 3);
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
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('detailLoading')), findsOneWidget);
    expect(reader.requestedBookingNumber, 'TX209912319999');
  });

  testWidgets('detail success displays read-only operational fields', (
    tester,
  ) async {
    await pumpBookingList(tester, FakeBookingReader());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
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
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
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
        ApiFailureKind.notFound,
        statusCode: 404,
        errorCode: 'BOOKING_NOT_FOUND',
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();
    expect(find.text('이 예약은 더 이상 배정 내역에서 확인할 수 없습니다.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detailBackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
  });

  testWidgets('detail error replaces stale success after repository update', (
    tester,
  ) async {
    final successReader = FakeBookingReader();
    const screenKey = Key('detailScreen');

    await tester.pumpWidget(
      MaterialApp(
        home: BookingDetailScreen(
          key: screenKey,
          bookingNumber: 'TX209912319999',
          repository: successReader,
          onUnauthorized: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(find.text('TX209912319999'), findsOneWidget);

    final missingReader = FakeBookingReader()
      ..detailError = const ApiException(
        ApiFailureKind.notFound,
        statusCode: 404,
        errorCode: 'BOOKING_NOT_FOUND',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: BookingDetailScreen(
          key: screenKey,
          bookingNumber: 'TX209912319999',
          repository: missingReader,
          onUnauthorized: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detailError')), findsOneWidget);
    expect(find.byKey(const Key('detailSuccess')), findsNothing);
    expect(find.text('TX209912319999'), findsNothing);
    expect(find.byKey(const Key('detailBackButton')), findsOneWidget);
    expect(missingReader.detailCount, 1);
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

  testWidgets('detail 401 expires auth and safely pops to login', (
    tester,
  ) async {
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    final authController = AuthController(
      AuthRepository(api: FakeAuthApi(), storage: storage),
    );
    final reader = FakeBookingReader()
      ..detailError = const ApiException(ApiFailureKind.unauthorized);
    await tester.pumpWidget(
      DriverApp(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        authController: authController,
        bookingRepository: reader,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();

    expect(find.text('기사 로그인'), findsOneWidget);
    expect(find.text('로그인이 만료되었습니다. 다시 로그인해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('detailLoading')), findsNothing);
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

  testWidgets('shows accept button only for DRIVER_ASSIGNED + ASSIGNED', (
    tester,
  ) async {
    await pumpDetail(tester, FakeBookingReader());
    expect(find.byKey(const Key('acceptBookingButton')), findsOneWidget);

    await pumpDetail(
      tester,
      FakeBookingReader()
        ..detailResult = bookingDetail(assignmentStatus: 'ACCEPTED'),
    );
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);

    await pumpDetail(
      tester,
      FakeBookingReader()..detailResult = bookingDetail(assignmentStatus: null),
    );
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);

    await pumpDetail(
      tester,
      FakeBookingReader()
        ..detailResult = bookingDetail(assignmentStatus: 'FUTURE_STATUS'),
    );
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);

    await pumpDetail(
      tester,
      FakeBookingReader()
        ..detailResult = bookingDetail(
          status: 'COMPLETED',
          assignmentStatus: 'ASSIGNED',
        ),
    );
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
  });

  testWidgets('accept button opens confirm dialog without API call', (
    tester,
  ) async {
    final reader = FakeBookingReader();
    await pumpDetail(tester, reader);
    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acceptConfirmDialog')), findsOneWidget);
    expect(reader.acceptCount, 0);
  });

  testWidgets('dialog cancel does not call accept API', (tester) async {
    final reader = FakeBookingReader();
    await pumpDetail(tester, reader);
    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptCancelButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acceptConfirmDialog')), findsNothing);
    expect(reader.acceptCount, 0);
  });

  testWidgets('dialog confirm calls accept once and removes button', (
    tester,
  ) async {
    var refreshCount = 0;
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(acceptanceEnvelope())
      ..detailResult = bookingDetail();
    await pumpDetail(tester, reader, onAccepted: () => refreshCount++);
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');

    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptConfirmButton')));
    await tester.pumpAndSettle();

    expect(reader.acceptCount, 1);
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
    expect(find.text('예약을 수락했습니다.'), findsOneWidget);
    expect(refreshCount, 1);
  });

  testWidgets('rapid taps still result in a single accept call', (
    tester,
  ) async {
    final completer = Completer<BookingAcceptance>();
    final reader = FakeBookingReader()
      ..acceptCompleter = completer
      ..detailResult = bookingDetail();
    final controller = BookingAcceptController(reader);
    await pumpDetail(tester, reader, acceptController: controller);

    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptConfirmButton')));
    await tester.pump();
    expect(find.byKey(const Key('acceptBookingLoading')), findsOneWidget);
    expect(reader.acceptCount, 1);

    completer.complete(BookingAcceptance.fromEnvelope(acceptanceEnvelope()));
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    await tester.pumpAndSettle();
    expect(reader.acceptCount, 1);
  });

  testWidgets('403 keeps detail open and shows admin guidance', (tester) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.forbidden);
    await pumpDetail(tester, reader);
    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(find.byKey(const Key('acceptBookingButton')), findsOneWidget);
    expect(find.textContaining('관리자에게 문의해 주세요'), findsOneWidget);
  });

  testWidgets('404 closes detail and refreshes list', (tester) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.notFound);
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    final listLoadsBefore = reader.listCount;
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(reader.listCount, greaterThan(listLoadsBefore));
  });

  testWidgets('timeout then ACCEPTED detail becomes success with one POST', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.timeout)
      ..detailResult = bookingDetail();
    await pumpDetail(tester, reader);
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');

    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptConfirmButton')));
    await tester.pumpAndSettle();

    expect(reader.acceptCount, 1);
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
    expect(find.text('예약을 수락했습니다.'), findsOneWidget);
  });

  testWidgets('dispose during accept does not throw', (tester) async {
    final completer = Completer<BookingAcceptance>();
    final reader = FakeBookingReader()..acceptCompleter = completer;
    await pumpDetail(tester, reader);
    await tester.tap(find.byKey(const Key('acceptBookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptConfirmButton')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(BookingAcceptance.fromEnvelope(acceptanceEnvelope()));
    await tester.pump();
  });
}
