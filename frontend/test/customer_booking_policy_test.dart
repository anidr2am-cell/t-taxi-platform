import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/utils/pricing_display.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/widgets/step_customer_info.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';

void main() {
  test('customer vehicle tiers show only fare-table vehicles (SEDAN, SUV, VAN)', () {
    final tiers = BookingWizardController.customerVehicleTierOrder;
    expect(tiers, contains('SEDAN'));
    expect(tiers, contains('SUV'));
    expect(tiers, contains('VAN'));
    expect(tiers, isNot(contains('VIP_SUV')));
    expect(tiers, isNot(contains('VIP_VAN')));
    expect(tiers, isNot(contains('LUXURY')));
  });

  test('pricing display maps NAME_SIGN to localized picket label', () {
    final l10n = AppLocalizations('en');
    final label = PricingDisplay.chargeItemLabel(
      l10n,
      const ChargeLineItem(
        chargeType: 'NAME_SIGN',
        description: 'Name sign service',
        quantity: 1,
        unitPrice: 100,
        amount: 100,
      ),
    );
    expect(label, 'Name sign service (Picket)');
  });

  test('pricing display hides internal distance estimate from VEHICLE_BASE label', () {
    final l10n = AppLocalizations('en');
    final label = PricingDisplay.chargeItemLabel(
      l10n,
      const ChargeLineItem(
        chargeType: 'VEHICLE_BASE',
        description: 'SEDAN CITY_TRANSFER (132.34 km est.)',
        quantity: 1,
        unitPrice: 1300,
        amount: 1300,
      ),
    );
    expect(label, 'Base price');
    expect(label.contains('km'), isFalse);
  });

  testWidgets('required labels are visible before focus', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: Scaffold(
            body: StepCustomerInfo(
              embedded: true,
              state: const BookingWizardState(),
              onNameChanged: (_) {},
              onEmailChanged: (_) {},
              onPhoneChanged: (_) {},
              onCountryChanged: (_) {},
              onAdditionalRequestsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('(Required)'), findsNWidgets(2));
    expect(find.textContaining('(Required) Email'), findsNothing);
    expect(find.textContaining('(Required) Country'), findsNothing);
    expect(find.textContaining('Messenger'), findsNothing);
  });
}
