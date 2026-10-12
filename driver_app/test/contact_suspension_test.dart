import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/time/bangkok_datetime.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/presentation/customer_contact_card.dart';
import 'package:tride_driver/features/dispatch/presentation/driver_home_shell.dart';
import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

void main() {
  test('UTC settlement time displays in Bangkok across midnight', () {
    expect(formatBangkokDateTime('2026-10-12T18:30:00.000Z'), '2026-10-13 01:30');
    expect(formatBangkokDateTime('2026-10-12T15:13:29+07:00'), '2026-10-12 15:13');
  });

  for (final language in ['ko', 'th']) {
    testWidgets('$language contacts fit 360dp and retain selectable identifiers', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final type in ['KAKAO', 'LINE', 'WHATSAPP', 'SMS', null]) {
        await tester.pumpWidget(localizedMaterialApp(
          locale: Locale(language),
          home: Scaffold(body: CustomerContactCard(contact: CustomerContact(
            messengerType: type,
            messengerId: type == null ? null : (type == 'KAKAO' || type == 'LINE' ? 'qa_customer_long_id_123456' : '+821012345678'),
            phone: '+66990000002',
          ))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SelectableText), findsWidgets);
      }
    });
  }

  testWidgets('equal WhatsApp phone is not repeated as emergency phone', (tester) async {
    await tester.pumpWidget(localizedMaterialApp(home: const Scaffold(body: CustomerContactCard(
      contact: CustomerContact(messengerType: 'WHATSAPP', messengerId: '+82 10-1234-5678', phone: '+821012345678'),
    ))));
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('Kakao phone is primary, ID is optional, and legacy ID-only remains visible', (tester) async {
    await tester.pumpWidget(localizedMaterialApp(home: const Scaffold(body: Column(children: [
      CustomerContactCard(contact: CustomerContact(
        messengerType: 'KAKAO', messengerId: 'qa-kakao', phone: '+821012345678',
      )),
      CustomerContactCard(contact: CustomerContact(
        messengerType: 'KAKAO', messengerId: 'legacy-id-only',
      )),
    ]))));
    await tester.pumpAndSettle();

    expect(find.textContaining('+821012345678'), findsOneWidget);
    expect(find.textContaining('qa-kakao'), findsOneWidget);
    expect(find.textContaining('legacy-id-only'), findsOneWidget);
    expect(find.text('번호 복사'), findsOneWidget);
    expect(find.text('ID 복사'), findsNWidgets(2));
    expect(find.text('번호를 연락처에 저장하면 카카오톡 친구 목록에 나타납니다.'), findsOneWidget);
  });

  for (final fails in [false, true]) {
    testWidgets('clipboard ${fails ? 'failure' : 'success'} is visible', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData' && fails) throw PlatformException(code: 'denied');
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(localizedMaterialApp(home: const Scaffold(body: CustomerContactCard(
        contact: CustomerContact(messengerType: 'KAKAO', messengerId: 'qa_customer'),
      ))));
      await tester.tap(find.text('ID 복사'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(fails ? '복사하지 못했습니다. 길게 눌러 복사해 주세요.' : '복사했습니다.'), findsOneWidget);
    });
  }

  testWidgets('suspended driver has only settlement/account and no online or edit actions', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = FakeDriverSocketConnection();
    final dispatch = FakeDispatchReader()..statusResult = dispatchStatus(status: 'SUSPENDED');
    await tester.pumpWidget(localizedMaterialApp(home: DriverHomeShell(
      bookingRepository: FakeBookingReader(),
      dispatchRepository: dispatch,
      localeController: await createTestLocaleController(),
      onUnauthorized: () async {}, onLogout: () async {},
      settlementApi: FakeSettlementApi()..items = [],
      accountApi: FakeAccountApi(), driverSocket: socket,
    )));
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
  });
}
