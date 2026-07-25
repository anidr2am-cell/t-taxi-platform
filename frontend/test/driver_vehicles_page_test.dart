import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_vehicle.dart';
import 'package:frontend/features/driver/pages/driver_vehicles_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  testWidgets('shows vehicle cards with approval status badges', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLanguages
            .map((code) => Locale(code))
            .toList(),
        localizationsDelegates: [
          AppLocalizationsDelegate('en'),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: DriverVehiclesPage(api: _FakeVehiclesApi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('차량 관리'), findsWidgets);
    expect(find.text('ABC-111'), findsOneWidget);
    expect(find.text('XYZ-222'), findsOneWidget);
    expect(find.textContaining('승인됨'), findsOneWidget);
    expect(find.textContaining('승인 대기'), findsOneWidget);
    expect(find.textContaining('차량 추가'), findsOneWidget);
  });
}

class _FakeVehiclesApi extends DriverApiService {
  @override
  Future<List<DriverVehicleItem>> listVehicles() async {
    return const [
      DriverVehicleItem(
        id: 1,
        vehicleTypeId: 1,
        vehicleTypeCode: 'SEDAN',
        vehicleTypeName: 'Sedan',
        plateNumber: 'ABC-111',
        isPrimary: true,
        isActive: true,
        approvalStatus: 'APPROVED',
      ),
      DriverVehicleItem(
        id: 2,
        vehicleTypeId: 2,
        vehicleTypeCode: 'SUV',
        vehicleTypeName: 'SUV',
        plateNumber: 'XYZ-222',
        isPrimary: false,
        isActive: false,
        approvalStatus: 'PENDING',
      ),
    ];
  }
}
