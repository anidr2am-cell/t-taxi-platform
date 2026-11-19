import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/service_type_option.dart';
import 'package:frontend/features/booking/widgets/booking_service_selection_summary.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_theme.dart';

void main() {
  for (final lang in ['ko', 'en', 'th', 'ja', 'zh', 'ru']) {
    for (final service in BookingServiceType.values) {
      for (final scale in [1.0, 1.4]) {
        testWidgets(
          '$lang $service at 375px / $scale is readable and tappable',
          (tester) async {
            tester.view.physicalSize = const Size(375, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var changes = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.lightTheme,
                locale: Locale(lang),
                supportedLocales: [Locale(lang)],
                localizationsDelegates: [
                  AppLocalizationsDelegate(lang),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: BookingServiceSelectionSummary(
                        service: service,
                        onChange: () => changes++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final label = find.byKey(
              const ValueKey('booking_selected_service_label'),
            );
            final text = tester.widget<Text>(label);
            expect(text.style!.fontSize, 20);
            expect(text.style!.fontWeight, FontWeight.w700);
            expect(text.maxLines, isNull);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            expect(tester.takeException(), isNull);
            await tester.tap(label);
            await tester.pump();
            expect(changes, 1);
            final field = find.byKey(
              const ValueKey('booking_selected_service_change'),
            );
            expect(tester.getSize(field).height, greaterThanOrEqualTo(60));
            await tester.tapAt(tester.getTopLeft(field) + const Offset(8, 8));
            await tester.pump();
            expect(changes, 2);
          },
        );
      }
    }
  }
}
