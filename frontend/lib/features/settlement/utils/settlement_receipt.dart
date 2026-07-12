/// Shared receipt presence / approval helpers for driver and admin settlement UIs.
bool settlementReceiptPresent(Map<String, dynamic>? settlement) {
  if (settlement == null) return false;
  final receiptFileId = settlement['receiptFileId'];
  if (receiptFileId is num && receiptFileId > 0) return true;
  final receiptStatus = settlement['receiptStatus'] as String? ?? '';
  if (receiptStatus == 'RECEIPT_SUBMITTED' || receiptStatus == 'SUBMITTED') {
    return true;
  }
  final commissionStatus = settlement['commissionStatus'] as String? ?? '';
  if (commissionStatus == 'RECEIPT_SUBMITTED') return true;
  final receiptUrl = settlement['receiptUrl'];
  if (receiptUrl is String && receiptUrl.isNotEmpty) return true;
  final metadata = settlement['receiptMetadata'];
  return metadata is Map && metadata.isNotEmpty;
}

bool settlementCanApprove(Map<String, dynamic>? settlement) {
  if (settlement == null) return false;
  if (settlement['canApprove'] == true) return true;
  return settlementReceiptPresent(settlement) &&
      settlement['commissionStatus'] != 'APPROVED' &&
      settlement['commissionStatus'] != 'PAID' &&
      settlement['receiptStatus'] != 'REJECTED';
}

bool driverUploadResponseConfirmed(Map<String, dynamic> response) {
  return settlementReceiptPresent(response);
}
