import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_receipt_email_card.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class Api extends AdminDispatchApiService {
  int previews = 0, sends = 0, confirmations = 0;
  String paymentStatus = "UNPAID";
  final bool eligible;
  Api({this.eligible = true});
  @override
  Future<Map<String, dynamic>> getReceiptEmailState(String n) async => {
    'eligible': eligible,
    'configured': true,
    'email': '',
    'locale': 'ko',
    'payment': {
      'status': paymentStatus,
      'amount': 1100,
      'currency': 'THB',
      'canConfirm': paymentStatus != 'PAID',
    },
  };
  @override
  Future<Map<String, dynamic>> confirmCustomerPayment(
    String n,
    Map<String, dynamic> body,
  ) async {
    confirmations++;
    paymentStatus = 'PAID';
    return getReceiptEmailState(n);
  }

  @override
  Future<Map<String, dynamic>> previewReceiptEmail(
    String n,
    Map<String, dynamic> body,
  ) async {
    previews++;
    return {
      'subject': 'QA 영수증',
      'text': '결제 확인 금액: 1,100 바트',
      'previewHash': 'abc',
    };
  }

  @override
  Future<Map<String, dynamic>> sendReceiptEmail(
    String n,
    Map<String, dynamic> body,
  ) async {
    sends++;
    return {
      'eligible': false,
      'configured': true,
      'delivery': {'status': 'DELIVERED'},
    };
  }
}

Widget host(Api api, {String locale = 'ko'}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLanguages
      .map(Locale.new)
      .toList(),
  localizationsDelegates: [
    AppLocalizationsDelegate(locale),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: SingleChildScrollView(
      child: AdminReceiptEmailCard(
        key: ValueKey(api),
        bookingNumber: 'TX209901010201',
        api: api,
      ),
    ),
  ),
);
void main() {
  for (final locale in ['ko', 'en', 'th', 'ja', 'zh']) {
    testWidgets('payment dialog at 375px in $locale', (t) async {
      await t.binding.setSurfaceSize(const Size(375, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = Api();
      await t.pumpWidget(host(api, locale: locale));
      await t.pumpAndSettle();
      final l = AppLocalizations(locale);
      await t.tap(find.text(l.t('admin_customer_payment_confirm')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text(l.t('admin_receipt_cancel')));
      await t.pumpAndSettle();
      expect(api.confirmations, 0);
    });
  }

  testWidgets(
    'payment confirmation requires reason, cancels safely, retains email and clears old preview',
    (t) async {
      final api = Api();
      await t.pumpWidget(host(api));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'qa@example.invalid');
      await t.tap(find.text('미리보기'));
      await t.pumpAndSettle();
      expect(api.previews, 1);
      await t.ensureVisible(find.text('고객 결제 확인'));
      await t.tap(find.text('고객 결제 확인'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '결제 수령 확인'))
            .onPressed,
        isNull,
      );
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(api.confirmations, 0);
      await t.tap(find.text('고객 결제 확인'));
      await t.pumpAndSettle();
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '현금 수령 확인',
      );
      await t.pump();
      await t.tap(find.text('결제 수령 확인'));
      await t.pumpAndSettle();
      expect(api.confirmations, 1);
      expect(api.sends, 0);
      expect(find.text('고객 결제 확인 완료'), findsOneWidget);
      expect(find.text('이 주소로 발송'), findsNothing);
      expect(find.text('qa@example.invalid'), findsOneWidget);
      expect(find.text('고객 결제 확인'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('preview only, explicit confirm once, then sending is locked', (
    t,
  ) async {
    final a = Api();
    await t.pumpWidget(host(a));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'late@example.invalid');
    await t.tap(find.text('미리보기'));
    await t.pumpAndSettle();
    expect(a.previews, 1);
    expect(a.sends, 0);
    expect(find.text('QA 영수증'), findsOneWidget);
    await t.ensureVisible(find.text('이 주소로 발송'));
    await t.tap(find.text('이 주소로 발송'));
    await t.pumpAndSettle();
    expect(a.sends, 0);
    expect(find.textContaining('late@example.invalid'), findsWidgets);
    await t.tap(find.text('발송 확정'));
    await t.pumpAndSettle();
    expect(a.sends, 1);
    expect(find.textContaining('메일 서버에서 접수'), findsOneWidget);
    expect(find.text('이 주소로 발송'), findsNothing);
  });
  testWidgets('invalid address is rejected; email edits invalidate preview', (
    t,
  ) async {
    final a = Api();
    await t.pumpWidget(host(a));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'invalid');
    await t.tap(find.text('미리보기'));
    await t.pumpAndSettle();
    expect(a.previews, 0);
    expect(find.text('올바른 이메일 주소를 입력해 주세요.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'late@example.invalid');
    await t.tap(find.text('미리보기'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'changed@example.invalid');
    await t.pumpAndSettle();
    expect(find.text('이 주소로 발송'), findsNothing);
    expect(a.sends, 0);
  });
  for (final lang in ['ko', 'en', 'th', 'ja', 'zh']) {
    testWidgets('blocked and missing-email card fits 375px $lang', (t) async {
      t.view.physicalSize = const Size(375, 812);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(host(Api(), locale: lang));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(host(Api(eligible: false), locale: lang));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
