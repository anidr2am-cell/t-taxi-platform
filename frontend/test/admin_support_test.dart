import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_support/pages/admin_support_inquiry_page.dart';
import 'package:frontend/features/admin_support/services/admin_support_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _scrollDetailToAttachments(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
  await tester.pumpAndSettle();
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

  testWidgets('admin support detail renders safe attachment actions', (
    tester,
  ) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-260708-ABC123'));
    await tester.pumpAndSettle();
    await _scrollDetailToAttachments(tester);

    expect(find.text('ticket.jpg'), findsOneWidget);
    expect(find.text('storage/private/ticket.jpg'), findsNothing);
    expect(
      find.byKey(const Key('admin_support_attachment_preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin_support_attachment_download')),
      findsOneWidget,
    );
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

  testWidgets('admin support detail shows empty attachment state', (
    tester,
  ) async {
    final api = _FakeAdminSupportApi(attachments: const []);

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-260708-ABC123'));
    await tester.pumpAndSettle();
    await _scrollDetailToAttachments(tester);

    expect(find.text('첨부 파일 없음'), findsOneWidget);
  });

  testWidgets('admin support attachment preview fetches authenticated bytes', (
    tester,
  ) async {
    final api = _FakeAdminSupportApi();

    await tester.pumpWidget(_wrap(AdminSupportInquiryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP-260708-ABC123'));
    await tester.pumpAndSettle();
    await _scrollDetailToAttachments(tester);
    await tester.tap(find.byKey(const Key('admin_support_attachment_preview')));
    await tester.pumpAndSettle();

    expect(api.previewFetches, 1);
    expect(find.text('ticket.jpg'), findsWidgets);
  });

  test('admin support api fetches attachment with auth header', () async {
    SharedPreferences.setMockInitialValues({
      'admin_access_token': 'admin-token',
    });
    Uri? requestedUri;
    Map<String, String>? headers;
    final service = AdminSupportApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        requestedUri = request.url;
        headers = request.headers;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );

    final file = await service.fetchAttachment(
      inquiryId: 1,
      attachmentId: 3,
      download: true,
    );

    expect(
      requestedUri.toString(),
      'http://localhost:3000/api/v1/admin/support/inquiries/1/attachments/3?download=1',
    );
    expect(headers?['Authorization'], 'Bearer admin-token');
    expect(file.bytes, orderedEquals([1, 2, 3]));
    expect(file.mimeType, 'image/png');
  });
}

class _FakeAdminSupportApi extends AdminSupportApiService {
  _FakeAdminSupportApi({List<Map<String, dynamic>>? attachments})
    : attachments =
          attachments ??
          const [
            {
              'id': 1,
              'originalFileName': 'ticket.jpg',
              'mimeType': 'image/jpeg',
              'fileSize': 123,
              'isImage': true,
              'previewUrl': '/api/v1/admin/support/inquiries/1/attachments/1',
              'downloadUrl':
                  '/api/v1/admin/support/inquiries/1/attachments/1?download=1',
              'storagePath': 'storage/private/ticket.jpg',
            },
          ];

  String updatedStatus = 'NEW';
  String? reply;
  int previewFetches = 0;
  final List<Map<String, dynamic>> attachments;

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
      'attachments': attachments,
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

  @override
  Future<AdminSupportAttachmentFile> fetchAttachment({
    required int inquiryId,
    required int attachmentId,
    bool download = false,
  }) async {
    previewFetches += download ? 0 : 1;
    return AdminSupportAttachmentFile(
      bytes: Uint8List.fromList(_pngBytes),
      mimeType: 'image/png',
    );
  }
}

const _pngBytes = [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
