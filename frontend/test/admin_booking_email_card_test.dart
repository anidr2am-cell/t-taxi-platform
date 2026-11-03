import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_receipt_email_card.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class BookingApi extends AdminDispatchApiService {
  int previews = 0, sends = 0;
  bool approved = false, lost = false;
  Map<String, dynamic>? last;
  @override
  Future<Map<String, dynamic>> getBookingEmailState(String n) async => {
    'eligible': !approved,
    'configured': true,
    'email': '',
    'locale': 'ko',
    if (approved) 'delivery': {'status': 'DELIVERED'},
  };
  @override
  Future<Map<String, dynamic>> previewBookingEmail(
    String n,
    Map<String, dynamic> b,
  ) async {
    previews++;
    last = b;
    return {
      'subject': 'QA 예약 안내',
      'text': 'QA booking details',
      'previewHash': 'qa-hash',
    };
  }

  @override
  Future<Map<String, dynamic>> sendBookingEmail(
    String n,
    Map<String, dynamic> b,
  ) async {
    sends++;
    last = b;
    approved = true;
    if (lost) throw Exception('lost response');
    return getBookingEmailState(n);
  }

  @override
  Future<Map<String, dynamic>> getReceiptEmailState(String n) async =>
      throw StateError('wrong receipt endpoint');
}

Widget host(BookingApi a, {String lang = 'ko'}) => MaterialApp(
  locale: Locale(lang),
  supportedLocales: AppLocalizations.supportedLanguages
      .map(Locale.new)
      .toList(),
  localizationsDelegates: [
    AppLocalizationsDelegate(lang),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: SingleChildScrollView(
      child: AdminReceiptEmailCard(
        bookingNumber: 'TX209901010201',
        api: a,
        bookingConfirmation: true,
      ),
    ),
  ),
);
void main() {
  for (final lang in AppLocalizations.supportedLanguages)
    testWidgets('booking email card fits 375px in $lang', (t) async {
      await t.binding.setSurfaceSize(const Size(375, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final a = BookingApi();
      await t.pumpWidget(host(a, lang: lang));
      await t.pumpAndSettle();
      expect(
        find.text(AppLocalizations(lang).t('admin_booking_email_title')),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizations(lang).t('admin_customer_payment_confirm')),
        findsNothing,
      );
      expect(t.takeException(), isNull);
      expect(a.sends, 0);
    });
  testWidgets(
    'preview, cancel, explicit send once, and disable repeated send',
    (t) async {
      final a = BookingApi();
      await t.pumpWidget(host(a));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'invalid');
      await t.tap(find.text('미리보기'));
      await t.pumpAndSettle();
      expect(a.previews, 0);
      await t.enterText(find.byType(TextField), 'qa@example.invalid');
      await t.tap(find.text('미리보기'));
      await t.pumpAndSettle();
      expect(a.previews, 1);
      expect(a.sends, 0);
      expect(find.text('QA 예약 안내'), findsOneWidget);
      await t.ensureVisible(find.text('이 주소로 발송'));
      await t.tap(find.text('이 주소로 발송'));
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(a.sends, 0);
      await t.tap(find.text('이 주소로 발송'));
      await t.pumpAndSettle();
      await t.tap(find.text('발송 확정'));
      await t.pumpAndSettle();
      expect(a.sends, 1);
      expect(a.last?['previewHash'], 'qa-hash');
      expect(find.text('이 주소로 발송'), findsNothing);
    },
  );
  testWidgets('lost response refreshes approved state without resending', (
    t,
  ) async {
    final a = BookingApi()..lost = true;
    await t.pumpWidget(host(a));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'qa@example.invalid');
    await t.tap(find.text('미리보기'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('이 주소로 발송'));
    await t.tap(find.text('이 주소로 발송'));
    await t.pumpAndSettle();
    await t.tap(find.text('발송 확정'));
    await t.pumpAndSettle();
    expect(a.sends, 1);
    expect(find.text('이 주소로 발송'), findsNothing);
  });
  testWidgets('editing recipient invalidates preview', (t) async {
    final a = BookingApi();
    await t.pumpWidget(host(a));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'qa@example.invalid');
    await t.tap(find.text('미리보기'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'other@example.invalid');
    await t.pumpAndSettle();
    expect(find.text('이 주소로 발송'), findsNothing);
    expect(a.sends, 0);
  });
}
