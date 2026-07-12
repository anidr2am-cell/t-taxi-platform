import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver_settlement/pages/driver_settlement_list_page.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

class _FakeSettlementApi extends DriverSettlementApiService {
  _FakeSettlementApi({this.error, this.uploadError});

  final Object? error;
  final Object? uploadError;
  int uploadCalls = 0;
  bool uploaded = false;

  @override
  Future<List<dynamic>> listSettlements() async {
    if (error != null) throw error!;
    return [];
  }

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    if (error != null) throw error!;
    if (uploaded) {
      return {
        'bookingNumber': bookingNumber,
        'commissionStatus': 'RECEIPT_SUBMITTED',
        'commissionAmount': 120,
        'currency': 'THB',
        'dueAt': '2026-07-08 12:00:00',
      };
    }
    return {
      'bookingNumber': bookingNumber,
      'commissionStatus': 'PENDING',
      'commissionAmount': 120,
      'currency': 'THB',
      'dueAt': '2026-07-08 12:00:00',
    };
  }

  @override
  Future<Map<String, dynamic>> uploadReceipt(
    String bookingNumber,
    List<int> bytes,
    String filename,
  ) async {
    uploadCalls += 1;
    if (uploadError != null) throw uploadError!;
    uploaded = true;
    return {
      'bookingNumber': bookingNumber,
      'commissionStatus': 'RECEIPT_SUBMITTED',
    };
  }
}

void main() {
  testWidgets('driver settlement shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DriverSettlementListPage(api: _FakeSettlementApi())),
    );
    await tester.pumpAndSettle();
    expect(find.text('정산 내역이 없습니다\n(ยังไม่มีรายการชำระบัญชี)'), findsOneWidget);
  });

  testWidgets('driver settlement shows error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementListPage(
          api: _FakeSettlementApi(
            error: const DriverSettlementApiException('Network error'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Network error'), findsOneWidget);
  });

  testWidgets('driver settlement hides settlement not found message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementDetailPage(
          bookingNumber: 'TX202607120002',
          api: _FakeSettlementApi(
            error: const DriverSettlementApiException(
              'Settlement not found',
              errorCode: 'SETTLEMENT_NOT_FOUND',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settlement not found'), findsNothing);
    expect(
      find.textContaining('We could not load the settlement information'),
      findsOneWidget,
    );
  });

  testWidgets('driver settlement detail selects file and uploads', (
    tester,
  ) async {
    final api = _FakeSettlementApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          receiptPicker: () async =>
              (bytes: [0x25, 0x50, 0x44, 0x46], filename: 'receipt.pdf'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('송금증 선택 / เลือกสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 파일: receipt.pdf\n(ไฟล์ที่เลือก)'), findsOneWidget);

    await tester.tap(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    expect(api.uploadCalls, 1);
    expect(find.text('상태\n(สถานะ): RECEIPT_SUBMITTED'), findsOneWidget);
  });

  testWidgets('driver settlement detail shows upload failure and retry', (
    tester,
  ) async {
    final api = _FakeSettlementApi(
      uploadError: const DriverSettlementApiException('Upload failed'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          receiptPicker: () async =>
              (bytes: [1, 2, 3], filename: 'receipt.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('송금증 선택 / เลือกสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Upload failed'), findsOneWidget);
    expect(find.text('업로드 재시도 / ลองอัปโหลดอีกครั้ง'), findsOneWidget);
  });

  test('isAllowedReceiptFilename validates extensions', () {
    expect(isAllowedReceiptFilename('receipt.pdf'), isTrue);
    expect(isAllowedReceiptFilename('photo.JPG'), isTrue);
    expect(isAllowedReceiptFilename('notes.txt'), isFalse);
  });
}
