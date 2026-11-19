import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_driver_vehicle_media.dart';

class _MediaApi extends AdminDispatchApiService {
  String? saved;
  @override
  Future<List<dynamic>> getDriverVehicleMedia(
    int driverId,
    int vehicleId,
  ) async => [
    {
      'fileId': 1,
      'category': 'DRIVER_VEHICLE_PHOTO',
      'mimeType': 'image/jpeg',
      'available': false,
    },
    {
      'fileId': 2,
      'category': 'DRIVER_VEHICLE_PHOTO',
      'mimeType': 'image/png',
      'available': true,
    },
  ];
  @override
  Future<Uint8List> getDriverVehicleMediaBytes(
    int driverId,
    int vehicleId,
    int fileId,
  ) async {
    expect(fileId, 2);
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
  }

  @override
  Future<Map<String, dynamic>> updateDriverInsurance(
    int driverId,
    int vehicleId,
    String? expiresOn,
  ) async {
    saved = expiresOn;
    return {'expiresOn': expiresOn, 'status': 'VALID'};
  }
}

void main() {
  testWidgets(
    'missing photo does not hide a readable image; expiry can be saved',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _MediaApi();
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminDriverVehicleMedia(
                driverId: 6,
                vehicle: const {
                  'vehicleId': 3,
                  'insurance': {
                    'expiresOn': '2027-05-01',
                    'status': 'EXPIRING',
                  },
                },
                api: api,
                onChanged: () => changed++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('The file is unavailable'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Insurance expires within one month'), findsOneWidget);
      await tester.tap(find.text('Set insurance expiry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(api.saved, '2027-05-01');
      expect(changed, 1);
      expect(find.text('Insurance valid'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
