import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_steps.dart';
import 'package:frontend/features/booking/pages/booking_wizard_page.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/widgets/booking_progress_header.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = BookingWizardController(
      storage: _EmptyStorage(),
      now: () => DateTime.utc(2026, 6, 29, 3),
    );
    controller.markInitializedForTest();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: BookingWizardPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 390.0, 430.0, 1024.0, 1280.0, 1440.0]) {
    testWidgets('booking wizard renders without overflow at ${width.toInt()}px',
        (tester) async {
      await pumpAtWidth(tester, width);
      expect(tester.takeException(), isNull);
      expect(find.byType(BookingProgressHeader), findsOneWidget);
      expect(find.text('1/5 Route'), findsOneWidget);
    });
  }

  testWidgets('progress header shows desktop step row on wide screens', (
    tester,
  ) async {
    await pumpAtWidth(tester, 1280);
    expect(find.text('Route'), findsWidgets);
  });

  testWidgets('swap route button has semantic label', (tester) async {
    await pumpAtWidth(tester, 360);
    expect(find.bySemanticsLabel('Swap locations'), findsOneWidget);
  });
}

class _EmptyStorage extends BookingStateStorage {
  @override
  Future<void> save(state) async {}

  @override
  Future<BookingWizardState?> load() async => null;

  @override
  Future<void> clear() async {}
}
