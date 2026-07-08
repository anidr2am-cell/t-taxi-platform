import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/support/services/support_inquiry_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('submit sends public support inquiry JSON request', () async {
    late http.Request captured;
    final service = SupportInquiryApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'publicId': 'SUP-260708-ABC123',
              'status': 'NEW',
              'createdAt': '2026-07-08 12:00:00',
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final receipt = await service.submit(
      message: 'Airport pickup question',
      locale: 'ko',
    );

    expect(captured.method, 'POST');
    expect(
      captured.url.toString(),
      'http://localhost:3000/api/v1/support/inquiries',
    );
    expect(jsonDecode(captured.body), {
      'message': 'Airport pickup question',
      'locale': 'ko',
    });
    expect(receipt.publicId, 'SUP-260708-ABC123');
    expect(receipt.status, 'NEW');
  });

  test('submit maps error response to support inquiry exception', () async {
    final service = SupportInquiryApiService(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'message': 'Validation failed'}),
          400,
        );
      }),
    );

    await expectLater(
      service.submit(message: 'x'),
      throwsA(isA<SupportInquiryApiException>()),
    );
  });
}
