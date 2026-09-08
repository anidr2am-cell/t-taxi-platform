import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/app_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/driver/services/driver_session.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _CapturingHttpClient extends http.BaseClient {
  _CapturingHttpClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'driver_access_token': 'driver-test-token',
    });
    DriverSession.resetSharedForTesting();
  });

  group('computeReceiptIdempotencyKey', () {
    test('returns stable sha256 hex for the same booking number and bytes', () {
      const bookingNumber = 'TX202607010001';
      final bytes = [0x25, 0x50, 0x44, 0x46];

      final first = computeReceiptIdempotencyKey(bookingNumber, bytes);
      final second = computeReceiptIdempotencyKey(bookingNumber, bytes);

      expect(first, second);
      expect(first, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('changes when file bytes change', () {
      const bookingNumber = 'TX202607010001';

      final first = computeReceiptIdempotencyKey(bookingNumber, [1, 2, 3]);
      final second = computeReceiptIdempotencyKey(bookingNumber, [1, 2, 4]);

      expect(first, isNot(equals(second)));
    });

    test('changes when booking number changes', () {
      final bytes = [1, 2, 3];

      final first = computeReceiptIdempotencyKey('TX202607010001', bytes);
      final second = computeReceiptIdempotencyKey('TX202607010002', bytes);

      expect(first, isNot(equals(second)));
    });
  });

  group('uploadReceipt Idempotency-Key header', () {
    test('sends Idempotency-Key matching computeReceiptIdempotencyKey', () async {
      const bookingNumber = 'TX202607010001';
      final bytes = [0x25, 0x50, 0x44, 0x46];
      final expectedKey = computeReceiptIdempotencyKey(bookingNumber, bytes);
      String? capturedKey;

      final apiClient = ApiClient(
        baseUrl: AppConfig.apiBaseUrl,
        httpClient: _CapturingHttpClient((request) async {
          expect(request, isA<http.MultipartRequest>());
          capturedKey = (request as http.MultipartRequest).headers['Idempotency-Key'];
          expect(
            request.url.path,
            endsWith('/driver/settlements/$bookingNumber/receipt'),
          );
          return http.Response(
            '{"success":true,"data":{"bookingNumber":"$bookingNumber","commissionStatus":"RECEIPT_SUBMITTED","receiptStatus":"RECEIPT_SUBMITTED","receiptFileId":42}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final service = DriverSettlementApiService(
        session: DriverSession(apiClient: apiClient),
      );

      await service.uploadReceipt(bookingNumber, bytes, 'receipt.pdf');

      expect(capturedKey, expectedKey);
      expect(capturedKey, isNotNull);
    });

    test('retry uses the same Idempotency-Key for identical booking and bytes', () async {
      const bookingNumber = 'TX202607010001';
      final bytes = [1, 2, 3, 4];
      final expectedKey = computeReceiptIdempotencyKey(bookingNumber, bytes);
      final capturedKeys = <String?>[];

      final apiClient = ApiClient(
        baseUrl: AppConfig.apiBaseUrl,
        httpClient: _CapturingHttpClient((request) async {
          capturedKeys.add(
            (request as http.MultipartRequest).headers['Idempotency-Key'],
          );
          return http.Response(
            '{"success":true,"data":{"bookingNumber":"$bookingNumber","commissionStatus":"RECEIPT_SUBMITTED","receiptStatus":"RECEIPT_SUBMITTED","receiptFileId":42}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final service = DriverSettlementApiService(
        session: DriverSession(apiClient: apiClient),
      );

      await service.uploadReceipt(bookingNumber, bytes, 'receipt.png');
      await service.uploadReceipt(bookingNumber, bytes, 'receipt.png');

      expect(capturedKeys, hasLength(2));
      expect(capturedKeys[0], expectedKey);
      expect(capturedKeys[1], expectedKey);
      expect(capturedKeys[0], capturedKeys[1]);
    });
  });
}
