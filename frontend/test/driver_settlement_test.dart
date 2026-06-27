import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver_settlement/pages/driver_settlement_list_page.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

class _FakeSettlementApi extends DriverSettlementApiService {
  _FakeSettlementApi({this.items, this.detail, this.error, this.uploadError});

  final List<dynamic>? items;
  final Map<String, dynamic>? detail;
  final Object? error;
  final Object? uploadError;
  int uploadCalls = 0;
  bool uploaded = false;

  @override
  Future<List<dynamic>> listSettlements() async {
    if (error != null) throw error!;
    return items ?? [];
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
    return detail ?? {
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
      MaterialApp(
        home: DriverSettlementListPage(api: _FakeSettlementApi()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No settlements'), findsOneWidget);
  });

  testWidgets('driver settlement shows error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementListPage(
          api: _FakeSettlementApi(error: const DriverSettlementApiException('Network error')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Network error'), findsOneWidget);
  });

  testWidgets('driver settlement detail selects file and uploads', (tester) async {
    final api = _FakeSettlementApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          receiptPicker: () async => (bytes: [0x25, 0x50, 0x44, 0x46], filename: 'receipt.pdf'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select receipt (JPG, PNG, PDF)'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: receipt.pdf'), findsOneWidget);

    await tester.tap(find.text('Upload receipt'));
    await tester.pumpAndSettle();
    expect(api.uploadCalls, 1);
    expect(find.text('Status: RECEIPT_SUBMITTED'), findsOneWidget);
  });

  testWidgets('driver settlement detail shows upload failure and retry', (tester) async {
    final api = _FakeSettlementApi(
      uploadError: const DriverSettlementApiException('Upload failed'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
          receiptPicker: () async => (bytes: [1, 2, 3], filename: 'receipt.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select receipt (JPG, PNG, PDF)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload receipt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Upload failed'), findsOneWidget);
    expect(find.text('Retry upload'), findsOneWidget);
  });

  test('isAllowedReceiptFilename validates extensions', () {
    expect(isAllowedReceiptFilename('receipt.pdf'), isTrue);
    expect(isAllowedReceiptFilename('photo.JPG'), isTrue);
    expect(isAllowedReceiptFilename('notes.txt'), isFalse);
  });
}
