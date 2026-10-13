import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/time/bangkok_datetime.dart';
import 'package:tride_driver/features/dispatch/presentation/driver_home_shell.dart';
import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

void main() {
  test('UTC settlement time displays in Bangkok across midnight', () {
    expect(
      formatBangkokDateTime('2026-10-12T18:30:00.000Z'),
      '2026-10-13 01:30',
    );
    expect(
      formatBangkokDateTime('2026-10-12T15:13:29+07:00'),
      '2026-10-12 15:13',
    );
  });

  testWidgets(
    'suspended driver has only settlement/account and no online or edit actions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final socket = FakeDriverSocketConnection();
      final dispatch = FakeDispatchReader()
        ..statusResult = dispatchStatus(status: 'SUSPENDED');
      await tester.pumpWidget(
        localizedMaterialApp(
          home: DriverHomeShell(
            bookingRepository: FakeBookingReader(),
            dispatchRepository: dispatch,
            localeController: await createTestLocaleController(),
            onUnauthorized: () async {},
            onLogout: () async {},
            settlementApi: FakeSettlementApi()..items = [],
            accountApi: FakeAccountApi(),
            driverSocket: socket,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.text('이용이 제한되었습니다. 관리자에게 문의하세요.'), findsOneWidget);
      expect(socket.connectCount, 0);
      expect(socket.disconnectCount, greaterThan(0));
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accountOnlineToggle')), findsNothing);
      expect(find.byKey(const Key('openProfileEdit')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
