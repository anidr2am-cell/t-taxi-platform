import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
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
import 'package:tride_driver/features/dispatch/data/driver_socket_service.dart';

import 'test_fakes.dart';

Future<void> pumpBookingList(
  WidgetTester tester,
  FakeBookingReader reader, {
  Future<void> Function()? onUnauthorized,
  Stream<DriverSocketEvent>? socketEvents,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BookingListScreen(
        repository: reader,
        onUnauthorized: onUnauthorized ?? () async {},
        socketEvents: socketEvents,
      ),
    ),
  );
}

Future<void> pumpDetail(
  WidgetTester tester,
  FakeBookingReader reader, {
  BookingAcceptController? acceptController,
  Future<void> Function()? onUnauthorized,
  ExternalUrlLauncher? externalUrlLauncher,
  DateTime Function()? now,
  Stream<DriverSocketEvent>? socketEvents,
  NameSignPhotoPicker? nameSignPhotoPicker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BookingDetailScreen(
        bookingNumber: 'TX209912319999',
        repository: reader,
        onUnauthorized: onUnauthorized ?? () async {},
        acceptController: acceptController,
        externalUrlLauncher: externalUrlLauncher,
        now: now,
        socketEvents: socketEvents,
        nameSignPhotoPicker: nameSignPhotoPicker,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> confirmAccept(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('acceptBookingButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('acceptConfirmButton')));
  await tester.pumpAndSettle();
}

Future<void> selectNameSignPhotoFromGallery(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('uploadNameSignPhotoButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nameSignPhotoGallery')));
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
    final reader = FakeBookingReader()
      ..listResult = bookingList(
        items: [
          bookingSummary(
            scheduledPickupAt: '2026-07-18T10:15:00.000+07:00',
            standbyReferenceTime: '2026-07-18T09:45:00.000+07:00',
          ),
        ],
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(find.text('TX209912319999'), findsOneWidget);
    expect(find.text('기사 배정'), findsOneWidget);
    expect(find.text('2026-07-18 10:15'), findsOneWidget);
    expect(find.text('대기 기준 2026-07-18 09:45'), findsOneWidget);
    expect(
      find.text('Suvarnabhumi Airport\n999 Nong Prue, Bang Phli'),
      findsOneWidget,
    );
    expect(find.text('Test Hotel\nBangkok'), findsOneWidget);
    expect(find.text('예상 수입 THB 900'), findsOneWidget);
  });

  testWidgets('list prefers nameTh over name for pickup and destination', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(
        items: [
          bookingSummary(
            scheduledPickupAt: '2026-07-18T10:15:00.000+07:00',
            pickupLocationName: 'BKK — Suvarnabhumi Airport',
            pickupLocationNameTh: 'ท่าอากาศยานสุวรรณภูมิ',
            destinationLocationName: 'Test Hotel',
            destinationLocationNameTh: 'โรงแรมทดสอบ',
          ),
        ],
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();

    expect(
      find.text('ท่าอากาศยานสุวรรณภูมิ\n999 Nong Prue, Bang Phli'),
      findsOneWidget,
    );
    expect(find.text('โรงแรมทดสอบ\nBangkok'), findsOneWidget);
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
      find.text('네임보드'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('네임보드'), findsOneWidget);
    expect(find.text('요청됨'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Synthetic fixture note'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Synthetic fixture note'), findsOneWidget);
    expect(find.text('THB 900'), findsOneWidget);
    expect(find.textContaining('전화'), findsNothing);
  });

  testWidgets('detail shows createdAt below pickup when available', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        createdAt: '2026-07-12T08:30:00.000Z',
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();

    expect(find.text('2026-07-18 09:30'), findsOneWidget);
    expect(find.text('예약: 7월 12일 15시 30분'), findsOneWidget);
    expect(find.byKey(const Key('bookingCreatedAtLabel')), findsOneWidget);
  });

  testWidgets('detail hides createdAt label when missing', (tester) async {
    await pumpBookingList(tester, FakeBookingReader());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();

    expect(find.text('2026-07-18 09:30'), findsOneWidget);
    expect(find.textContaining('예약:'), findsNothing);
    expect(find.byKey(const Key('bookingCreatedAtLabel')), findsNothing);
  });

  testWidgets('detail prefers nameTh over name for pickup and destination', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(items: [bookingSummary()])
      ..detailResult = bookingDetail(
        pickupLocationName: 'BKK — Suvarnabhumi Airport',
        pickupLocationNameTh: 'ท่าอากาศยานสุวรรณภูมิ',
        destinationLocationName: 'Test Hotel',
        destinationLocationNameTh: 'โรงแรมทดสอบ',
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();

    expect(
      find.text('ท่าอากาศยานสุวรรณภูมิ\n999 Nong Prue, Bang Phli'),
      findsOneWidget,
    );
    expect(find.text('โรงแรมทดสอบ\nBangkok'), findsOneWidget);
  });

  testWidgets('detail error retries successfully', (tester) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(
        items: [
          bookingSummary(
            allowedActions: const ['VIEW_DETAILS', 'ACCEPT_BOOKING'],
          ),
        ],
      )
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
        dispatchRepository: FakeDispatchReader(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 운행'));
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
        dispatchRepository: FakeDispatchReader(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 운행'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();

    expect(find.text('기사 로그인'), findsOneWidget);
    expect(find.text('로그인이 만료되었습니다. 다시 로그인해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('detailLoading')), findsNothing);
    expect(storage.tokens, isNull);
    expect(storage.clearCount, 1);
  });

  testWidgets('booking list does not expose logout action', (tester) async {
    await pumpBookingList(tester, FakeBookingReader());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logoutButton')), findsNothing);
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

  testWidgets(
    'before standby time shows disabled state and allowed-time notice',
    (tester) async {
      final reader = FakeBookingReader()
        ..detailResult = bookingDetail(
          canConfirmStandby: false,
          standbyAllowedAt: '2026-07-18T01:30:00.000Z',
        );

      await pumpDetail(tester, reader);

      expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
      final pendingButton = tester.widget<FilledButton>(
        find.byKey(const Key('standbyPendingButton')),
      );
      expect(pendingButton.onPressed, isNull);
      expect(find.text('2026-07-18 08:30부터 대기 확정 가능'), findsOneWidget);
    },
  );

  testWidgets('after standby time with ACCEPT_BOOKING shows enabled button', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        canConfirmStandby: true,
        allowedActions: const ['VIEW_DETAILS', 'ACCEPT_BOOKING'],
      );

    await pumpDetail(tester, reader);

    final acceptButton = tester.widget<FilledButton>(
      find.byKey(const Key('acceptBookingButton')),
    );
    expect(acceptButton.onPressed, isNotNull);
    expect(find.byKey(const Key('standbyAllowedAtNotice')), findsNothing);
  });

  testWidgets('without ACCEPT_BOOKING action hides accept button', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        canConfirmStandby: true,
        allowedActions: const ['VIEW_DETAILS'],
      );

    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
    expect(find.byKey(const Key('standbyPendingButton')), findsNothing);
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
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(acceptanceEnvelope())
      ..detailResult = bookingDetail();
    await pumpDetail(tester, reader);
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');

    await confirmAccept(tester);

    expect(reader.acceptCount, 1);
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
    expect(find.text('예약을 수락했습니다.'), findsOneWidget);
  });

  testWidgets('accept success refreshes list once only after leaving detail', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..acceptResult = BookingAcceptance.fromEnvelope(acceptanceEnvelope())
      ..detailResult = bookingDetail();
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    final listLoadsBeforeDetail = reader.listCount;

    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');
    await confirmAccept(tester);

    expect(reader.acceptCount, 1);
    expect(reader.listCount, listLoadsBeforeDetail);
    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(reader.listCount, listLoadsBeforeDetail + 1);
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
    await confirmAccept(tester);

    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(find.byKey(const Key('acceptBookingButton')), findsOneWidget);
    expect(find.textContaining('관리자에게 문의해 주세요'), findsOneWidget);
  });

  testWidgets('standby too early shows a clear Korean guidance message', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(
        ApiFailureKind.standbyTooEarly,
        statusCode: 409,
        errorCode: 'DRIVER_STANDBY_TOO_EARLY',
      );
    await pumpDetail(tester, reader);

    await confirmAccept(tester);

    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(find.textContaining('아직 대기 확정 시간이 아닙니다.'), findsOneWidget);
    expect(reader.acceptCount, 1);
  });

  testWidgets('missing standby reference shows administrator guidance', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(
        ApiFailureKind.standbyReferenceTimeMissing,
        statusCode: 409,
        errorCode: 'DRIVER_STANDBY_REFERENCE_TIME_MISSING',
      );
    await pumpDetail(tester, reader);

    await confirmAccept(tester);

    expect(find.textContaining('대기 확정 기준 시간을 확인할 수 없습니다.'), findsOneWidget);
    expect(find.textContaining('관리자에게 문의해 주세요.'), findsOneWidget);
    expect(reader.acceptCount, 1);
  });

  testWidgets('404 closes detail and refreshes list once', (tester) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.notFound);
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    final listLoadsBefore = reader.listCount;
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();
    await confirmAccept(tester);

    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(reader.listCount, listLoadsBefore + 1);
  });

  testWidgets('timeout then ACCEPTED detail becomes success with one POST', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..acceptError = const ApiException(ApiFailureKind.timeout)
      ..detailResult = bookingDetail();
    await pumpDetail(tester, reader);
    reader.detailResult = bookingDetail(assignmentStatus: 'ACCEPTED');

    await confirmAccept(tester);

    expect(reader.acceptCount, 1);
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
    expect(find.text('예약을 수락했습니다.'), findsOneWidget);
  });

  testWidgets('AppBar back pops without refresh when unchanged', (
    tester,
  ) async {
    final reader = FakeBookingReader();
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    final listLoadsBefore = reader.listCount;

    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(reader.listCount, listLoadsBefore);
  });

  testWidgets('system back pops detail without exception', (tester) async {
    final reader = FakeBookingReader();
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();

    final popped = await tester.binding.handlePopRoute();
    expect(popped, isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
  });

  testWidgets('BKK airport pickup with name sign shows Gate 3 meeting place', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(nameSignRequested: true);
    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('bkkMeetingGateBanner')), findsOneWidget);
    expect(find.text('미팅 장소: 3번 게이트 (피켓 요청됨)'), findsOneWidget);
    expect(find.textContaining('7번 게이트'), findsNothing);
  });

  testWidgets(
    'BKK airport pickup without name sign shows Gate 7 meeting place',
    (tester) async {
      final reader = FakeBookingReader()
        ..detailResult = bookingDetail(nameSignRequested: false);
      await pumpDetail(tester, reader);

      expect(find.byKey(const Key('bkkMeetingGateBanner')), findsOneWidget);
      expect(find.text('미팅 장소: 7번 게이트'), findsOneWidget);
      expect(find.textContaining('3번 게이트'), findsNothing);
    },
  );

  testWidgets('non-airport pickup does not show meeting gate banner', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        serviceTypeCode: 'CITY_TRANSFER',
        serviceTypeName: 'City transfer',
        origin: 'Bangkok Hotel',
        pickupLocationName: 'Bangkok Hotel',
        pickupLocationAddress: 'Sukhumvit Road',
      );
    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('bkkMeetingGateBanner')), findsNothing);
    expect(find.textContaining('게이트'), findsNothing);
  });

  testWidgets('airport pickup outside BKK does not show meeting gate banner', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        nameSignRequested: true,
        origin: 'DMK Airport',
        pickupLocationName: 'DMK Airport',
        pickupLocationAddress: 'Don Mueang International Airport',
      );
    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('bkkMeetingGateBanner')), findsNothing);
    expect(find.textContaining('게이트'), findsNothing);
  });

  testWidgets('DRIVER_ARRIVED emphasizes name-sign photo upload', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'DRIVER_ARRIVED',
        assignmentStatus: 'ACCEPTED',
        allowedActions: const ['MARK_PICKED_UP'],
      );
    await pumpDetail(tester, reader);

    final button = find.byKey(const Key('uploadNameSignPhotoButton'));
    expect(button, findsOneWidget);
    expect(tester.widget(button), isA<FilledButton>());
    expect(find.text('피켓 사진 업로드'), findsOneWidget);
  });

  testWidgets('ON_ROUTE allows weaker upload with airport-arrival guidance', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'ON_ROUTE',
        assignmentStatus: 'ACCEPTED',
        allowedActions: const ['MARK_ARRIVED'],
      );
    await pumpDetail(tester, reader);

    final button = find.byKey(const Key('uploadNameSignPhotoButton'));
    expect(button, findsOneWidget);
    expect(tester.widget(button), isA<OutlinedButton>());
    expect(find.byKey(const Key('nameSignPhotoOnRouteNotice')), findsOneWidget);
  });

  testWidgets('PICKED_UP hides upload and shows existing photo as view-only', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'PICKED_UP',
        assignmentStatus: 'ACCEPTED',
        allowedActions: const ['END_TRIP'],
        nameSignPhotoUrl:
            '/api/v1/driver/bookings/TX209912319999/name-sign-photo',
      );
    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('uploadNameSignPhotoButton')), findsNothing);
    expect(find.byKey(const Key('nameSignPhotoViewOnly')), findsOneWidget);
    expect(find.byKey(const Key('nameSignPhotoPreview')), findsOneWidget);
  });

  testWidgets(
    'name-sign photo upload updates preview and marks detail changed',
    (tester) async {
      final reader = FakeBookingReader()
        ..detailResult = bookingDetail(
          status: 'DRIVER_ARRIVED',
          assignmentStatus: 'ACCEPTED',
          allowedActions: const ['MARK_PICKED_UP'],
        );
      await pumpDetail(
        tester,
        reader,
        nameSignPhotoPicker: (source) async {
          expect(source, ImageSource.gallery);
          return const NameSignPhotoFile(
            filename: 'gate-sign.jpg',
            bytes: [1, 2, 3],
          );
        },
      );

      await selectNameSignPhotoFromGallery(tester);

      expect(reader.nameSignPhotoUploadCount, 1);
      expect(reader.nameSignPhotoLoadCount, 1);
      expect(find.byKey(const Key('nameSignPhotoPreview')), findsOneWidget);
      expect(find.text('피켓 사진이 업로드되었습니다.'), findsOneWidget);
      expect(find.text('다시 촬영/교체'), findsOneWidget);
    },
  );

  testWidgets('existing name-sign photo can be replaced', (tester) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'DRIVER_ARRIVED',
        assignmentStatus: 'ACCEPTED',
        allowedActions: const ['MARK_PICKED_UP'],
        nameSignPhotoUrl:
            '/api/v1/driver/bookings/TX209912319999/name-sign-photo',
      );
    await pumpDetail(
      tester,
      reader,
      nameSignPhotoPicker: (_) async => const NameSignPhotoFile(
        filename: 'replacement.webp',
        bytes: [4, 5, 6],
      ),
    );

    expect(find.text('다시 촬영/교체'), findsOneWidget);
    await selectNameSignPhotoFromGallery(tester);

    expect(reader.nameSignPhotoUploadCount, 1);
    expect(find.text('피켓 사진이 교체되었습니다.'), findsOneWidget);
  });

  for (final scenario in [
    (
      ApiException(
        ApiFailureKind.validation,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
      ),
      '피켓 사진과 현재 예약 상태를 다시 확인해 주세요.',
    ),
    (
      ApiException(
        ApiFailureKind.invalidFileType,
        statusCode: 400,
        errorCode: 'INVALID_FILE_TYPE',
      ),
      'JPG, JPEG, PNG, WEBP 사진만 업로드할 수 있습니다.',
    ),
    (
      ApiException(
        ApiFailureKind.fileTooLarge,
        statusCode: 400,
        errorCode: 'FILE_TOO_LARGE',
      ),
      '파일 크기가 너무 큽니다. 더 작은 사진을 선택해 주세요.',
    ),
    (
      ApiException(
        ApiFailureKind.notFound,
        statusCode: 404,
        errorCode: 'BOOKING_NOT_FOUND',
      ),
      '예약 정보를 찾을 수 없습니다.',
    ),
    (
      ApiException(
        ApiFailureKind.forbidden,
        statusCode: 403,
        errorCode: 'FORBIDDEN',
      ),
      '이 예약의 피켓 사진을 업로드할 권한이 없습니다.',
    ),
  ]) {
    testWidgets('name-sign upload explains ${scenario.$1.errorCode}', (
      tester,
    ) async {
      final reader = FakeBookingReader()
        ..detailResult = bookingDetail(
          status: 'DRIVER_ARRIVED',
          assignmentStatus: 'ACCEPTED',
          allowedActions: const ['MARK_PICKED_UP'],
        )
        ..nameSignPhotoError = scenario.$1;
      await pumpDetail(
        tester,
        reader,
        nameSignPhotoPicker: (_) async =>
            const NameSignPhotoFile(filename: 'sign.jpg', bytes: [1]),
      );

      await selectNameSignPhotoFromGallery(tester);

      expect(find.text(scenario.$2), findsOneWidget);
      expect(
        find.byKey(const Key('uploadNameSignPhotoButton')),
        findsOneWidget,
      );
    });
  }

  testWidgets('trip list gate badge shares detail gate condition', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(
        items: [
          bookingSummary(nameSignRequested: true),
          bookingSummary(
            bookingNumber: 'TX209912319998',
            origin: 'DMK Airport',
            pickupLocationName: 'Don Mueang International Airport',
            pickupLocationAddress: 'Don Mueang',
            nameSignRequested: true,
          ),
        ],
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bookingGate-TX209912319999')), findsOneWidget);
    expect(find.text('3번 게이트'), findsOneWidget);
    expect(find.byKey(const Key('bookingGate-TX209912319998')), findsNothing);
  });

  testWidgets(
    'assignment released socket event closes matching detail and refreshes list',
    (tester) async {
      final reader = FakeBookingReader();
      final socket = FakeDriverSocketConnection();
      await pumpBookingList(tester, reader, socketEvents: socket.events);
      await tester.pumpAndSettle();
      final initialListLoads = reader.listCount;
      await tester.tap(find.byKey(const Key('booking-TX209912319999')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detailSuccess')), findsOneWidget);

      socket.emit(DriverSocketEventType.assignmentReleased, {
        'bookingNumber': 'TX209912319999',
        'reasonCode': 'ADMIN_REASSIGNED',
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
      expect(reader.listCount, initialListLoads + 1);
      expect(find.textContaining('배정이 종료되어 목록으로 돌아갑니다.'), findsOneWidget);
    },
  );

  testWidgets(
    'assignment released with ADMIN_RELEASED shows admin cancel message',
    (tester) async {
      final reader = FakeBookingReader();
      final socket = FakeDriverSocketConnection();
      await pumpBookingList(tester, reader, socketEvents: socket.events);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-TX209912319999')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detailSuccess')), findsOneWidget);

      socket.emit(DriverSocketEventType.assignmentReleased, {
        'bookingNumber': 'TX209912319999',
        'reasonCode': 'ADMIN_RELEASED',
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
      expect(find.textContaining('관리자에 의해 배정이 취소되어'), findsOneWidget);
      expect(find.textContaining('고객센터로 문의해주세요'), findsOneWidget);
    },
  );

  testWidgets(
    'assignment released with DRIVER_RELEASED keeps default close message',
    (tester) async {
      final reader = FakeBookingReader();
      final socket = FakeDriverSocketConnection();
      await pumpBookingList(tester, reader, socketEvents: socket.events);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-TX209912319999')));
      await tester.pumpAndSettle();

      socket.emit(DriverSocketEventType.assignmentReleased, {
        'bookingNumber': 'TX209912319999',
        'reasonCode': 'DRIVER_RELEASED',
      });
      await tester.pumpAndSettle();

      expect(
        find.text('이 예약의 배정이 종료되어 목록으로 돌아갑니다.'),
        findsOneWidget,
      );
      expect(find.textContaining('관리자에 의해 배정이 취소되어'), findsNothing);
    },
  );

  final tripCases =
      <
        ({
          String status,
          Object? assignment,
          String action,
          String buttonLabel,
          String nextStatus,
          List<String> nextActions,
          int Function(FakeBookingReader) count,
        })
      >[
        (
          status: 'DRIVER_ASSIGNED',
          assignment: 'ACCEPTED',
          action: 'START_ON_ROUTE',
          buttonLabel: '운행 시작',
          nextStatus: 'ON_ROUTE',
          nextActions: const ['VIEW_DETAILS', 'MARK_ARRIVED'],
          count: (reader) => reader.startRouteCount,
        ),
        (
          status: 'ON_ROUTE',
          assignment: 'ACCEPTED',
          action: 'MARK_ARRIVED',
          buttonLabel: '도착 확인',
          nextStatus: 'DRIVER_ARRIVED',
          nextActions: const ['VIEW_DETAILS', 'MARK_PICKED_UP'],
          count: (reader) => reader.arriveCount,
        ),
        (
          status: 'DRIVER_ARRIVED',
          assignment: 'ACCEPTED',
          action: 'MARK_PICKED_UP',
          buttonLabel: '탑승 확인',
          nextStatus: 'PICKED_UP',
          nextActions: const ['VIEW_DETAILS', 'END_TRIP'],
          count: (reader) => reader.pickedUpCount,
        ),
      ];

  for (final tripCase in tripCases) {
    testWidgets(
      '${tripCase.action} is action-gated and refreshes to the next button',
      (tester) async {
        final reader = FakeBookingReader()
          ..detailResult = bookingDetail(
            status: tripCase.status,
            assignmentStatus: tripCase.assignment,
            canConfirmStandby: false,
            allowedActions: ['VIEW_DETAILS', tripCase.action],
          );
        await pumpDetail(tester, reader);
        reader.detailResult = bookingDetail(
          status: tripCase.nextStatus,
          assignmentStatus: 'ACCEPTED',
          canConfirmStandby: false,
          allowedActions: tripCase.nextActions,
        );

        await tester.tap(find.byKey(Key('tripAction-${tripCase.action}')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('tripActionConfirmDialog')),
          findsOneWidget,
        );
        expect(tripCase.count(reader), 0);
        await tester.tap(find.byKey(const Key('tripActionConfirmButton')));
        await tester.pumpAndSettle();

        expect(tripCase.count(reader), 1);
        expect(
          find.text('${tripCase.buttonLabel} 처리가 완료되었습니다.'),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('tripAction-${tripCase.nextActions.last}')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('trip action is hidden without the matching allowedAction', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'ON_ROUTE',
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS'],
      );
    await pumpDetail(tester, reader);
    expect(find.byKey(const Key('tripAction-MARK_ARRIVED')), findsNothing);
  });

  testWidgets('trip action loading prevents a duplicate POST', (tester) async {
    final actionCompleter = Completer<void>();
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'ON_ROUTE',
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'MARK_ARRIVED'],
      )
      ..actionCompleter = actionCompleter;
    await pumpDetail(tester, reader);
    await tester.tap(find.byKey(const Key('tripAction-MARK_ARRIVED')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tripActionConfirmButton')));
    await tester.pump();

    expect(reader.arriveCount, 1);
    expect(find.byKey(const Key('tripActionLoading')), findsOneWidget);
    actionCompleter.complete();
    reader.detailResult = bookingDetail(
      status: 'DRIVER_ARRIVED',
      assignmentStatus: 'ACCEPTED',
      canConfirmStandby: false,
      allowedActions: const ['VIEW_DETAILS', 'MARK_PICKED_UP'],
    );
    await tester.pumpAndSettle();
    expect(reader.arriveCount, 1);
  });

  testWidgets('trip action failure keeps detail and shows guidance', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'ON_ROUTE',
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'MARK_ARRIVED'],
      )
      ..actionError = const ApiException(
        ApiFailureKind.invalidStatusTransition,
        statusCode: 409,
        errorCode: 'INVALID_STATUS_TRANSITION',
      );
    await pumpDetail(tester, reader);
    await tester.tap(find.byKey(const Key('tripAction-MARK_ARRIVED')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tripActionConfirmButton')));
    await tester.pumpAndSettle();

    expect(reader.arriveCount, 1);
    expect(find.byKey(const Key('detailSuccess')), findsOneWidget);
    expect(find.textContaining('운행 상태가 이미 변경되었습니다.'), findsOneWidget);
  });

  testWidgets('end trip succeeds and returns to the previous screen', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        status: 'PICKED_UP',
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'END_TRIP'],
      );
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/detail',
        routes: {
          '/': (_) => const Scaffold(body: Text('내 운행 목록')),
          '/detail': (_) => BookingDetailScreen(
            bookingNumber: 'TX209912319999',
            repository: reader,
            onUnauthorized: () async {},
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tripAction-END_TRIP')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tripActionConfirmButton')));
    await tester.pumpAndSettle();

    expect(reader.endTripCount, 1);
    expect(find.text('내 운행 목록'), findsOneWidget);
  });

  testWidgets('release dialog shows all reasons and requires OTHER detail', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
      );
    await pumpDetail(tester, reader);
    await tester.ensureVisible(
      find.byKey(const Key('releaseAssignmentButton')),
    );
    await tester.tap(find.byKey(const Key('releaseAssignmentButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('releaseReason-OTHER')), findsOneWidget);
    await tester.tap(find.byKey(const Key('releaseReason-OTHER')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('releaseConfirmButton')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('releaseReasonDetail')),
      '개인 긴급 사유',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('releaseConfirmButton')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('emergency-only release hides normal reasons', (tester) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
        releaseAssignmentAvailable: false,
        releaseAssignmentEmergencyOnly: true,
        assignmentReleaseDeadline: '2026-07-18T07:30:00.000+07:00',
        assignmentReleaseBlockedReason: 'WITHIN_TWO_HOURS',
      );
    await pumpDetail(
      tester,
      reader,
      now: () => DateTime.parse('2026-07-18T08:00:00.000+07:00'),
    );
    await tester.ensureVisible(
      find.byKey(const Key('releaseAssignmentButton')),
    );
    await tester.tap(find.byKey(const Key('releaseAssignmentButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emergencyOnlyNotice')), findsOneWidget);
    expect(find.byKey(const Key('releaseReason-ACCIDENT')), findsOneWidget);
    expect(
      find.byKey(const Key('releaseReason-SCHEDULE_CONFLICT')),
      findsNothing,
    );
    expect(find.byKey(const Key('releaseReason-OTHER')), findsNothing);
  });

  testWidgets('release success submits selected reason and returns to list', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
      );
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/detail',
        routes: {
          '/': (_) => const Scaffold(body: Text('내 운행 목록')),
          '/detail': (_) => BookingDetailScreen(
            bookingNumber: 'TX209912319999',
            repository: reader,
            onUnauthorized: () async {},
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('releaseAssignmentButton')),
    );
    await tester.tap(find.byKey(const Key('releaseAssignmentButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('releaseReason-SCHEDULE_CONFLICT')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('releaseConfirmButton')));
    await tester.pumpAndSettle();

    expect(reader.releaseCount, 1);
    expect(reader.releasedReasonCode, 'SCHEDULE_CONFLICT');
    expect(find.text('내 운행 목록'), findsOneWidget);
  });

  testWidgets('release response and socket echo close detail exactly once', (
    tester,
  ) async {
    final socket = FakeDriverSocketConnection();
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
      )
      ..releaseCompleter = Completer<void>();
    await pumpBookingList(tester, reader, socketEvents: socket.events);
    await tester.pumpAndSettle();
    final listLoadsBefore = reader.listCount;
    await tester.tap(find.byKey(const Key('booking-TX209912319999')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('releaseAssignmentButton')),
    );
    await tester.tap(find.byKey(const Key('releaseAssignmentButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('releaseReason-SCHEDULE_CONFLICT')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('releaseConfirmButton')));
    await tester.pump();

    socket.emit(DriverSocketEventType.assignmentReleased, {
      'bookingNumber': 'TX209912319999',
      'reasonCode': 'SCHEDULE_CONFLICT',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);

    reader.releaseCompleter!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookingListSuccess')), findsOneWidget);
    expect(reader.listCount, listLoadsBefore + 1);
  });

  testWidgets('past deadline disables non-emergency release', (tester) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
        releaseAssignmentAvailable: true,
        assignmentReleaseDeadline: '2026-07-18T07:30:00.000+07:00',
      );
    await pumpDetail(
      tester,
      reader,
      now: () => DateTime.parse('2026-07-18T08:00:00.000+07:00'),
    );
    await tester.ensureVisible(
      find.byKey(const Key('releaseAssignmentButton')),
    );

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('releaseAssignmentButton')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('releaseDeadlineNotice')), findsOneWidget);
  });

  testWidgets('blocked release is disabled and explains the reason', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ACCEPTED',
        canConfirmStandby: false,
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
        releaseAssignmentAvailable: false,
        assignmentReleaseBlockedReason: 'TRIP_ALREADY_STARTED',
      );
    await pumpDetail(tester, reader);
    await tester.ensureVisible(
      find.byKey(const Key('releaseAssignmentButton')),
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('releaseAssignmentButton')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('운행이 시작되어 배정을 반납할 수 없습니다.'), findsOneWidget);
  });

  testWidgets('map links appear for coordinates and launch Google Maps URL', (
    tester,
  ) async {
    Uri? launched;
    await pumpDetail(
      tester,
      FakeBookingReader(),
      externalUrlLauncher: (url) async {
        launched = url;
        return true;
      },
    );
    await tester.ensureVisible(find.byKey(const Key('pickupMapLink')));
    await tester.tap(find.byKey(const Key('pickupMapLink')));
    await tester.pump();

    expect(launched?.host, 'www.google.com');
    expect(launched?.path, '/maps/search/');
    expect(launched?.queryParameters['query'], '13.69,100.7501');
  });

  testWidgets('map links are hidden when coordinates are absent', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(includeCoordinates: false);
    await pumpDetail(tester, reader);
    expect(find.byKey(const Key('pickupMapLink')), findsNothing);
    expect(find.byKey(const Key('destinationMapLink')), findsNothing);
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

  testWidgets('shows release choice before accept when assignment is ASSIGNED', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ASSIGNED',
        allowedActions: const [
          'VIEW_DETAILS',
          'RELEASE_ASSIGNMENT',
          'ACCEPT_BOOKING',
        ],
      );
    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('preAcceptReleaseActionCard')), findsOneWidget);
    expect(find.byKey(const Key('releaseAssignmentButton')), findsOneWidget);
    expect(find.byKey(const Key('acceptBookingButton')), findsOneWidget);
  });

  testWidgets('shows prominent release card while waiting for standby', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..detailResult = bookingDetail(
        assignmentStatus: 'ASSIGNED',
        canConfirmStandby: false,
        standbyAllowedAt: '2099-12-31T08:30:00.000+07:00',
        allowedActions: const ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
      );
    await pumpDetail(tester, reader);

    expect(find.byKey(const Key('releaseAssignmentProminentCard')), findsOneWidget);
    expect(find.byKey(const Key('releaseAssignmentButton')), findsOneWidget);
    expect(find.byKey(const Key('acceptBookingButton')), findsNothing);
  });

  testWidgets('list shows release icon after capabilities prefetch', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(
        items: [
          bookingSummary(
            allowedActions: const [
              'VIEW_DETAILS',
              'RELEASE_ASSIGNMENT',
              'ACCEPT_BOOKING',
            ],
            assignmentStatus: 'ASSIGNED',
          ),
        ],
      )
      ..detailResult = bookingDetail(
        assignmentStatus: 'ASSIGNED',
        allowedActions: const [
          'VIEW_DETAILS',
          'RELEASE_ASSIGNMENT',
          'ACCEPT_BOOKING',
        ],
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('releaseAssignmentListButton-TX209912319999')),
      findsOneWidget,
    );
  });

  testWidgets('list release icon opens dialog and refreshes list on success', (
    tester,
  ) async {
    final reader = FakeBookingReader()
      ..listResult = bookingList(
        items: [
          bookingSummary(
            allowedActions: const [
              'VIEW_DETAILS',
              'RELEASE_ASSIGNMENT',
              'ACCEPT_BOOKING',
            ],
            assignmentStatus: 'ASSIGNED',
          ),
        ],
      )
      ..detailResult = bookingDetail(
        assignmentStatus: 'ASSIGNED',
        allowedActions: const [
          'VIEW_DETAILS',
          'RELEASE_ASSIGNMENT',
          'ACCEPT_BOOKING',
        ],
      );
    await pumpBookingList(tester, reader);
    await tester.pumpAndSettle();
    final initialListLoads = reader.listCount;

    await tester.tap(
      find.byKey(const Key('releaseAssignmentListButton-TX209912319999')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('releaseAssignmentDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('releaseReason-SCHEDULE_CONFLICT')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('releaseConfirmButton')));
    await tester.pumpAndSettle();

    expect(reader.releaseCount, 1);
    expect(reader.listCount, greaterThan(initialListLoads));
    expect(find.text('배정을 반납했습니다.'), findsOneWidget);
  });
}
