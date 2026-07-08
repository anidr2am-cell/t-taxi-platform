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
  testWidgets('admin support list shows inquiries', (tester) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('SUP-260708-ABC123'), findsOneWidget);
    expect(find.textContaining('공항 픽업 문의'), findsOneWidget);
    expect(find.text('신규'), findsWidgets);
  });

  testWidgets('admin support detail shows message and updates status', (
    tester,
  ) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-260708-ABC123'));
    await tester.pumpAndSettle();

    expect(find.text('공항 픽업 문의 전체 내용'), findsOneWidget);
    expect(find.text('ticket.jpg'), findsOneWidget);

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
          'messagePreview': '공항 픽업 문의',
          'customerName': 'Test Customer',
          'customerPhone': '+66810000000',
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
      'message': '공항 픽업 문의 전체 내용',
      'customerName': 'Test Customer',
      'customerPhone': '+66810000000',
      'customerEmail': null,
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
}
