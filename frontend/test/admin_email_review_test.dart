import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_notification/pages/admin_email_review_page.dart';
import 'package:frontend/features/admin_notification/services/admin_notification_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class FakeMailApi extends AdminNotificationApiService {
  FakeMailApi({this.recoverable = false});
  final bool recoverable;
  int approvals = 0, records = 0;
  @override
  Future<Map<String, dynamic>> listEmailReviews({
    bool includeHandled = false,
    int page = 1,
  }) async => {
    'items': [
      {
        'deliveryId': 1,
        'attemptId': 2,
        'bookingNumber': 'QA_MAIL',
        'notificationType': 'BOOKING_CREATED',
        'outcome': recoverable ? 'NOT_ACCEPTED' : 'UNKNOWN',
        'recoverable': recoverable,
        'updatedAt': '2026-10-15T03:00:00.000Z',
        'traceId': 'trace-1234',
        'messageId': '<mail-1@trider.taxi>',
        if (recoverable) 'smtpCommand': 'RCPT TO',
        if (recoverable) 'smtpResponseCode': 550,
        if (recoverable) 'errorCode': 'EENVELOPE',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> reviewEmail(
    int id, {
    required String action,
    required String reason,
    int? expectedAttemptId,
  }) async {
    if (action == 'RETRY_APPROVED') {
      approvals++;
      expect(expectedAttemptId, 2);
    } else {
      records++;
    }
    expect(reason.trim().length, greaterThanOrEqualTo(3));
    return {'outcome': 'ACCEPTED'};
  }

  @override
  Future<Map<String, dynamic>> emailHistory(int id) async => {
    'attempts': [
      {
        'trace_id': 'trace-1234',
        'message_id': 'mail-1',
        'outcome': 'UNKNOWN',
        'started_at': '2026-10-15T03:00:00Z',
      },
    ],
    'reviews': [],
  };
}

Widget app(FakeMailApi api, String lang) => MaterialApp(
  locale: Locale(lang),
  supportedLocales: [Locale(lang)],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: AdminEmailReviewPage(api: api),
);

void main() {
  for (final lang in ['ko', 'en', 'zh', 'ja', 'th']) {
    testWidgets(
      '375px $lang unknown mail blocks recovery and labels are translated',
      (tester) async {
        tester.view.physicalSize = const Size(375, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FakeMailApi();
        await tester.pumpWidget(app(api, lang));
        await tester.pumpAndSettle();
        final l = AppLocalizations(lang);
        expect(find.text(l.t('admin_email_title')), findsOneWidget);
        expect(find.text(l.t('admin_email_outcome_UNKNOWN')), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l.t('admin_email_RETRY_APPROVED')),
        );
        expect(button.onPressed, isNull);
        expect(api.approvals, 0);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('2026-10-15 10:00'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'approval requires reason and records only one approved recovery',
    (tester) async {
      final api = FakeMailApi(recoverable: true);
      await tester.pumpWidget(app(api, 'ko'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('미수락 메일 승인 복구'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('QA_MAIL'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('RCPT TO 550'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '확인'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'SMTP 550 미수락 확인');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '확인'));
      await tester.pumpAndSettle();
      expect(api.approvals, 1);
      expect(find.textContaining('고객 수신 완료를 뜻하지는 않습니다'), findsOneWidget);
    },
  );
  testWidgets('manual contact review does not recover or send email', (
    tester,
  ) async {
    final api = FakeMailApi();
    await tester.pumpWidget(app(api, 'ko'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('별도 연락 처리'));
    await tester.pumpAndSettle();
    expect(find.textContaining('메일은 발송하지 않습니다'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '관리자 채널로 안내 완료');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(api.records, 1);
    expect(api.approvals, 0);
  });
}
