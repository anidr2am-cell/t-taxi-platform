import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_account_page.dart';
import 'package:frontend/features/driver/pages/driver_profile_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

class _ProfileApi extends DriverApiService {
  _ProfileApi(this.profile);

  final Map<String, dynamic> profile;
  int passwordChangeRequests = 0;

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    passwordChangeRequests++;
    expect(currentPassword, 'incorrect-test-password');
    expect(newPassword, 'new-test-password');
    throw const DriverApiException(
      'Current password is incorrect',
      statusCode: 400,
      errorCode: 'CURRENT_PASSWORD_INCORRECT',
    );
  }

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
  testWidgets('profile opens password change and reports wrong password', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ProfileApi({'name': 'Somchai'});
    await tester.pumpWidget(MaterialApp(home: DriverProfilePage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openDriverPasswordChange')));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'incorrect-test-password');
    await tester.enterText(fields.at(1), 'new-test-password');
    await tester.enterText(fields.at(2), 'new-test-password');
    await tester.tap(find.widgetWithText(FilledButton, '변경 / เปลี่ยน'));
    await tester.pumpAndSettle();

    expect(api.passwordChangeRequests, 1);
    expect(find.textContaining('현재 비밀번호를 확인해 주세요.'), findsOneWidget);
    expect(dialog, findsOneWidget);
  });

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
          settlementApi: DriverSettlementApiService(),
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
          settlementApi: DriverSettlementApiService(),
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
