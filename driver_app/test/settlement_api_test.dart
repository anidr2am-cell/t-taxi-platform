import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/settlement/data/settlement_api.dart';
import 'package:tride_driver/features/settlement/data/settlement_models.dart';

import 'test_fakes.dart';

void main() {
  SettlementApi api(http.Client client) => SettlementApi(
    client: ApiClient(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      httpClient: client,
    ),
    storage: FakeTokenStorage(
      const AuthTokens(
        accessToken: 'settlement-token',
        refreshToken: 'refresh',
      ),
    ),
  );

  Map<String, dynamic> envelope(Object data) => {'success': true, 'data': data};

  test('list settlements calls the driver endpoint and parses items', () async {
    late http.BaseRequest request;
    final result = await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(
            envelope({
              'items': [
                settlementJson(
                  bookingNumber: 'TX1',
                  commissionStatus: 'OVERDUE',
                  blocksNewCalls: true,
                ),
              ],
            }),
          ),
          200,
        );
      }),
    ).listSettlements();

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/driver/settlements');
    expect(request.headers['authorization'], 'Bearer settlement-token');
    expect(result.single.bookingNumber, 'TX1');
    expect(result.single.commissionStatus.code, SettlementStatusCode.overdue);
    expect(result.single.blocksNewCalls, isTrue);
  });

  test('list item parses nameSignAmount from API payload', () async {
    final result = await api(
      MockClient(
        (_) async => http.Response(
          jsonEncode(
            envelope({
              'items': [
                settlementJson(
                  bookingNumber: 'TX-SIGN',
                  nameSignAmount: 150,
                  driverExpectedIncomeAmount: 1000,
                ),
              ],
            }),
          ),
          200,
        ),
      ),
    ).listSettlements();

    expect(result.single.nameSignAmount, 150);
    expect(result.single.driverExpectedIncomeAmount, 1000);
  });

  test('detail parses payment instructions', () async {
    final result = await api(
      MockClient(
        (_) async => http.Response(
          jsonEncode(
            envelope(
              settlementJson(
                paymentInstructions: const {
                  'bankName': 'Kasikorn',
                  'accountName': 'T-Ride Co.',
                  'accountNumber': '123-4-56789-0',
                  'promptPayNumber': '0999999999',
                  'promptPayQrImageUrl': '/api/v1/files/qr.png',
                },
              ),
            ),
          ),
          200,
        ),
      ),
    ).getSettlement('TX209912310001');

    expect(result.paymentInstructions.bankName, 'Kasikorn');
    expect(
      result.paymentInstructions.promptPayQrImageUrl,
      '/api/v1/files/qr.png',
    );
  });

  test('receipt upload sends multipart file field with MIME type', () async {
    late http.BaseRequest request;
    final result =
        await api(
          MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode(
                envelope(
                  settlementJson(
                    commissionStatus: 'RECEIPT_SUBMITTED',
                    receiptUrl: '/api/v1/driver/settlements/TX1/receipt',
                  ),
                ),
              ),
              200,
            );
          }),
        ).uploadReceipt(
          'TX1',
          const SettlementUploadFile(filename: 'receipt.png', bytes: [1, 2, 3]),
          idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
        );

    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/driver/settlements/TX1/receipt');
    expect(request.headers['Idempotency-Key'], '550e8400-e29b-41d4-a716-446655440000');
    expect(request.headers.containsKey('Idempotency-Key'), isTrue);
    expect(result.commissionStatus.code, SettlementStatusCode.receiptSubmitted);
  });

  test('receipt download includes authorization and returns bytes', () async {
    late http.BaseRequest request;
    final result = await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response.bytes(const [1, 2, 3], 200);
      }),
    ).downloadReceipt('/api/v1/driver/settlements/TX1/receipt');

    expect(request.method, 'GET');
    expect(request.headers['authorization'], 'Bearer settlement-token');
    expect(result, [1, 2, 3]);
  });

  for (final entry in {
    'VALIDATION_ERROR': ApiFailureKind.validation,
    'INVALID_FILE_TYPE': ApiFailureKind.invalidFileType,
    'FILE_TOO_LARGE': ApiFailureKind.fileTooLarge,
    'SETTLEMENT_NOT_FOUND': ApiFailureKind.settlementNotFound,
    'RECEIPT_ALREADY_APPROVED': ApiFailureKind.receiptAlreadyApproved,
  }.entries) {
    test('receipt upload classifies ${entry.key}', () async {
      await expectLater(
        api(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'success': false, 'error_code': entry.key}),
              entry.key == 'RECEIPT_ALREADY_APPROVED' ? 409 : 400,
            ),
          ),
        ).uploadReceipt(
          'TX1',
          const SettlementUploadFile(filename: 'receipt.jpg', bytes: [1]),
          idempotencyKey: 'retry-key-1',
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            entry.value,
          ),
        ),
      );
    });
  }

  test('receipt upload rejects unsupported files before transport', () async {
    var calls = 0;
    await expectLater(
      api(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ).uploadReceipt(
        'TX1',
        const SettlementUploadFile(filename: 'receipt.gif', bytes: [1]),
        idempotencyKey: 'retry-key-2',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.invalidFileType,
        ),
      ),
    );
    expect(calls, 0);
  });
}
