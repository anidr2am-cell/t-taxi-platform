import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_models.dart';
import 'package:tride_driver/features/dispatch/data/driver_socket_service.dart';
import 'package:tride_driver/features/dispatch/presentation/driver_home_shell.dart';
import 'package:tride_driver/features/dispatch/presentation/open_calls_screen.dart';

import 'package:tride_driver/l10n/app_localizations.dart';

import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

final _ko = AppLocalizations(const Locale('ko'));

String deadlineAfter(Duration duration) =>
    DateTime.now().toUtc().add(duration).toIso8601String();

OpenCall urgentCall({
  String bookingNumber = 'TX209912319997',
  int? minRequiredEtaMinutes = 30,
}) => openCall(
  bookingNumber: bookingNumber,
  isUrgentRequest: true,
  negotiationId: 9,
  minRequiredEtaMinutes: minRequiredEtaMinutes,
);

FakeDispatchReader urgentReader({int? minRequiredEtaMinutes = 30}) {
  final reader = FakeDispatchReader()
    ..statusResult = dispatchStatus(
      online: true,
      canReceiveCalls: true,
      status: 'AVAILABLE',
    )
    ..openCallsResult = OpenCallList(
      items: [urgentCall(minRequiredEtaMinutes: minRequiredEtaMinutes)],
      blockedReason: null,
      message: null,
    );
  reader.urgentLockResult = UrgentCallLockResult(
    bookingNumber: 'TX209912319997',
    negotiationId: 9,
    attemptId: 1,
    attemptNumber: 1,
    driverId: 7,
    status: 'LOCKED',
    lockExpiresAt: deadlineAfter(const Duration(minutes: 3)),
  );
  reader.urgentEtaResult = UrgentCallEtaResult(
    bookingNumber: 'TX209912319997',
    negotiationId: 9,
    attemptNumber: 1,
    driverId: 7,
    status: 'AWAITING_CUSTOMER',
    etaMinutes: 20,
    customerDecisionExpiresAt: deadlineAfter(const Duration(minutes: 2)),
  );
  return reader;
}

Future<void> pumpUrgentScreen(
  WidgetTester tester,
  FakeDispatchReader reader, {
  FakeDriverSocketConnection? socket,
  VoidCallback? onClaimed,
  ValueChanged<bool>? onActivity,
}) async {
  await tester.pumpWidget(
    localizedMaterialApp(
      home: OpenCallsScreen(
        repository: reader,
        onUnauthorized: () async {},
        onClaimed: onClaimed ?? () {},
        driverSocket: socket,
        onUrgentActivityChanged: onActivity,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openEtaDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('urgentAccept-TX209912319997')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.byKey(const Key('urgentEtaDialog')), findsOneWidget);
}

Future<void> submitEta(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('urgentEtaInput')), value);
  await tester.tap(find.byKey(const Key('urgentEtaSubmit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('urgent card shows route, operation data, amount, and luggage', (
    tester,
  ) async {
    await pumpUrgentScreen(tester, urgentReader());

    expect(find.byKey(const Key('urgentCallsSection')), findsOneWidget);
    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(find.text('Pattaya Hotel'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
    expect(find.text('Airport pickup · Sedan · ${_ko.passengersCount(2)}'), findsOneWidget);
    expect(find.text('1200 THB'), findsOneWidget);
    expect(find.text(_ko.carriers20InchCount(1)), findsOneWidget);
    expect(find.text(_ko.previousRejectionRequiresEtaUnder(30)), findsOneWidget);
  });

  testWidgets('lock success opens a non-dismissible ETA dialog', (
    tester,
  ) async {
    final reader = urgentReader();
    final activity = <bool>[];
    await pumpUrgentScreen(tester, reader, onActivity: activity.add);

    await openEtaDialog(tester);
    expect(reader.urgentLockCount, 1);
    expect(activity, [true]);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('urgentEtaDialog')), findsOneWidget);
    expect(find.byKey(const Key('urgentLeaveDialog')), findsOneWidget);
  });

  for (final scenario in [
    (
      ApiException(
        ApiFailureKind.validation,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
      ),
      '입력 내용을 다시 확인해 주세요.',
      false,
    ),
    (
      ApiException(
        ApiFailureKind.urgentNotUrgentBooking,
        statusCode: 400,
        errorCode: 'URGENT_NOT_URGENT_BOOKING',
      ),
      '긴급콜로 처리할 수 없는 예약입니다.',
      false,
    ),
    (
      ApiException(
        ApiFailureKind.notFound,
        statusCode: 404,
        errorCode: 'DRIVER_NOT_FOUND',
      ),
      '예약 정보를 찾을 수 없습니다.',
      false,
    ),
    (
      ApiException(
        ApiFailureKind.notFound,
        statusCode: 404,
        errorCode: 'NOT_FOUND',
      ),
      '예약 정보를 찾을 수 없습니다.',
      false,
    ),
    (
      ApiException(
        ApiFailureKind.urgentNotBroadcasting,
        statusCode: 409,
        errorCode: 'URGENT_NEGOTIATION_NOT_BROADCASTING',
      ),
      '더 이상 수락할 수 없는 긴급콜입니다.',
      true,
    ),
    (
      ApiException(
        ApiFailureKind.urgentAlreadyLocked,
        statusCode: 409,
        errorCode: 'URGENT_ALREADY_LOCKED',
      ),
      '다른 기사가 이미 수락한 콜입니다.',
      true,
    ),
  ]) {
    testWidgets('lock failure ${scenario.$1.errorCode} is handled', (
      tester,
    ) async {
      final reader = urgentReader()..urgentLockError = scenario.$1;
      await pumpUrgentScreen(tester, reader);

      await tester.tap(find.byKey(const Key('urgentAccept-TX209912319997')));
      await tester.pumpAndSettle();

      expect(find.text(scenario.$2), findsOneWidget);
      expect(
        find.byKey(const Key('urgentCall-TX209912319997')),
        scenario.$3 ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('ETA dialog validates integer and previous minimum', (
    tester,
  ) async {
    final reader = urgentReader();
    await pumpUrgentScreen(tester, reader);
    await openEtaDialog(tester);

    await submitEta(tester, '30');
    expect(find.text('30분 미만으로 입력해 주세요.'), findsOneWidget);
    expect(reader.urgentEtaCount, 0);

    await submitEta(tester, '0');
    expect(find.text('1분 이상의 정수를 입력해 주세요.'), findsOneWidget);
    expect(reader.urgentEtaCount, 0);
  });

  testWidgets('ETA countdown uses warning color during final 30 seconds', (
    tester,
  ) async {
    final reader = urgentReader();
    reader.urgentLockResult = UrgentCallLockResult(
      bookingNumber: 'TX209912319997',
      negotiationId: 9,
      attemptId: 1,
      attemptNumber: 1,
      driverId: 7,
      status: 'LOCKED',
      lockExpiresAt: deadlineAfter(const Duration(seconds: 20)),
    );
    await pumpUrgentScreen(tester, reader);
    await openEtaDialog(tester);

    final text = tester.widget<Text>(
      find.byKey(const Key('urgentEtaCountdown')),
    );
    final context = tester.element(find.byKey(const Key('urgentEtaDialog')));
    expect(text.style?.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('ETA countdown expiry closes dialog and shows guidance', (
    tester,
  ) async {
    final reader = urgentReader();
    reader.urgentLockResult = UrgentCallLockResult(
      bookingNumber: 'TX209912319997',
      negotiationId: 9,
      attemptId: 1,
      attemptNumber: 1,
      driverId: 7,
      status: 'LOCKED',
      lockExpiresAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String(),
    );
    await pumpUrgentScreen(tester, reader);
    await tester.tap(find.byKey(const Key('urgentAccept-TX209912319997')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('urgentEtaDialog')), findsNothing);
    expect(find.text('ETA 입력 시간이 만료되었습니다.'), findsOneWidget);
  });

  testWidgets('server minimum keeps ETA dialog open with inline guidance', (
    tester,
  ) async {
    final reader = urgentReader(minRequiredEtaMinutes: null)
      ..urgentEtaError = const ApiException(
        ApiFailureKind.urgentEtaNotFastEnough,
        statusCode: 422,
        errorCode: 'URGENT_ETA_NOT_FAST_ENOUGH',
        errors: [
          {'minRequiredEtaMinutes': 18, 'submittedEtaMinutes': 20},
        ],
      );
    await pumpUrgentScreen(tester, reader);
    await openEtaDialog(tester);
    await submitEta(tester, '20');

    expect(find.byKey(const Key('urgentEtaDialog')), findsOneWidget);
    expect(find.text('18분 미만으로 입력해 주세요.'), findsOneWidget);
  });

  for (final scenario in [
    (
      ApiFailureKind.urgentEtaExpired,
      'URGENT_ETA_WINDOW_EXPIRED',
      'ETA 입력 시간이 만료되었습니다.',
    ),
    (
      ApiFailureKind.urgentNotLockedDriver,
      'URGENT_NOT_LOCKED_DRIVER',
      '다른 기사에게 넘어간 요청입니다.',
    ),
  ]) {
    testWidgets('ETA terminal error ${scenario.$2} closes dialog', (
      tester,
    ) async {
      final reader = urgentReader()
        ..urgentEtaError = ApiException(
          scenario.$1,
          statusCode: scenario.$1 == ApiFailureKind.urgentNotLockedDriver
              ? 403
              : 409,
          errorCode: scenario.$2,
        );
      await pumpUrgentScreen(tester, reader);
      await openEtaDialog(tester);
      await submitEta(tester, '20');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('urgentEtaDialog')), findsNothing);
      expect(find.text(scenario.$3), findsOneWidget);
    });
  }

  testWidgets('expired customer deadline keeps banner in checking state', (
    tester,
  ) async {
    final reader = urgentReader();
    reader.urgentEtaResult = UrgentCallEtaResult(
      bookingNumber: 'TX209912319997',
      negotiationId: 9,
      attemptNumber: 1,
      driverId: 7,
      status: 'AWAITING_CUSTOMER',
      etaMinutes: 20,
      customerDecisionExpiresAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String(),
    );
    await pumpUrgentScreen(tester, reader);
    await openEtaDialog(tester);
    await submitEta(tester, '20');

    expect(find.byKey(const Key('urgentAwaitingBanner')), findsOneWidget);
    expect(find.text('라운드 종료 확인 중...'), findsOneWidget);
    expect(find.byKey(const Key('urgentAwaitingBanner')), findsOneWidget);
  });

  testWidgets('confirmed moves to trips after showing success banner', (
    tester,
  ) async {
    final reader = urgentReader();
    final socket = FakeDriverSocketConnection();
    var claimed = 0;
    await pumpUrgentScreen(
      tester,
      reader,
      socket: socket,
      onClaimed: () => claimed++,
    );
    await openEtaDialog(tester);
    await submitEta(tester, '20');
    expect(find.textContaining('고객 확인 대기 중'), findsOneWidget);

    socket.emit(DriverSocketEventType.urgentCallConfirmed, {
      'bookingNumber': 'TX209912319997',
      'negotiationId': 9,
      'bookingStatus': 'DRIVER_ASSIGNED',
    });
    await tester.pump();
    expect(find.text('고객이 확인했습니다. 예약이 배정되었습니다.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(claimed, 1);
  });

  for (final scenario in [
    (DriverSocketEventType.urgentCallRoundEnded, '고객이 거절했거나 라운드가 종료되었습니다.'),
    (DriverSocketEventType.urgentCallCancelled, '협상이 취소되었습니다.'),
  ]) {
    testWidgets('${scenario.$1} clears banner and gives guidance', (
      tester,
    ) async {
      final reader = urgentReader();
      final socket = FakeDriverSocketConnection();
      await pumpUrgentScreen(tester, reader, socket: socket);
      await openEtaDialog(tester);
      await submitEta(tester, '20');

      socket.emit(scenario.$1, {'bookingNumber': 'TX209912319997'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('urgentAwaitingBanner')), findsNothing);
      expect(find.text(scenario.$2), findsOneWidget);
    });
  }

  testWidgets('other driver lock hides card while own lock does not', (
    tester,
  ) async {
    final reader = urgentReader();
    final socket = FakeDriverSocketConnection();
    await pumpUrgentScreen(tester, reader, socket: socket);

    socket.emit(DriverSocketEventType.urgentCallLocked, {
      'bookingNumber': 'TX209912319997',
      'lockedDriverId': 99,
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('urgentCall-TX209912319997')), findsNothing);

    socket.emit(DriverSocketEventType.urgentCallUnlocked, {
      'bookingNumber': 'TX209912319997',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('urgentCall-TX209912319997')), findsOneWidget);

    socket.emit(DriverSocketEventType.urgentCallLocked, {
      'bookingNumber': 'TX209912319997',
      'lockedDriverId': 7,
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('urgentCall-TX209912319997')), findsOneWidget);
  });

  testWidgets('round-ended unlocked new sequence restores rebroadcast card', (
    tester,
  ) async {
    final reader = urgentReader();
    final socket = FakeDriverSocketConnection();
    await pumpUrgentScreen(tester, reader, socket: socket);

    socket.emit(DriverSocketEventType.urgentCallLocked, {
      'bookingNumber': 'TX209912319997',
      'lockedDriverId': 99,
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('urgentCall-TX209912319997')), findsNothing);

    socket.emit(DriverSocketEventType.urgentCallRoundEnded, {
      'bookingNumber': 'TX209912319997',
      'attemptCount': 1,
      'minRequiredEtaMinutes': 20,
    });
    socket.emit(DriverSocketEventType.urgentCallUnlocked, {
      'bookingNumber': 'TX209912319997',
    });
    socket.emit(DriverSocketEventType.urgentCallNew, {
      'bookingNumber': 'TX209912319997',
      'attemptCount': 1,
      'minRequiredEtaMinutes': 20,
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('urgentCall-TX209912319997')), findsOneWidget);
  });

  testWidgets('tab exit while waiting requires explicit confirmation', (
    tester,
  ) async {
    final dispatch = urgentReader();
    await tester.pumpWidget(
      localizedMaterialApp(
        home: DriverHomeShell(
          bookingRepository: FakeBookingReader(),
          dispatchRepository: dispatch,
          onUnauthorized: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openEtaDialog(tester);
    await submitEta(tester, '20');

    await tester.tap(find.text('내 운행'));
    await tester.pump();
    expect(find.byKey(const Key('urgentLeaveDialog')), findsOneWidget);
    expect(find.textContaining('서버의 잠금은 즉시 해제되지 않으며'), findsOneWidget);

    await tester.tap(find.byKey(const Key('urgentLeaveStay')));
    await tester.pump();
    expect(find.text('새 콜'), findsWidgets);
  });
}
