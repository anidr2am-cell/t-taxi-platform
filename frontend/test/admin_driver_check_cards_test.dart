import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/utils/admin_driver_check_messages.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_driver_check_cards.dart';
import 'package:frontend/l10n/app_localizations.dart';

Map<String, dynamic> sample() => {
  'bookingNumber': 'TX209901010183',
  'scheduledPickupAt': '2026-10-29T17:15:00.000Z',
  'route': {
    'origin': {
      'name': 'QA Airport',
      'nameTh': 'สนามบินทดสอบ',
      'address': 'QA meeting gate 4',
    },
  },
  'activeAssignment': {
    'driverDisplayName': 'QA Somchai',
    'vehicle': {'plateNumber': 'QA 1234'},
    'isActive': true,
  },
  'customer': {
    'phone': '+821012345678',
    'email': 'private@example.invalid',
    'messengerId': 'PRIVATE_ID',
  },
};
Widget host({String language = 'ko', Future<void> Function(String)? copy}) =>
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLanguages
          .map(Locale.new)
          .toList(),
      localizationsDelegates: [
        AppLocalizationsDelegate(language),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminDriverCheckCards(detail: sample(), copyText: copy),
        ),
      ),
    );

void main() {
  test(
    'Thai date, weekday and 24-hour time use Bangkok across midnight and offsets',
    () {
      final original = buildAdminDriverCheckMessages(sample());
      expect(original.first.thai, contains('2026-10-30 (วันศุกร์) เวลา 00:15'));
      expect(original.first.korean, contains('2026-10-30 (금요일) 00:15'));
      for (final raw in ['2026-10-30T02:15:00+09:00', '2026-10-30 00:15:00']) {
        final value = sample()..['scheduledPickupAt'] = raw;
        expect(
          buildAdminDriverCheckMessages(value).first.thai,
          original.first.thai,
        );
      }
    },
  );
  test(
    'sendable content has booking, meeting point and reference assignment but no customer contacts',
    () {
      for (final message in buildAdminDriverCheckMessages(sample())) {
        expect(message.thai, contains('TX209901010183'));
        expect(message.thai, isNot(contains('+821012345678')));
        expect(message.thai, isNot(contains('PRIVATE_ID')));
        expect(message.thai, isNot(contains('private@example.invalid')));
      }
      final messages = buildAdminDriverCheckMessages(sample());
      expect(messages.first.thai, contains('สนามบินทดสอบ · QA meeting gate 4'));
      expect(messages.first.thai, contains('ข้อมูลอ้างอิง'));
      expect(messages.first.thai, contains('QA Somchai'));
      expect(messages.first.thai, contains('QA 1234'));
      for (final card in messages.take(3)) {
        expect(card.thai, contains('ชื่อผู้ขับจริง: ______'));
        expect(card.thai, contains('ทะเบียนรถจริง: ______'));
      }
      expect(messages[2].thai, contains('ชื่อผู้ขับจริง: ______'));
      expect(messages[2].thai, contains('ทะเบียนรถจริง: ______'));
      expect(messages[2].thai, contains('รับผิดชอบการจองนี้'));
      expect(messages[2].thai, contains('พร้อมรับงานใหม่'));
      expect(messages[2].thai, contains('วันเวลาออกจริง'));
      expect(messages[2].thai, contains('ETA'));
      expect(messages.last.thai, isNot(contains('\n')));
    },
  );
  test(
    'missing or inactive assignments never use previous driver or infer departure',
    () {
      final detail = sample()
        ..['activeAssignment'] = null
        ..['scheduledPickupAt'] = 'invalid'
        ..['assignmentHistory'] = [
          {
            'driverDisplayName': 'OLD DRIVER',
            'vehicle': {'plateNumber': 'OLD PLATE'},
          },
        ]
        ..['status'] = 'ON_ROUTE';
      final text = buildAdminDriverCheckMessages(detail).first;
      expect(text.thai, contains('ยังไม่ระบุ'));
      expect(text.thai, isNot(contains('OLD DRIVER')));
      expect(text.thai, isNot(contains('OLD PLATE')));
      expect(text.thai, isNot(contains('2026-10-30')));
      final inactive = sample()
        ..['activeAssignment'] = {
          'driverDisplayName': 'INACTIVE',
          'isActive': false,
        };
      expect(
        buildAdminDriverCheckMessages(inactive).first.thai,
        isNot(contains('INACTIVE')),
      );
    },
  );
  testWidgets(
    'copy contains Thai only, reports success and does not send or change booking',
    (tester) async {
      String? copied;
      await tester.pumpWidget(
        host(
          copy: (text) async {
            copied = text;
          },
        ),
      );
      await tester.pumpAndSettle();
      final tooltip = AppLocalizations('ko')
          .t('admin_copy_action')
          .replaceAll('{field}', '예약 전달 시 확인 · 태국어 · 기사에게 보낼 내용');
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(copied, buildAdminDriverCheckMessages(sample()).first.thai);
      expect(copied, isNot(contains('한국어 뜻')));
      expect(find.text('복사했습니다'), findsOneWidget);
    },
  );
  testWidgets('copy failure gives existing localized guidance', (tester) async {
    await tester.pumpWidget(
      host(
        copy: (_) async {
          throw Exception('denied');
        },
      ),
    );
    await tester.pumpAndSettle();
    final tooltip = AppLocalizations('ko')
        .t('admin_copy_action')
        .replaceAll('{field}', '예약 전달 시 확인 · 태국어 · 기사에게 보낼 내용');
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    expect(
      find.text(AppLocalizations('ko').t('admin_copy_failed')),
      findsOneWidget,
    );
  });
  for (final lang in AppLocalizations.supportedLanguages) {
    testWidgets('cards and bilingual content fit 375px in $lang', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(language: lang));
      await tester.pumpAndSettle();
      final title = AppLocalizations(lang).t('admin_driver_check_handoff');
      expect(title, isNot('admin_driver_check_handoff'));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizations(lang).t('admin_driver_check_korean')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
