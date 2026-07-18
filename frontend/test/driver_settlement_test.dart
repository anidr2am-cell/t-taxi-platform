import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver_settlement/pages/driver_settlement_list_page.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

class _FakeSettlementApi extends DriverSettlementApiService {
  _FakeSettlementApi({this.error, this.uploadError, this.detail});

  final Object? error;
  final Object? uploadError;
  final Map<String, dynamic>? detail;
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
    if (detail != null) return detail!;
    if (uploaded) {
      return {
        'bookingNumber': bookingNumber,
        'commissionStatus': 'RECEIPT_SUBMITTED',
        'receiptStatus': 'RECEIPT_SUBMITTED',
        'receiptFileId': 42,
        'commissionAmount': 120,
        'companyCommissionAmount': 120,
        'companyCommissionCurrency': 'THB',
        'customerPaymentAmount': 1200,
        'customerPaymentCurrency': 'THB',
        'driverExpectedIncomeAmount': 1080,
        'driverExpectedIncomeCurrency': 'THB',
        'currency': 'THB',
        'dueAt': '2026-07-08 12:00:00',
      };
    }
    return {
      'bookingNumber': bookingNumber,
      'commissionStatus': 'DUE',
      'commissionAmount': 120,
      'companyCommissionAmount': 120,
      'companyCommissionCurrency': 'THB',
      'customerPaymentAmount': 1200,
      'customerPaymentCurrency': 'THB',
      'driverExpectedIncomeAmount': 1080,
      'driverExpectedIncomeCurrency': 'THB',
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
      'receiptStatus': 'RECEIPT_SUBMITTED',
      'receiptFileId': 42,
    };
  }
}

Map<String, dynamic> _settlementDetail({
  String status = 'DUE',
  bool blocksNewCalls = true,
  num? companyCommissionAmount = 120,
  num? customerPaymentAmount = 1200,
  num? driverExpectedIncomeAmount = 1080,
  String? receiptStatus,
}) {
  return {
    'bookingNumber': 'TX202607010001',
    'commissionStatus': status,
    'blocksNewCalls': blocksNewCalls,
    'receiptStatus': receiptStatus ?? 'NONE',
    'commissionAmount': companyCommissionAmount,
    'companyCommissionAmount': companyCommissionAmount,
    'companyCommissionCurrency': companyCommissionAmount == null ? null : 'THB',
    'customerPaymentAmount': customerPaymentAmount,
    'customerPaymentCurrency': customerPaymentAmount == null ? null : 'THB',
    'driverExpectedIncomeAmount': driverExpectedIncomeAmount,
    'driverExpectedIncomeCurrency': driverExpectedIncomeAmount == null
        ? null
        : 'THB',
    'currency': 'THB',
    'dueAt': '2026-07-08 12:00:00',
  };
}

Widget _settlementDetailPage(
  Map<String, dynamic> detail, {
  Locale locale = const Locale('ko'),
}) {
  return MaterialApp(
    locale: locale,
    home: DriverSettlementDetailPage(
      key: ValueKey(
        '${locale.languageCode}-${detail['commissionStatus']}-${detail['blocksNewCalls']}-${detail['companyCommissionAmount']}',
      ),
      bookingNumber: 'TX202607010001',
      api: _FakeSettlementApi(detail: detail),
    ),
  );
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

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pumpAndSettle();
    expect(find.text('선택한 파일: receipt.pdf\n(ไฟล์ที่เลือก)'), findsOneWidget);

    await tester.ensureVisible(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    expect(api.uploadCalls, 1);
    expect(find.textContaining('RECEIPT_SUBMITTED'), findsOneWidget);
    expect(find.text('THB 120'), findsOneWidget);
    expect(find.text('THB 1,080'), findsOneWidget);
    expect(find.text('THB 1,200'), findsOneWidget);
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

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Upload failed'), findsOneWidget);
    expect(find.text('업로드 재시도 / ลองอัปโหลดอีกครั้ง'), findsOneWidget);
  });

  testWidgets('driver settlement detail rejects incomplete upload response', (
    tester,
  ) async {
    final api = _IncompleteUploadApi();
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

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('송금증 업로드 / อัปโหลดสลิปโอนเงิน'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DUE'), findsOneWidget);
    expect(find.textContaining('RECEIPT_SUBMITTED'), findsNothing);
  });

  testWidgets('driver settlement detail shows manual approval notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverSettlementDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeSettlementApi(
            detail: {
              'bookingNumber': 'TX202607010001',
              'commissionStatus': 'APPROVED',
              'approvalMode': 'MANUAL_WITHOUT_RECEIPT',
              'commissionAmount': 120,
              'companyCommissionAmount': 120,
              'companyCommissionCurrency': 'THB',
              'customerPaymentAmount': 1200,
              'customerPaymentCurrency': 'THB',
              'driverExpectedIncomeAmount': 1080,
              'driverExpectedIncomeCurrency': 'THB',
              'currency': 'THB',
              'dueAt': '2026-07-08 12:00:00',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settlement approved'), findsOneWidget);
    expect(
      find.text(
        'An administrator confirmed this settlement. If no other settlements are unresolved, you can receive new calls.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Upload'), findsNothing);
  });

  testWidgets('settlement messages align with public blocker status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(status: 'NOT_DUE_YET', blocksNewCalls: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 회사 수수료 납부 대상이 아닙니다'), findsOneWidget);
    expect(find.textContaining('신규 배차를 받을 수 있습니다'), findsOneWidget);
    expect(find.textContaining('신규 배차를 받을 수 없습니다'), findsNothing);
    expect(find.textContaining('영수증을 제출'), findsNothing);

    await tester.pumpWidget(
      _settlementDetailPage(_settlementDetail(status: 'DUE')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('회사 수수료를 납부하고 영수증을 제출'), findsOneWidget);
    expect(find.textContaining('신규 배차를 받을 수 없습니다'), findsOneWidget);

    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(status: 'DUE', blocksNewCalls: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('회사 수수료를 납부하고 영수증을 제출'), findsOneWidget);
    expect(find.textContaining('신규 배차를 받을 수 없습니다'), findsNothing);

    await tester.pumpWidget(
      _settlementDetailPage(_settlementDetail(status: 'OVERDUE')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('수수료 납부 기한이 지났습니다'), findsOneWidget);
    expect(find.textContaining('수수료 납부와 영수증 제출'), findsOneWidget);

    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(
          status: 'RECEIPT_SUBMITTED',
          receiptStatus: 'RECEIPT_SUBMITTED',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('영수증 검토 중'), findsWidgets);
    expect(find.textContaining('관리자 승인 후'), findsOneWidget);

    await tester.pumpWidget(
      _settlementDetailPage(_settlementDetail(status: 'REJECTED')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('영수증이 반려되었습니다'), findsOneWidget);
    expect(find.textContaining('다시 제출'), findsOneWidget);

    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(status: 'APPROVED', blocksNewCalls: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('정산이 완료되었습니다'), findsOneWidget);

    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(status: 'WAIVED', blocksNewCalls: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('회사 수수료가 면제되었습니다'), findsOneWidget);
    expect(find.textContaining('신규 배차를 받을 수 있습니다'), findsOneWidget);
    expect(find.textContaining('신규 배차를 받을 수 없습니다'), findsNothing);
    expect(find.textContaining('영수증을 제출'), findsNothing);
  });

  testWidgets('settlement amount fallbacks do not show unsafe income', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(
          companyCommissionAmount: 1500,
          customerPaymentAmount: 1300,
          driverExpectedIncomeAmount: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('THB 1,500'), findsOneWidget);
    expect(find.text('THB 1,300'), findsOneWidget);
    expect(find.textContaining('THB -'), findsNothing);
    expect(find.textContaining('기사 예상 수입'), findsNothing);

    await tester.pumpWidget(
      _settlementDetailPage(
        _settlementDetail(
          companyCommissionAmount: null,
          driverExpectedIncomeAmount: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('수수료 정보 확인 필요'), findsOneWidget);
    expect(find.textContaining('수입 정보를 확인할 수 없습니다'), findsNothing);
  });

  testWidgets('settlement messages have no raw keys for supported locales', (
    tester,
  ) async {
    for (final code in ['ko', 'en', 'th', 'zh', 'ja']) {
      await tester.pumpWidget(
        _settlementDetailPage(
          _settlementDetail(status: 'WAIVED', blocksNewCalls: false),
          locale: Locale(code),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('driver_settlement'), findsNothing);
      expect(find.textContaining('driver_commission'), findsNothing);
    }
  });

  test('isAllowedReceiptFilename validates extensions', () {
    expect(isAllowedReceiptFilename('receipt.pdf'), isTrue);
    expect(isAllowedReceiptFilename('photo.JPG'), isTrue);
    expect(isAllowedReceiptFilename('notes.txt'), isFalse);
  });
}

class _IncompleteUploadApi extends _FakeSettlementApi {
  @override
  Future<Map<String, dynamic>> uploadReceipt(
    String bookingNumber,
    List<int> bytes,
    String filename,
  ) async {
    uploadCalls += 1;
    return {'bookingNumber': bookingNumber, 'commissionStatus': 'PENDING'};
  }
}
