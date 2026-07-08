import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_support/pages/admin_support_inquiry_page.dart';
import 'package:frontend/features/admin_support/services/admin_support_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  testWidgets('admin support list shows inquiries and contact fields', (
    tester,
  ) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('SUP-260708-ABC123'), findsOneWidget);
    expect(find.textContaining('Airport pickup question'), findsOneWidget);
    expect(find.textContaining('test-kakao'), findsOneWidget);
    expect(find.textContaining('legacy@example.com'), findsNothing);
    expect(find.text('신규'), findsWidgets);
  });

  testWidgets('admin support detail shows thread and sends reply', (
    tester,
  ) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-260708-ABC123'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('admin_support_message_thread')),
      findsOneWidget,
    );
    expect(find.text('Airport pickup full question'), findsOneWidget);
    expect(find.text('test-line'), findsOneWidget);
    expect(find.text('legacy@example.com'), findsNothing);
    expect(find.byKey(const Key('admin_support_reply_input')), findsOneWidget);
    expect(
      find.byKey(const Key('admin_support_send_reply_button')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('admin_support_reply_input')),
      'We will check this booking.',
    );
    await tester.tap(find.byKey(const Key('admin_support_send_reply_button')));
    await tester.pumpAndSettle();

    expect(api.reply, 'We will check this booking.');
    expect(api.updatedStatus, 'IN_PROGRESS');
    expect(find.text('We will check this booking.'), findsOneWidget);
  });

  testWidgets('admin support detail updates status', (tester) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-260708-ABC123'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처리중').last);
    await tester.pumpAndSettle();

    expect(api.updatedStatus, 'IN_PROGRESS');
    expect(find.text('처리중'), findsWidgets);
  });
}

class _FakeAdminSupportApi extends AdminSupportApiService {
  _FakeAdminSupportApi();

  String updatedStatus = 'NEW';
  String? reply;

  @override
  Future<Map<String, dynamic>> listInquiries({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    return {
      'page': 1,
      'total': 1,
      'items': [
        {
          'id': 1,
          'publicId': 'SUP-260708-ABC123',
          'status': updatedStatus,
          'messagePreview': 'Airport pickup question',
          'latestMessagePreview': reply ?? 'Airport pickup question',
          'customerName': 'Test Customer',
          'customerPhone': '+66810000000',
          'kakaoId': 'test-kakao',
          'lineId': 'test-line',
          'attachmentCount': 1,
          'createdAt': '2026-07-08 12:00:00',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getInquiry(int id) async {
    return {
      'id': id,
      'publicId': 'SUP-260708-ABC123',
      'status': updatedStatus,
      'message': 'Airport pickup full question',
      'customerName': 'Test Customer',
      'customerPhone': '+66810000000',
      'customerEmail': 'legacy@example.com',
      'kakaoId': 'test-kakao',
      'lineId': 'test-line',
      'messages': [
        {
          'id': 1,
          'senderType': 'CUSTOMER',
          'message': 'Airport pickup full question',
        },
        if (reply != null) {'id': 2, 'senderType': 'ADMIN', 'message': reply},
      ],
      'attachments': [
        {'id': 1, 'originalFileName': 'ticket.jpg', 'mimeType': 'image/jpeg'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> updateStatus(int id, String status) async {
    updatedStatus = status;
    return getInquiry(id);
  }

  @override
  Future<Map<String, dynamic>> sendReply(int id, String message) async {
    reply = message;
    updatedStatus = 'IN_PROGRESS';
    return getInquiry(id);
  }
}
