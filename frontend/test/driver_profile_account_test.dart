import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_account_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

class _ProfileApi extends DriverApiService {
  _ProfileApi(this.profile);

  final Map<String, dynamic> profile;

  @override
  Future<String?> getSavedToken() async => 'tok';

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<Map<String, dynamic>> getRatingSummary() async => {
    'averageRating': 4.8,
    'reviewCount': 3,
  };

  @override
  Future<DriverStatus> getStatus() async => const DriverStatus(
    driverId: 7,
    active: true,
    online: true,
    status: 'AVAILABLE',
    hasActiveJob: false,
  );

  @override
  Future<int> getUnreadNotificationCount() async => 0;

  @override
  Future<Map<String, dynamic>> getProfile() async => profile;
}

void main() {
  testWidgets('account page shows vehicle details when profile has vehicle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: DriverAccountPage(
          api: _ProfileApi({
            'name': 'Somchai',
            'phone': '+66812345678',
            'email': 'driver@example.com',
            'vehicle': {
              'typeCode': 'SUV',
              'typeName': 'SUV',
              'modelName': 'Fortuner',
              'plateNumber': '1กก 1234',
              'color': 'White',
              'year': 2021,
            },
          }),
          settlementApi: const DriverSettlementApiService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Fortuner'), findsOneWidget);
    expect(find.textContaining('1กก 1234'), findsOneWidget);
    expect(find.textContaining('White'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account page shows Thai empty vehicle message', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: DriverAccountPage(
          api: _ProfileApi({
            'name': 'Somchai',
            'phone': '+66812345678',
            'email': 'driver@example.com',
            'vehicle': null,
          }),
          settlementApi: const DriverSettlementApiService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('ยังไม่มีข้อมูลรถที่ลงทะเบียนไว้'),
      findsOneWidget,
    );
  });
}
