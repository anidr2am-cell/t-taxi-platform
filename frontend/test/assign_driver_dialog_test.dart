import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/widgets/assign_driver_dialog.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _FakeDispatchApi extends AdminDispatchApiService {
  _FakeDispatchApi(this.drivers);

  final List<Map<String, dynamic>> drivers;
  String? lastBookingNumber;

  @override
  Future<List<dynamic>> listDrivers({
    bool? archived,
    String? bookingNumber,
  }) async {
    lastBookingNumber = bookingNumber;
    return drivers;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ko'),
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('assign dialog disables conflict driver and allows eligible driver', (
    tester,
  ) async {
    final api = _FakeDispatchApi([
      {
        'driverId': 101,
        'displayName': 'OK Driver',
        'phone': '+661',
        'eligibilityState': 'AVAILABLE',
        'activeAssignmentCount': 1,
        'assignmentEligible': true,
        'pickupTimeConflict': false,
      },
      {
        'driverId': 102,
        'displayName': 'Conflict Driver',
        'phone': '+662',
        'eligibilityState': 'AVAILABLE',
        'activeAssignmentCount': 1,
        'assignmentEligible': false,
        'pickupTimeConflict': true,
      },
    ]);

    AssignDriverDialogResult? result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showDialog<AssignDriverDialogResult>(
                  context: context,
                  builder: (_) => AssignDriverDialog(
                    api: api,
                    isReassign: false,
                    bookingNumber: 'TX202609240001',
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(api.lastBookingNumber, 'TX202609240001');

    expect(find.text('Conflict Driver'), findsOneWidget);
    expect(find.text('OK Driver'), findsOneWidget);

    await tester.tap(find.text('OK Driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(result?.driverId, 101);
  });

  testWidgets('conflict driver card is not selectable', (tester) async {
    final api = _FakeDispatchApi([
      {
        'driverId': 102,
        'displayName': 'Conflict Driver',
        'phone': '+662',
        'eligibilityState': 'AVAILABLE',
        'activeAssignmentCount': 1,
        'assignmentEligible': false,
        'pickupTimeConflict': true,
      },
    ]);

    await tester.pumpWidget(
      _wrap(
        AssignDriverDialog(
          api: api,
          isReassign: false,
          bookingNumber: 'TX202609240001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conflict Driver'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_off), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
  });
}
