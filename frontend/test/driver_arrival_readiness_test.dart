import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/widgets/driver_arrival_readiness_card.dart';

class QaInbox extends DriverApiService {
  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async => {
    'items': [
      {'notificationType': 'CUSTOMER_GATE_ARRIVED'},
      {'notificationType': 'DRIVER_ASSIGNED'},
    ],
  };
}

void main() {
  testWidgets(
    'Thai driver guide fits 375px, highlights arrival and does not claim permission before PWA install',
    (tester) async {
      tester.view.physicalSize = const Size(375, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverArrivalReadinessCard(api: QaInbox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ลูกค้าถึงประตู 7 แล้ว (1)'), findsOneWidget);
      await tester.tap(find.textContaining('ลูกค้าถึงประตู 7 แล้ว (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('iOS 16.4'), findsOneWidget);
      await tester.ensureVisible(find.text('เปิดรับแจ้งเตือน / 알림 켜기'));
      await tester.tap(find.text('เปิดรับแจ้งเตือน / 알림 켜기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('กรุณาเพิ่ม T-Ride Driver'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
