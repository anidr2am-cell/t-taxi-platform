import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/settlement/utils/settlement_receipt.dart';

void main() {
  test('settlementReceiptPresent accepts receiptFileId', () {
    expect(
      settlementReceiptPresent({'receiptFileId': 12}),
      isTrue,
    );
  });

  test('settlementReceiptPresent accepts receiptStatus RECEIPT_SUBMITTED', () {
    expect(
      settlementReceiptPresent({'receiptStatus': 'RECEIPT_SUBMITTED'}),
      isTrue,
    );
  });

  test('settlementReceiptPresent accepts legacy SUBMITTED receiptStatus', () {
    expect(
      settlementReceiptPresent({'receiptStatus': 'SUBMITTED'}),
      isTrue,
    );
  });

  test('settlementCanApprove prefers API canApprove flag', () {
    expect(
      settlementCanApprove({
        'canApprove': true,
        'commissionStatus': 'PENDING',
      }),
      isTrue,
    );
  });

  test('driverUploadResponseConfirmed rejects empty upload payload', () {
    expect(driverUploadResponseConfirmed({'commissionStatus': 'PENDING'}), isFalse);
  });
}
