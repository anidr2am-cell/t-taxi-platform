import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_shell_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/widgets/driver_status_control.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_access_token': 'qa-token'});
  });

  testWidgets(
    'suspended shell is bilingual and exposes only settlement and account at 375px',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          home: DriverShellPage(
            api: _SuspendedApi(),
            settlementApi: _SettlementApi(),
            enableCallSocket: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('이용이 제한되었습니다'), findsOneWidget);
      expect(find.textContaining('การใช้งานถูกจำกัด'), findsOneWidget);
      expect(find.byType(DriverStatusControl), findsNothing);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.work_outline), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}

class _SuspendedApi extends DriverApiService {
  @override
  Future<String?> getSavedToken() async => 'qa-token';

  @override
  Future<DriverStatus> getStatus() async => const DriverStatus(
    driverId: 2,
    active: true,
    online: false,
    status: 'SUSPENDED',
    hasActiveJob: false,
  );

  @override
  Future<Map<String, dynamic>> getRatingSummary() async => const {};

  @override
  Future<String?> getDriverDisplayName() async => 'QA Driver';

  @override
  Future<Map<String, dynamic>> getProfile() async => const {};

  @override
  Future<int> getUnreadNotificationCount() async => 0;
}

class _SettlementApi extends DriverSettlementApiService {
  @override
  Future<List<dynamic>> listSettlements() async => const [];
}
