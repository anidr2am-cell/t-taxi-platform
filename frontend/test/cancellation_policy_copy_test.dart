import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/landing/widgets/landing_trust_section.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  final policyMarkers = {
    'ko': ['운행 시작 전', '2시간보다 많이', '예약 조회', '무료 취소', '전액 환불'],
    'en': ['Before the trip starts', 'more than 2 hours', 'booking lookup', 'free of charge', 'full refund'],
    'zh': ['尚未开始', '超过2小时', '预订查询', '免费取消', '全额退款'],
    'ja': ['運行開始前', '2時間前より前', '予約照会', '無料', '全額返金'],
    'th': ['ยังไม่เริ่มการเดินทาง', 'มากกว่า 2 ชั่วโมง', 'ตรวจสอบการจอง', 'ยกเลิกฟรี', 'คืนเต็มจำนวน'],
  };
  for (final language in policyMarkers.keys) {
    testWidgets('cancellation policy is accurate and wraps at 375px: $language', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = AppLocalizations(language);
      final description = l10n.t('landing_trust_refund_desc');
      final hint = l10n.t('booking_cancel_policy_hint');
      for (final marker in policyMarkers[language]!) {
        expect(description, contains(marker));
        expect(hint, contains(marker));
      }
      // The unconfirmed price-match clause must stay for Edward's review.
      expect(description, contains('48'));
      expect(description, isNot(contains('24')));
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLanguages.map((code) => Locale(code)),
        localizationsDelegates: [
          AppLocalizationsDelegate(language),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: SingleChildScrollView(child: LandingTrustSection())),
      ));
      await tester.pumpAndSettle();
      expect(find.text(description), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
