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
    'destination': {'nameTh': 'โรงแรมทดสอบ', 'address': 'QA Hotel Road'},
  },
  'serviceType': {'code': 'AIRPORT_PICKUP'},
  'vehicle': {'typeCode': 'SEDAN'},
  'passengers': {'adults': 2, 'children': 1, 'infants': 0},
  'luggage': {'carriers20Inch': 2, 'carriers24InchPlus': 1, 'golfBags': 0},
  'flight': {'flightNumber': 'KE651'},
  'options': {'nameSign': true},
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
    'sign copy preserves explicit name and handles missing or disabled signs',
    () {
      final detail = sample();
      for (final name in ['홍길동 สมชาย Jane {booking}', null, '  ']) {
        detail['options'] = {'nameSign': true, 'nameSignText': name};
        final message = buildAdminDriverCheckMessages(detail).single;
        if (name != null && name.trim().isNotEmpty) {
          expect(message.thai, contains('ชื่อที่ต้องเขียนบนป้าย: $name'));
          expect(message.korean, contains('피켓에 적을 이름: $name'));
        } else {
          expect(
            message.thai,
            contains('ยังไม่ได้ระบุชื่อ กรุณาสอบถามผู้ดูแล'),
          );
          expect(message.korean, contains('이름 미등록 — 관리자 확인 필요'));
        }
      }
      detail['options'] = {'nameSign': false, 'nameSignText': 'STALE NAME'};
      expect(
        buildAdminDriverCheckMessages(detail).single.thai,
        isNot(contains('STALE NAME')),
      );
    },
  );

  test(
    'Thai date, weekday and 24-hour time use Bangkok across midnight and offsets',
    () {
      final original = buildAdminDriverCheckMessages(sample());
      expect(original.first.thai, contains('2026-10-30 (วันศุกร์)'));
      expect(original.first.korean, contains('2026-10-30 (금요일)'));
      expect(original.first.thai, contains('เวลารับ: 00:15'));
      expect(original.first.korean, contains('픽업 시각: 00:15'));
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
      expect(messages, hasLength(1));
      final text = messages.single.thai;
      for (final part in [
        'สนามบินทดสอบ · QA meeting gate 4',
        'โรงแรมทดสอบ · QA Hotel Road',
        'รับจากสนามบิน',
        'ซีดาน',
        'KE651',
        'ผู้ใหญ่ 2 / เด็ก 1 / ทารก 0',
        'QA Somchai',
        'QA 1234',
        'ป้ายชื่อ',
      ]) {
        expect(text, contains(part));
      }
      for (final removed in [
        '______',
        'ตอบกลับ',
        'กรอก',
        'ETA',
        'พร้อมรับงานใหม่',
      ]) {
        expect(text, isNot(contains(removed)));
      }
      expect(text, contains('ไม่ได้หมายความว่าคนขับออกเดินทางแล้ว'));
      expect(text, contains('การติดต่อกับลูกค้าดำเนินการผ่านผู้ดูแล'));
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
  test(
    'no fabricated counts, no optional lines or empty placeholders when absent',
    () {
      final detail = sample()
        ..remove('passengers')
        ..remove('luggage')
        ..remove('flight')
        ..remove('options');
      final text = buildAdminDriverCheckMessages(detail).single.thai;
      expect(text, contains('ผู้ใหญ่ ยังไม่ระบุ'));
      expect(text, isNot(contains('✈️')));
      expect(text, isNot(contains('🪧')));
      expect(text, isNot(matches(RegExp(r'\{[A-Za-z]+\}'))));
      final value = sample();
      (value['route'] as Map)['origin'] = {'nameTh': '{driver}'};
      expect(
        buildAdminDriverCheckMessages(value).single.thai,
        contains('จุดรับ: {driver}'),
      );
    },
  );
  test(
    'all service and vehicle labels are Thai with no status-dependent departure claims',
    () {
      for (final service in [
        'AIRPORT_PICKUP',
        'AIRPORT_DROPOFF',
        'CITY_TRANSFER',
        'GOLF_TRANSFER',
      ]) {
        for (final vehicle in ['SEDAN', 'SUV', 'VAN']) {
          final detail = sample()
            ..['serviceType'] = {'code': service}
            ..['vehicle'] = {'typeCode': vehicle}
            ..['status'] = 'ON_ROUTE';
          final text = buildAdminDriverCheckMessages(detail).single.thai;
          expect(text, isNot(contains(service)));
          expect(text, isNot(contains(vehicle)));
          expect(text, isNot(contains('ETA')));
        }
      }
    },
  );
  test('finance separates collection commission sign and net', () {
    final detail = sample()
      ..['driverFinancialSummary'] = {
        'collectionMode': 'DRIVER_COLLECTS',
        'paymentStatus': 'UNPAID',
        'currency': 'THB',
        'customerTotalAmount': 1100,
        'collectFromCustomerAmount': 1100,
        'commissionAmount': 200,
        'nameSignAmount': 100,
        'companyDeductionAmount': 200,
        'driverNetAmount': 900,
        'driverReceiptAmount': 900,
        'driverOperatingIncomeAmount': 800,
        'nameSignAdvanceAmount': 100,
        'nameSignReimbursementAmount': 100,
        'basis': 'CURRENT_TRIP_RULE_ESTIMATE',
        'needsConfirmation': false,
      };
    final text = buildAdminDriverCheckMessages(detail).single.thai;
    expect(text, contains('เก็บจากลูกค้าโดยตรง'));
    expect(text, contains('ค่าคอมมิชชันบริษัท: ฿200'));
    expect(text, contains('ยอดเงินที่คนขับได้รับ (รวมเงินคืนค่าป้าย): ฿900'));
    expect(text, contains('฿1,100'));
    expect(text, contains('รายได้จากงานหลังหักต้นทุนค่าป้าย: ฿800'));
    expect(text, isNot(contains('ยอดหักรวมของบริษัท')));
    expect(text, contains('ห้ามเรียกเก็บค่าป้ายเพิ่ม'));
    expect(text, contains('ประมาณการ'));
    final paid = sample()
      ..['driverFinancialSummary'] = <String, dynamic>{
        ...Map<String, dynamic>.from(detail['driverFinancialSummary'] as Map),
        'paymentStatus': 'PAID',
        'collectFromCustomerAmount': 0,
      };
    final paidText = buildAdminDriverCheckMessages(paid).single.thai;
    expect(paidText, isNot(contains('เก็บจากลูกค้าโดยตรง')));
    expect(paidText, contains('ไม่เรียกเก็บซ้ำ'));
    detail['driverFinancialSummary'] = <String, dynamic>{
      ...Map<String, dynamic>.from(detail['driverFinancialSummary'] as Map),
      'collectionMode': 'ADMIN_PAYS',
      'collectFromCustomerAmount': 0,
      'adminPayoutAmount': 900,
      'paymentStatus': 'PAID',
      'basis': 'REGISTERED_PAYOUT',
    };
    final admin = buildAdminDriverCheckMessages(detail).single.thai;
    expect(admin, contains('ไม่เรียกเก็บเงินลูกค้า'));
    expect(admin, contains('คนขับรับจากลูกค้า: ฿0'));
    expect(admin, contains('ยอดที่ผู้ดูแลจะจ่ายให้คนขับ: ฿900'));
    expect(admin, contains('ลูกค้าชำระแล้ว'));
    expect(admin, contains('ไม่หักเพิ่ม'));
    final korean = buildAdminDriverCheckMessages(detail).single.korean;
    expect(korean, contains('회사 수수료: ฿200'));
    expect(korean, isNot(contains('회사 수수료 몫')));
    expect(korean, contains('기사 수령액(피켓비 보전 포함): ฿900'));
    expect(korean, contains('운행 수익(수령액에서 선납 피켓 원가 제외): ฿800'));
  });
  test('missing or invalid money needs confirmation, not zero', () {
    final missing = buildAdminDriverCheckMessages(sample()).single.thai;
    expect(missing, contains('ต้องให้ผู้ดูแลตรวจสอบ'));
    expect(missing, contains('ค่าคอมมิชชันบริษัท: ยังไม่ระบุ'));
    expect(missing, isNot(contains('฿0')));
    final detail = sample()
      ..['driverFinancialSummary'] = {
        'currency': 'THB',
        'driverReceiptAmount': -1,
        'needsConfirmation': true,
      };
    expect(
      buildAdminDriverCheckMessages(detail).single.thai,
      contains('ยอดเงินที่คนขับได้รับ (รวมเงินคืนค่าป้าย): ยังไม่ระบุ'),
    );
  });
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
          .replaceAll('{field}', '예약 정보 복사 · 태국어 · 기사에게 보낼 내용');
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
        .replaceAll('{field}', '예약 정보 복사 · 태국어 · 기사에게 보낼 내용');
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
      expect(find.text(title), findsOneWidget);
      expect(
        find.text(AppLocalizations(lang).t('admin_driver_check_korean')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
