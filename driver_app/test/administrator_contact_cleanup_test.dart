import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/bookings/presentation/booking_detail_screen.dart';
import 'package:tride_driver/features/account/data/account_models.dart';
import 'package:tride_driver/features/account/presentation/profile_edit_page.dart';
import 'package:tride_driver/features/support/data/support_contact_api.dart';
import 'package:tride_driver/features/support/presentation/driver_support_page.dart';
import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

class _SupportApi implements SupportContactDataSource {
  @override
  Future<Uri?> getAdministratorLineUrl() async =>
      Uri.parse('https://lin.ee/qa');
}

void main() {
  for (final language in ['ko', 'th']) {
    testWidgets(
      '$language assigned detail routes customer contact to administrator at 360dp',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          localizedMaterialApp(
            locale: Locale(language),
            home: BookingDetailScreen(
              bookingNumber: 'TX202610130001',
              repository: FakeBookingReader(),
              onUnauthorized: () async {},
              supportContactApi: _SupportApi(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('bookingContactAdministrator'));
        await tester.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(
            language == 'ko'
                ? '고객 연락은 관리자를 통해 진행합니다.'
                : 'การติดต่อลูกค้าดำเนินการผ่านผู้ดูแล',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('WhatsApp'), findsNothing);
        expect(tester.takeException(), isNull);
        await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(DriverSupportPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$language profile vehicle options use the server active types at 360dp',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FakeAccountApi()
          ..vehicleTypes = const [
            VehicleTypeOption(id: 1, code: 'SEDAN', name: 'Sedan'),
            VehicleTypeOption(id: 2, code: 'SUV', name: 'SUV'),
            VehicleTypeOption(id: 4, code: 'VAN', name: 'Van'),
          ];
        await tester.pumpWidget(
          localizedMaterialApp(
            locale: Locale(language),
            home: ProfileEditPage(api: api, initialProfile: api.profile),
          ),
        );
        await tester.pumpAndSettle();
        final dropdown = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(find.text('SUV'), findsWidgets);
        expect(find.text('VAN'), findsWidgets);
        for (final disabled in ['VIP_SUV', 'VIP_VAN', 'LUXURY']) {
          expect(find.text(disabled), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
