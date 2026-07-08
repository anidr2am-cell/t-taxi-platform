import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/support/pages/customer_support_page.dart';
import 'package:frontend/features/support/services/support_inquiry_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapSupport({
  Locale locale = const Locale('ko'),
  double width = 360,
  double height = 900,
  SupportInquiryApiService? api,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate(locale.languageCode),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, height)),
      child: CustomerSupportPage(api: api),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomerSupportPage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders support landing content without inline chat input', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_title')), findsWidgets);
      expect(find.text(l10n.t('support_page_intro')), findsOneWidget);
      expect(find.text(l10n.t('support_inquiry_button')), findsOneWidget);
      expect(find.byKey(const Key('support_message_input')), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text(l10n.t('support_faq_placeholder')), findsOneWidget);
    });

    testWidgets('inquiry button opens popup with contact fields and input', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_dialog_title')), findsOneWidget);
      expect(find.text(l10n.t('support_default_guide')), findsOneWidget);
      expect(
        find.byKey(const Key('support_customer_phone_input')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('support_kakao_input')), findsOneWidget);
      expect(find.byKey(const Key('support_line_input')), findsOneWidget);
      expect(find.byKey(const Key('support_message_input')), findsOneWidget);
      expect(find.byKey(const Key('support_attach_button')), findsOneWidget);
      expect(find.byKey(const Key('support_send_button')), findsOneWidget);
      expect(find.text(l10n.t('support_attachment_help')), findsOneWidget);
    });

    testWidgets('sending a message includes contact fields and receipt', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');
      final api = _FakeSupportApi();

      await tester.pumpWidget(_wrapSupport(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('support_customer_phone_input')),
        '+66810000000',
      );
      await tester.enterText(
        find.byKey(const Key('support_kakao_input')),
        'test-kakao',
      );
      await tester.enterText(
        find.byKey(const Key('support_line_input')),
        'test-line',
      );
      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'BKK to Pattaya inquiry',
      );
      await tester.ensureVisible(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();

      expect(api.messages, ['BKK to Pattaya inquiry']);
      expect(api.phone, '+66810000000');
      expect(api.kakaoId, 'test-kakao');
      expect(api.lineId, 'test-line');
      expect(api.savedLookup, true);
      expect(find.text('BKK to Pattaya inquiry'), findsOneWidget);
      expect(
        find.textContaining(l10n.t('support_auto_receipt')),
        findsOneWidget,
      );
      expect(find.textContaining('SUP-260708-ABC123'), findsOneWidget);
      final input = tester.widget<TextField>(
        find.byKey(const Key('support_message_input')),
      );
      expect(input.controller?.text, isEmpty);
    });

    testWidgets('opening popup loads stored inquiry thread', (tester) async {
      final api = _FakeSupportApi(
        lookup: const SupportInquiryLookup(
          publicId: 'SUP-260708-ABC123',
          token: 'lookup-token',
        ),
        thread: const SupportInquiryThread(
          publicId: 'SUP-260708-ABC123',
          status: 'IN_PROGRESS',
          messages: [
            SupportInquiryMessage(
              senderType: 'CUSTOMER',
              message: 'Customer question',
            ),
            SupportInquiryMessage(senderType: 'ADMIN', message: 'Admin reply'),
          ],
        ),
      );

      await tester.pumpWidget(_wrapSupport(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      expect(api.loadedThread, true);
      expect(find.text('Customer question'), findsOneWidget);
      expect(find.text('Admin reply'), findsOneWidget);
    });

    testWidgets('submit shows loading state while API is pending', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');
      final completer = Completer<SupportInquiryReceipt>();
      final api = _FakeSupportApi(completer: completer);

      await tester.pumpWidget(_wrapSupport(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'Loading inquiry',
      );
      await tester.ensureVisible(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_send_button')));
      await tester.pump();

      expect(find.text(l10n.t('support_sending')), findsOneWidget);

      completer.complete(
        const SupportInquiryReceipt(
          publicId: 'SUP-260708-LOADING',
          lookupToken: 'lookup-token',
          status: 'NEW',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('SUP-260708-LOADING'), findsOneWidget);
    });

    testWidgets('submit failure keeps typed message visible for retry', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');
      final api = _FakeSupportApi(
        error: const SupportInquiryApiException('Network error'),
      );

      await tester.pumpWidget(_wrapSupport(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'Retry this message',
      );
      await tester.ensureVisible(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_send_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('support_error_message')), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.textContaining(l10n.t('support_auto_receipt')), findsNothing);
      final input = tester.widget<TextField>(
        find.byKey(const Key('support_message_input')),
      );
      expect(input.controller?.text, 'Retry this message');
    });

    testWidgets('chat popup can be closed', (tester) async {
      final l10n = AppLocalizations('ko');

      await tester.pumpWidget(_wrapSupport());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_dialog_title')), findsOneWidget);

      await tester.tap(find.byKey(const Key('support_close_button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_dialog_title')), findsNothing);
      expect(find.byKey(const Key('support_message_input')), findsNothing);
    });

    testWidgets('has no overflow at common widths', (tester) async {
      for (final width in [360.0, 768.0, 1440.0]) {
        await tester.pumpWidget(_wrapSupport(width: width));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Page at $width');

        await tester.tap(find.byKey(const Key('support_open_inquiry_button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Popup at $width');
        expect(find.byKey(const Key('support_message_input')), findsOneWidget);

        await tester.tap(find.byKey(const Key('support_close_button')));
        await tester.pumpAndSettle();
      }
    });
  });
}

class _FakeSupportApi extends SupportInquiryApiService {
  _FakeSupportApi({this.error, this.completer, this.lookup, this.thread})
    : super(baseUrl: 'http://test.local');

  final Object? error;
  final Completer<SupportInquiryReceipt>? completer;
  final SupportInquiryLookup? lookup;
  final SupportInquiryThread? thread;
  final List<String> messages = [];
  String? phone;
  String? kakaoId;
  String? lineId;
  bool savedLookup = false;
  bool loadedThread = false;

  @override
  Future<SupportInquiryReceipt> submit({
    required String message,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? kakaoId,
    String? lineId,
    String? locale,
    List<SupportInquiryAttachmentDraft> attachments = const [],
  }) async {
    messages.add(message);
    phone = customerPhone;
    this.kakaoId = kakaoId;
    this.lineId = lineId;
    if (error != null) throw error!;
    if (completer != null) return completer!.future;
    return const SupportInquiryReceipt(
      publicId: 'SUP-260708-ABC123',
      lookupToken: 'lookup-token',
      status: 'NEW',
    );
  }

  @override
  Future<void> saveLatestLookup(SupportInquiryReceipt receipt) async {
    savedLookup = true;
  }

  @override
  Future<SupportInquiryLookup?> loadLatestLookup() async => lookup;

  @override
  Future<SupportInquiryThread> getThread({
    required String publicId,
    required String lookupToken,
  }) async {
    loadedThread = true;
    return thread ??
        const SupportInquiryThread(
          publicId: 'SUP-260708-ABC123',
          status: 'NEW',
          messages: [],
        );
  }
}
