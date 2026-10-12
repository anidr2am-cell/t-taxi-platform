import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/screens/admin/admin_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'admin rail scrolls to and opens the final menu at 700px height',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'admin_access_token': 'admin-token',
      });

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: const MaterialApp(home: AdminScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byKey(const Key('admin_navigation_rail_scroll'));
      expect(scrollable, findsOneWidget);
      final scrollPosition = find.descendant(
        of: scrollable,
        matching: find.byType(Scrollable),
      );
      expect(scrollPosition, findsOneWidget);

      final finalMenu = find.text('Manual call registration');
      await tester.scrollUntilVisible(
        finalMenu,
        300,
        scrollable: scrollPosition,
      );
      await tester.tap(finalMenu);
      await tester.pump();

      expect(find.text('Manual call registration'), findsWidgets);
      expect(find.text('Register admin manual call'), findsOneWidget);
    },
  );
}
