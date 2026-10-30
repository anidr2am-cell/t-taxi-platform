import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/widgets/driver_name_sign_details.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('parses only explicit sign name without customer fallback', () {
    for (final name in ['홍길동', 'สมชาย ใจดี', 'Jane O’Neil {booking}']) {
      expect(DriverBooking.fromJson({'nameSignText': name}).nameSignText, name);
    }
    for (final value in [null, 123, {}]) {
      expect(
        DriverBooking.fromJson({
          'nameSignText': value,
          'customerDisplayName': 'DO NOT USE',
        }).nameSignText,
        isNull,
      );
    }
  });
  for (final lang in ['ko', 'th']) {
    for (final name in <String?>[
      '홍길동 สมชาย Jane O’Neil {booking}',
      null,
      '   ',
    ]) {
      testWidgets('bilingual sign and missing fallback 375 $lang $name', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(lang),
            supportedLocales: const [Locale('ko'), Locale('th')],
            localizationsDelegates: [
              AppLocalizationsDelegate(lang),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: DriverNameSignDetails(name: name)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('피켓에 적을 이름\n(ชื่อที่ต้องเขียนบนป้าย)'),
          findsOneWidget,
        );
        if (name != null && name.trim().isNotEmpty) {
          expect(find.text(name), findsOneWidget);
        } else {
          expect(find.textContaining('관리자에게 확인하세요'), findsOneWidget);
          expect(find.textContaining('กรุณาสอบถามผู้ดูแล'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
